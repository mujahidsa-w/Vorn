class_name Vehicle
extends VehicleBody3D
## Drivable vehicles of the battle royale: a two-seat dune buggy and a dirt bike.
##   - Godot's raycast-wheel physics on the height-map desert; low centre of mass, a righting torque keeps the bike up;
##   - the models are built here (tube-frame buggy, dirt bike); the bike runs on four physics wheels with two drawn,
##     leaning into the turns;
##   - the engine note is synthesised from the speed; bullets wear the hull down until it burns and blows up;
##     anyone in the way at speed is run over.
## The vehicle's front is its +Z axis (Godot's vehicle convention).

const SPEC := {
	"buggy": {"name": "باغي", "mass": 720.0, "engine": 1700.0, "rev": 800.0, "brake": 9.0, "steer": 0.5, "top": 27.0, "hp": 700.0,
		"r": 0.43, "track": 0.86, "front": 1.28, "rear": -1.18, "wy": 0.36, "seat": Vector3(-0.34, 0.12, -0.05), "cam": 6.8, "hum": 24.0,
		"box": Vector3(1.5, 0.55, 3.1), "box_y": 0.2},
	"bike": {"name": "دراجة", "mass": 260.0, "engine": 920.0, "rev": 340.0, "brake": 4.0, "steer": 0.42, "top": 31.0, "hp": 380.0,
		"r": 0.36, "track": 0.3, "front": 0.74, "rear": -0.7, "wy": 0.3, "seat": Vector3(0, 0.36, -0.15), "cam": 5.2, "hum": 46.0,
		"box": Vector3(0.45, 0.55, 1.75), "box_y": 0.3},
}
const PAINT := [Color(0.80, 0.55, 0.20), Color(0.55, 0.12, 0.08), Color(0.34, 0.40, 0.24), Color(0.85, 0.80, 0.70), Color(0.15, 0.30, 0.55)]

var kind := "buggy"
var spec: Dictionary
var game: Node
var hp := 700.0
var driver: Actor = null
var controls := Vector3.ZERO          # steer (-1 left .. 1 right), throttle (-1 .. 1), handbrake (0/1)
var wrecked := false
var paint := Color.WHITE
var wheels: Array[VehicleWheel3D] = []
var _steer := 0.0
var _visual: Node3D                   # the drawn model (leans on the bike)
var _bike_wheels: Array[Node3D] = []  # drawn wheels of the bike: [front fork, front wheel, rear wheel]
var _spin := 0.0
var _engine: EngineSound
var _upside := 0.0
var _smoke: CPUParticles3D
var _look_quiet := 0.0
var _hit_cd := {}                     # actor -> time of the last run-over hit
var autopilot := false                # controls apply with nobody seated (physics checks)
var remote := false                   # online client: the host drives the physics, snapshots place it
var _net_pos := Vector3.ZERO
var _net_rot := Quaternion.IDENTITY
var net_vel := Vector3.ZERO

func setup(g: Node, k: String, c: Color) -> void:
	game = g
	kind = k
	spec = SPEC[k]
	paint = c
	hp = float(spec["hp"])

