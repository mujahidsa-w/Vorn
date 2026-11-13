extends CharacterBody3D
# Player: first-person view, weapons, recoil, shop, bomb. Input comes from keyboard + mouse
# or from the touch controls in hud.gd. In test mode an autopilot plays instead.

const MOUSE_SENS := 0.0022

var main
var team := "ct"
var nick := "أنت"
var is_player := true
var alive := false
var hp := 100
var armor := 0
var money := 800
var head_h := 1.45
var he := 0
var kills := 0
var deaths := 0
var primary := ""
var cur := "pistol"
var last_w := "knife"
var ammo := {"pistol": 12, "ak": 30, "m4": 30, "sniper": 5, "knife": 0}
var reserve := {"pistol": 36, "ak": 90, "m4": 90, "sniper": 20, "knife": 0}
var cam: Camera3D
var vm: Node3D
var models := {}
var arms: Node3D
var arm_l: Node3D
var pitch := 0.0
var cd := 0.0
var reload_t := 0.0
var switch_t := 0.0
var heat := 0.0
var kick_v := 0.0
var cur_spread := 0.0
var scoped := false
var hitmark := 0.0
var shake := 0.0
var bob := 0.0
var step_t := 0.0
var buy_open := false
var crouch := false
var trigger := false
# touch input state (written by hud.gd)
var t_move := Vector2.ZERO
var t_fire := false
var t_jump := false
var t_use := false
var t_crouch := false
var aim_assist := 0.0
var ap_path: Array = []
var ap_t := 0.0
var ap_last := -1
var ap_goal := -1

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 1.8
	cap.radius = 0.35
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	cam = Camera3D.new()
	cam.position.y = 1.62
	cam.fov = 78
	cam.near = 0.03
	add_child(cam)
	vm = Node3D.new()
	cam.add_child(vm)
	arms = load("res://models/arms_%s.glb" % team).instantiate()
	vm.add_child(arms)
	arm_l = arms.find_child("VArmL", true, false)
	for k in ["knife", "pistol", "ak", "m4", "sniper"]:
		var m: Node3D = load("res://models/%s.glb" % k).instantiate()
		m.visible = false
		vm.add_child(m)
		models[k] = m
	for mi in vm.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func respawn(pos: Vector3, yaw: float) -> void:
	alive = true
	hp = 100
	global_position = pos
	rotation = Vector3(0, yaw, 0)
	velocity = Vector3.ZERO
	pitch = 0.0
	collision_layer = 2
	cam.top_level = false
	cam.transform = Transform3D(Basis(), Vector3(0, 1.62, 0))
	cam.fov = 78
	cam.current = true
	vm.visible = true
	scoped = false
	buy_open = false
	reload_t = 0.0
	heat = 0.0
	t_crouch = false
	for k in ammo:
		ammo[k] = main.W[k].mag
		reserve[k] = main.W[k].res
	equip(primary if primary != "" else "pistol", true)

func lose_gear() -> void:
	primary = ""
	armor = 0
	he = 0

func equip(k: String, quiet := false) -> void:
	if k == cur and models[k].visible: return
	if k != cur: last_w = cur
	cur = k
	for n in models: models[n].visible = n == k
	arm_l.visible = main.W[k].slot == 1
	switch_t = 0.35
	reload_t = 0.0
	scoped = false
	cam.fov = 78
	if not quiet: main.play("switch", -8)

func hurt(dmg: float, attacker, wkey: String, head: bool) -> void:
	if not alive or main.god: return
	if armor > 0 and wkey != "bomb":
		var ab: float = dmg * 0.5
		armor = max(0, armor - int(ab * 0.5))
		dmg -= ab
	hp -= int(round(dmg))
	main.hud.on_hurt(attacker)
	shake = max(shake, 0.25)
	if hp <= 0:
		alive = false
		collision_layer = 0
		vm.visible = false
		cam.top_level = true
		buy_open = false
		scoped = false
		main.plant_prog = 0.0
		main.defuse_prog = 0.0
		main.on_kill(self, attacker, wkey, head)

func can_buy() -> bool:
	return alive and (main.phase == "freeze" or (main.phase == "live" and main.round_time > 85.0))

func owned(k: String) -> bool:
	return (k == "armor" and armor >= 100) or (k == "he" and he >= 1) or k == primary

