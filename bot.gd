extends CharacterBody3D
# Bot: walks the waypoint graph, sees by raycast, fires in bursts, plants and defuses the bomb. Jointed animation in code.

var main
var team := "ct"
var nick := "بوت"
var is_player := false
var alive := false
var hp := 100
var armor := 0
var money := 800
var head_h := 1.45
var wkey := "pistol"
var kills := 0
var deaths := 0
var last_step := 0
var primary := ""
var mdl: Node3D
var P := {}
var gun: Node3D
var guns := {}
var tag: Label3D
var path: Array = []
var goal := -1
var hold_t := 0.0
var off := Vector3.ZERO
var tgt = null
var see_t := 0.0
var react := 0.0
var cd := 0.0
var burst := 0
var mag := 12
var reload_t := 0.0
var strafe := 1.0
var strafe_t := 0.0
var ph := 0.0
var yaw_t := 0.0
var stuck_t := 0.0
var side_t := 0.0
var work_t := 0.0
var flinch := 0.0
var look_t := 0.0
var skill := 1.0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 1.8
	cap.radius = 0.36
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	mdl = load("res://models/fighter_%s.glb" % team).instantiate()
	add_child(mdl)
	for n in ["Hips", "Torso", "Head", "ArmL", "ArmR", "ForeL", "ForeR", "LegL", "LegR", "ShinL", "ShinR"]:
		P[n] = mdl.find_child(n, true, false)
	gun = Node3D.new()
	P["Torso"].add_child(gun)
	gun.position = Vector3(0.16, 0.36, -0.3)
	for k in ["pistol", "ak", "m4", "sniper"]:
		var g: Node3D = load("res://models/%s.glb" % k).instantiate()
		g.visible = false
		gun.add_child(g)
		guns[k] = g
	tag = Label3D.new()
	tag.text = nick
	tag.font = main.hud.f_bd
	tag.outline_size = 10
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 40
	tag.pixel_size = 0.004
	tag.no_depth_test = true
	tag.modulate = Color(0.5, 0.8, 1.0) if team == "ct" else Color(1.0, 0.75, 0.35)
	tag.position.y = 2.1
	add_child(tag)
	skill = randf_range(0.8, 1.25)
	off = Vector3(randf_range(-0.9, 0.9), 0, randf_range(-0.9, 0.9))

func respawn(pos: Vector3, yaw: float) -> void:
	alive = true
	hp = 100
	global_position = pos
	rotation = Vector3(0, yaw, 0)
	yaw_t = yaw
	velocity = Vector3.ZERO
	collision_layer = 2
	mdl.rotation = Vector3.ZERO
	mdl.visible = true
	mdl.position = Vector3.ZERO
	for n in P: P[n].rotation = Vector3.ZERO
	gun.visible = true
	tag.visible = team == main.player.team
	tgt = null
	path = []
	goal = -1
	hold_t = 0.0
	work_t = 0.0
	reload_t = 0.0
	# shopping
	if primary == "" and main.round_n > 1 and money >= 2700:
		primary = "ak" if team == "t" else "m4"
		money -= 2700
		if money >= 2600 and randf() < 0.15:
			primary = "sniper"
			money -= 2000
	if armor < 100 and money >= 650 and main.round_n > 1:
		armor = 100
		money -= 650
	wkey = primary if primary != "" else "pistol"
	for k in guns: guns[k].visible = k == wkey
	mag = main.W[wkey].mag
	pose_aim()

func lose_gear() -> void:
	primary = ""
	armor = 0

func pose_aim() -> void:
	var rifle: bool = wkey != "pistol"
	P["ArmR"].rotation = Vector3(1.05, 0, -0.25)
	P["ForeR"].rotation = Vector3(0.75, 0, 0.0)
	P["ArmL"].rotation = Vector3(1.3, 0, 0.55) if rifle else Vector3(1.05, 0, 0.3)
	P["ForeL"].rotation = Vector3(0.35, 0, 0.0) if rifle else Vector3(0.75, 0, 0)
	gun.position = Vector3(0.14, 0.34, -0.3) if rifle else Vector3(0.1, 0.4, -0.52)

func hurt(dmg: float, attacker, wk: String, head: bool) -> void:
	if not alive: return
	if armor > 0 and wk != "bomb":
		var ab: float = dmg * 0.5
		armor = max(0, armor - int(ab * 0.5))
		dmg -= ab
	hp -= int(round(dmg))
	flinch = 0.35
	if attacker and attacker.alive and attacker.team != team and tgt == null:
		var to: Vector3 = attacker.global_position - global_position
		yaw_t = atan2(-to.x, -to.z)
		see_t = 0.0
		react = min(react, 0.15)
	if hp <= 0: die(attacker, wk, head)

