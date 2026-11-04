extends Node
## 30-second intro cinematic: a police cruiser chases the robbers' Mustang through
## night-time LA, the robbers stop and a shootout breaks out, the getaway car explodes.
## It is recorded to a video (see tools) and played while the game loads.

const Car = preload("res://scripts/game3d/car.gd")
const Rig = preload("res://scripts/game3d/rig.gd")
const W = preload("res://scripts/game3d/weapons.gd")

const LENGTH := 30.0

var world
var cam: Camera3D
var t := 0.0
var cum: PackedFloat32Array
var path: Array = []
var hy := PackedFloat32Array()
var tans: Array = []
var _hq_r := Quaternion()
var _hq_p := Quaternion()
var _hq_init := false
var robber
var police
var s_rob := 0.0
var s_pol := 0.0
var v_rob := 24.0
var v_pol := 25.0
var stop_s := 0.0
var actors: Array = []        # {rig, holder, weapon, team, id, next}
var spawned := false
var exploded := false
var ui: CanvasLayer
var bar_t: ColorRect
var bar_b: ColorRect
var title: Label
var sub: Label
var fade: ColorRect
var start_i := 300
var done := false
var _shot := -1
var _ry_r := INF
var _ry_p := INF
var _look := Vector3.ZERO


func run() -> void:
	_route_len()
	_smooth_path()
	robber = _car("mustang_gt", "robber")
	police = _car("police_gt500", "police")
	police.siren_on = true
	police.siren_mode = 1
	police.siren.play()
	s_rob = cum[start_i] + 40.0
	s_pol = s_rob - 26.0
	stop_s = s_rob + 24.0 * 14.0
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.far = 2500.0
	world.add_child(cam)
	cam.current = true
	_build_ui()


func _route_len() -> void:
	cum = PackedFloat32Array()
	cum.append(0.0)
	for i in range(1, world.route.size()):
		cum.append(cum[i - 1] + (world.route[i] as Vector3).distance_to(world.route[i - 1]))
	# pick the longest gently-curving stretch for the chase
	var best := 300
	var best_score := -INF
	for i in range(60, world.route.size() - 120, 10):
		var turn := 0.0
		for k in range(i, i + 90, 6):
			var a: Vector3 = world.route[k + 6] - world.route[k]
			var b: Vector3 = world.route[k + 12] - world.route[k + 6]
			a.y = 0
			b.y = 0
			turn += absf(a.normalized().signed_angle_to(b.normalized(), Vector3.UP))
		var score := -turn
		# no pillars / walls in the cars' path for the whole chase (~450 m)
		var hits := 0
		var k2 := i
		while k2 < mini(i + 70, world.route.size() - 2):
			var p0: Vector3 = world.route[k2]
			var fw: Vector3 = (world.route[k2 + 1] as Vector3) - p0
			fw.y = 0
			fw = fw.normalized()
			var sd := fw.cross(Vector3.UP)
			for lat in [-2.5, 0.0, 2.5]:
				var a0: Vector3 = p0 + Vector3(0, 1.0, 0) + sd * lat
				if not world._ray(a0, a0 + fw * 9.0).is_empty():
					hits += 1
				if not world._ray(a0 + Vector3(0, 4.0, 0), a0 + fw * 9.0 + Vector3(0, 4.0, 0)).is_empty():
					hits += 1
			k2 += 1
		score -= hits * 2.0
		if score > best_score:
			best_score = score
			best = i
	start_i = best


