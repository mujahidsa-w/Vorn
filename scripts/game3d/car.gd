extends CharacterBody3D
## Car with realistic-feeling arcade handling:
## engine must be started (2 s), progressive throttle, 5-speed auto gearbox,
## smooth speed-sensitive steering with yaw inertia, body roll / pitch.

const GEAR_TOP := [0.0, 8.0, 13.5, 19.5, 26.0, 33.0]    # m/s at redline per gear (~120 km/h top)
const GEAR_ACC := [0.0, 2.3, 1.8, 1.35, 0.95, 0.65]      # m/s² at full throttle (gentle, realistic)
const MAX_REV := 6.0
const BRAKE := 9.0
const WHEELBASE := 2.75
const GRAV := 22.0

enum { OFF, STARTING, ON }

var kind := "robber"
var model_path := ""
var display_name := "CAR"
var world
var driver = null
var speed := 0.0
var steer := 0.0
var throttle_v := 0.0
var gear := 1
var shift_t := 0.0
var yaw_rate := 0.0
var engine_state := OFF
var start_t := 0.0
var rpm := 0.0
var siren_on := false
var t := 0.0
var visual: Node3D
var model: Node3D
var cam: Camera3D
var cam_yaw_off := 0.0
var lights_red: OmniLight3D
var lights_blue: OmniLight3D
var head_l: SpotLight3D
var head_r: SpotLight3D
var tail: OmniLight3D
var engine: AudioStreamPlayer3D
var starter: AudioStreamPlayer3D
var siren: AudioStreamPlayer3D
var siren_yelp: AudioStreamPlayer3D
var siren_mode := 0          # 0 off, 1 wail, 2 yelp
var _cam_pos := Vector3.ZERO
var _cam_h := 0.0
# online: another player is driving this car
var net_driver := ""
var net_target := Transform3D()
var net_speed := 0.0
var net_boom := false
var _acc_vis := 0.0
var _last_speed := 0.0
var _kick := Vector3.ZERO
var wheels := {}
var hp := 100.0
var wrecked := false
var on_fire_t := -1.0
var _fire_node: Node3D
var _hit_cd := 0.0
var wheel_r := 0.36
var spin := 0.0
# looks
var paint := Color(0, 0, 0, 0)       # alpha > 0: repaint the body this colour
var tail_mats: Array = []            # rear light glass (glows when braking)
var head_mats: Array = []            # headlight glass
var lights_on := false
var beams_allowed := true            # traffic: only the closest cars cast real headlight beams
var braking := false
var _smoke: Array = []               # rear tyre smoke emitters
var _skid_prev := {}                 # wheel -> last ground point
var _slip := 0.0
var _beam_t := 0.0
# traffic AI (set by street_life.gd every physics frame)
var ai_on := false
var ai_thr := 0.0
var ai_brake := false
var ai_steer := 0.0
var traffic := false