func die(attacker, wk: String, head: bool) -> void:
	alive = false
	collision_layer = 0
	tag.visible = false
	mdl.visible = true
	gun.visible = false
	var tw := create_tween().set_parallel(true)
	var back := -1.0 if randf() < 0.7 else 1.0
	tw.tween_property(mdl, "rotation:x", back * 1.5, 0.45).set_ease(Tween.EASE_IN)
	tw.tween_property(mdl, "position:y", 0.22, 0.45).set_ease(Tween.EASE_IN)
	tw.tween_property(mdl, "position:z", -back * 0.6, 0.45)
	for n in ["ArmL", "ArmR"]: tw.tween_property(P[n], "rotation", Vector3(randf_range(-0.6, 0.6), 0, (0.9 if n == "ArmR" else -0.9)), 0.4)
	for n in ["ForeL", "ForeR", "ShinL", "ShinR"]: tw.tween_property(P[n], "rotation", Vector3(randf_range(-0.5, 0.3), 0, 0), 0.4)
	main.on_kill(self, attacker, wk, head)

func eye() -> Vector3:
	return global_position + Vector3(0, 1.55, 0)

func look_for_enemy() -> void:
	var best = null
	var bd := 70.0
	var fwd := -global_transform.basis.z
	for a in main.actors:
		if not a.alive or a.team == team: continue
		var to: Vector3 = a.global_position - global_position
		var d := to.length()
		if d > bd: continue
		if d > 6.0 and fwd.angle_to(Vector3(to.x, 0, to.z).normalized()) > 1.25: continue
		if main.los(eye(), a.global_position + Vector3(0, 1.2, 0)):
			bd = d
			best = a
	if best != tgt:
		tgt = best
		if tgt: react = randf_range(0.28, 0.6) / skill + (0.25 if wkey == "sniper" else 0.0)

func pick_goal() -> void:
	var cur: int = main.nearest_node(global_position)
	if team == "t":
		if main.phase == "planted":
			var hn: Array = main.hold_nodes()
			goal = hn[randi() % hn.size()]
			path = main.find_path(cur, goal)
			hold_t = randf_range(5, 9)
		else:
			goal = main.site_node
			path = main.find_path(cur, main.route_via)
			var p2: Array = main.find_path(main.route_via, goal)
			p2.pop_front()
			path.append_array(p2)
			hold_t = 3.0
	else:
		if main.phase == "planted":
			goal = main.site_node
			hold_t = 2.0
		else:
			goal = main.DEFEND[randi() % main.DEFEND.size()]
			hold_t = randf_range(9, 16)
		path = main.find_path(cur, goal)

func shoot() -> void:
	var w: Dictionary = main.W[wkey]
	var from := eye()
	var aim: Vector3 = tgt.global_position + Vector3(0, (tgt.head_h + 0.12) if randf() < 0.10 * skill else 1.05, 0)
	var dir := (aim - from).normalized()
	var err: float = (0.05 if wkey != "sniper" else 0.012) / skill + Vector2(velocity.x, velocity.z).length() * 0.008
	dir = (dir + Vector3(randfn(0.0, err), randfn(0.0, err * 0.6), randfn(0.0, err))).normalized()
	var mz: Node3D = guns[wkey].find_child("Muzzle", true, false)
	var mpos: Vector3 = mz.global_position if mz else from + dir * 0.8
	main.fire(self, from, dir, wkey, mpos)
	main.play3d(w.snd, global_position, 2.0, 90)
	main.flash(mpos, 2.5, 5.0, 0.04)
	mag -= 1
	if mag <= 0: reload_t = 2.0