func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	remote = game != null and game.get("net_role") == "client"
	if remote:
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
		_net_pos = global_position
		_net_rot = global_basis.get_rotation_quaternion()
	mass = float(spec["mass"])
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.15, 0)
	angular_damp = 1.2 if kind == "buggy" else 3.0
	set_meta("vehicle", self)
	set_meta("wood", false)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = spec["box"]
	cs.shape = bs
	cs.position = Vector3(0, float(spec["box_y"]) + (spec["box"] as Vector3).y * 0.5 - 0.2, 0)
	add_child(cs)
	_visual = Node3D.new()
	_visual.name = "Model"
	add_child(_visual)
	if kind == "buggy":
		_buggy_model()
	else:
		_bike_model()
	var r: float = spec["r"]
	var tr: float = spec["track"]
	for z in [float(spec["front"]), float(spec["rear"])]:
		for sx in [-1.0, 1.0]:
			var w := VehicleWheel3D.new()
			w.position = Vector3(sx * tr, float(spec["wy"]), z)
			w.wheel_radius = r
			w.wheel_rest_length = 0.24
			w.suspension_travel = 0.28
			w.suspension_stiffness = 32.0 if kind == "buggy" else 40.0
			w.suspension_max_force = mass * 9.8 * 1.6
			w.damping_compression = 2.3
			w.damping_relaxation = 3.2
			w.wheel_friction_slip = 3.6 if kind == "buggy" else 4.2
			w.wheel_roll_influence = 0.12 if kind == "buggy" else 0.04
			w.use_as_traction = true if kind == "buggy" else z < 0.0
			w.use_as_steering = z > 0.0
			add_child(w)
			wheels.append(w)
			if kind == "buggy":
				w.add_child(_wheel_mesh(r, 0.32, sx))
	_engine = EngineSound.new()
	_engine.hum = float(spec["hum"])
	add_child(_engine)
	for g in find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).visibility_range_end = 260.0

# ------------------------------------------------------------------ driving
func net_pose(pos: Vector3, rot: Quaternion, vel: Vector3, steer: float) -> void:
	_net_pos = pos
	_net_rot = rot
	net_vel = vel
	_steer = steer

func net_wreck() -> void:
	if wrecked:
		return
	hp = 0.0
	_explode(null)

func speed() -> float:
	return (net_vel if remote else linear_velocity).dot(global_basis.z)

func _physics_process(dt: float) -> void:
	if remote:
		var k := 1.0 - exp(-14.0 * dt)
		if global_position.distance_to(_net_pos) > 20.0:
			global_position = _net_pos
		else:
			global_position = global_position.lerp(_net_pos + net_vel * dt, k)
		global_basis = Basis(global_basis.get_rotation_quaternion().slerp(_net_rot, k))
		if driver:
			driver.global_position = global_transform * (spec["seat"] as Vector3)
		return
	if wrecked:
		return
	if driver == null and not autopilot and linear_velocity.length() < 0.4 and angular_velocity.length() < 0.4:
		# parked: hold still and let the body sleep (no forces, no scripts working on it)
		engine_force = 0.0
		brake = float(spec["brake"]) * 0.6
		return
	var fwd := global_basis.z
	var v := linear_velocity
	var speed := v.dot(fwd)
	var c := controls if (driver and driver.alive) or autopilot else Vector3(0, 0, 1)
	var top: float = spec["top"]
	var throttle := c.y
	# engine: forward with a soft limit at top speed, the brakes when pulling back while rolling forward, then reverse
	if throttle > 0.05:
		engine_force = float(spec["engine"]) * throttle * clampf(1.0 - speed / top, 0.0, 1.0)
		brake = 0.0
	elif throttle < -0.05:
		if speed > 1.5:
			engine_force = 0.0
			brake = float(spec["brake"]) * -throttle
		else:
			engine_force = -float(spec["rev"]) * -throttle * clampf(1.0 + speed / 8.0, 0.0, 1.0)
			brake = 0.0
	else:
		engine_force = 0.0
		brake = float(spec["brake"]) * (0.15 if driver else 0.6)
	if c.z > 0.5:
		brake = float(spec["brake"]) * 1.4
		engine_force = 0.0
	# steering eases off with speed
	var max_s: float = float(spec["steer"]) * clampf(1.0 - absf(speed) / 45.0, 0.38, 1.0)
	_steer = move_toward(_steer, -c.x * max_s, dt * 2.6)
	steering = _steer
	# keep upright: the bike balances itself, the buggy is helped back onto its wheels
	var up := global_basis.y
	var roll := global_basis.x.dot(Vector3.UP)
	if kind == "bike":
		# roll = sin of the tilt about the forward axis; a spring-damper about that axis holds it level
		apply_torque(fwd * (-roll * mass * 9.0 - angular_velocity.dot(fwd) * mass * 1.6))
	if up.y < 0.35 and v.length() < 2.0:
		_upside += dt
		if _upside > 2.0:
			_upside = 0.0
			var yaw := atan2(fwd.x, fwd.z)
			global_basis = Basis(Vector3.UP, yaw)
			global_position += Vector3(0, 1.2, 0)
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
	else:
		_upside = 0.0
	# the sand holds a car a little more than a road would
	apply_central_force(-up * mass * 0.6 * minf(absf(speed), 20.0))
	_run_over(speed)
	_seat_driver()

