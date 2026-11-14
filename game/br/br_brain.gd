class_name BRBrain
extends Node
## Battle royale bot: loots what it needs (a gun first, then ammo, armour and meds), keeps ahead of the
## sandstorm, fights whoever it sees with a skill-dependent aim, heals when it is quiet, and gets itself unstuck.

var a: Actor
var game
var rng := RandomNumberGenerator.new()
var skill := 0.5
var goal := Vector3.ZERO
var goal_kind := ""
var goal_t := 0.0
var item: Loot
var route: Array = []          # waypoints before the goal (door, inside the door, stairs)
var skip := {}                 # items that could not be reached -> time to forget them
var target: Actor
var target_seen := false
var see_t := 0.0
var lost_t := 0.0
var quiet_t := 0.0
var scan_t := 0.0
var heard := Vector3.INF
var heard_t := 0.0
var stuck_t := 0.0
var stuck_n := 0
var last_p := Vector3.ZERO
var side_t := 0.0
var side_dir := Vector3.ZERO
var strafe := 1.0
var strafe_t := 0.0
var burst := 0
var burst_cd := 0.0
var loot_left := 90.0
var aim_err := Vector2.ZERO
var steer := Vector3.ZERO
var steer_t := 0.0

func setup(actor: Actor, g) -> void:
	a = actor
	game = g
	rng.randomize()
	skill = rng.randf_range(0.3, 0.85)
	loot_left = rng.randf_range(70.0, 160.0)

func hear(pos: Vector3) -> void:
	heard = pos
	heard_t = 3.0

func think(dt: float) -> void:
	if not a.alive:
		return
	goal_t += dt
	loot_left -= dt
	heard_t -= dt
	burst_cd -= dt
	scan_t -= dt
	if scan_t <= 0.0:
		scan_t = 0.14 + (1.0 - skill) * 0.16
		_scan()
	var wish := Vector2.ZERO
	var jump := false
	var crouch := false
	if target and target.alive:
		quiet_t = 0.0
		var r: Array = _fight(dt)
		wish = r[0]
		crouch = r[1]
	else:
		target = null
		quiet_t += dt
		if a.hp < 75 and quiet_t > 3.0 and not game.heal.has(a):
			game.use_heal(a)
		if game.heal.has(a):
			crouch = true
		else:
			var r2: Array = _travel(dt)
			wish = r2[0]
			jump = r2[1]
		_best_weapon()
	a.move_step(wish, jump, crouch, false, dt)

# ------------------------------------------------------------------ seeing
func _range() -> float:
	var cls: String = a.wd()["cls"]
	return {"sniper": 230.0, "rifle": 150.0, "smg": 75.0, "pistol": 55.0, "shotgun": 32.0, "knife": 18.0, "nade": 30.0}.get(cls, 60.0)

func _scan() -> void:
	var best: Actor = null
	var bd := 1e9
	var eye := a.eye()
	var fwd := -Basis(Vector3.UP, a.view_yaw).z
	var lim := _range()
	if a.inv[1] == "" and a.inv[2] == "":
		lim = 6.0             # unarmed: a gun first; only stabs what is right in front of it
	if not game.in_safe(a.global_position):
		lim = minf(lim, 25.0)
	for o in game.actors:
		if o == a or not o.alive or game.fly[o]["st"] == "plane" or int(skip.get(o, 0)) > Time.get_ticks_msec():
			continue
		var to: Vector3 = o.global_position - a.global_position
		var d := to.length()
		if d > lim:
			continue
		var flat := Vector3(to.x, 0, to.z)
		var ang := fwd.angle_to(flat) if flat.length() > 0.1 else 0.0
		var noticed: bool = ang < 1.25 or d < 10.0 or (heard_t > 0.0 and o.global_position.distance_to(heard) < 18.0) or o == target
		if not noticed:
			continue
		if not game.world.los(eye, o.eye(), []) or game.smoke_blocks(eye, o.eye()):
			continue
		if d < bd:
			bd = d
			best = o
	if best:
		if best != target:
			see_t = 0.0
			aim_err = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * (0.05 + (1.0 - skill) * 0.08)
		target = best
		target_seen = true
		lost_t = 0.0
	elif target:
		target_seen = false
		lost_t += 0.2
		if lost_t > 1.6:
			target = null

