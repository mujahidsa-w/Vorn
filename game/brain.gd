class_name Brain
extends Node
## Мозг бота (и автопилот игрока для проверок): зрение, прицеливание с ошибкой и временем реакции,
## стрельба очередями, движение по сетке навигации, роли в раунде (заход на точку, закладка, удержание, разминирование).

var a: Actor
var game
var world: World
var skill := 0.5
var path := PackedVector3Array()
var pi := 0
var goal := Vector3.INF
var goal_tag := ""
var target: Actor
var see_t := 0.0
var lost_t := 9.0
var last_seen := Vector3.INF
var sense_t := 0.0
var aim_err := Vector2.ZERO
var err_t := 0.0
var strafe := 1.0
var strafe_t := 0.0
var burst := 0
var burst_pause := 0.0
var role := ""
var hold_i := 0
var hold_t := 0.0
var stuck_t := 0.0
var last_pos := Vector3.ZERO
var look_yaw := 0.0
var repath_t := 0.0
var jump_cd := 0.0
var alert := Vector3.INF
var alert_t := 0.0
var crouch_fire := false
var rng := RandomNumberGenerator.new()
var plan_t := 0.0
var scope_t := 0.0
var nade_t := 0.0
var nade_at := Vector3.ZERO

func setup(actor: Actor, g) -> void:
	a = actor
	game = g
	world = g.world
	rng.seed = hash(actor.nick) + 77
	var d := int(G.settings["difficulty"])
	# разброс мастерства одинаковый у обеих команд (по номеру бойца), иначе одна пятёрка стабильно сильнее другой
	var idx := int(String(actor.name).get_slice("_", 1)) if String(actor.name).contains("_") else 0
	skill = [0.28, 0.55, 0.82][clampi(d, 0, 2)] + [0.0, 0.06, -0.06, 0.03, -0.03][idx % 5]

func new_round() -> void:
	path = PackedVector3Array()
	goal = Vector3.INF
	goal_tag = ""
	target = null
	see_t = 0.0
	lost_t = 9.0
	last_seen = Vector3.INF
	alert = Vector3.INF
	hold_t = 0.0
	burst = 0
	plan_t = 0.0
	look_yaw = a.view_yaw

var holding := false               # стоит на точке и держит проход
var hold_adv := 0.0                # преимущество держащего: быстрее реагирует на первого вышедшего
var hold_look := Vector3.INF

func react_time() -> float:
	return lerpf(0.62, 0.2, skill) * (0.75 if hold_adv > 0.0 else 1.0)

# ------------------------------------------------------------------ зрение
func _sense() -> void:
	var eye := a.eye()
	var fwd := -Basis(Vector3.UP, a.view_yaw).z
	var best: Actor = null
	var bd := 1e9
	for e in game.actors:
		var o := e as Actor
		if not o.alive or o.team == a.team:
			continue
		var to := o.eye() - eye
		var d := to.length()
		if d > 75.0:
			continue
		var dn := to / maxf(d, 0.001)
		var in_fov := fwd.dot(Vector3(dn.x, 0, dn.z).normalized()) > 0.38 or d < 4.0
		if a.flash_t > 0.6:
			in_fov = d < 2.5
		if not in_fov:
			continue
		if not world.los(eye, o.eye() - Vector3(0, 0.12, 0), a.hit_rids):
			if not world.los(eye, o.global_position + Vector3(0, 0.9 * (1.0 - 0.3 * o.crouch_t), 0), a.hit_rids):
				continue
		if game.smoke_blocks(eye, o.eye()):
			continue
		o.set_meta("seen_ms", Time.get_ticks_msec())
		if d < bd:
			bd = d
			best = o
	if best:
		if target != best:
			see_t = 0.0 if target == null else see_t * 0.5
			_new_err()
			if holding and a.speed_h() < 0.6:
				aim_err *= 0.65
				hold_adv = 2.5
		target = best
		last_seen = best.global_position
		lost_t = 0.0
		game.report(a.team, best.global_position)
	else:
		if target:
			lost_t = 0.0
		target = null

func _new_err() -> void:
	var e := lerpf(7.0, 1.4, skill)
	aim_err = Vector2(rng.randf_range(-e, e), rng.randf_range(-e * 0.6, e * 0.6))

func hear(pos: Vector3) -> void:
	if target == null and a.alive and a.global_position.distance_to(pos) < 32.0:
		alert = pos
		alert_t = 3.5

