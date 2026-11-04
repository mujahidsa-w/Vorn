extends Node3D
## Visual effects: explosions, lingering fires, muzzle flashes, tracers, impacts.

const TEX_FIRE := preload("res://assets/fx/fire.png")
const TEX_SMOKE := preload("res://assets/fx/smoke.png")
const TEX_SPARK := preload("res://assets/fx/spark.png")
const TEX_MUZZLE := preload("res://assets/fx/muzzle.png")
const TEX_SCORCH := preload("res://assets/fx/scorch.png")
const TEX_RING := preload("res://assets/fx/ring.png")

var world
var fires: Array = []     # {node, light, pos, t, radius}
var _mats := {}


func _mat(tex: Texture2D, additive: bool, billboard := BaseMaterial3D.BILLBOARD_PARTICLES) -> StandardMaterial3D:
	var key := str(tex.resource_path) + str(additive) + str(billboard)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.albedo_texture = tex
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = billboard
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	_mats[key] = m
	return m


func _particles(tex: Texture2D, additive: bool, amount: int, life: float, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _mat(tex, additive)
	p.mesh = q
	p.local_coords = false
	return p


func _ramp(cols: Array) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, cols[0])
	g.set_color(1, cols[cols.size() - 1])
	for i in range(1, cols.size() - 1):
		g.add_point(float(i) / (cols.size() - 1), cols[i])
	return g


func _curve(pts: Array) -> Curve:
	var c := Curve.new()
	for p in pts:
		c.add_point(p)
	return c


func _free_after(n: Node, t: float) -> void:
	get_tree().create_timer(t, false).timeout.connect(n.queue_free)


func _light(pos: Vector3, col: Color, energy: float, rng: float, dur: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur).set_ease(Tween.EASE_IN)
	tw.tween_callback(l.queue_free)