# ------------------------------------------------------------------ fighting
func _fight(dt: float) -> Array:
	see_t += dt
	var cls: String = a.wd()["cls"]
	var tp := target.global_position + Vector3(0, 1.25 if target.crouch_t < 0.5 else 0.9, 0)
	if skill > 0.7 and see_t > 1.0:
		tp.y += 0.3          # the good ones go for the head
	var eye := a.eye()
	var to := tp - eye
	var d := to.length()
	var yaw := atan2(-to.x, -to.z)
	var pitch := atan2(to.y, Vector2(to.x, to.z).length())
	aim_err = aim_err.lerp(Vector2.ZERO, 1.0 - exp(-(0.8 + skill * 2.0) * dt))
	var turn := (2.2 + skill * 6.5) * dt
	a.view_yaw = rotate_toward(a.view_yaw, yaw + aim_err.x, turn)
	a.view_pitch = move_toward(a.view_pitch, clampf(pitch + aim_err.y - deg_to_rad(a.punch.x) * 0.5 * skill, -1.4, 1.4), turn)
	var off := absf(angle_difference(a.view_yaw, yaw)) + absf(a.view_pitch - pitch)
	# ammunition and weapon
	if cls != "knife" and cls != "nade" and a.ammo.has(a.cur) and a.mag() == 0:
		if a.reserve() > 0:
			a.start_reload()
		else:
			_best_weapon(true)
	var react := 0.55 - skill * 0.35
	if target_seen and see_t > react and burst_cd <= 0.0 and off < 0.05 + 0.6 / maxf(d, 1.0):
		if cls == "knife":
			if d < 1.7:
				a.try_fire()
		elif cls == "sniper":
			if not a.scoped:
				a.try_fire(true)
			elif off < 0.025 and a.speed_h() < 1.5:
				a.try_fire()
				burst_cd = 0.4
		elif a.try_fire():
			burst += 1
			var lim := 1
			if a.wd().get("auto", false):
				lim = int(lerpf(3.0, 9.0, clampf(1.0 - d / 40.0, 0.0, 1.0)))
			if burst >= lim:
				burst = 0
				burst_cd = rng.randf_range(0.15, 0.45) + (1.0 - skill) * 0.3
	# movement: keep the distance the weapon likes, strafe
	strafe_t -= dt
	if strafe_t <= 0.0:
		strafe = -strafe if rng.randf() < 0.7 else strafe
		strafe_t = rng.randf_range(0.4, 1.3)
	var want: float = {"shotgun": 7.0, "smg": 14.0, "pistol": 16.0, "knife": 1.0, "sniper": 60.0}.get(cls, 28.0)
	var fwd := 0.0
	if not target_seen:
		fwd = 0.8
	elif d > want + 6.0:
		fwd = 0.7
	elif d < want - 6.0:
		fwd = -0.5
	var crouch: bool = target_seen and cls in ["rifle", "sniper"] and d > 25.0 and skill > 0.5 and burst > 0
	if cls == "knife":
		if d > 9.0 or see_t > 6.0:
			if see_t > 6.0:
				skip[target] = Time.get_ticks_msec() + 12000
			target = null      # not worth chasing with a knife: back to looting
		return [Vector2(0, 1.0), false]
	return [Vector2(strafe * (0.9 if cls != "sniper" else 0.2), fwd), crouch]

func _best_weapon(force := false) -> void:
	## primary with ammunition, else the pistol, else the knife
	var pick := "knife"
	for slot in [2, 1]:
		var w: String = a.inv[slot]
		if w != "" and a.ammo.has(w) and int(a.ammo[w][0]) + int(a.ammo[w][1]) > 0:
			pick = w
	if (force or a.cur == "knife" or not a.ammo.has(a.cur)) and pick != a.cur and a.switch_t <= 0.0:
		a.switch_to(pick)

# ------------------------------------------------------------------ travelling
func _value(l: Loot) -> float:
	match l.kind:
		"weapon":
			var slot: int = DB.W[l.id]["slot"]
			var cur: String = a.inv[slot]
			var r_new: int = Loot.WEAPON_RANK.get(l.id, 1)
			var r_old: int = Loot.WEAPON_RANK.get(cur, 0) if cur != "" else -4
			return maxf(0.0, (r_new - r_old) * 6.0)
		"ammo":
			return 5.0 if game.wants(a, l) else 0.0
		"med":
			return 3.5 if game.wants(a, l) else 0.0
		"armor":
			return 7.0 if game.wants(a, l) else 0.0
		"nade":
			return 1.0 if game.wants(a, l) else 0.0
	return 0.0

func _pick_goal() -> void:
	goal_t = 0.0
	item = null
	route = []
	var me := Vector2(a.global_position.x, a.global_position.z)
	var c1: Vector2 = game.storm["c1"]
	var r1: float = game.storm["r1"]
	var c0: Vector2 = game.storm["c"]
	var r0: float = game.storm["r"]
	var unarmed: bool = a.inv[1] == "" and a.inv[2] == ""
	var storm_near := me.distance_to(c0) > r0 - 30.0
	var outside_next := me.distance_to(c1) > maxf(r1 * 0.8, 8.0)
	if storm_near or (outside_next and (game.storm["closing"] or loot_left < 0.0)):
		var p := c1 + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, r1 * 0.55)
		goal = Vector3(p.x, 0, p.y)
		goal_kind = "zone"
		return
	if unarmed or loot_left > 0.0:
		var best: Loot = null
		var bs := 0.0
		var radius := 120.0 if unarmed else 70.0
		var now := Time.get_ticks_msec()
		for l in game.items:
			var it := l as Loot
			var d := it.global_position.distance_to(a.global_position)
			if d > radius or int(skip.get(it, 0)) > now:
				continue
			var v := _value(it)
			if unarmed and it.kind == "weapon":
				v += 30.0
			var sc := v / (d + 8.0)
			if sc > bs:
				bs = sc
				best = it
		if best:
			item = best
			goal = best.global_position
			goal_kind = "item"
			route = (best.get_meta("path", []) as Array).duplicate()
			_shortcut()
			return
	var p2 := c1 + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, maxf(r1 * 0.7, 4.0))
	goal = Vector3(p2.x, 0, p2.y)
	goal_kind = "roam"