# ------------------------------------------------------------------ главный шаг
func think(dt: float) -> void:
	if not a.alive:
		return
	sense_t -= dt
	if sense_t <= 0.0:
		sense_t = 0.12
		_sense()
	lost_t += dt
	hold_adv -= dt
	if a.speed_h() > 1.5:
		holding = false
	jump_cd -= dt
	alert_t -= dt
	var wish := Vector2.ZERO
	var want_jump := false
	var want_crouch := false
	var want_walk := false
	if game.frozen():
		_turn_to(look_yaw, 0.0, dt, 200.0)
		a.move_step(Vector2.ZERO, false, false, false, dt)
		return
	var pt0 := a.plant_t
	var dt0 := a.defuse_t
	if target and target.alive:
		see_t += dt
		var res := _combat(dt)
		wish = res[0]
		want_crouch = res[1]
	else:
		see_t = 0.0
		burst = 0
		if a.scoped:
			a.try_fire(true)
		_objective(dt)
		if _try_nade(dt):
			a.move_step(Vector2.ZERO, false, false, false, dt)
			return
		var mv := _follow(dt)
		wish = mv[0]
		want_jump = mv[1]
		want_walk = goal_tag == "hold_walk"
		# перезарядка в спокойной обстановке
		if a.ammo.has(a.cur) and a.mag() < int(a.wd()["mag"]) * 0.5 and a.reload_t <= 0.0 and lost_t > 2.0:
			a.start_reload()
		_best_weapon()
	# закладку и разминирование бросаем, если в этом кадре их не продолжили (иначе боец остаётся стоять)
	if a.plant_t >= 0.0 and a.plant_t == pt0:
		game.try_plant(a, false)
	if a.defuse_t >= 0.0 and a.defuse_t == dt0:
		game.try_defuse(a, false)
	a.move_step(wish, want_jump, want_crouch, want_walk, dt)

func _try_nade(dt: float) -> bool:
	## граната туда, где только что видели противника
	if nade_t > 0.0:
		nade_t -= dt
		var to := nade_at - a.eye()
		var d := Vector2(to.x, to.z).length()
		_turn_to(atan2(-to.x, -to.z), clampf(deg_to_rad(10.0 + d * 1.1), 0.1, 0.7), dt, 400.0)
		if nade_t <= 0.35 and a.throwing <= 0.0 and DB.W[a.cur]["cls"] == "nade" and a.fire_cd <= 0.0:
			a.try_fire(d < 9.0)
		return true
	if a.nades.is_empty() or lost_t > 2.5 or lost_t < 0.6 or not last_seen.is_finite() or game.state == game.S.FREEZE:
		return false
	var dist := a.global_position.distance_to(last_seen)
	if dist < 7.0 or dist > 26.0 or rng.randf() > 0.012:
		return false
	var id: String = a.nades[rng.randi() % a.nades.size()]
	a.switch_to(id)
	nade_at = last_seen + Vector3(0, 0.5, 0)
	nade_t = 1.0
	return true

func _best_weapon() -> void:
	if a.plant_t >= 0.0 or a.cur == "c4" and goal_tag == "plant" or nade_t > 0.0 or a.throwing > 0.0:
		return
	var w: String = a.inv[1] if a.inv[1] != "" else a.inv[2]
	if w != "" and a.ammo.has(w) and a.ammo[w][0] + a.ammo[w][1] <= 0:
		w = a.inv[2] if a.inv[2] != "" and a.ammo[a.inv[2]][0] + a.ammo[a.inv[2]][1] > 0 else "knife"
	if w != "" and a.cur != w and a.switch_t <= 0.0 and a.throwing <= 0.0:
		a.switch_to(w)