func _physics_process(dt: float) -> void:
	if not alive or main.phase == "menu": return
	cd -= dt
	see_t -= dt
	flinch = max(0.0, flinch - dt)
	if see_t <= 0:
		see_t = 0.18 + randf() * 0.06
		look_for_enemy()
	if reload_t > 0:
		reload_t -= dt
		if reload_t <= 0: mag = main.W[wkey].mag
	var live: bool = main.phase == "live" or main.phase == "planted"
	var wish := Vector3.ZERO
	var spd := 4.6
	if tgt and tgt.alive and live:
		# combat
		work_t = 0.0
		var to: Vector3 = tgt.global_position - global_position
		yaw_t = atan2(-to.x, -to.z)
		react -= dt
		strafe_t -= dt
		if strafe_t <= 0:
			strafe_t = randf_range(0.5, 1.3)
			strafe = [-1.0, 1.0, 0.0][randi() % 3]
		wish = global_transform.basis.x * strafe
		spd = 2.3
		if react <= 0 and cd <= 0 and reload_t <= 0 and abs(angle_difference(rotation.y, yaw_t)) < 0.25:
			if burst <= 0:
				burst = (randi_range(2, 5) if main.W[wkey].auto else 1)
			shoot()
			burst -= 1
			cd = main.W[wkey].rate if burst > 0 else randf_range(0.25, 0.6) + (1.2 if wkey == "sniper" else 0.0)
	elif live:
		tgt = null
		if path.is_empty():
			# arrived: work on the bomb or hold the position
			var did := false
			if team == "t" and main.phase == "live" and main.bomb_carrier == self and goal == main.site_node:
				work_t += dt
				did = true
				if work_t >= 3.2:
					work_t = 0.0
					main.plant_bomb(global_position - global_transform.basis.z * 0.6, self)
			elif team == "ct" and main.phase == "planted" and main.bomb:
				var tb: Vector3 = main.bomb.global_position - global_position
				tb.y = 0
				did = true
				if tb.length() > 1.3:
					wish = tb.normalized()
					yaw_t = atan2(-tb.x, -tb.z)
					work_t = 0.0
				else:
					work_t += dt
					if work_t >= 6.0:
						work_t = 0.0
						main.defused(self)
			if not did:
				work_t = 0.0
				hold_t -= dt
				look_t -= dt
				if look_t <= 0:
					look_t = randf_range(1.5, 3.5)
					yaw_t += randf_range(-1.4, 1.4)
				if hold_t <= 0: pick_goal()
		else:
			work_t = 0.0
			var p: Vector3 = main.NODES[path[0]] + off
			var to2 := p - global_position
			to2.y = 0
			if to2.length() < 1.4:
				path.pop_front()
			else:
				wish = to2.normalized()
				yaw_t = atan2(-wish.x, -wish.z)
		if goal == -1 or (team == "ct" and main.phase == "planted" and goal != main.site_node) or (team == "t" and main.phase == "planted" and goal == main.site_node and path.is_empty() and hold_t <= 0):
			pick_goal()
	# unstuck
	if side_t > 0:
		side_t -= dt
		wish = (wish + global_transform.basis.x * strafe * 1.5).normalized()
	var hs := Vector2(velocity.x, velocity.z).length()
	if wish.length() > 0.1 and hs < 0.6 and tgt == null:
		stuck_t += dt
		if stuck_t > 0.6:
			stuck_t = 0.0
			side_t = 0.7
			strafe = -1.0 if randf() < 0.5 else 1.0
	else:
		stuck_t = 0.0
	velocity.x = move_toward(velocity.x, wish.x * spd, 30 * dt)
	velocity.z = move_toward(velocity.z, wish.z * spd, 30 * dt)
	velocity.y -= 17 * dt
	move_and_slide()
	rotation.y = lerp_angle(rotation.y, yaw_t, dt * 9)
	animate(dt, hs)

func animate(dt: float, hs: float) -> void:
	# a teammate right in front of the camera must not block the view
	if team == main.player.team: mdl.visible = not main.player.alive or global_position.distance_to(main.player.global_position) > 0.85
	var k: float = clamp(hs / 4.6, 0, 1)
	ph += dt * (4.0 + hs * 2.2) * (1.0 if hs > 0.3 else 0.0)
	var s := sin(ph)
	if int(ph / PI) != last_step:
		last_step = int(ph / PI)
		if hs > 3.0 and main.player and main.player.global_position.distance_to(global_position) < 26.0:
			main.play3d("step%d" % (1 + randi() % 4), global_position, -4.0, 30.0)
	P["LegL"].rotation.x = s * 0.8 * k
	P["LegR"].rotation.x = -s * 0.8 * k
	P["ShinL"].rotation.x = -max(0.0, sin(ph - 1.2)) * 1.1 * k
	P["ShinR"].rotation.x = -max(0.0, sin(ph - 1.2 + PI)) * 1.1 * k
	P["Hips"].position.y = 0.95 + abs(cos(ph)) * 0.035 * k - (0.12 if work_t > 0 else 0.0)
	var pt := 0.0
	if tgt and tgt.alive:
		var to: Vector3 = tgt.global_position + Vector3(0, 1.1, 0) - eye()
		pt = clamp(atan2(to.y, Vector2(to.x, to.z).length()), -0.5, 0.5)
	if work_t > 0: pt = -0.7
	P["Torso"].rotation.x = lerp(P["Torso"].rotation.x, pt - flinch * 0.6, dt * 10)
	P["Torso"].rotation.y = sin(ph) * 0.08 * k
	P["Head"].rotation.y = lerp(P["Head"].rotation.y, sin(ph * 0.5) * 0.15 * k, dt * 5)