func buy(i: int) -> void:
	if i < 0 or i >= main.BUY.size(): return
	var k: String = main.BUY[i][0]
	var pr: int = main.PRICE[k] if main.PRICE.has(k) else main.W[k].price
	if money < pr or owned(k):
		main.play("click", -6)
		return
	money -= pr
	main.play("buy")
	if k == "armor": armor = 100
	elif k == "he": he = 1
	else:
		primary = k
		ammo[k] = main.W[k].mag
		reserve[k] = main.W[k].res
		equip(k)

func look(rel: Vector2, k: float) -> void:
	if not alive: return
	var s: float = k * (0.25 if scoped else 1.0)
	rotate_y(-rel.x * s)
	pitch = clamp(pitch - rel.y * s, -1.5, 1.5)

func toggle_scope() -> void:
	if alive and cur == "sniper" and reload_t <= 0: scoped = not scoped

func _unhandled_input(ev: InputEvent) -> void:
	if main.phase == "menu" or main.test != "" or main.hud.modal(): return
	if ev is InputEventMouse and ev.device == InputEvent.DEVICE_ID_EMULATION: return
	if ev is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(ev.relative, MOUSE_SENS)
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			trigger = ev.pressed
			if ev.pressed and alive and not main.W[cur].auto: try_fire()
		if ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed: toggle_scope()
	if ev is InputEventKey and ev.pressed and not ev.echo and alive:
		var kc: int = ev.physical_keycode
		if kc == KEY_B:
			buy_open = can_buy() and not buy_open
		elif kc == KEY_1 and primary != "": equip(primary)
		elif kc == KEY_2: equip("pistol")
		elif kc == KEY_3: equip("knife")
		elif kc == KEY_Q: equip(last_w)
		elif kc == KEY_R: reload()
		elif kc == KEY_G: throw_he()

func reload() -> void:
	var w: Dictionary = main.W[cur]
	if not alive or w.mag == 0 or reload_t > 0 or ammo[cur] >= w.mag or reserve[cur] <= 0: return
	reload_t = w.reload
	scoped = false
	main.play("reload", -4)

func try_fire() -> void:
	if not alive or cd > 0 or reload_t > 0 or switch_t > 0.1 or buy_open or main.phase == "freeze" or main.phase == "match": return
	var w: Dictionary = main.W[cur]
	if w.mag > 0 and ammo[cur] <= 0:
		main.play("click", -6)
		cd = 0.25
		if reserve[cur] > 0: reload()
		return
	cd = w.rate
	if w.mag > 0: ammo[cur] -= 1
	var sp: float = cur_spread
	if cur == "sniper" and scoped: sp = 0.0006 + Vector2(velocity.x, velocity.z).length() * 0.01
	var b := cam.global_transform.basis
	var dir: Vector3 = (-b.z + b.x * randfn(0.0, sp) + b.y * randfn(0.0, sp)).normalized()
	var mz: Node3D = models[cur].find_child("Muzzle", true, false)
	var mpos: Vector3 = mz.global_position if mz else cam.global_position - b.z * 0.6
	main.fire(self, cam.global_position, dir, cur, mpos)
	main.play(w.snd, -3)
	if cur != "knife":
		main.flash(mpos, 3.0, 6.0, 0.04)
		pitch = min(pitch + w.kick * (0.6 + heat * 0.22), 1.5)
		rotate_y(randf_range(-1, 1) * w.kick * (0.2 + heat * 0.1))
		heat = min(heat + 1.0, 8.0)
		kick_v = 0.07 if cur != "sniper" else 0.16
		if cur == "sniper":
			scoped = false
	else:
		kick_v = -0.25

func throw_he() -> void:
	if not alive or he <= 0 or main.phase == "freeze": return
	he -= 1
	var g := RigidBody3D.new()
	g.collision_layer = 4
	g.collision_mask = 1
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.08
	cs.shape = sh
	g.add_child(cs)
	g.add_child(load("res://models/grenade.glb").instantiate())
	main.fx_root.add_child(g)
	var b := cam.global_transform.basis
	g.global_position = cam.global_position - b.z * 0.6
	g.linear_velocity = -b.z * 17.0 + Vector3.UP * 3.5 + velocity
	g.angular_velocity = Vector3(6, 2, 4)
	main.play("switch", -4)
	var me = self
	var boom := func():
		if is_instance_valid(g):
			main.explode(g.global_position, 9.0, 140.0, me, "he")
			g.queue_free()
	get_tree().create_timer(1.7, false).timeout.connect(boom)

