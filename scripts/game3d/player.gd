extends CharacterBody3D
## On-foot player: third/first person camera, walk / crouch / prone, punches,
## weapons with IK hands, health + armor, death (WASTED) and respawn.

const W = preload("res://scripts/game3d/weapons.gd")
const Rig = preload("res://scripts/game3d/rig.gd")

const WALK := 1.45
const RUN := 3.3
const CROUCH_SPEED := 0.85
const PRONE_SPEED := 0.4
const GRAV := 18.0
const RESPAWN_TIME := 300.0

var world
var pivot: Node3D
var spring: SpringArm3D
var cam: Camera3D
var model: Node3D
var rig
var cop_team := false
var col_shape: CollisionShape3D
var capsule: CapsuleShape3D
var yaw := 0.0
var pitch := -0.12
var speed_now := 0.0
var active := true
var frozen := false          # competitive buy phase: can look around, cannot move or shoot
var aiming := false
var first_person := false
const BODY_LAYER := 1 << 19
var stance := 0
var _dist_acc := 0.0
var _shake := 0.0
var _fall_v := 0.0
var _kick := Vector3.ZERO

# health
var hp := 100.0
var armor := 0.0
var dead := false
var dead_t := 0.0
var respawn_left := 0.0
var last_hit_t := 99.0

# combat
var inventory: Array = []
var ammo := {}
var current := ""
var weapon_node: Node3D
var arm_w := 0.0
var fire_cd := 0.0
var reload_t := 0.0
var c4_list: Array = []
var _lmb_prev := false
var punch_cd := -5.0
var _punch_hit := false
var _punch_until := -1.0
var _mag_dropped := false
var _punch_idx := 0
var fire_hold_t := 99.0
var running := false
const PUNCH_HITS := [0.7, 0.9, 1.2, 1.4]
const PUNCH_ENDS := [0.8, 1.05, 1.3, 1.75]


func _ready() -> void:
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50)
	collision_layer = 2
	collision_mask = 1 | 2 | 8
	var col := CollisionShape3D.new()
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	col.shape = capsule
	col.position.y = 0.9
	add_child(col)
	col_shape = col
	rig = Rig.new()
	rig.rotation.y = PI
	var holder := Node3D.new()
	holder.rotation.y = PI
	add_child(holder)
	holder.add_child(rig)
	rig.rotation.y = 0.0
	rig.setup(cop_team)
	# own body on its own render layer: hidden from our camera in first person, still casts shadows
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = BODY_LAYER
	model = holder
	pivot = Node3D.new()
	pivot.top_level = true
	add_child(pivot)
	spring = SpringArm3D.new()
	spring.spring_length = 2.3
	spring.margin = 0.2
	spring.add_excluded_object(get_rid())
	spring.position = Vector3(0.5, 0, 0)
	pivot.add_child(spring)
	cam = Camera3D.new()
	cam.fov = float(Game.settings.get("fov", 62.0))
	cam.far = [900.0, 1500.0, 3000.0][clampi(int(Game.settings.quality), 0, 2)]
	cam.near = 0.05
	spring.add_child(cam)


func set_active(on: bool) -> void:
	active = on
	visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	col_shape.disabled = not on
	if on:
		cam.current = true