func _seat_driver() -> void:
	if driver == null:
		return
	if not driver.alive:
		leave(driver, true)
		return
	driver.global_position = global_transform * (spec["seat"] as Vector3)
	driver.velocity = linear_velocity

func _run_over(speed: float) -> void:
	if absf(speed) < 6.0 or game == null:
		return
	var fwd := global_basis.z * signf(speed)
	var front := global_position + fwd * ((spec["box"] as Vector3).z * 0.5 + 0.2)
	var now := Time.get_ticks_msec()
	for a in game.actors:
		var o := a as Actor
		if not o.alive or o == driver or o.vehicle != null:
			continue
		var d := o.global_position + Vector3(0, 0.6, 0) - front
		if d.length() < 1.3 + (spec["box"] as Vector3).x * 0.3 and now - int(_hit_cd.get(o, 0)) > 600:
			_hit_cd[o] = now
			var dmg := clampf(absf(speed) * 5.0, 30.0, 160.0)
			o.velocity += fwd * absf(speed) * 0.7 + Vector3(0, 4.0, 0)
			o.take_damage(dmg, driver, "runover", "chest", global_position)
			game.sound_at("land", o.global_position, 0.0, null)

# ------------------------------------------------------------------ seats
func can_enter(a: Actor) -> bool:
	return not wrecked and driver == null and a.alive and a.global_position.distance_to(global_position) < 3.4

func enter(a: Actor) -> void:
	if not can_enter(a):
		return
	driver = a
	a.vehicle = self
	a.vehicle_cd = Time.get_ticks_msec() + 500
	a.prone = false
	a.lean_want = 0.0
	a.scoped = false
	a.collision_layer = 0
	a.collision_mask = 0
	a.crouch_t = 1.0
	a._apply_crouch()
	var fwd := global_basis.z
	a.view_yaw = atan2(-fwd.x, -fwd.z)
	a.view_pitch = -0.12
	if a == game.player:
		game.player.cam_mode = "drive"
	if a == game.player:
		(a as Player).ensure_body()
	if a.body:
		a.body.visible = true
	game.sound_at("draw", global_position, -4.0, a)

func leave(a: Actor, forced := false) -> void:
	if driver != a:
		return
	driver = null
	controls = Vector3.ZERO
	a.vehicle = null
	a.vehicle_cd = Time.get_ticks_msec() + 500
	a.crouch_t = 0.0
	if a.alive:
		a.collision_layer = 2
		a.collision_mask = 1
		# out of the driver's side, or over the top if that is blocked
		var side := global_transform * Vector3(-(spec["box"] as Vector3).x * 0.5 - 0.7, 0.4, 0)
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.8, 0), side + Vector3(0, 0.4, 0), 1, [get_rid()])
		if not space.intersect_ray(q).is_empty():
			side = global_position + Vector3(0, 2.2, 0)
		a.global_position = side
		a.velocity = linear_velocity * 0.6
		if linear_velocity.length() > 9.0 and not forced:
			a.take_damage((linear_velocity.length() - 9.0) * 6.0, null, "fall", "legs", a.global_position)
	if a == game.player:
		game.player.cam_mode = ""
	pass