func _ground_quad(pos: Vector3, n: Vector3, size: float, tex: Texture2D, additive: bool, life: float, grow := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := _mat(tex, additive, BaseMaterial3D.BILLBOARD_DISABLED).duplicate()
	m.vertex_color_use_as_albedo = false
	q.material = m
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos + n * 0.03
	var up := Vector3.FORWARD if absf(n.y) > 0.9 else Vector3.UP
	mi.look_at(pos + n, up)
	if grow > 0.0:
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "scale", Vector3.ONE * grow, life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(m, "albedo_color:a", 0.0, life)
	_free_after(mi, life + 0.1)
	return mi


# ---------------------------------------------------------------- explosion
func explosion(pos: Vector3, radius: float) -> void:
	var q: int = clampi(int(Game.settings.quality), 0, 2)
	_light(pos + Vector3(0, 1.5, 0), Color(1.0, 0.62, 0.28), 16.0, radius * 4.0, 1.1)
	# fireball
	var fb := _particles(TEX_FIRE, true, [20, 28, 40][q], 1.1, 2.6)
	fb.one_shot = true
	fb.explosiveness = 0.95
	fb.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fb.emission_sphere_radius = radius * 0.18
	fb.direction = Vector3.UP
	fb.spread = 180.0
	fb.initial_velocity_min = 2.0
	fb.initial_velocity_max = radius * 0.9
	fb.damping_min = 4.0
	fb.damping_max = 6.0
	fb.gravity = Vector3(0, 2.0, 0)
	fb.scale_amount_min = 1.0
	fb.scale_amount_max = 2.2
	fb.scale_amount_curve = _curve([Vector2(0, 0.5), Vector2(0.25, 1.0), Vector2(1, 1.4)])
	fb.color_ramp = _ramp([Color(1, 1, 0.9, 1), Color(1, 0.7, 0.3, 1), Color(0.9, 0.3, 0.05, 0.7), Color(0.2, 0.08, 0.03, 0.0)])
	fb.angle_min = 0
	fb.angle_max = 360
	add_child(fb)
	fb.global_position = pos + Vector3(0, 0.8, 0)
	fb.emitting = true
	_free_after(fb, 2.0)
	# sparks
	var sp := _particles(TEX_SPARK, true, [30, 50, 80][q], 1.4, 0.35)
	(sp.mesh as QuadMesh).material = _mat(TEX_SPARK, true, BaseMaterial3D.BILLBOARD_FIXED_Y)
	sp.one_shot = true
	sp.explosiveness = 1.0
	sp.direction = Vector3.UP
	sp.spread = 75.0
	sp.initial_velocity_min = 8.0
	sp.initial_velocity_max = 22.0
	sp.gravity = Vector3(0, -12, 0)
	sp.scale_amount_min = 0.6
	sp.scale_amount_max = 1.2
	sp.color_ramp = _ramp([Color(1, 0.95, 0.7, 1), Color(1, 0.5, 0.1, 1), Color(0.6, 0.15, 0.0, 0)])
	add_child(sp)
	sp.global_position = pos + Vector3(0, 0.6, 0)
	sp.emitting = true
	_free_after(sp, 2.0)
	# smoke column
	var sm := _particles(TEX_SMOKE, false, [16, 26, 40][q], 7.0, 3.0)
	sm.one_shot = true
	sm.explosiveness = 0.6
	sm.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sm.emission_sphere_radius = radius * 0.25
	sm.direction = Vector3.UP
	sm.spread = 25.0
	sm.initial_velocity_min = 2.0
	sm.initial_velocity_max = 6.0
	sm.damping_min = 0.8
	sm.damping_max = 1.4
	sm.gravity = Vector3(0, 0.8, 0)
	sm.scale_amount_min = 1.2
	sm.scale_amount_max = 2.2
	sm.scale_amount_curve = _curve([Vector2(0, 0.6), Vector2(1, 2.8)])
	sm.angle_min = 0
	sm.angle_max = 360
	sm.color_ramp = _ramp([Color(0.15, 0.13, 0.12, 0.0), Color(0.12, 0.11, 0.1, 0.85), Color(0.25, 0.24, 0.23, 0.5), Color(0.3, 0.3, 0.3, 0.0)])
	add_child(sm)
	sm.global_position = pos + Vector3(0, 1.0, 0)
	sm.emitting = true
	_free_after(sm, 8.0)
	# debris
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.08, 0.07, 0.06)
	for i in [4, 7, 10][q]:
		var rb := RigidBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var sz := Vector3(randf_range(0.08, 0.3), randf_range(0.05, 0.15), randf_range(0.08, 0.3))
		bs.size = sz
		cs.shape = bs
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = sz
		bm.material = dmat
		mi.mesh = bm
		rb.add_child(mi)
		rb.collision_layer = 4
		rb.collision_mask = 1
		add_child(rb)
		rb.global_position = pos + Vector3(randf_range(-0.5, 0.5), 0.8, randf_range(-0.5, 0.5))
		rb.linear_velocity = Vector3(randf_range(-1, 1), randf_range(0.6, 1.4), randf_range(-1, 1)).normalized() * randf_range(6.0, 14.0)
		rb.angular_velocity = Vector3(randf(), randf(), randf()) * 10.0
		_free_after(rb, 7.0)
	# shockwave + scorch
	var g = world._ground(pos) if world else {}
	var gp: Vector3 = g.position if g and not g.is_empty() else pos
	var gn: Vector3 = g.normal if g and not g.is_empty() else Vector3.UP
	_ground_quad(gp, gn, radius * 0.5, TEX_RING, true, 0.45, 5.0)
	_ground_quad(gp, gn, radius * 1.1, TEX_SCORCH, false, 45.0)
	# lingering fires around the impact
	for i in [2, 3, 5][q]:
		var a := randf() * TAU
		var d := randf_range(0.5, radius * 0.4)
		var fp := pos + Vector3(cos(a) * d, 0, sin(a) * d)
		var gg = world._ground(fp) if world else {}
		if gg and not gg.is_empty():
			fp = gg.position
		fire_patch(fp, randf_range(12.0, 22.0), randf_range(0.7, 1.3))