func _travel(dt: float) -> Array:
	var reached := false
	if goal_kind != "":
		var flat := Vector2(goal.x - a.global_position.x, goal.z - a.global_position.z)
		reached = flat.length() < (0.6 if goal_kind == "item" else 3.0)
	var limit := 45.0 if goal_kind != "item" else 14.0 + route.size() * 6.0
	if goal_kind == "" or reached or goal_t > limit or (goal_kind == "item" and (item == null or not is_instance_valid(item) or item.taken)):
		if goal_kind == "item" and item and is_instance_valid(item) and not item.taken:
			skip[item] = Time.get_ticks_msec() + 60000          # could not reach it, or it was no use
		goal_kind = ""
		_pick_goal()
	elif goal_kind != "zone" and fmod(goal_t, 4.0) < dt:
		# the storm may have moved on since this goal was chosen
		var me := Vector2(a.global_position.x, a.global_position.z)
		if me.distance_to(game.storm["c"]) > float(game.storm["r"]) - 30.0:
			_pick_goal()
	var dest := goal
	if fmod(goal_t, 0.6) < dt:
		_shortcut()
	while route.size() > 0:
		var wp: Vector3 = route[0]
		if Vector2(wp.x - a.global_position.x, wp.z - a.global_position.z).length() < 1.6 and absf(wp.y - a.global_position.y) < 2.2:
			route.pop_front()
		else:
			dest = wp
			break
	var to := dest - a.global_position
	to.y = 0.0
	if to.length() < 0.3:
		return [Vector2.ZERO, false]
	var dir := to.normalized()
	# sidestep while unsticking
	if side_t > 0.0:
		side_t -= dt
		dir = (dir * 0.3 + side_dir).normalized()
	else:
		dir = _avoid(dir, dt)
	a.view_yaw = lerp_angle(a.view_yaw, atan2(-dir.x, -dir.z), 1.0 - exp(-7.0 * dt))
	a.view_pitch = lerpf(a.view_pitch, 0.0, 1.0 - exp(-3.0 * dt))
	var jump := false
	stuck_t += dt
	if stuck_t > 1.0:
		var moved := Vector2(a.global_position.x - last_p.x, a.global_position.z - last_p.z).length()
		last_p = a.global_position
		stuck_t = 0.0
		if moved < 0.6:
			stuck_n += 1
			jump = true
			side_dir = Vector3(-dir.z, 0, dir.x) * (1.0 if rng.randf() < 0.5 else -1.0)
			side_t = 0.9
			if stuck_n >= 3:
				stuck_n = 0
				_pick_goal()
		else:
			stuck_n = 0
	var ahead := Basis(Vector3.UP, a.view_yaw).inverse() * dir
	return [Vector2(ahead.x, -ahead.z).normalized(), jump]

func _walkable(from: Vector3, to: Vector3) -> bool:
	## nothing at knee or chest height between two points (doorways pass, walls and windows do not)
	var space: PhysicsDirectSpaceState3D = a.get_world_3d().direct_space_state
	for h in [0.45, 1.2]:
		var q := PhysicsRayQueryParameters3D.create(from + Vector3(0, h, 0), to + Vector3(0, h, 0), 1)
		if not space.intersect_ray(q).is_empty():
			return false
	return absf(to.y - from.y) < 1.2

func _shortcut() -> void:
	## drop the first waypoint when the next one (or the item) can be walked to directly
	while route.size() > 0:
		var nxt: Vector3 = route[1] if route.size() > 1 else goal
		if _walkable(a.global_position, nxt):
			route.pop_front()
		else:
			break

func _avoid(dir: Vector3, dt: float) -> Vector3:
	## look a couple of metres ahead at knee and chest height; turn to the first free direction
	steer_t -= dt
	if steer_t > 0.0 and steer != Vector3.ZERO:
		return (dir * 0.25 + steer).normalized()
	steer_t = 0.25
	var space: PhysicsDirectSpaceState3D = a.get_world_3d().direct_space_state
	for ang in [0.0, 0.6, -0.6, 1.1, -1.1, 1.6, -1.6]:
		var d := Basis(Vector3.UP, ang) * dir
		var blocked := false
		for h in [1.0, 1.5]:
			var from := a.global_position + Vector3(0, h, 0)
			var q := PhysicsRayQueryParameters3D.create(from, from + d * 2.2, 1)
			if not space.intersect_ray(q).is_empty():
				blocked = true
				break
		if not blocked:
			steer = d if ang != 0.0 else Vector3.ZERO
			return d
	steer = Vector3.ZERO
	return dir