## A smoothed copy of the route (moving average) so the cars follow a clean curve.
func _smooth_path() -> void:
	path = []
	var n: int = world.route.size()
	for i in n:
		var acc := Vector3.ZERO
		var cnt := 0
		for k in range(-4, 5):
			var j := clampi(i + k, 0, n - 1)
			acc += world.route[j]
			cnt += 1
		var avg := acc / cnt
		path.append(Vector3(avg.x, (world.route[i] as Vector3).y, avg.z))
	tans = []
	for i in n:
		var a: Vector3 = path[maxi(i - 1, 0)]
		var b: Vector3 = path[mini(i + 1, n - 1)]
		var d := b - a
		d.y = 0
		tans.append(d.normalized() if d.length() > 0.01 else Vector3.FORWARD)
	cum = PackedFloat32Array()
	cum.append(0.0)
	for i in range(1, n):
		cum.append(cum[i - 1] + Vector2(path[i].x - path[i - 1].x, path[i].z - path[i - 1].z).length())
	# road height profile, measured once and smoothed along the road (no per-frame jitter, no lag)
	var raw := PackedFloat32Array()
	for i in n:
		var p: Vector3 = path[i]
		var side := (tans[i] as Vector3).cross(Vector3.UP).normalized()
		var sum := 0.0
		var cnt := 0
		for lat in [-2.0, 0.0, 2.0]:
			var q: Vector3 = p + side * lat
			var g: Dictionary = world._ray(q + Vector3(0, 2.5, 0), q - Vector3(0, 8.0, 0))
			if not g.is_empty():
				sum += float(g.position.y)
				cnt += 1
		raw.append(sum / cnt if cnt > 0 else p.y)
	hy = PackedFloat32Array()
	for i in n:
		var acc := 0.0
		var c := 0
		for k in range(-3, 4):
			acc += raw[clampi(i + k, 0, n - 1)]
			c += 1
		hy.append(acc / c)


func _at(s: float, lateral := 0.0) -> Transform3D:
	var i := cum.bsearch(s)
	i = clampi(i, 2, cum.size() - 3)
	var seg := maxf(cum[i] - cum[i - 1], 0.01)
	var f := clampf((s - cum[i - 1]) / seg, 0.0, 1.0)
	# Catmull-Rom through the smoothed points: continuous position and heading
	var p0: Vector3 = path[i - 2]
	var p1: Vector3 = path[i - 1]
	var p2: Vector3 = path[i]
	var p3: Vector3 = path[i + 1]
	var f2 := f * f
	var f3 := f2 * f
	var p := 0.5 * ((2.0 * p1) + (-p0 + p2) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * f3)
	var tan: Vector3 = (tans[i - 1] as Vector3).slerp(tans[i], f).normalized()
	var nrm := tan.cross(Vector3.UP).normalized()
	p += nrm * lateral
	p.y = lerpf(hy[i - 1], hy[i], f)
	var slope := (hy[i] - hy[i - 1]) / seg
	var dir := Vector3(tan.x, slope, tan.z).normalized()
	return Transform3D(Basis.looking_at(dir, Vector3.UP), p)


func _car(model: String, kind: String):
	var c := Car.new()
	c.model_path = "res://assets/models/cars/%s.glb" % model
	c.display_name = "CINE"
	c.kind = kind
	c.world = world
	world.add_child(c)
	c.set_physics_process(false)
	return c