func _captured() -> bool:
	return Game.touch or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _sens() -> float:
	return 0.0022 * float(Game.settings.get("sens", 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if not active or not _captured() or dead:
		return
	if frozen and event is InputEventMouseButton:
		return
	if event is InputEventMouseMotion and not Game.touch:
		var s := _sens() * (0.45 if aiming else 1.0)
		if aiming and current == "sniper":
			s = _sens() * 0.18
		var inv := -1.0 if bool(Game.settings.get("invert_y", false)) else 1.0
		yaw -= event.relative.x * s
		pitch = clampf(pitch - event.relative.y * s * inv, -1.25, 0.8)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1, KEY_2, KEY_3, KEY_4:
				var i: int = event.physical_keycode - KEY_1
				if i < inventory.size():
					equip(inventory[i])
			KEY_X:
				equip("")
			KEY_R:
				_reload()
			KEY_G:
				detonate_c4()
			KEY_V:
				first_person = not first_person
			KEY_C:
				set_stance(0 if stance == 1 else 1)


func set_stance(s: int) -> void:
	stance = s
	rig.stance = s
	capsule.height = [1.8, 1.25, 0.6][s]
	capsule.radius = 0.3
	col_shape.position.y = capsule.height * 0.5


func _key(k: Key) -> bool:
	return Input.is_physical_key_pressed(k)


func push(v: Vector3) -> void:
	_kick += v


# ---------------------------------------------------------------- movement
func _physics_process(delta: float) -> void:
	last_hit_t += delta
	if dead:
		_dead_tick(delta)
		velocity.x = move_toward(velocity.x, 0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0, 8.0 * delta)
		velocity.y -= GRAV * delta
		move_and_slide()
		return
	var inp := Vector2.ZERO
	if _captured():
		inp.x = float(_key(KEY_D)) - float(_key(KEY_A))
		inp.y = float(_key(KEY_S)) - float(_key(KEY_W))
	if frozen:
		inp = Vector2.ZERO
	aiming = _captured() and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and current != ""
	var moving := inp.length() > 0.1
	running = moving and stance == 0 and not aiming and _key(KEY_SHIFT) and reload_t <= 0.0
	var target_speed := 0.0
	if moving:
		target_speed = RUN if running else [WALK, CROUCH_SPEED, PRONE_SPEED][stance] * (0.7 if aiming and stance == 0 else 1.0)
	# smooth build-up: walking -> jog -> run, and a softer slowdown
	var acc := (1.1 if speed_now > WALK else 1.8) if target_speed > speed_now else 3.5
	speed_now = move_toward(speed_now, target_speed, acc * delta)
	var dir := Basis(Vector3.UP, yaw) * Vector3(inp.x, 0, inp.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	var want := dir * speed_now if moving else Vector3(velocity.x, 0, velocity.z).normalized() * speed_now
	var blend := 1.0 - exp(-delta * (8.0 if is_on_floor() else 1.5))
	velocity.x = lerpf(velocity.x, want.x, blend) + _kick.x
	velocity.z = lerpf(velocity.z, want.z, blend) + _kick.z
	if _kick.y > 0.0:
		velocity.y = _kick.y
	if _captured() and Input.is_physical_key_pressed(KEY_SPACE) and is_on_floor() and stance == 0 and reload_t <= 0.0:
		velocity.y = 4.6
		rig.in_air = true
	_kick = _kick.move_toward(Vector3.ZERO, delta * 30.0)
	_kick.y = 0.0
	if not is_on_floor():
		velocity.y -= GRAV * delta
		_fall_v = minf(_fall_v, velocity.y)
	move_and_slide()
	if is_on_floor() and _fall_v < -11.0:
		take_damage((-_fall_v - 11.0) * 9.0, null, Vector3.DOWN)
	if is_on_floor():
		_fall_v = 0.0
		rig.in_air = false
	elif velocity.y < -3.0:
		rig.in_air = true
	if global_position.y < -200.0 and world:
		world.respawn_player()
	var hv := Vector2(velocity.x, velocity.z)
	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var long_gun: bool = current != "" and W.DATA[current].type in ["rifle", "rpg"] and (not running or fire_hold_t < 0.6)
	if aiming or first_person or long_gun or (current != "" and lmb) or stance == 2 and hv.length() < 0.1:
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-delta * 14.0))
	elif hv.length() > 0.2:
		var face := atan2(-velocity.x, -velocity.z)
		rotation.y = lerp_angle(rotation.y, face, 1.0 - exp(-delta * 4.5))
	if is_on_floor() and hv.length() > 0.3 and stance == 0:
		_dist_acc += hv.length() * delta
		if _dist_acc > (1.05 if running else 0.72):
			_dist_acc = 0.0
			_footstep(running)
	if hp < 100.0 and last_hit_t > 8.0 and hp > 0.0:
		hp = minf(hp + delta * 2.0, 50.0 if hp < 50.0 else hp)   # slow regen up to half
	_combat_tick(delta)


## Footstep sound depends on what we walk on: road / pavement, grass and dirt, polished floors, puddles.
func _footstep(running: bool) -> void:
	var kind := "concrete"
	if world:
		var g: Dictionary = world._ground(global_position + Vector3(0, 0.5, 0))
		if not g.is_empty() and g.collider and g.collider.has_meta("surface"):
			var srf := str(g.collider.get_meta("surface"))
			if srf.contains("gerass") or srf.contains("sand") or srf.contains("cliff"):
				kind = "grass"
		if kind == "concrete" and world.sky and world.sky.wet > 0.45:
			kind = "wet"
			if running and randf() < 0.6:
				world.fx.splash(global_position + Vector3(0, 0.05, 0))
	if world and world.audio_world:
		world.audio_world.play_footstep(global_position, kind, running)
	else:
		Game.play_sfx("step_%s_%d" % [kind, randi_range(1, 3)], randf_range(0.9, 1.1), (-11.0 if running else -14.0) + (2.0 if kind == "wet" else 0.0))


func _process(delta: float) -> void:
	if dead:
		_animate(delta)
		return
	var cam_dist := float(Game.settings.get("cam_dist", 2.3))
	var fov := float(Game.settings.get("fov", 62.0))
	var piv_h: float = [1.58, 1.15, 0.5][stance]
	pivot.global_position = global_position + Vector3(0, piv_h, 0)
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.02
	_shake = maxf(0.0, _shake - delta * 3.0)
	pivot.rotation = Vector3(pitch, yaw, 0) + shake
	var want_len := (cam_dist * 0.55 if aiming else cam_dist)
	var want_off := 0.62 if aiming else 0.5
	var want_fov := (fov - 12.0) if aiming else fov
	if aiming and current == "sniper":
		want_fov = 16.0
		want_len = 0.9
	if first_person:
		want_len = 0.0
		want_off = 0.0
		var hp_pos: Vector3 = rig.head_position()
		pivot.global_position = hp_pos + Vector3(0, 0.08, 0) + (-global_transform.basis.z) * 0.12
	spring.spring_length = lerpf(spring.spring_length, want_len, 1.0 - exp(-delta * 12.0))
	spring.position.x = lerpf(spring.position.x, want_off, 1.0 - exp(-delta * 12.0))
	if first_person:
		spring.spring_length = 0.0
		spring.position.x = 0.0
	cam.fov = lerpf(cam.fov, want_fov, 1.0 - exp(-delta * 10.0))
	cam.cull_mask = (0xFFFFF & ~BODY_LAYER) if first_person else 0xFFFFF
	_animate(delta)


# ---------------------------------------------------------------- animation
func _animate(delta: float) -> void:
	var target_w := 1.0 if (current != "" and not dead) else 0.0
	arm_w = move_toward(arm_w, target_w, delta * 4.0)
	var typ: String = W.DATA[current].type if current != "" else ""
	if weapon_node:
		var d: Dictionary = W.DATA[current]
		weapon_node.position = d.pos
		weapon_node.rotation_degrees = d.rot
		if stance == 2:
			weapon_node.position = Vector3(-0.1, 0.32, 0.75)
		else:
			weapon_node.position.y += rig.position.y
		if arm_w > 0.5 and d.type != "c4":
			var pt := clampf(pitch, -0.6, 0.6) * (1.0 if aiming or first_person else 0.6)
			if stance == 2:
				pt = clampf(pitch, -0.3, 0.3)
			weapon_node.rotate(Vector3.RIGHT, -pt)
	rig.weapon = weapon_node
	rig.weapon_id = current
	fire_hold_t += delta
	rig.aiming = aiming or fire_hold_t < 1.2 or first_person
	var fwd := -global_transform.basis.z
	var right := global_transform.basis.x
	var vl := Vector2(velocity.dot(right), velocity.dot(fwd))
	rig.update(delta, vl, is_on_floor(), typ, arm_w, pitch)
	if weapon_node and current != "" and first_person and W.DATA[current].type != "c4" and stance != 2:
		# view-model: hold the weapon in front of the camera
		var d2: Dictionary = W.DATA[current]
		var vb := Basis(Vector3.UP, deg_to_rad(float(d2.rot.y) + 180.0)) * Basis(Vector3.BACK, deg_to_rad(float(d2.rot.z)))
		var off := Vector3(0.0, -0.115, -0.5) if aiming else Vector3(0.15, -0.19, -0.4)
		if d2.type == "pistol":
			off = Vector3(0.0, -0.1, -0.36) if aiming else Vector3(0.12, -0.15, -0.42)
		off.z += rig.recoil * 0.05
		weapon_node.global_transform = cam.global_transform * Transform3D(vb, off)


# ---------------------------------------------------------------- health
func take_damage(amount: float, attacker, dir := Vector3.ZERO) -> void:
	if dead or amount <= 0.0:
		return
	if armor > 0.0:
		var absorbed := minf(armor, amount * 0.66)
		armor -= absorbed
		amount -= absorbed
	hp -= amount
	last_hit_t = 0.0
	_shake = maxf(_shake, 0.6)
	if world and world.hud:
		world.hud.damage_flash(dir)
	if hp <= 0.0:
		hp = 0.0
		die(attacker)


func die(attacker) -> void:
	if dead:
		return
	dead = true
	dead_t = 0.0
	respawn_left = RESPAWN_TIME
	rig.death_clip = "death_c" if stance == 1 else ["death_front", "death_fwd", "death_back"][randi() % 3]
	equip("")
	set_stance(0)
	rig.dead = true
	if world:
		world.on_player_died(self, attacker)


func _dead_tick(delta: float) -> void:
	dead_t += delta
	respawn_left -= delta
	if respawn_left <= 0.0 and world:
		world.respawn_player()


func revive() -> void:
	dead = false
	rig.dead = false
	hp = 100.0
	armor = 0.0
	velocity = Vector3.ZERO
	set_stance(0)


# ---------------------------------------------------------------- weapons
func give_weapon(id: String) -> bool:
	if not W.DATA.has(id):
		return false
	var fresh := not inventory.has(id)
	if fresh:
		if inventory.size() >= 4:
			inventory.remove_at(inventory.find(current) if current != "" else 0)
		inventory.append(id)
	ammo[id] = int(W.DATA[id].mag)
	equip(id)
	Game.play_sfx("pickup")
	return fresh


func give_armor() -> void:
	armor = 50.0
	Game.play_sfx("pickup")


func equip(id: String) -> void:
	if weapon_node:
		weapon_node.queue_free()
		weapon_node = null
	current = id
	reload_t = 0.0
	if rig:
		rig.reload_t = -1.0
	rig.grips = {}
	if id == "":
		return
	var d: Dictionary = W.DATA[id]
	weapon_node = load(d.path).instantiate()
	model.add_child(weapon_node)
	weapon_node.position = d.pos
	weapon_node.rotation_degrees = d.rot
	for mi in weapon_node.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	rig.grips = W.grips_for(id, weapon_node)
	Game.play_sfx("pickup", 1.2, -6.0)


func _reload() -> void:
	if current == "" or reload_t > 0.0:
		return
	var d: Dictionary = W.DATA[current]
	if int(ammo.get(current, 0)) >= int(d.mag):
		return
	reload_t = 1.8 if d.type != "rpg" else 2.0
	_mag_dropped = false
	Game.play_sfx("reload")


func muzzle_pos() -> Vector3:
	if weapon_node == null:
		return global_position + Vector3(0, 1.4, 0)
	return weapon_node.global_transform * W.muzzle_local(current, weapon_node)


func _combat_tick(delta: float) -> void:
	fire_cd -= delta
	punch_cd -= delta
	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _captured()
	var just := lmb and not _lmb_prev
	_lmb_prev = lmb
	# punches when unarmed
	if current == "":
		# punch combo from the mocap clip (jab, cross, hook, cross); each click extends it
		rig.guard_w = move_toward(rig.guard_w, 1.0 if punch_cd > -1.5 else 0.0, delta * 3.0)
		if just and stance != 2:
			punch_cd = 0.0
			rotation.y = yaw
			if rig.punch_t < 0.0:
				rig.punch_t = 0.45
				_punch_idx = 0
				_punch_until = PUNCH_ENDS[0]
				_punch_hit = false
			elif _punch_idx < PUNCH_ENDS.size() - 1 and _punch_until <= PUNCH_ENDS[_punch_idx]:
				_punch_until = PUNCH_ENDS[_punch_idx + 1]
		if rig.punch_t >= 0.0:
			rig.punch_t = minf(rig.punch_t + delta * 1.2, _punch_until)
			if not _punch_hit and rig.punch_t >= PUNCH_HITS[_punch_idx]:
				_punch_hit = true
				Game.play_sfx("whoosh", 1.7, -10.0)
				if world:
					world.melee(self, global_position + Vector3(0, 1.3, 0), -global_transform.basis.z, 1.3, 14.0)
			if rig.punch_t >= PUNCH_ENDS[_punch_idx]:
				if _punch_until > PUNCH_ENDS[_punch_idx]:
					_punch_idx += 1
					_punch_hit = false
				else:
					rig.punch_t = -1.0
		return
	rig.guard_w = 0.0
	if reload_t > 0.0:
		reload_t -= delta
		var dur: float = 2.0 if W.DATA[current].type == "rpg" else 1.8
		var prog := 1.0 - reload_t / dur
		rig.reload_t = prog
		if prog > 0.3 and not _mag_dropped:
			_mag_dropped = true
			_drop_magazine()
		if reload_t <= 0.0:
			ammo[current] = int(W.DATA[current].mag)
			rig.reload_t = -1.0
		return
	if arm_w < 0.8:
		return
	var d: Dictionary = W.DATA[current]
	var want: bool = lmb if d.auto else just
	if not want or fire_cd > 0.0:
		return
	fire_cd = float(d.rate)
	if int(ammo.get(current, 0)) <= 0:
		Game.play_sfx("empty")
		_reload()
		return
	ammo[current] = int(ammo[current]) - 1
	fire_hold_t = 0.0
	rig.recoil = minf(rig.recoil + float(d.recoil) * 40.0, 1.0)
	var origin := cam.global_position
	var dir := -cam.global_transform.basis.z
	var spread := float(d.spread) * (0.35 if aiming else 1.0) * (0.6 if stance > 0 else 1.0)
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
	var mp := muzzle_pos()
	match d.type:
		"pistol", "rifle":
			if not world or not world.audio_world:
				Game.play_sfx(d.sound, randf_range(0.95, 1.05), 4.0)
			if world:
				world.fx.muzzle(mp, dir)
				world.fire_bullet(self, origin, dir, mp, float(d.get("damage", 25.0)))
			var rec := float(d.recoil) * (0.6 if stance > 0 else 1.0)
			pitch += rec
			yaw += randf_range(-1, 1) * rec * 0.4
			_shake = 0.4 + rec * 10.0
		"rpg":
			Game.play_sfx("rocket")
			if world:
				world.fx.muzzle(mp, dir)
				world.fire_rocket(mp + dir * 0.6, dir, get_rid(), self)
			_shake = 1.2
			pitch += 0.04
			if int(ammo[current]) <= 0:
				_reload()
		"c4":
			if world:
				var p = world.place_c4(origin, dir, get_rid())
				if p:
					c4_list.append(p)
					Game.play_sfx("c4beep")


func detonate_c4() -> void:
	if c4_list.is_empty() or world == null:
		return
	for p in c4_list:
		if is_instance_valid(p):
			world.explode(p.global_position, 9.0, self)
			if world.net:
				world.net.send_blast(p.global_position, 9.0)
			p.queue_free()
	c4_list.clear()


## Reload: the empty magazine falls out of the weapon, a fresh one appears in the left hand.
func _drop_magazine() -> void:
	if weapon_node == null or world == null:
		return
	var d: Dictionary = W.DATA[current]
	if d.type == "rpg" or d.type == "c4":
		return
	var xf: Transform3D = rig.magazine_world()
	var body := RigidBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 1
	body.mass = 0.4
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.035, 0.16, 0.07) if d.type == "rifle" else Vector3(0.025, 0.11, 0.035)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.08, 0.08, 0.09)
	m.metallic = 0.6
	m.roughness = 0.4
	bm.material = m
	mi.mesh = bm
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = bm.size
	cs.shape = sh
	body.add_child(cs)
	world.add_child(body)
	body.global_transform = xf
	body.linear_velocity = velocity + Vector3(0, -1.0, 0)
	body.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-2, 2), randf_range(-4, 4))
	get_tree().create_timer(15.0).timeout.connect(body.queue_free)
	# the new magazine in the left hand
	var nm := MeshInstance3D.new()
	nm.mesh = bm
	world.add_child(nm)
	var tw := nm.create_tween()
	tw.tween_method(func(_v: float): if is_instance_valid(nm) and rig: nm.global_position = rig.left_hand_pos(), 0.0, 1.0, reload_t * 0.7)
	tw.tween_callback(nm.queue_free)