# ------------------------------------------------------------------ бой
func _combat(dt: float) -> Array:
	var eye := a.eye()
	var tp := target.eye()
	var chest := target.global_position + Vector3(0, lerpf(1.22, 0.85, target.crouch_t), 0)
	var aim_at := chest.lerp(tp - Vector3(0, 0.03, 0), clampf(skill * 0.8, 0.0, 0.7))
	var to := aim_at - eye
	var dist := to.length()
	var yaw := atan2(-to.x, -to.z)
	var pitch := atan2(to.y, Vector2(to.x, to.z).length())
	# ошибка наводки затухает, пока цель на виду
	err_t += dt
	var k := exp(-see_t * lerpf(1.6, 3.6, skill))
	var ex := deg_to_rad(aim_err.x) * k + deg_to_rad(sin(err_t * 2.3) * lerpf(1.3, 0.35, skill))
	var ey := deg_to_rad(aim_err.y) * k + deg_to_rad(cos(err_t * 1.7) * lerpf(0.9, 0.25, skill))
	# поправка на отдачу
	var comp := lerpf(0.25, 0.9, skill)
	yaw += ex - deg_to_rad(a.punch.y) * comp
	pitch += ey - deg_to_rad(a.punch.x) * comp
	_turn_to(yaw, pitch, dt, lerpf(210.0, 520.0, skill))
	look_yaw = a.view_yaw
	_best_weapon()
	var d := a.wd()
	var cls: String = d["cls"]
	var dy := absf(wrapf(yaw - a.view_yaw, -PI, PI))
	var dp := absf(pitch - a.view_pitch)
	var tol := atan2(0.32, dist) + deg_to_rad(1.0)
	var on_target := dy < tol and dp < tol * 1.3
	var wish := Vector2.ZERO
	var crouch := false
	strafe_t -= dt
	if strafe_t <= 0.0:
		strafe_t = rng.randf_range(0.5, 1.3)
		strafe = -strafe if rng.randf() < 0.75 else strafe
		crouch_fire = rng.randf() < 0.25 and dist > 9.0
	if cls == "knife":
		wish = Vector2(0, 1)
		if dist < 1.7 and on_target:
			a.try_fire(dist < 1.3 and rng.randf() < 0.3)
		return [wish, false]
	if cls == "nade" or cls == "c4":
		_best_weapon()
		return [Vector2(strafe, 0), false]
	if a.reload_t > 0.0 or a.mag() == 0:
		if a.mag() == 0 and a.reload_t <= 0.0:
			# пустой магазин: пистолет, если есть патроны, иначе перезарядка
			var sec: String = a.inv[2]
			if a.cur != sec and sec != "" and a.ammo.has(sec) and a.ammo[sec][0] > 0 and dist < 25.0:
				a.switch_to(sec)
			else:
				a.start_reload()
		return [Vector2(strafe, -0.6), false]
	burst_pause -= dt
	if see_t >= react_time() and on_target and burst_pause <= 0.0:
		if cls == "sniper":
			if not a.scoped:
				a.try_fire(true)
				scope_t = 0.22 + (1.0 - skill) * 0.3
			else:
				scope_t -= dt
				if scope_t <= 0.0 and a.speed_h() < 1.0:
					a.try_fire()
		else:
			if a.try_fire():
				burst += 1
				var lim := 30
				if d.get("auto", false):
					lim = int(lerpf(3, 9, clampf(1.0 - dist / 30.0, 0.0, 1.0))) + rng.randi_range(0, 2)
				else:
					lim = 1
				if burst >= lim:
					burst = 0
					burst_pause = (rng.randf_range(0.12, 0.3) if d.get("auto", false) else rng.randf_range(0.1, 0.28)) * lerpf(1.5, 0.9, skill)
	# движение в бою: стоим при стрельбе на дистанции, шагаем в стороны вблизи и между очередями
	var firing := burst > 0 or (see_t >= react_time() and on_target)
	if dist > 10.0 and firing and cls != "smg":
		wish = Vector2.ZERO
		crouch = crouch_fire
	elif dist < 3.0:
		wish = Vector2(strafe, -0.8)
	else:
		wish = Vector2(strafe, 0.0)
	return [wish, crouch]

func _turn_to(yaw: float, pitch: float, dt: float, speed_deg: float) -> void:
	var s := deg_to_rad(speed_deg) * dt
	var dy := wrapf(yaw - a.view_yaw, -PI, PI)
	# чем больше угол, тем быстрее доворот
	var ky := clampf(absf(dy) * 3.2, 0.25, 1.0)
	a.view_yaw = wrapf(a.view_yaw + clampf(dy, -s * ky, s * ky), -PI, PI)
	var dp := pitch - a.view_pitch
	a.view_pitch = clampf(a.view_pitch + clampf(dp, -s * 0.7, s * 0.7), -1.4, 1.4)

# ------------------------------------------------------------------ задачи раунда
func _set_goal(p: Vector3, tag: String) -> void:
	if goal.is_finite() and goal.distance_to(p) < 1.0 and goal_tag == tag and path.size() > 0:
		return
	goal = p
	goal_tag = tag
	path = world.path(a.global_position, p)
	pi = 0