func autopilot(dt: float) -> Vector3:
	# test bot instead of a human: walks to the site, shoots what it sees, buys, plants/defuses
	ap_t -= dt
	var ti := int(main.t_all)
	if main.selftest and ti != ap_last:
		ap_last = ti
		print("SELFTEST step ", ti, " cur=", cur, " money=", money, " he=", he, " armor=", armor)
		if ti == 1:
			money = 16000
			buy(3)
			buy(4)
			buy(2)
		if ti == 3: buy_open = true
		if ti == 5: buy_open = false
		if ti == 7: scoped = true
		if ti == 8: try_fire()
		if ti == 9: throw_he()
		if ti == 10: equip("knife")
		if ti == 11: try_fire()
		if ti == 12:
			equip("pistol")
			ammo["pistol"] = 3
			reload()
		if ti == 14: buy(0)
		if ti == 15: equip(last_w)
	if main.selftest and ti < 16: return Vector3.ZERO
	if main.phase == "freeze" and primary == "" and money >= 2700: buy(0)
	var tgt = null
	var bd := 1e9
	for a in main.actors:
		if a.alive and a.team != team:
			var d: float = a.global_position.distance_to(global_position)
			if d < bd and main.los(cam.global_position, a.global_position + Vector3(0, 1.3, 0)):
				bd = d
				tgt = a
	var goal: Vector3 = main.bomb.global_position if main.bomb else main.NODES[main.site_node]
	if tgt and not main.nofire:
		var to: Vector3 = tgt.global_position + Vector3(0, 1.25, 0) - cam.global_position
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), dt * 10)
		pitch = lerp(pitch, atan2(to.y, Vector2(to.x, to.z).length()), dt * 10)
		if abs(angle_difference(rotation.y, atan2(-to.x, -to.z))) < 0.05: try_fire()
		if ammo[cur] == 0: reload()
		return Vector3.ZERO
	var gn: int = main.nearest_node(goal)
	if ap_path.is_empty() or gn != ap_goal:
		ap_goal = gn
		ap_path = main.find_path(main.nearest_node(global_position), gn)
	var use_e: bool = false
	var p: Vector3 = main.NODES[ap_path[0]] if ap_path.size() > 0 else goal
	if ap_path.size() <= 1 and global_position.distance_to(goal) < 12.0: p = goal
	var to2 := p - global_position
	to2.y = 0
	if to2.length() < 1.3:
		if ap_path.size() > 1: ap_path.pop_front()
		elif global_position.distance_to(goal) < 2.0: use_e = true
	if use_e:
		pitch = lerp(pitch, -0.9, dt * 5)
		do_use(dt, true)
		return Vector3.ZERO
	do_use(dt, false)
	rotation.y = lerp_angle(rotation.y, atan2(-to2.x, -to2.z), dt * 8)
	pitch = lerp(pitch, 0.0, dt * 4)
	return to2.normalized()

func can_plant() -> bool:
	return alive and team == "t" and main.phase == "live" and main.bomb_carrier == self and main.near_site(global_position)

func can_defuse() -> bool:
	return alive and team == "ct" and main.phase == "planted" and main.bomb != null and global_position.distance_to(main.bomb.global_position) < 2.4

func do_use(dt: float, held: bool) -> void:
	var fwd := -global_transform.basis.z
	if held and can_plant() and is_on_floor():
		main.plant_prog += dt
		if main.plant_prog >= 3.2:
			main.plant_prog = 0.0
			main.plant_bomb(global_position + fwd * 0.7, self)
	else:
		main.plant_prog = 0.0
	if held and can_defuse():
		main.defuse_prog += dt
		if main.defuse_prog >= 5.0:
			main.defuse_prog = 0.0
			main.defused(self)
	else:
		main.defuse_prog = 0.0

func update_aim_assist() -> void:
	# touch only: slows the camera a little while the crosshair is on a visible enemy
	aim_assist = 0.0
	if not main.hud.touch_mode: return
	var o := cam.global_position
	var fwd := -cam.global_transform.basis.z
	for a in main.actors:
		if not a.alive or a.team == team: continue
		var to: Vector3 = a.global_position + Vector3(0, 1.1, 0) - o
		var d := to.length()
		if d < 60.0 and fwd.angle_to(to) < 0.05 + 0.5 / max(d, 1.0) and main.los(o, a.global_position + Vector3(0, 1.2, 0)):
			aim_assist = 1.0
			return