# ------------------------------------------------------------------ damage
func damage(n: float, by: Actor) -> void:
	if wrecked or remote:
		return
	hp -= n
	if hp < float(spec["hp"]) * 0.3 and _smoke == null:
		_smoke = _make_smoke()
	if hp <= 0.0:
		_explode(by)

func _explode(by: Actor) -> void:
	wrecked = true
	engine_force = 0.0
	brake = 2.0
	game.fx.explosion(global_position + Vector3(0, 0.6, 0), 6.0)
	game.sound_at("he_explode", global_position, 4.0, null)
	if driver:
		var d := driver
		leave(d, true)
		d.take_damage(150.0, by, "vehicle", "chest", global_position)
	for a in game.actors:
		var o := a as Actor
		if o.alive and o.vehicle == null:
			var dist := o.global_position.distance_to(global_position)
			if dist < 6.0:
				o.take_damage(120.0 * (1.0 - dist / 6.0), by, "vehicle", "chest", global_position)
	_engine.queue_free()
	for g in _visual.find_children("*", "MeshInstance3D", true, false):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.07, 0.065, 0.06)
		m.roughness = 1.0
		(g as MeshInstance3D).material_override = m
	if _smoke == null:
		_smoke = _make_smoke()
	_smoke.amount = 60

func _make_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 24
	p.lifetime = 4.0
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0.4, 0.6, 0.2)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.8
	var qm := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = game.fx.soft_tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	qm.material = m
	p.mesh = qm
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(0.12, 0.11, 0.1, 0.7), Color(0.3, 0.3, 0.3, 0.0)])
	p.color_ramp = g
	p.position = Vector3(0, 0.8, float(spec["front"]) * 0.6)
	add_child(p)
	p.emitting = true
	return p

# ------------------------------------------------------------------ camera, sound, drawn parts
func _process(dt: float) -> void:
	var speed := speed()
	if _engine:
		_engine.rpm = clampf(absf(speed) / float(spec["top"]), 0.0, 1.0)
		_engine.load_k = absf(controls.y) if driver else 0.0
		_engine.on = driver != null and not wrecked
	if kind == "bike":
		_bike_visual(dt, speed)
	if driver and game and driver == game.player:
		_chase_camera(dt, speed)

