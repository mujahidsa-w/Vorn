extends CharacterBody3D
## NPC: civilian / employee / guard. Walks between waypoints, idles, flees from
## danger; guards fight back. Has health and dies.

const Rig = preload("res://scripts/game3d/rig.gd")
const W = preload("res://scripts/game3d/weapons.gd")

enum { IDLE, WALK, FLEE, COWER, COMBAT, DEAD }

var world
var role := "civ"            # civ | employee | guard
var hp := 40.0
var rig
var state := IDLE
var target := Vector3.ZERO
var face_yaw := 0.0
var timer := 0.0
var speed := 0.0
var waypoints: Array = []    # Vector3 world points
var inside_test: Callable    # pos -> bool (inside the bank)
var door := Vector3.ZERO
var home := Vector3.ZERO
var home_yaw := 0.0
var danger := Vector3.ZERO
var enemy = null
var fire_cd := 0.0
var weapon_node: Node3D
var _kick := Vector3.ZERO
var _lod_t := 0.0
var _route: Array = []
var corpse_t := 0.0
var path_mode := false       # street pedestrian: walks the waypoints in order, without stopping
var path_i := 0
var walk_speed := 1.3


func _ready() -> void:
	collision_layer = 8
	collision_mask = 1 | 2 | 8
	floor_snap_length = 0.4
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	var holder := Node3D.new()
	holder.rotation.y = PI
	add_child(holder)
	rig = Rig.new()
	holder.add_child(rig)
	var v: String = {"civ": ["civ", "civ", "hero"][randi() % 3], "employee": "employee", "guard": "guard"}[role]
	rig.setup(v)
	hp = {"civ": 40.0, "employee": 40.0, "guard": 80.0}[role]
	if role == "guard":
		weapon_node = load(W.DATA.m4.path).instantiate()
		holder.add_child(weapon_node)
		weapon_node.position = W.DATA.m4.pos
		weapon_node.rotation_degrees = W.DATA.m4.rot
		rig.weapon = weapon_node
		rig.weapon_id = "m4"
		rig.grips = W.grips_for("m4", weapon_node)
	home = global_position
	home_yaw = rotation.y
	face_yaw = rotation.y
	timer = randf_range(0.5, 4.0)


func push(v: Vector3) -> void:
	_kick += v


func take_damage(amount: float, attacker, dir := Vector3.ZERO) -> void:
	if state == DEAD:
		return
	hp -= amount
	if world:
		world.fx.impact(global_position + Vector3(0, 1.2, 0), -dir.normalized() if dir.length() > 0 else Vector3.UP, true)
	if hp <= 0.0:
		_die()
		return
	if role == "guard" and attacker != null:
		enemy = attacker
		state = COMBAT
	elif role != "guard":
		alert(global_position - dir * 3.0)


func _die() -> void:
	rig.death_clip = "death_c" if rig.stance == 1 else ["death_front", "death_fwd", "death_back"][randi() % 3]
	state = DEAD
	rig.dead = true
	collision_layer = 0
	collision_mask = 1
	velocity = Vector3.ZERO
	corpse_t = 90.0
	if world:
		world.alert(global_position, 25.0, null)


func alert(pos: Vector3, attacker = null) -> void:
	if state == DEAD:
		return
	danger = pos
	if role == "guard":
		if attacker != null:
			enemy = attacker
			state = COMBAT
		return
	state = FLEE
	timer = randf_range(6.0, 10.0)


func _goto(p: Vector3) -> void:
	# route through the door when crossing the bank wall
	_route.clear()
	if inside_test.is_valid() and door != Vector3.ZERO:
		var a: bool = inside_test.call(global_position)
		var b: bool = inside_test.call(p)
		if a != b:
			_route.append(door + (Vector3(0, 0, -2.5).rotated(Vector3.UP, home_yaw) if a else Vector3.ZERO))
			_route.append(door)
	_route.append(p)
	target = _route[0]
	state = WALK