func _physics_process(dt: float) -> void:
	if main.phase == "menu": return
	var firing: bool = (trigger or t_fire) and not main.hud.modal()
	cd -= dt
	hitmark = max(0.0, hitmark - dt)
	shake = max(0.0, shake - dt * 1.5)
	heat = max(0.0, heat - dt * (3.0 if firing and main.W[cur].auto else 7.0))
	switch_t = max(0.0, switch_t - dt)
	if not alive:
		spectate(dt)
		return
	var wish := Vector3.ZERO
	var using := false
	var walk := false
	if main.test != "":
		wish = autopilot(dt)
	else:
		var f := Input.get_axis("ui_down", "ui_up")
		var ix := t_move.x
		var iz := t_move.y - f
		if Input.is_physical_key_pressed(KEY_W): iz -= 1
		if Input.is_physical_key_pressed(KEY_S): iz += 1
		if Input.is_physical_key_pressed(KEY_A): ix -= 1
		if Input.is_physical_key_pressed(KEY_D): ix += 1
		var v := Vector3(ix, 0, iz)
		if v.length() > 1.0: v = v.normalized()
		wish = global_transform.basis * v
		crouch = Input.is_physical_key_pressed(KEY_CTRL) or t_crouch
		walk = Input.is_physical_key_pressed(KEY_SHIFT)
		using = Input.is_physical_key_pressed(KEY_E) or t_use
		do_use(dt, using)
		if firing and main.W[cur].auto: try_fire()
		if is_on_floor() and (Input.is_physical_key_pressed(KEY_SPACE) or t_jump) and main.phase != "freeze": velocity.y = 5.6
		update_aim_assist()
	var busy: bool = main.plant_prog > 0 or main.defuse_prog > 0 or main.phase == "freeze"
	var spd: float = 5.4
	if cur == "knife": spd = 6.0
	if walk: spd = 2.7
	if crouch: spd = 2.1
	if scoped: spd = 2.2
	if busy: spd = 0.0
	var acc: float = 55.0 if is_on_floor() else 12.0
	velocity.x = move_toward(velocity.x, wish.x * spd, acc * dt)
	velocity.z = move_toward(velocity.z, wish.z * spd, acc * dt)
	velocity.y -= 17.0 * dt
	move_and_slide()
	var hs: float = Vector2(velocity.x, velocity.z).length()
	head_h = 1.0 if crouch else 1.45
	# reload
	if reload_t > 0:
		reload_t -= dt
		if reload_t <= 0:
			var need: int = min(main.W[cur].mag - ammo[cur], reserve[cur])
			ammo[cur] += need
			reserve[cur] -= need
	# spread
	var w: Dictionary = main.W[cur]
	cur_spread = w.spread * (1.0 + heat * 1.3) + hs * 0.006 + (0.0 if is_on_floor() else 0.07)
	if crouch: cur_spread *= 0.6
	# camera and hands
	var eye: float = 1.12 if crouch else 1.62
	cam.position.y = lerp(cam.position.y, eye, dt * 12)
	cam.rotation = Vector3(pitch + randf_range(-1, 1) * shake * 0.03, randf_range(-1, 1) * shake * 0.03, 0)
	cam.fov = lerp(cam.fov, 16.0 if scoped else 78.0, dt * 18)
	vm.visible = not scoped
	bob += dt * hs * 1.9
	kick_v = lerp(kick_v, 0.0, dt * 14)
	var base := Vector3(0.17, -0.2, -0.4)
	if cur == "pistol": base = Vector3(0.15, -0.17, -0.48)
	if cur == "knife": base = Vector3(0.2, -0.22, -0.42)
	var rl: float = sin(clamp(reload_t / max(w.reload, 0.01), 0, 1) * PI) if reload_t > 0 else 0.0
	vm.position = base + Vector3(cos(bob * 0.5) * 0.006, sin(bob) * 0.006 - switch_t * 0.7 - rl * 0.16, kick_v)
	vm.rotation = Vector3(kick_v * 0.6 + rl * 0.7, 0, -rl * 0.5 + (0.5 if cur == "knife" else 0.0))
	# footsteps
	step_t -= dt * hs
	if is_on_floor() and hs > 3.0 and step_t <= 0:
		step_t = 2.3
		main.play("step%d" % (1 + randi() % 4), -14)

func spectate(dt: float) -> void:
	var mate = null
	for a in main.actors:
		if a.alive and a.team == team: mate = a
	if mate == null: return
	var back: Vector3 = mate.global_transform.basis.z
	cam.global_position = cam.global_position.lerp(mate.global_position + Vector3(0, 2.3, 0) + back * 3.6, dt * 5)
	cam.look_at(mate.global_position + Vector3(0, 1.4, 0))
	cam.fov = 78