func _ready() -> void:
	floor_snap_length = 0.8
	floor_max_angle = deg_to_rad(48)
	safe_margin = 0.04
	collision_layer = 1
	collision_mask = 1 | 2 | 8
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 1.0, 4.6)
	col.shape = box
	col.position.y = 0.75
	add_child(col)
	visual = Node3D.new()
	add_child(visual)
	model = load(model_path).instantiate()
	model.rotation.y = PI
	visual.add_child(model)
	_setup_materials()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if int(Game.settings.quality) > 0 and not traffic else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if traffic:
			mi.visibility_range_end = 240.0
		var nm := str(mi.name)
		for k in ["FL", "FR", "RL", "RR"]:
			if nm.begins_with("WHEEL_" + k):
				wheels[k] = {"node": mi, "base": mi.transform}
				var ab: AABB = mi.mesh.get_aabb()
				wheel_r = maxf(ab.size.y, ab.size.z) * 0.5
	# put the tyres exactly on the ground (the collision box floats 0.25 m above it)
	var lowest := INF
	for k in wheels:
		var wn: MeshInstance3D = wheels[k].node
		var rel := Transform3D()
		var nn: Node = wn
		while nn and nn != visual:
			if nn is Node3D:
				rel = (nn as Node3D).transform * rel
			nn = nn.get_parent()
		lowest = minf(lowest, (rel * wn.mesh.get_aabb()).position.y)
	if lowest < INF:
		visual.position.y = 0.21 - lowest
	# soft contact shadow so the car sits on the road even where no light casts a shadow
	var sh := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.3, 5.0)
	qm.orientation = PlaneMesh.FACE_Y
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.75))
	g.set_color(1, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 64
	gt.height = 128
	var sm := StandardMaterial3D.new()
	sm.albedo_texture = gt
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.render_priority = -1
	qm.material = sm
	sh.mesh = qm
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sh.position = Vector3(0, 0.235, 0)
	add_child(sh)
	head_l = _spot(Vector3(-0.65, 0.7, -2.3))
	head_r = _spot(Vector3(0.65, 0.7, -2.3))
	tail = OmniLight3D.new()
	tail.light_color = Color(1.0, 0.05, 0.05)
	tail.light_energy = 0.4
	tail.omni_range = 4.0
	tail.position = Vector3(0, 0.8, 2.6)
	visual.add_child(tail)
	if kind == "police":
		lights_red = _omni(Vector3(-0.45, 1.6, 0.2), Color(1.0, 0.05, 0.1))
		lights_blue = _omni(Vector3(0.45, 1.6, 0.2), Color(0.1, 0.3, 1.0))
		siren = _audio("res://assets/audio/siren.wav", true, 30.0, -1.0)
		siren_yelp = _audio("res://assets/audio/siren_yelp.wav", true, 30.0, -1.0)
	engine = _audio("res://assets/audio/engine.wav", true, 8.0, -8.0)
	starter = _audio("res://assets/audio/engine_start.wav", false, 8.0, -4.0)
	_set_lights(false)
	cam = Camera3D.new()
	cam.top_level = true
	cam.fov = 70
	cam.far = [900.0, 1500.0, 3000.0][clampi(int(Game.settings.quality), 0, 2)]
	add_child(cam)


func _setup_materials() -> void:
	var done := {}
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			var m: Material = mi.get_active_material(si)
			if not (m is StandardMaterial3D):
				continue
			var nm := str(m.resource_name)
			var kind_m := ""
			if paint.a > 0.0 and (nm.contains("CarPaint_Max") or nm.contains("CarPaintNormal") or nm == "CarPaint"):
				kind_m = "paint"
			elif nm.contains("LightGlass_Red") or nm == "Red_Glass":
				kind_m = "tail"
			elif nm.contains("M_Light_Max") or nm == "Lights":
				kind_m = "head"
			if kind_m == "":
				continue
			if not done.has(m):
				var d: StandardMaterial3D = m.duplicate()
				if kind_m == "paint":
					d.albedo_color = paint
					d.metallic = 0.55
					d.roughness = 0.25
					d.clearcoat_enabled = true
				else:
					d.emission_enabled = true
					d.emission = Color(1.0, 0.05, 0.02) if kind_m == "tail" else Color(1.0, 0.95, 0.85)
					d.emission_energy_multiplier = 0.0
					(tail_mats if kind_m == "tail" else head_mats).append(d)
				done[m] = d
			mi.set_surface_override_material(si, done[m])
	for side in [-0.75, 0.75]:
		var sm: CPUParticles3D = null
		if world and world.fx:
			sm = world.fx.tyre_smoke()
			add_child(sm)
			sm.position = Vector3(side, 0.35, 1.45)
			_smoke.append(sm)


func _beams_wanted() -> bool:
	if not beams_allowed:
		return false
	var sky = world.sky if world else null
	return sky == null or sky.night > 0.2 or sky.fog > 0.55 or sky.rain > 0.6


func _audio(path: String, loop: bool, unit: float, vol: float) -> AudioStreamPlayer3D:
	var a := AudioStreamPlayer3D.new()
	var s = load(path)
	if loop and s is AudioStreamWAV:
		s = s.duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	a.stream = s
	a.bus = "SFX"
	a.unit_size = unit
	a.volume_db = vol
	add_child(a)
	return a


func _spot(p: Vector3) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.position = p
	l.rotation_degrees = Vector3(-6, 0, 0)
	l.light_color = Color(1.0, 0.95, 0.85)
	l.light_energy = 5.0
	l.spot_range = 45.0
	l.spot_angle = 32.0
	l.spot_attenuation = 0.8
	visual.add_child(l)
	return l


func _omni(p: Vector3, c: Color) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = p
	l.light_color = c
	l.light_energy = 0.0
	l.omni_range = 14.0
	visual.add_child(l)
	return l


func _set_lights(on: bool) -> void:
	lights_on = on
	var beams := on and _beams_wanted()
	head_l.visible = beams
	head_r.visible = beams
	_update_tail()
	for m in head_mats:
		m.emission_energy_multiplier = (3.5 if beams else 0.8) if on else 0.0


func _update_tail() -> void:
	var e := 0.0
	if braking:
		e = 4.0
	elif lights_on:
		e = 1.4
	tail.light_energy = e if e > 0.0 else 0.0
	tail.visible = e > 0.0
	for m in tail_mats:
		m.emission_energy_multiplier = e * 1.2


func enter(p) -> void:
	driver = p
	_cam_pos = global_position + global_transform.basis.z * 5.0 + Vector3(0, 2.0, 0)
	_cam_h = atan2(global_transform.basis.z.x, global_transform.basis.z.z)
	cam.global_position = _cam_pos
	cam.current = true
	Game.play_sfx("door")


func exit_car() -> void:
	driver = null
	throttle_v = 0.0
	Game.play_sfx("door")


func start_engine() -> void:
	if engine_state != OFF:
		return
	engine_state = STARTING
	start_t = 2.3
	starter.play()


func stop_engine() -> void:
	engine_state = OFF
	engine.stop()
	starter.stop()
	_set_lights(false)
	if siren_on:
		siren_on = false
		siren_mode = 0
		siren.stop()
		siren_yelp.stop()


func _key(k: Key) -> bool:
	return Input.is_physical_key_pressed(k)


func _unhandled_input(event: InputEvent) -> void:
	if driver == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_Q:
				if kind == "police":
					# Q: off -> wail -> yelp -> off (like a real siren controller)
					siren_mode = (siren_mode + 1) % 3
					siren_on = siren_mode > 0
					siren.stop()
					siren_yelp.stop()
					if siren_mode == 1:
						siren.play()
					elif siren_mode == 2:
						siren_yelp.play()
			KEY_H:
				Game.play_sfx("horn")
			KEY_I:
				if engine_state == OFF:
					start_engine()
				elif engine_state == ON and absf(speed) < 1.0:
					stop_engine()
			KEY_W:
				if engine_state == OFF:
					start_engine()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not Game.touch:
		cam_yaw_off = clampf(cam_yaw_off - event.relative.x * 0.004, -2.6, 2.6)


func push(v: Vector3) -> void:
	_kick += v


var _idle_t := 0.0


func _physics_process(delta: float) -> void:
	t += delta
	# parked and untouched: skip the physics step (big saving with many parked / waiting cars)
	if driver == null and not ai_on and net_driver == "" and on_fire_t < 0.0 and absf(speed) < 0.05 and _kick.length_squared() < 0.0001 and is_on_floor():
		_idle_t += delta
		if _idle_t > 1.0 and fmod(t, 0.5) > delta:
			return
	else:
		_idle_t = 0.0
	var thr_in := 0.0
	var brake_in := false
	var steer_in := 0.0
	var hand := false
	_hit_cd = maxf(0.0, _hit_cd - delta)
	if on_fire_t > 0.0:
		on_fire_t -= delta
		if on_fire_t <= 0.0:
			explode_car(null)
	if driver != null and (Game.touch or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED) and not wrecked:
		thr_in = float(_key(KEY_W))
		brake_in = _key(KEY_S)
		steer_in = float(_key(KEY_A)) - float(_key(KEY_D))
		hand = _key(KEY_SPACE)
	elif ai_on and driver == null and not wrecked and net_driver == "":
		thr_in = ai_thr
		brake_in = ai_brake
		steer_in = ai_steer
	# engine start sequence
	if engine_state == STARTING:
		start_t -= delta
		if start_t <= 0.0:
			engine_state = ON
			engine.play()
			_set_lights(true)
	var running := engine_state == ON
	if not running:
		thr_in = 0.0
	# pedal moves progressively, releases quicker
	throttle_v = move_toward(throttle_v, thr_in, delta * (0.6 if thr_in > throttle_v else 2.0))
	# automatic gearbox
	shift_t = maxf(0.0, shift_t - delta)
	if gear < 5 and speed > GEAR_TOP[gear] * 0.94 and shift_t <= 0.0:
		gear += 1
		shift_t = 0.32
	elif gear > 1 and speed < GEAR_TOP[gear - 1] * 0.62:
		gear -= 1
	var on_floor := is_on_floor()
	if on_floor:
		if brake_in and speed > 0.4:
			speed = move_toward(speed, 0.0, BRAKE * delta)
		elif brake_in and running:
			speed = move_toward(speed, -MAX_REV, 2.2 * delta)
		elif throttle_v > 0.01 and speed < -0.3:
			speed = move_toward(speed, 0.0, BRAKE * delta)
		elif throttle_v > 0.01 and shift_t <= 0.0:
			var top: float = GEAR_TOP[5]
			var a: float = GEAR_ACC[gear] * throttle_v * (1.0 - pow(clampf(speed / top, 0.0, 1.0), 3.0))
			speed += a * delta
		else:
			# rolling resistance + air drag: long natural coast
			speed = move_toward(speed, 0.0, (0.35 + 0.0009 * speed * speed + (0.6 if running else 0.0) * (1.0 - throttle_v)) * delta)
		if hand:
			speed = move_toward(speed, 0.0, 7.0 * delta)
	var was_braking := braking
	braking = running and ((brake_in and speed > 0.4) or (hand and absf(speed) > 1.0))
	if braking != was_braking:
		_update_tail()
	_acc_vis = lerpf(_acc_vis, (speed - _last_speed) / maxf(delta, 0.001), 1.0 - exp(-delta * 5.0))
	_last_speed = speed
	# rpm (0..1)
	var lo: float = GEAR_TOP[gear - 1] * 0.62 if gear > 1 else 0.0
	var target_rpm := clampf((speed - lo) / maxf(GEAR_TOP[gear] - lo, 1.0), 0.0, 1.0) * 0.8 + 0.12 + throttle_v * 0.08
	if shift_t > 0.0:
		target_rpm *= 0.75
	rpm = lerpf(rpm, target_rpm if running else 0.0, 1.0 - exp(-delta * 6.0))
	# steering: slow, smooth, speed sensitive
	var max_steer := lerpf(0.6, 0.11, clampf(absf(speed) / 40.0, 0.0, 1.0))
	if hand:
		max_steer *= 1.35
	var target_steer := steer_in * max_steer
	var rate := 0.9
	if target_steer * steer < 0.0:
		rate = 0.6            # changing from right to left (or back) is slower, like a real steering wheel
	elif absf(target_steer) < absf(steer):
		rate = 1.3            # self-centering
	rate *= lerpf(1.0, 0.7, clampf(absf(speed) / 35.0, 0.0, 1.0))
	steer = move_toward(steer, target_steer, delta * rate)
	var want_yaw := speed / WHEELBASE * tan(steer) if on_floor else yaw_rate * 0.98
	yaw_rate = lerpf(yaw_rate, want_yaw, 1.0 - exp(-delta * (1.9 if not hand else 4.5)))
	rotate_y(yaw_rate * delta)
	var fwd := -global_transform.basis.z
	var vy := velocity.y
	velocity = fwd * speed + Vector3(_kick.x, 0, _kick.z)
	_kick.x = move_toward(_kick.x, 0, delta * 12.0)
	_kick.z = move_toward(_kick.z, 0, delta * 12.0)
	if _kick.y > 0.0:
		vy = _kick.y
		_kick.y = 0.0
		on_floor = false
	if on_floor:
		velocity.y = minf(vy, 0.0) - 2.0 * delta
	else:
		velocity.y = vy - GRAV * delta
	move_and_slide()
	for i in get_slide_collision_count():
		var cl := get_slide_collision(i)
		var n := cl.get_normal()
		var other := cl.get_collider()
		if absf(n.y) < 0.6:
			var hit := absf(fwd.dot(n))
			var imp := absf(speed) * hit
			if other and other.has_method("take_damage") and other != driver:
				# hit a person or another car
				if _hit_cd <= 0.0 and absf(speed) > 2.5:
					_hit_cd = 0.4
					if other is CharacterBody3D and other.has_method("push") and not other.has_method("hit_by_car"):
						other.push(fwd * speed * 0.6)
						other.take_damage(imp * 1.5, driver, fwd)
						speed *= 0.55
						take_damage(imp * 0.4, null)
					elif other.has_method("hit_by_car"):
						other.hit_by_car(self, fwd * speed)
						speed *= 0.85
			elif hit > 0.25 and absf(speed) > 2.0:
				# wall: lose speed, slide along it, small bounce
				speed *= (1.0 - 0.7 * hit)
				yaw_rate *= 0.4
				global_position += n * 0.05
				if imp > 12.0 and _hit_cd <= 0.0:
					_hit_cd = 0.5
					take_damage((imp - 12.0) * 1.6, null)
					Game.play_sfx("door", 0.6, 2.0)
	if global_position.y < -200.0 and world:
		world.respawn_car(self)
	# visual body motion
	var up := get_floor_normal() if is_on_floor() else Vector3.UP
	var local_up := global_transform.basis.inverse() * up
	var tx := atan2(-local_up.z, local_up.y) + clampf(_acc_vis * 0.006, -0.05, 0.05)
	var tz := atan2(local_up.x, local_up.y) - clampf(yaw_rate * speed * 0.0045, -0.07, 0.07)
	visual.rotation.x = lerp_angle(visual.rotation.x, tx, 1.0 - exp(-delta * 6.0))
	visual.rotation.z = lerp_angle(visual.rotation.z, tz, 1.0 - exp(-delta * 5.0))
	# wheels: roll with speed, front wheels steer
	spin = fmod(spin + speed / maxf(wheel_r, 0.2) * delta, TAU)
	for k in wheels:
		var w: Dictionary = wheels[k]
		var st := steer * 1.4 if k.begins_with("F") else 0.0
		var b: Transform3D = w.base
		w.node.transform = Transform3D(Basis(Vector3.UP, st) * Basis(Vector3.RIGHT, spin) * b.basis, b.origin)
	if engine.playing:
		engine.pitch_scale = 0.55 + rpm * 1.5
		engine.volume_db = (-10.0 + throttle_v * 4.0) - (6.0 if traffic else 0.0)
	_tyres(delta, on_floor, brake_in, hand)


## Skid marks and tyre smoke: hard braking, handbrake slides, wheelspin and fast cornering.
func _tyres(delta: float, on_floor: bool, brake_in: bool, hand: bool) -> void:
	var lat := absf(yaw_rate * speed)
	var slip := 0.0
	if on_floor:
		if hand and absf(speed) > 5.0:
			slip = 1.0
		elif brake_in and speed > 13.0:
			slip = 0.8
		elif throttle_v > 0.85 and gear == 1 and speed < 7.0 and speed > 0.3 and engine_state == ON:
			slip = 0.7
		if lat > 9.0:
			slip = maxf(slip, clampf((lat - 9.0) / 6.0, 0.3, 1.0))
	_slip = lerpf(_slip, slip, 1.0 - exp(-delta * 10.0))
	var on := _slip > 0.25
	for sm in _smoke:
		sm.emitting = on and (world == null or world.sky == null or world.sky.wet < 0.6)
	if world == null or world.fx == null:
		return
	if not on:
		_skid_prev.clear()
		return
	var b := global_transform.basis
	var n := get_floor_normal() if is_on_floor() else Vector3.UP
	for k in ["RL", "RR"]:
		var lp := Vector3(-0.78 if k == "RL" else 0.78, 0.0, 1.35)
		var p := global_position + b * lp
		if _skid_prev.has(k):
			world.fx.skid(_skid_prev[k], p, n, _slip)
		_skid_prev[k] = p
	if hand and absf(speed) > 5.0:
		for k in ["FL", "FR"]:
			var lp := Vector3(-0.78 if k == "FL" else 0.78, 0.0, -1.35)
			var p := global_position + b * lp
			if _skid_prev.has(k):
				world.fx.skid(_skid_prev[k], p, n, _slip * 0.6)
			_skid_prev[k] = p
	if _slip > 0.5 and engine.playing and randf() < delta * 3.0:
		Game.play_sfx("skid", randf_range(0.9, 1.1), clampf(-4.0 - _cam_dist() * 0.3, -24.0, -4.0))


func _cam_dist() -> float:
	var c: Camera3D = get_viewport().get_camera_3d()
	return c.global_position.distance_to(global_position) if c else 10.0


func _process(delta: float) -> void:
	if net_driver != "" and net_target != Transform3D():
		var xf := global_transform
		var p := xf.origin.lerp(net_target.origin, 1.0 - exp(-delta * 10.0))
		if p.distance_to(net_target.origin) > 15.0:
			p = net_target.origin
		var q := xf.basis.get_rotation_quaternion().slerp(net_target.basis.get_rotation_quaternion(), 1.0 - exp(-delta * 10.0))
		global_transform = Transform3D(Basis(q), p)
		cine_update(delta, net_speed)
	_beam_t -= delta
	if _beam_t <= 0.0 and lights_on:
		_beam_t = 0.5
		var want := _beams_wanted()
		if want != head_l.visible:
			_set_lights(true)
	if kind == "police":
		var ph := fmod(t * 3.0, 1.0)
		lights_red.light_energy = (6.0 if ph < 0.5 else 0.0) if siren_on else 0.0
		lights_blue.light_energy = (6.0 if ph >= 0.5 else 0.0) if siren_on else 0.0
	if driver != null:
		# camera heading follows the car smoothly (no snapping when the car turns)
		var car_back := global_transform.basis.z
		car_back.y = 0
		var target_h := atan2(car_back.x, car_back.z) + cam_yaw_off
		_cam_h = lerp_angle(_cam_h, target_h, 1.0 - exp(-delta * 2.2))
		var back := Vector3(sin(_cam_h), 0, cos(_cam_h))
		var dist := 4.4 + absf(speed) * 0.02
		var want := global_position + back * dist + Vector3(0, 1.75, 0)
		_cam_pos = _cam_pos.lerp(want, 1.0 - exp(-delta * 3.5))
		cam.global_position = _cam_pos
		cam.look_at(global_position + Vector3(0, 1.05, 0) - back * 2.0, Vector3.UP)
		cam.fov = lerpf(cam.fov, 64.0 + absf(speed) * 0.06, 1.0 - exp(-delta * 2.0))
		cam_yaw_off = lerpf(cam_yaw_off, 0.0, 1.0 - exp(-delta * 1.2))


## Cinematics: the car is moved by a script; this keeps wheels, body and engine alive.
func cine_update(delta: float, spd: float, steer_amt := 0.0) -> void:
	speed = spd
	steer = steer_amt
	spin = fmod(spin + speed / maxf(wheel_r, 0.2) * delta, TAU)
	for k in wheels:
		var w: Dictionary = wheels[k]
		var st := steer * 1.4 if k.begins_with("F") else 0.0
		var b: Transform3D = w.base
		w.node.transform = Transform3D(Basis(Vector3.UP, st) * Basis(Vector3.RIGHT, spin) * b.basis, b.origin)
	if engine_state != ON and spd > 0.5:
		engine_state = ON
		engine.play()
		_set_lights(true)
	if engine.playing:
		rpm = clampf(spd / 30.0, 0.15, 1.0)
		engine.pitch_scale = 0.55 + rpm * 1.4
		engine.volume_db = -4.0


func kmh() -> int:
	return int(absf(speed) * 3.6)


# ---------------------------------------------------------------- damage
func take_damage(amount: float, attacker, _dir := Vector3.ZERO) -> void:
	if wrecked or amount <= 0.0:
		return
	hp -= amount
	if hp <= 35.0 and on_fire_t < 0.0 and world:
		# engine catches fire, explodes a few seconds later (like GTA)
		on_fire_t = randf_range(5.0, 8.0)
		_fire_node = world.fx.fire_patch(Vector3(0, 1.0, -1.6), 30.0, 0.8, self)
	if hp <= 0.0:
		explode_car(attacker)


func hit_by_car(other, vel: Vector3) -> void:
	push(vel * 0.5)
	take_damage(vel.length() * 0.8, other.driver if other else null)


func explode_car(attacker) -> void:
	if wrecked:
		return
	wrecked = true
	hp = 0.0
	if world and world.get("net") and not net_boom:
		world.net.send_car_boom(world.cars.find(self))
	on_fire_t = -1.0
	stop_engine()
	speed *= 0.3
	if world:
		world.explode(global_position + Vector3(0, 0.8, 0), 9.0, attacker, self)
		if driver != null:
			world.kill_driver(self, attacker)
		world.fx.fire_patch(Vector3(0, 1.1, 0), 40.0, 1.6, self)
	push(Vector3(randf_range(-2, 2), 6.5, randf_range(-2, 2)))
	# burnt look
	var burnt := StandardMaterial3D.new()
	burnt.albedo_color = Color(0.05, 0.045, 0.04)
	burnt.roughness = 0.95
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = burnt
	head_l.visible = false
	head_r.visible = false
	tail.light_energy = 0.0
	lights_on = false
	braking = false
	for sm in _smoke:
		sm.emitting = false
	if kind == "police":
		siren_on = false
		siren_mode = 0
		siren.stop()
		siren_yelp.stop()