func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 20
	world.add_child(ui)
	bar_t = ColorRect.new()
	bar_t.color = Color.BLACK
	Game.lay(bar_t, [0, 0, 1, 0], [0, 0, 0, 0])
	ui.add_child(bar_t)
	bar_b = ColorRect.new()
	bar_b.color = Color.BLACK
	Game.lay(bar_b, [0, 1, 1, 1], [0, 0, 0, 0])
	ui.add_child(bar_b)
	title = Game.label("", 92, Game.font_wide, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	Game.lay(title, [0, 0.5, 1, 0.5], [0, -80, 0, 30])
	ui.add_child(title)
	sub = Game.label("", 26, Game.font_tag, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	Game.lay(sub, [0, 0.5, 1, 0.5], [0, 34, 0, 80])
	ui.add_child(sub)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	Game.lay(fade, [0, 0, 1, 1], [0, 0, 0, 0])
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(fade)


func _process(delta: float) -> void:
	if cam == null or done:
		return
	t += delta
	_drive(delta)
	_shots(delta)
	_fight(delta)
	_overlay()
	if t >= LENGTH:
		done = true
		Engine.time_scale = 1.0
		get_tree().quit()


# ---------------------------------------------------------------- the chase
func _drive(delta: float) -> void:
	var want_mode := 2 if (t > 10.5 and t < 17.0) else 1
	if want_mode != police.siren_mode:
		police.siren_mode = want_mode
		police.siren.stop()
		police.siren_yelp.stop()
		if want_mode == 1:
			police.siren.play()
		else:
			police.siren_yelp.play()
	if t < 15.0:
		v_rob = lerpf(v_rob, 27.0, delta * 0.3)
		v_pol = lerpf(v_pol, 27.6 if s_rob - s_pol > 14.0 else 26.5, delta * 0.5)
	else:
		# robbers slam the brakes, police stop behind them
		v_rob = move_toward(v_rob, 0.0, 15.0 * delta)
		var gap := s_rob - s_pol
		v_pol = move_toward(v_pol, 0.0 if gap < 13.0 else v_rob + 2.0, 14.0 * delta)
		if gap < 11.0:
			v_pol = minf(v_pol, v_rob)
	s_rob += v_rob * delta
	s_pol += v_pol * delta
	var weave := sin(t * 0.9) * 1.2 if t < 15.0 else 0.0
	var spin := clampf((t - 15.0) / 1.5, 0.0, 1.0) * 0.55 if t >= 15.0 else 0.0
	var xr := _at(s_rob, 1.6 + weave)
	# smooth the ground height (no jitter from bumpy collision), origin 0.21 m below the tyres
	var xp := _at(s_pol, -1.2 - weave * 0.6)
	_ry_r = xr.origin.y
	_ry_p = xp.origin.y
	# heading is low-pass filtered too, so the bodies never twitch
	var qr := xr.basis.rotated(Vector3.UP, spin).get_rotation_quaternion()
	var qp := xp.basis.get_rotation_quaternion()
	if not _hq_init:
		_hq_init = true
		_hq_r = qr
		_hq_p = qp
	_hq_r = _hq_r.slerp(qr, 1.0 - exp(-delta * 6.0))
	_hq_p = _hq_p.slerp(qp, 1.0 - exp(-delta * 6.0))
	robber.global_transform = Transform3D(Basis(_hq_r), Vector3(xr.origin.x, _ry_r - 0.21, xr.origin.z))
	police.global_transform = Transform3D(Basis(_hq_p), Vector3(xp.origin.x, _ry_p - 0.21, xp.origin.z))
	robber.cine_update(delta, v_rob, -weave * 0.08)
	police.cine_update(delta, v_pol, weave * 0.05)


# ---------------------------------------------------------------- camera
func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _shots(delta: float) -> void:
	var rp: Vector3 = robber.global_position
	var pp: Vector3 = police.global_position
	var rf: Vector3 = -robber.global_transform.basis.z
	var rr: Vector3 = robber.global_transform.basis.x
	var pos: Vector3
	var look: Vector3
	if t < 6.0:
		# aerial establishing shot sweeping down onto the chase
		var k := _ease(t / 6.0)
		var mid := rp.lerp(pp, 0.5)
		pos = mid + rf * lerpf(60.0, 22.0, k) + rr * lerpf(-40.0, -12.0, k) + Vector3(0, lerpf(45.0, 7.0, k), 0)
		look = mid + Vector3(0, 1.0, 0)
	elif t < 11.0:
		# low tracking shot beside the Mustang, police lights behind
		var k2 := (t - 6.0) / 5.0
		pos = rp + rr * -6.0 + rf * lerpf(5.0, 0.5, k2) + Vector3(0, 1.0, 0)
		look = rp.lerp(pp, 0.25) + Vector3(0, 0.8, 0)
	elif t < 15.0:
		# chase cam behind the police car
		pos = pp + police.global_transform.basis.z * 6.5 + Vector3(0, 3.0, 0)
		look = rp + Vector3(0, 1.0, 0)
	elif t < 18.5:
		# the stop: side view of both cars
		var mid2 := rp.lerp(pp, 0.5)
		pos = mid2 + rr * 13.0 + Vector3(0, 2.2, 0) + rf * (t - 15.0) * 0.6
		look = mid2 + Vector3(0, 0.8, 0)
	elif t < 23.0:
		# shootout: over the cops' shoulders towards the robbers
		var k3 := (t - 18.5) / 4.5
		var behind := (pp - rp).normalized()
		pos = pp + behind * 6.0 + rr * lerpf(2.6, -1.8, k3) + Vector3(0, 2.3, 0)
		look = rp + Vector3(0, 1.1, 0)
	elif t < 26.5:
		# reverse angle: from behind the getaway car, watching the cops
		var behind2 := (rp - pp).normalized()
		pos = rp + behind2 * 6.0 + rr * -3.5 + Vector3(0, 1.4 + (t - 23.0) * 0.4, 0)
		look = rp.lerp(pp, 0.4) + Vector3(0, 1.0, 0)
	else:
		# slow crane up over the burning wreck
		var k4 := _ease((t - 26.5) / 3.5)
		pos = rp + rr * 9.0 + rf * 6.0 + Vector3(0, lerpf(2.5, 14.0, k4), 0)
		look = rp + Vector3(0, 0.5, 0)
	# keep the camera out of walls and bridges
	# keep a clear view: if a pillar or wall is in the way, rise above it
	for k in 6:
		var q := PhysicsRayQueryParameters3D.create(look, pos + Vector3(0, k * 2.0, 0))
		q.exclude = [robber.get_rid(), police.get_rid()]
		if world.space.intersect_ray(q).is_empty():
			pos += Vector3(0, k * 2.0, 0)
			break
	# hard cuts between shots, light smoothing inside a shot
	var shot := 0
	for edge in [6.0, 11.0, 15.0, 18.5, 23.0, 26.5]:
		if t >= edge:
			shot += 1
	var cut := shot != _shot
	if cut or cam.global_position == Vector3.ZERO:
		_shot = shot
		cam.global_position = pos
	cam.global_position = cam.global_position.lerp(pos, 1.0 - exp(-delta * 12.0))
	if cut or _look == Vector3.ZERO:
		_look = look
	_look = _look.lerp(look, 1.0 - exp(-delta * 10.0))
	cam.look_at(_look, Vector3.UP)
	var shake := 0.0
	if exploded and t < 25.5:
		shake = (25.5 - t) * 0.08
	cam.rotation += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.05


# ---------------------------------------------------------------- the shootout
func _actor(team: String, wid: String, xf: Transform3D, variant: String) -> void:
	var holder := Node3D.new()
	world.add_child(holder)
	holder.global_transform = xf
	var model := Node3D.new()
	model.rotation.y = PI
	holder.add_child(model)
	var r := Rig.new()
	model.add_child(r)
	r.setup(variant)
	var d: Dictionary = W.DATA[wid]
	var wn: Node3D = load(d.path).instantiate()
	model.add_child(wn)
	wn.position = d.pos
	wn.rotation_degrees = d.rot
	r.weapon = wn
	r.weapon_id = wid
	r.grips = W.grips_for(wid, wn)
	r.aiming = true
	actors.append({"rig": r, "holder": holder, "w": wn, "team": team, "id": wid, "next": randf_range(0.2, 0.8), "crouch": false})


func _fight(delta: float) -> void:
	if t >= 17.0 and not spawned:
		spawned = true
		var rp: Vector3 = robber.global_position
		var pp: Vector3 = police.global_position
		var to_p := (pp - rp)
		to_p.y = 0
		to_p = to_p.normalized()
		var side := to_p.cross(Vector3.UP).normalized()
		var face_p := Basis.looking_at(to_p, Vector3.UP)
		var face_r := Basis.looking_at(-to_p, Vector3.UP)
		_actor("rob", "akm", Transform3D(face_p, _g(rp + side * 1.9 + to_p * 0.6)), "hero")
		_actor("rob", "akm", Transform3D(face_p, _g(rp - side * 2.0 - to_p * 0.5)), "hero")
		_actor("cop", "m4", Transform3D(face_r, _g(pp + side * 1.9 - to_p * 0.4)), "cop")
		_actor("cop", "m4", Transform3D(face_r, _g(pp - side * 1.9 - to_p * 0.9)), "guard")
		actors[3].crouch = true
	for a in actors:
		var r = a.rig
		r.stance = 1 if a.crouch else 0
		r.update(delta, Vector2.ZERO, true, "rpg" if a.id == "rpg" else "rifle", 1.0, 0.0)
		if r.dead or t > 26.0:
			continue
		a.next -= delta
		if a.next <= 0.0 and t > 18.0:
			a.next = randf_range(0.09, 0.14) if randf() < 0.75 else randf_range(0.5, 1.1)
			_shoot(a)
	if t >= 24.6 and not exploded:
		exploded = true
		world.fx.explosion(robber.global_position + Vector3(0, 0.8, 0), 9.0)
		world.fx.fire_patch(Vector3(0, 1.1, 0), 30.0, 1.6, robber)
		Game.play_sfx("explosion", 0.95, 4.0)
		robber.cine_update(0.0, 0.0)
		for a in actors:
			if a.team == "rob":
				a.rig.dead = true
				a.rig.death_clip = "death_back"
				a.holder.global_position += (a.holder.global_position - robber.global_position).normalized() * 0.8
		var burnt := StandardMaterial3D.new()
		burnt.albedo_color = Color(0.05, 0.045, 0.04)
		burnt.roughness = 0.95
		for mi in robber.model.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = burnt
		robber.head_l.visible = false
		robber.head_r.visible = false
	if t >= 25.0 and t < 26.4:
		Engine.time_scale = 0.4
	else:
		Engine.time_scale = 1.0


func _g(p: Vector3) -> Vector3:
	# local ground only (never snap onto a bridge overhead)
	var g: Dictionary = world._ray(p + Vector3(0, 2.5, 0), p - Vector3(0, 8.0, 0))
	return g.position if not g.is_empty() else p


func _shoot(a: Dictionary) -> void:
	var wn: Node3D = a.w
	var mp: Vector3 = wn.global_transform * W.muzzle_local(a.id, wn)
	var foes: Array = []
	for b in actors:
		if b.team != a.team and not b.rig.dead:
			foes.append(b)
	var target: Vector3
	if foes.is_empty():
		target = (police.global_position if a.team == "rob" else robber.global_position) + Vector3(0, 1.0, 0)
	else:
		target = (foes[randi() % foes.size()].holder as Node3D).global_position + Vector3(0, 1.2, 0)
	target += Vector3(randf_range(-1.6, 1.6), randf_range(-0.6, 0.9), randf_range(-1.6, 1.6))
	var dir := (target - mp).normalized()
	world.fx.muzzle(mp, dir)
	var hit: Dictionary = world._ray(mp + dir * 0.3, mp + dir * 120.0)
	var end: Vector3 = hit.position if not hit.is_empty() else mp + dir * 120.0
	world.fx.tracer(mp, end)
	if not hit.is_empty():
		world.fx.impact(end, hit.normal, false)
	a.rig.recoil = minf(a.rig.recoil + 0.4, 1.0)
	var d := cam.global_position.distance_to(mp)
	Game.play_sfx("shot_ak" if a.id == "akm" else "shot_rifle", randf_range(0.94, 1.06), clampf(2.0 - d * 0.12, -20.0, 0.0))


# ---------------------------------------------------------------- overlay
func _overlay() -> void:
	var h := 110.0 * _ease(t / 1.5)
	bar_t.offset_bottom = h
	bar_b.offset_top = -h
	fade.color.a = clampf(1.0 - t / 1.2, 0.0, 1.0) + clampf((t - 28.6) / 1.2, 0.0, 1.0)
	if t > 1.5 and t < 5.5:
		title.text = ""
		sub.text = "LOS ANGELES  •  02:14 AM"
		sub.modulate.a = clampf(minf(t - 1.5, 5.5 - t), 0.0, 1.0)
	elif t > 26.6:
		title.text = "COPS  &  ROBBERS"
		sub.text = "TWO SIDES  •  ONE CITY"
		var k := clampf((t - 26.6) / 1.0, 0.0, 1.0)
		title.modulate.a = k
		sub.modulate.a = k
	else:
		title.text = ""
		sub.text = ""