# ---------------------------------------------------------------- fire
func fire_patch(pos: Vector3, duration: float, size := 1.0, attach: Node3D = null) -> Node3D:
	var root := Node3D.new()
	if attach:
		attach.add_child(root)
		root.position = pos
	else:
		add_child(root)
		root.global_position = pos
	var f := _particles(TEX_FIRE, true, 24, 0.9, 0.9 * size)
	f.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	f.emission_sphere_radius = 0.35 * size
	f.direction = Vector3.UP
	f.spread = 12.0
	f.initial_velocity_min = 1.0
	f.initial_velocity_max = 2.5
	f.gravity = Vector3(0, 1.5, 0)
	f.scale_amount_curve = _curve([Vector2(0, 0.6), Vector2(0.3, 1.0), Vector2(1, 0.2)])
	f.angle_min = 0
	f.angle_max = 360
	f.color_ramp = _ramp([Color(1, 0.9, 0.6, 0.9), Color(1, 0.5, 0.12, 0.8), Color(0.6, 0.15, 0.02, 0.0)])
	f.local_coords = attach != null
	root.add_child(f)
	var s := _particles(TEX_SMOKE, false, 10, 3.0, 1.4 * size)
	s.direction = Vector3.UP
	s.spread = 10.0
	s.initial_velocity_min = 1.0
	s.initial_velocity_max = 2.0
	s.gravity = Vector3(0, 0.5, 0)
	s.scale_amount_curve = _curve([Vector2(0, 0.5), Vector2(1, 2.0)])
	s.color_ramp = _ramp([Color(0.1, 0.1, 0.1, 0.0), Color(0.1, 0.1, 0.1, 0.55), Color(0.2, 0.2, 0.2, 0.0)])
	root.add_child(s)
	s.position = Vector3(0, 0.8, 0)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.5, 0.15)
	l.light_energy = 2.2 * size
	l.omni_range = 6.0 * size
	root.add_child(l)
	l.position = Vector3(0, 0.8, 0)
	var rec := {"node": root, "light": l, "t": duration, "radius": 1.0 * size, "base": 2.2 * size, "tick": 0.0}
	fires.append(rec)
	return root


func _process(delta: float) -> void:
	var tt := Time.get_ticks_msec() / 1000.0
	for i in range(fires.size() - 1, -1, -1):
		var f: Dictionary = fires[i]
		if not is_instance_valid(f.node):
			fires.remove_at(i)
			continue
		f.t -= delta
		var fade := clampf(f.t / 3.0, 0.0, 1.0)
		f.light.light_energy = (f.base + sin(tt * 17.0 + i) * 0.4 + sin(tt * 7.0) * 0.3) * fade
		f.tick -= delta
		if f.tick <= 0.0 and world:
			f.tick = 0.5
			world.burn_damage(f.node.global_position, f.radius + 0.6, 6.0)
		if f.t <= 0.0:
			for c in f.node.get_children():
				if c is CPUParticles3D:
					c.emitting = false
			_free_after(f.node, 3.0)
			fires.remove_at(i)


# ---------------------------------------------------------------- guns
func muzzle(pos: Vector3, dir: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.45, 0.45)
	q.material = _mat(TEX_MUZZLE, true, BaseMaterial3D.BILLBOARD_ENABLED)
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos + dir * 0.08
	mi.rotation.z = randf() * TAU
	mi.scale = Vector3.ONE * randf_range(0.8, 1.2)
	_free_after(mi, 0.05)
	# side flame cone
	var f2 := MeshInstance3D.new()
	var q2 := QuadMesh.new()
	q2.size = Vector2(0.18, 0.5)
	q2.material = _mat(TEX_FIRE, true, BaseMaterial3D.BILLBOARD_DISABLED)
	f2.mesh = q2
	add_child(f2)
	f2.global_position = pos + dir * 0.28
	f2.look_at(pos + dir * 2.0 + Vector3(0, 0.001, 0), Vector3.UP)
	f2.rotate_object_local(Vector3.RIGHT, PI / 2)
	_free_after(f2, 0.04)
	_light(pos, Color(1.0, 0.7, 0.3), 3.5, 6.0, 0.07)


func _beam(a: Vector3, dir: Vector3, length: float, width: float, col: Color) -> Array:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, width, length)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = col
	m.disable_receive_shadows = true
	bm.material = m
	mi.mesh = bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = a + dir * length * 0.5
	mi.look_at(mi.global_position + dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD)
	return [mi, m]


func tracer(a: Vector3, b: Vector3, col := Color(1.0, 0.12, 0.08)) -> void:
	# one bright red bullet per shot (core + glow), flying from the muzzle to the hit point
	var len := a.distance_to(b)
	if len < 0.3:
		return
	var dir := (b - a) / len
	var seg := minf(len, 2.2)
	var head: Array = _beam(a, dir, seg, 0.11, Color(1.6, 0.08, 0.04, 0.45))     # glow
	var mi: MeshInstance3D = head[0]
	for part in [[seg, 0.05, Color(2.6, 0.25, 0.12, 1.0)], [seg * 0.5, 0.022, Color(3.0, 2.2, 1.6, 1.0)]]:
		var bm: Array = _beam(a, dir, part[0], part[1], part[2])
		bm[0].reparent(mi, false)
		bm[0].position = Vector3(0, 0, -(seg - float(part[0])) * 0.5)
		bm[0].rotation = Vector3.ZERO
	var travel := maxf(len - seg, 0.0)
	var t := clampf(travel / 170.0, 0.05, 0.8)
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position", a + dir * (seg * 0.5 + travel), t)
	tw.tween_callback(mi.queue_free)


