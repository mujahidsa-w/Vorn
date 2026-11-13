class_name Fx
extends Node3D
## Эффекты из пула: трассеры, следы пуль, пыль, кровь, вспышки, взрывы, дым, огонь.

var _tracers: Array[MeshInstance3D] = []
var _ti := 0
var _decals: Array[Decal] = []
var _di := 0
var _puffs: Array[CPUParticles3D] = []
var _pi := 0
var _blood: Array[CPUParticles3D] = []
var _bi := 0
var _flashes: Array[OmniLight3D] = []
var _fi := 0
var hole_tex: ImageTexture
var soft_tex: ImageTexture
var flash_tex: ImageTexture

func _ready() -> void:
	hole_tex = _hole()
	soft_tex = _soft()
	flash_tex = _flash()
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = Color(1.0, 0.86, 0.5, 0.75)
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 28:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.014, 0.014, 1.0)
		mi.mesh = bm
		mi.material_override = tm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_tracers.append(mi)
	for i in 90:
		var d := Decal.new()
		d.texture_albedo = hole_tex
		d.size = Vector3(0.16, 0.3, 0.16)
		d.albedo_mix = 1.0
		d.normal_fade = 0.3
		d.upper_fade = 0.3
		d.lower_fade = 0.3
		d.distance_fade_enabled = true
		d.distance_fade_begin = 40.0
		d.distance_fade_length = 10.0
		d.cull_mask = 1
		d.visible = false
		add_child(d)
		_decals.append(d)
	for i in 18:
		_puffs.append(_particles(Color(0.78, 0.68, 0.52, 0.55), 14, 0.5, 2.2, 0.10, 0.28))
	for i in 8:
		_blood.append(_particles(Color(0.45, 0.02, 0.02, 0.85), 12, 0.35, 3.2, 0.03, 0.09))
	for i in 10:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.78, 0.42)
		l.omni_range = 7.0
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_flashes.append(l)

func _particles(col: Color, n: int, life: float, vel: float, s0: float, s1: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = n
	p.lifetime = life
	p.explosiveness = 0.95
	p.direction = Vector3(0, 1, 0)
	p.spread = 55.0
	p.initial_velocity_min = vel * 0.4
	p.initial_velocity_max = vel
	p.gravity = Vector3(0, -3.0, 0)
	p.damping_min = 3.0
	p.damping_max = 5.0
	p.scale_amount_min = s0
	p.scale_amount_max = s1
	var qm := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = soft_tex
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	qm.material = m
	p.mesh = qm
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p

func _hole() -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var r := Vector2(x - s / 2.0 + 0.5, y - s / 2.0 + 0.5).length() / (s / 2.0)
			var a := 0.0
			var c := Color(0.03, 0.03, 0.03)
			if r < 0.22:
				a = 1.0
			elif r < 0.75:
				a = (0.75 - r) / 0.53 * (0.55 + 0.3 * sin(atan2(y - s / 2.0, x - s / 2.0) * 7.0))
				c = Color(0.12, 0.10, 0.08)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, clampf(a, 0, 1)))
	return ImageTexture.create_from_image(img)

func _soft() -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var r := Vector2(x - s / 2.0 + 0.5, y - s / 2.0 + 0.5).length() / (s / 2.0)
			var a := clampf(1.0 - r, 0, 1)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)

func _flash() -> ImageTexture:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var p := Vector2(x - s / 2.0 + 0.5, y - s / 2.0 + 0.5) / (s / 2.0)
			var r := p.length()
			var ang := atan2(p.y, p.x)
			var star := pow(absf(cos(ang * 2.5)), 6.0)
			var a := clampf((1.0 - r) * (0.55 + 0.9 * star) + clampf(0.35 - r, 0, 1) * 2.0, 0, 1)
			img.set_pixel(x, y, Color(1.0, 0.86 - 0.3 * r, 0.5 - 0.4 * r, a))
	return ImageTexture.create_from_image(img)

func tracer(a: Vector3, b: Vector3) -> void:
	var l := a.distance_to(b)
	if l < 2.0:
		return
	var mi := _tracers[_ti]
	_ti = (_ti + 1) % _tracers.size()
	# короткий отрезок, летящий вдоль линии выстрела
	var seg := minf(l * 0.5, 9.0)
	var dir := (b - a) / l
	var t0 := randf_range(0.15, 0.5)
	var c := a + dir * (l * t0 + seg / 2.0)
	mi.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT), c)
	mi.scale = Vector3(1, 1, seg)
	mi.visible = true
	get_tree().create_timer(0.05).timeout.connect(func(): mi.visible = false)