func _objective(dt: float) -> void:
	plan_t -= dt
	hold_t -= dt
	var b: Dictionary = game.bomb
	var st: String = b["state"]
	if lost_t < 3.5 and last_seen.is_finite() and st != "planted":
		_set_goal(last_seen, "chase")
		return
	if alert_t > 0.0 and alert.is_finite() and goal_tag in ["hold", "hold_walk", ""]:
		var to := alert - a.global_position
		look_yaw = atan2(-to.x, -to.z)
	if a.team == "t":
		if st == "planted":
			_guard(b["pos"], "guard")
			return
		if st == "dropped":
			if game.nearest_alive("t", b["pos"]) == a:
				_set_goal(b["pos"], "bomb")
				return
		var site: String = game.t_plan
		if a.inv[5] == "c4":
			var spot: Vector3 = game.plant_spot(site, a)
			if world.site_at(a.global_position) == site and a.global_position.distance_to(spot) < 1.2:
				goal_tag = "plant"
				path = PackedVector3Array()
				if a.cur != "c4":
					a.switch_to("c4")
				else:
					game.try_plant(a, true)
				return
			_set_goal(spot, "plant_go")
			return
		_guard(world.rect_center(world.data["site_" + site]), "site_" + site)
	else:
		if st == "planted":
			var bp: Vector3 = b["pos"]
			var defuser: Actor = game.nearest_alive("ct", bp)
			if defuser == a:
				if a.global_position.distance_to(bp) < 1.3:
					path = PackedVector3Array()
					goal_tag = "defuse"
					var to2 := bp - a.eye()
					look_yaw = atan2(-to2.x, -to2.z)
					game.try_defuse(a, true)
					return
				_set_goal(bp, "defuse_go")
			else:
				_guard(bp, "retake")
			return
		# удержание: своя точка, либо переход на точку, где замечен противник
		if plan_t <= 0.0:
			plan_t = rng.randf_range(4.0, 7.0)
			var hot: String = game.hot_site("ct")
			if hot != "" and hot != role and rng.randf() < 0.55 and role != "":
				role = hot
				hold_t = 0.0
		if role == "":
			role = "a"
		_hold(role)

func _hold(key: String) -> void:
	var pts: Array = world.data["hold"].get(key, [])
	if pts.is_empty():
		return
	if hold_t <= 0.0 or not goal_tag.begins_with("hold"):
		hold_t = rng.randf_range(7.0, 16.0)
		hold_i = rng.randi() % pts.size()
		var p: Array = pts[hold_i]
		_set_goal(World.w(p[0], p[1]), "hold")
		# куда смотреть с точки: навстречу пути, которым сюда придёт атака (от её базы)
		hold_look = Vector3.INF
		var tb: Vector3 = world.spawn("t", 0).origin
		var ap := world.path(tb, goal)
		if ap.size() > 4:
			var acc := 0.0
			var k := ap.size() - 1
			while k > 0 and acc < 9.0:
				acc += ap[k].distance_to(ap[k - 1])
				k -= 1
			hold_look = ap[k]
	if path.size() > 0 and pi >= path.size():
		holding = a.speed_h() < 0.6
		# на месте: держать проход, откуда ждём атаку, либо смотреть туда, где шумели
		if not (alert_t > 0.0):
			var c := World.w(42, 30) if key != "mid" else World.w(42, 12)
			if hold_look.is_finite():
				c = hold_look
			var to := c - a.global_position
			look_yaw = atan2(-to.x, -to.z) + sin(Time.get_ticks_msec() * 0.0006 + hash(a.nick) % 7) * 0.22

func _guard(center: Vector3, tag: String) -> void:
	if hold_t <= 0.0 or goal_tag != tag:
		hold_t = rng.randf_range(6.0, 12.0)
		var best := center
		for i in 8:
			var p := center + Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))
			var c := world.cell(p)
			if not world.astar.is_point_solid(c):
				best = world.cell_center(c)
				break
		_set_goal(best, tag)
	if path.size() > 0 and pi >= path.size():
		var to := center - a.global_position
		look_yaw = atan2(-to.x, -to.z) + sin(Time.get_ticks_msec() * 0.0008 + hash(a.nick) % 5) * 0.9

# ------------------------------------------------------------------ движение по пути
func _follow(dt: float) -> Array:
	var pos := a.global_position
	var jump := false
	if path.size() == 0 or pi >= path.size():
		_turn_to(look_yaw, 0.0, dt, 150.0)
		return [Vector2.ZERO, false]
	var wp := path[pi]
	var to := wp - pos
	to.y = 0
	var reach := 0.55 if pi < path.size() - 1 else 0.35
	while to.length() < reach:
		pi += 1
		if pi >= path.size():
			return [Vector2.ZERO, false]
		wp = path[pi]
		to = wp - pos
		to.y = 0
	var dir := to.normalized()
	# смотреть вперёд по пути (на пару точек дальше), чтобы повороты были плавными
	var ahead := path[mini(pi + 3, path.size() - 1)] - pos
	if ahead.length() > 0.5:
		look_yaw = atan2(-ahead.x, -ahead.z)
	_turn_to(look_yaw, 0.0, dt, 260.0)
	var local := Basis(Vector3.UP, a.view_yaw).inverse() * dir
	var wish := Vector2(local.x, -local.z)
	# застревание
	stuck_t += dt
	if stuck_t > 0.7:
		if pos.distance_to(last_pos) < 0.25 and a.max_speed() > 0.5:
			if jump_cd <= 0.0:
				jump = true
				jump_cd = 0.9
			else:
				path = world.path(pos, goal)
				pi = mini(1, path.size())
		last_pos = pos
		stuck_t = 0.0
	return [wish, jump]