func impact(pos: Vector3, n: Vector3, flesh := false) -> void:
	var sp := _particles(TEX_SPARK if not flesh else TEX_SMOKE, not flesh, 8, 0.35, 0.12 if not flesh else 0.25)
	sp.one_shot = true
	sp.explosiveness = 1.0
	sp.direction = n
	sp.spread = 35.0
	sp.initial_velocity_min = 2.0
	sp.initial_velocity_max = 5.0
	sp.gravity = Vector3(0, -9, 0)
	sp.color_ramp = _ramp([Color(1, 0.9, 0.6, 1), Color(1, 0.4, 0.1, 0)]) if not flesh else _ramp([Color(0.55, 0.0, 0.0, 0.9), Color(0.3, 0.0, 0.0, 0)])
	add_child(sp)
	sp.global_position = pos + n * 0.03
	sp.emitting = true
	_free_after(sp, 0.8)
	if not flesh:
		_ground_quad(pos, n, 0.09, TEX_SCORCH, false, 20.0)


# ---------------------------------------------------------------- tyres
const SKID_MAX := 900
var _skid_mm: MultiMesh
var _skid_i := 0


func _skid_init() -> void:
	_skid_mm = MultiMesh.new()
	_skid_mm.transform_format = MultiMesh.TRANSFORM_3D
	_skid_mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.orientation = PlaneMesh.FACE_Y
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.015, 0.014, 0.013)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	m.render_priority = -1
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	_skid_mm.mesh = q
	_skid_mm.instance_count = SKID_MAX
	_skid_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _skid_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-50000, -5000, -50000), Vector3(100000, 10000, 100000))
	add_child(mmi)


## Black rubber mark on the road between two wheel positions.
func skid(a: Vector3, b: Vector3, n: Vector3, strength := 1.0) -> void:
	if _skid_mm == null:
		_skid_init()
	var d := b - a
	var l := d.length()
	if l < 0.04 or l > 4.0:
		return
	var fwd := d / l
	var up := n.normalized()
	var side := fwd.cross(up).normalized()
	fwd = up.cross(side).normalized()
	var xf := Transform3D(Basis(side * 0.23, up, fwd * (l + 0.03)), (a + b) * 0.5 + up * 0.025)
	_skid_mm.set_instance_transform(_skid_i, xf)
	_skid_mm.set_instance_color(_skid_i, Color(1, 1, 1, clampf(0.35 + strength * 0.4, 0.2, 0.8)))
	_skid_i = (_skid_i + 1) % SKID_MAX
	_skid_mm.visible_instance_count = mini(maxi(_skid_mm.visible_instance_count, _skid_i), SKID_MAX)
	if _skid_i == 0:
		_skid_mm.visible_instance_count = SKID_MAX


## Grey tyre smoke that trails behind a skidding / spinning wheel.
func tyre_smoke() -> CPUParticles3D:
	var p := _particles(TEX_SMOKE, false, 26, 1.6, 1.4)
	p.local_coords = false
	p.emitting = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 35.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, 0.35, 0)
	p.damping_min = 0.6
	p.damping_max = 1.2
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.scale_amount_curve = _curve([Vector2(0.0, 0.35), Vector2(1.0, 2.6)])
	p.color_ramp = _ramp([Color(0.82, 0.82, 0.84, 0.0), Color(0.8, 0.8, 0.82, 0.42), Color(0.7, 0.7, 0.72, 0.0)])
	return p


## Small water splashes (footsteps / tyres in the rain).
func splash(pos: Vector3) -> void:
	var p := _particles(TEX_SPARK, false, 10, 0.45, 0.12)
	p.one_shot = true
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.4
	p.gravity = Vector3(0, -9.8, 0)
	p.color_ramp = _ramp([Color(0.8, 0.85, 0.95, 0.6), Color(0.8, 0.85, 0.95, 0.0)])
	add_child(p)
	p.global_position = pos
	p.emitting = true
	_free_after(p, 1.0)