func impact(pos: Vector3, normal: Vector3, surf := "stone") -> void:
	var d := _decals[_di]
	_di = (_di + 1) % _decals.size()
	var up := normal.normalized()
	var x := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(up)
	var s := randf_range(0.11, 0.17)
	d.global_transform = Transform3D(Basis(x, up, z).rotated(up, randf() * TAU), pos + up * 0.02)
	d.size = Vector3(s, 0.25, s)
	d.visible = true
	var p := _puffs[_pi]
	_pi = (_pi + 1) % _puffs.size()
	p.global_position = pos + up * 0.03
	p.direction = up
	p.restart()
	p.emitting = true

func blood(pos: Vector3, dir: Vector3) -> void:
	var p := _blood[_bi]
	_bi = (_bi + 1) % _blood.size()
	p.global_position = pos
	p.direction = dir
	p.restart()
	p.emitting = true

func flash(pos: Vector3, energy := 3.0, rng := 7.0, dur := 0.06, col := Color(1.0, 0.78, 0.42)) -> void:
	var l := _flashes[_fi]
	_fi = (_fi + 1) % _flashes.size()
	l.global_position = pos
	l.light_energy = energy
	l.omni_range = rng
	l.light_color = col
	l.visible = true
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur)
	tw.tween_callback(func(): l.visible = false)

func explosion(pos: Vector3, radius := 6.0) -> void:
	flash(pos + Vector3(0, 0.6, 0), 28.0, radius * 3.0, 0.45, Color(1.0, 0.6, 0.25))
	for cfg in [[Color(1.0, 0.72, 0.3, 0.95), 26, 0.45, radius * 2.2, 0.6, 1.6, -1.0], [Color(0.16, 0.14, 0.12, 0.85), 30, 1.6, radius * 1.1, 1.0, 2.6, 0.6],
			[Color(0.62, 0.54, 0.4, 0.6), 30, 2.4, radius * 0.9, 0.8, 2.2, -2.5]]:
		var p := _particles(cfg[0], cfg[1], cfg[2], cfg[3], cfg[4], cfg[5])
		p.spread = 180.0
		p.gravity = Vector3(0, cfg[6], 0)
		p.global_position = pos + Vector3(0, 0.4, 0)
		p.restart()
		p.emitting = true
		get_tree().create_timer(cfg[2] + 0.5).timeout.connect(p.queue_free)

func smoke_cloud(pos: Vector3, radius: float, dur: float) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.74, 0.74, 0.72, 0.0)
	mat.albedo_texture = soft_tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 0.6
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 31 + pos.z * 17)
	for i in 46:
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		var s := rng.randf_range(radius * 0.9, radius * 1.5)
		qm.size = Vector2(s, s)
		mi.mesh = qm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var v := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.15, 0.75), rng.randf_range(-1, 1))
		mi.position = v.normalized() * rng.randf_range(0.0, radius * 0.72) * Vector3(1, 0.62, 1) + Vector3(0, radius * 0.42, 0)
		mi.sorting_offset = rng.randf_range(-1, 1)
		root.add_child(mi)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.9, 1.0)
	tw.tween_interval(dur - 4.0)
	tw.tween_property(mat, "albedo_color:a", 0.0, 3.0)
	tw.tween_callback(root.queue_free)
	root.scale = Vector3(0.2, 0.2, 0.2)
	create_tween().tween_property(root, "scale", Vector3.ONE, 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return root

func fire_area(pos: Vector3, radius: float, dur: float) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	var p := CPUParticles3D.new()
	p.amount = 90
	p.lifetime = 0.7
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.85
	p.direction = Vector3(0, 1, 0)
	p.spread = 12.0
	p.gravity = Vector3(0, 3.5, 0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.8
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	var qm := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = soft_tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	qm.material = m
	p.mesh = qm
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.35, 0.9))
	g.add_point(0.5, Color(1.0, 0.4, 0.08, 0.7))
	g.set_color(g.get_point_count() - 1, Color(0.3, 0.05, 0.0, 0.0))
	p.color_ramp = g
	p.scale = Vector3(1, 0.25, 1)
	root.add_child(p)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.5, 0.15)
	l.light_energy = 4.0
	l.omni_range = radius * 2.6
	l.position.y = 0.6
	root.add_child(l)
	get_tree().create_timer(dur).timeout.connect(func():
		p.emitting = false
		create_tween().tween_property(l, "light_energy", 0.0, 0.6)
		get_tree().create_timer(1.0).timeout.connect(root.queue_free))
	return root

func clear_round() -> void:
	for d in _decals:
		d.visible = false