func _physics_process(delta: float) -> void:
	if state == DEAD:
		corpse_t -= delta
		velocity.x = move_toward(velocity.x, 0, 6 * delta)
		velocity.z = move_toward(velocity.z, 0, 6 * delta)
		velocity.y -= 18.0 * delta
		move_and_slide()
		if corpse_t <= 0.0:
			queue_free()
		return
	fire_cd -= delta
	timer -= delta
	var want_speed := 0.0
	var dir := Vector3.ZERO
	match state:
		IDLE:
			if timer <= 0.0:
				if path_mode and waypoints.size() > 0:
					path_i = mini(path_i + 1, waypoints.size() - 1)
					_goto(waypoints[path_i])
				elif role == "civ" and waypoints.size() > 0:
					_goto(waypoints[randi() % waypoints.size()])
				else:
					timer = randf_range(3.0, 8.0)
					face_yaw = home_yaw + randf_range(-0.4, 0.4)
		WALK:
			var to := target - global_position
			to.y = 0
			if to.length() < 0.5:
				_route.pop_front()
				if _route.size() > 0:
					target = _route[0]
				elif path_mode:
					state = IDLE
					timer = 0.0
				else:
					state = IDLE
					timer = randf_range(4.0, 11.0)
					face_yaw = _face_for(global_position)
			else:
				dir = to.normalized()
				want_speed = walk_speed
		FLEE:
			var away := global_position - danger
			away.y = 0
			if away.length() < 0.1:
				away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
			dir = away.normalized()
			want_speed = 3.4
			if timer <= 0.0:
				state = COWER
				timer = randf_range(8.0, 14.0)
				rig.stance = 1
		COWER:
			if timer <= 0.0:
				rig.stance = 0
				state = IDLE
				timer = 1.0
		COMBAT:
			if enemy == null or not is_instance_valid(enemy) or (enemy.get("dead") == true):
				enemy = null
				state = IDLE
				timer = 2.0
			else:
				var to2: Vector3 = enemy.global_position - global_position
				to2.y = 0
				face_yaw = atan2(-to2.x, -to2.z)
				var dist := to2.length()
				if dist > 60.0:
					enemy = null
					state = IDLE
				elif dist > 18.0:
					dir = to2.normalized()
					want_speed = 2.2
				elif fire_cd <= 0.0:
					fire_cd = randf_range(0.45, 0.9)
					_shoot(dist)
	speed = move_toward(speed, want_speed, 4.0 * delta)
	var hv := dir * speed
	velocity.x = hv.x + _kick.x
	velocity.z = hv.z + _kick.z
	_kick = _kick.move_toward(Vector3.ZERO, delta * 20.0)
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = -0.5
	move_and_slide()
	if dir.length() > 0.1 and state != COMBAT:
		face_yaw = atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, face_yaw, 1.0 - exp(-delta * 6.0))


func _face_for(p: Vector3) -> float:
	# civilians face the closest "service point" direction they arrived at (home yaw of the bank)
	return home_yaw + PI if inside_test.is_valid() and inside_test.call(p) else home_yaw


func _shoot(dist: float) -> void:
	if world == null or weapon_node == null:
		return
	var mp: Vector3 = weapon_node.global_transform * W.muzzle_local("m4", weapon_node)
	var aim: Vector3 = enemy.global_position + Vector3(0, 1.2 if enemy.get("stance") != 2 else 0.3, 0)
	var hit_chance := clampf(0.55 - dist * 0.012, 0.15, 0.55)
	if enemy.get("stance") == 1:
		hit_chance *= 0.7
	if randf() > hit_chance:
		aim += Vector3(randf_range(-1.5, 1.5), randf_range(-0.8, 1.2), randf_range(-1.5, 1.5))
	world.fx.muzzle(mp, (aim - mp).normalized())
	rig.recoil = minf(rig.recoil + 0.35, 1.0)
	var cam: Camera3D = world.current_camera()
	var vol := clampf(5.0 - (cam.global_position.distance_to(global_position) if cam else 20.0) * 0.2, -22.0, 3.0)
	Game.play_sfx("shot_rifle", randf_range(0.95, 1.05), vol)
	world.fire_bullet(self, mp, (aim - mp).normalized(), mp, 9.0)


func _process(delta: float) -> void:
	# animation level of detail
	var cam: Camera3D = world.current_camera() if world else null
	var d := cam.global_position.distance_to(global_position) if cam else 0.0
	if d > 80.0:
		return
	_lod_t -= delta
	if d > 30.0 and _lod_t > 0.0:
		return
	var dt := delta if d <= 30.0 else (0.1 - _lod_t)
	_lod_t = 0.1
	var typ := "rifle" if role == "guard" else ""
	rig.aiming = state == COMBAT
	var fwd := -global_transform.basis.z
	var vl := Vector2(velocity.dot(global_transform.basis.x), velocity.dot(fwd))
	rig.update(dt if dt > 0.0 else delta, vl, true, typ, 1.0 if role == "guard" and state != DEAD else 0.0, 0.0)