func _chase_camera(dt: float, speed: float) -> void:
	var p: Player = game.player
	if p.look_acc.length() > 0.0005:
		_look_quiet = 0.0
	else:
		_look_quiet += dt
	p.look_acc = Vector2.ZERO
	# after a moment without looking around, the camera swings back behind the vehicle
	if _look_quiet > 1.2 and absf(speed) > 4.0:
		var fwd := global_basis.z * signf(speed)
		var want := atan2(-fwd.x, -fwd.z)
		p.view_yaw = lerp_angle(p.view_yaw, want, 1.0 - exp(-1.8 * dt))
	var pivot := global_position + Vector3(0, 1.5, 0)
	var pitch := clampf(p.view_pitch, -0.7, 0.4) - 0.2
	var off := Basis(Vector3.UP, p.view_yaw) * Basis(Vector3.RIGHT, pitch) * Vector3(0, 0, float(spec["cam"]))
	var want_pos := pivot + off
	var q := PhysicsRayQueryParameters3D.create(pivot, want_pos, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		want_pos = (hit["position"] as Vector3) + ((pivot - want_pos).normalized() * 0.3)
	var xf := Transform3D(Basis.IDENTITY, want_pos).looking_at(pivot + Vector3(0, 0.3, 0), Vector3.UP)
	p.head.global_transform = xf

func _bike_visual(dt: float, speed: float) -> void:
	_spin += speed / float(spec["r"]) * dt
	var lean := clampf(-_steer * absf(speed) * 0.045, -0.45, 0.45)
	_visual.rotation.z = lerpf(_visual.rotation.z, lean, 1.0 - exp(-6.0 * dt))
	if _bike_wheels.size() == 3:
		_bike_wheels[0].rotation.y = _steer
		_bike_wheels[1].rotation.x = _spin
		_bike_wheels[2].rotation.x = _spin

# ------------------------------------------------------------------ models
func _mat(c: Color, metal := 0.2, rough := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m

func _box(parent: Node3D, sz: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = sz
	mi.mesh = b
	mi.position = pos
	mi.rotation = rot
	mi.material_override = m
	parent.add_child(mi)
	return mi

func _tube(parent: Node3D, a: Vector3, b: Vector3, r: float, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = a.distance_to(b)
	cm.radial_segments = 10
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	var up := (b - a).normalized()
	var x := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.basis = Basis(x, up, x.cross(up))
	mi.position = (a + b) * 0.5
	parent.add_child(mi)

func _wheel_mesh(r: float, w: float, side: float) -> Node3D:
	var root := Node3D.new()
	var tire := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = w
	cm.radial_segments = 22
	tire.mesh = cm
	tire.rotation.z = PI / 2.0
	tire.material_override = _mat(Color(0.07, 0.07, 0.07), 0.0, 0.92)
	root.add_child(tire)
	var rim := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = r * 0.55
	rm.bottom_radius = r * 0.55
	rm.height = w + 0.01
	rm.radial_segments = 14
	rim.mesh = rm
	rim.rotation.z = PI / 2.0
	rim.material_override = _mat(Color(0.55, 0.55, 0.52), 0.8, 0.35)
	root.add_child(rim)
	# lugs so the spin reads
	for i in 5:
		var a := TAU * i / 5.0
		var lug := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w + 0.03, 0.05, r * 0.32)
		lug.mesh = bm
		lug.position = Vector3(0, sin(a) * r * 0.33, cos(a) * r * 0.33)
		lug.rotation.x = a
		lug.material_override = _mat(Color(0.25, 0.25, 0.24), 0.7, 0.4)
		root.add_child(lug)
	return root

func _buggy_model() -> void:
	var v := _visual
	var body := _mat(paint, 0.35, 0.45)
	var frame := _mat(Color(0.12, 0.12, 0.12), 0.7, 0.4)
	var dark := _mat(Color(0.06, 0.06, 0.06), 0.1, 0.8)
	var seat := _mat(Color(0.16, 0.13, 0.11), 0.0, 0.9)
	# floor pan, nose and engine deck
	_box(v, Vector3(1.25, 0.08, 2.5), Vector3(0, 0.0, 0.0), frame)
	_box(v, Vector3(1.3, 0.26, 0.9), Vector3(0, 0.2, 1.25), body, Vector3(-0.32, 0, 0))
	_box(v, Vector3(1.2, 0.14, 0.5), Vector3(0, 0.36, 1.62), body, Vector3(-0.1, 0, 0))
	_box(v, Vector3(1.1, 0.42, 0.8), Vector3(0, 0.28, -1.12), dark)
	_box(v, Vector3(1.25, 0.06, 0.95), Vector3(0, 0.52, -1.1), body)
	# side pods (paint) and fenders over the wheels
	for sx in [-1.0, 1.0]:
		_box(v, Vector3(0.14, 0.3, 1.4), Vector3(sx * 0.66, 0.16, 0.0), body)
		_box(v, Vector3(0.36, 0.06, 0.8), Vector3(sx * 0.86, 0.66, 1.28), body)
		_box(v, Vector3(0.36, 0.06, 0.8), Vector3(sx * 0.86, 0.66, -1.18), body)
		# exhausts
		_tube(v, Vector3(sx * 0.3, 0.3, -1.45), Vector3(sx * 0.32, 0.42, -1.7), 0.045, frame)
	# seats
	for sx in [-0.34, 0.34]:
		_box(v, Vector3(0.48, 0.12, 0.5), Vector3(sx, 0.12, -0.12), seat)
		_box(v, Vector3(0.48, 0.62, 0.12), Vector3(sx, 0.45, -0.42), seat, Vector3(-0.18, 0, 0))
	# steering wheel
	_tube(v, Vector3(-0.34, 0.3, 0.55), Vector3(-0.34, 0.62, 0.32), 0.02, frame)
	var sw := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.13
	tm.outer_radius = 0.16
	sw.mesh = tm
	sw.position = Vector3(-0.34, 0.64, 0.3)
	sw.rotation.x = deg_to_rad(60.0)
	sw.material_override = dark
	v.add_child(sw)
	# roll cage
	var c := [Vector3(-0.62, 0.05, 0.55), Vector3(0.62, 0.05, 0.55), Vector3(-0.62, 0.05, -0.65), Vector3(0.62, 0.05, -0.65)]
	var t := [Vector3(-0.5, 1.32, 0.15), Vector3(0.5, 1.32, 0.15), Vector3(-0.52, 1.36, -0.55), Vector3(0.52, 1.36, -0.55)]
	for i in 4:
		_tube(v, c[i], t[i], 0.035, frame)
	_tube(v, t[0], t[1], 0.035, frame)
	_tube(v, t[2], t[3], 0.035, frame)
	_tube(v, t[0], t[2], 0.035, frame)
	_tube(v, t[1], t[3], 0.035, frame)
	_tube(v, t[2], Vector3(-0.3, 0.5, -1.4), 0.03, frame)
	_tube(v, t[3], Vector3(0.3, 0.5, -1.4), 0.03, frame)
	_tube(v, Vector3(-0.62, 0.05, 0.55), Vector3(-0.55, 0.3, 1.55), 0.03, frame)
	_tube(v, Vector3(0.62, 0.05, 0.55), Vector3(0.55, 0.3, 1.55), 0.03, frame)
	# lamps
	var lamp := _mat(Color(1.0, 0.95, 0.8))
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.93, 0.75)
	lamp.emission_energy_multiplier = 1.5
	for sx in [-0.42, 0.42]:
		var l := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.07
		cm.bottom_radius = 0.08
		cm.height = 0.06
		l.mesh = cm
		l.rotation.x = PI / 2.0
		l.position = Vector3(sx, 1.38, 0.2)
		l.material_override = lamp
		v.add_child(l)
	# spare wheel on the back
	var spare := _wheel_mesh(0.34, 0.24, 1.0)
	spare.position = Vector3(0, 0.62, -1.62)
	spare.rotation.y = PI / 2.0
	v.add_child(spare)

func _bike_model() -> void:
	var v := _visual
	var body := _mat(paint, 0.3, 0.4)
	var frame := _mat(Color(0.14, 0.14, 0.15), 0.75, 0.35)
	var dark := _mat(Color(0.05, 0.05, 0.05), 0.1, 0.85)
	var chrome := _mat(Color(0.7, 0.7, 0.68), 0.9, 0.25)
	var r: float = spec["r"]
	var hub_y: float = float(spec["wy"]) - 0.24 + 0.03
	# rear wheel and swing arm
	var rw := Node3D.new()
	rw.position = Vector3(0, hub_y, float(spec["rear"]))
	v.add_child(rw)
	rw.add_child(_wheel_mesh(r, 0.17, 1.0))
	_tube(v, Vector3(0, hub_y, float(spec["rear"])), Vector3(0, hub_y + 0.18, -0.05), 0.035, frame)
	# front: fork turns with the bars
	var fork := Node3D.new()
	fork.position = Vector3(0, 0.62, 0.52)
	fork.rotation.x = deg_to_rad(-24.0)
	v.add_child(fork)
	var fw := Node3D.new()
	fw.position = Vector3(0, hub_y - 0.62, float(spec["front"]) - 0.52)
	fw.position = Basis(Vector3.RIGHT, deg_to_rad(24.0)) * fw.position
	fork.add_child(fw)
	fw.add_child(_wheel_mesh(r, 0.13, 1.0))
	for sx in [-0.08, 0.08]:
		_tube(fork, Vector3(sx, 0.05, 0.0), fw.position + Vector3(sx, 0, 0), 0.025, chrome)
	_tube(fork, Vector3(-0.36, 0.12, -0.04), Vector3(0.36, 0.12, -0.04), 0.018, frame)
	for sx in [-0.36, 0.36]:
		_tube(fork, Vector3(sx, 0.12, -0.04), Vector3(sx * 1.08, 0.12, -0.04), 0.026, dark)
	_box(fork, Vector3(0.22, 0.04, 0.32), fw.position + Vector3(0, r + 0.06, 0.02), body)
	_bike_wheels.assign([fork, fw, rw])
	# frame, tank, seat, engine, exhaust, side panels
	_tube(v, Vector3(0, 0.62, 0.5), Vector3(0, 0.25, -0.05), 0.035, frame)
	_tube(v, Vector3(0, 0.62, 0.5), Vector3(0, 0.55, -0.45), 0.035, frame)
	_box(v, Vector3(0.3, 0.22, 0.48), Vector3(0, 0.66, 0.2), body, Vector3(-0.12, 0, 0))
	_box(v, Vector3(0.26, 0.09, 0.72), Vector3(0, 0.6, -0.35), dark, Vector3(0.05, 0, 0))
	_box(v, Vector3(0.24, 0.3, 0.34), Vector3(0, 0.28, 0.1), frame)
	_box(v, Vector3(0.05, 0.2, 0.4), Vector3(0.15, 0.48, -0.42), body)
	_box(v, Vector3(0.05, 0.2, 0.4), Vector3(-0.15, 0.48, -0.42), body)
	_tube(v, Vector3(0.12, 0.3, 0.25), Vector3(0.16, 0.42, -0.6), 0.035, chrome)
	_box(v, Vector3(0.16, 0.05, 0.38), Vector3(0, 0.6, -0.82), body, Vector3(-0.15, 0, 0))
	# foot pegs
	_tube(v, Vector3(-0.22, 0.24, -0.08), Vector3(0.22, 0.24, -0.08), 0.015, frame)

## synthesised engine note: a low thrum that rises with the revs and opens up under throttle
class EngineSound extends AudioStreamPlayer3D:
	var hum := 24.0
	var rpm := 0.0
	var load_k := 0.0
	var on := false
	var _pb: AudioStreamGeneratorPlayback
	var _rate := 22050.0
	var _ph := 0.0
	var _lp := 0.0
	var _vol := 0.0

	func _ready() -> void:
		var g := AudioStreamGenerator.new()
		g.mix_rate = _rate
		g.buffer_length = 0.15
		stream = g
		bus = "SFX"
		unit_size = 9.0
		max_distance = 160.0
		volume_db = -2.0

	func _process(dt: float) -> void:
		# only a running engine is synthesised (a dozen idle generators would cost more than the rest of the game)
		if not on and _vol <= 0.0:
			if playing:
				stop()
				_pb = null
			return
		if _pb == null:
			play()
			_pb = get_stream_playback()
			if _pb == null:
				return
		_vol = move_toward(_vol, (0.35 + 0.4 * load_k + 0.25 * rpm) if on else 0.0, dt * 1.5)
		var f := hum * (1.0 + rpm * 2.6 + load_k * 0.25)
		for i in _pb.get_frames_available():
			_ph += TAU * f / _rate
			_lp += ((randf() * 2.0 - 1.0) - _lp) * 0.08
			# firing pulses: a sharp fundamental with odd harmonics and a little noise
			var s := sin(_ph) * 0.5 + sin(_ph * 2.0) * 0.28 + sin(_ph * 3.0) * 0.2 * (0.5 + load_k) + _lp * (0.25 + 0.3 * load_k)
			s = clampf(s * 1.4, -1.0, 1.0)
			_pb.push_frame(Vector2(s, s) * _vol * 0.6)
		if _ph > 1000.0:
			_ph -= TAU * 100.0
