class_name World
extends Node3D
## Карта: сцена из glb + данные из json (коллизии, зоны, навигация, лампы), свет и окружение.
## Координаты карты (x — восток, y — север, z — высота) -> мир Godot (x, z, -y).

var data := {}
var size := Vector2i(96, 80)
var astar := AStarGrid2D.new()
var env: Environment
var sun: DirectionalLight3D
var props_body: StaticBody3D
var world_body: StaticBody3D

static func w(x: float, y: float, z := 0.0) -> Vector3:
	return Vector3(x, z, -y)

static func m(p: Vector3) -> Vector2:
	return Vector2(p.x, -p.z)

func load_map(map_name := "kasbah") -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/maps/%s.json" % map_name))
	size = Vector2i(int(data["size"][0]), int(data["size"][1]))
	var scn: PackedScene = load("res://assets/maps/%s.glb" % map_name)
	if scn:
		var inst := scn.instantiate()
		inst.name = "Geometry"
		add_child(inst)
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			(mi as MeshInstance3D).gi_mode = GeometryInstance3D.GI_MODE_STATIC
			_fix_materials(mi)
	_colliders()
	_nav()
	_lights()
	_marks()

func _fix_materials(mi: MeshInstance3D) -> void:
	var mesh := mi.mesh
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			var n := sm.resource_name
			sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			# светлые покрытия на солнце выгорали в белое — приглушены
			for pair in [["map_sand", 0.72], ["map_concrete", 0.8], ["map_dirt_road", 0.82], ["map_plaster_white", 0.88]]:
				if n == pair[0]:
					sm.albedo_color = Color(pair[1], pair[1], pair[1] * 0.97)
			if n.contains("lamp_glow"):
				sm.emission_enabled = true
				sm.emission = Color(1.0, 0.62, 0.28)
				sm.emission_energy_multiplier = 5.0
			if n.contains("palm_leaf") or n.contains("flower") or n.contains("fabric") or n.contains("cloth") or n.contains("carpet"):
				sm.cull_mode = BaseMaterial3D.CULL_DISABLED
				sm.backlight_enabled = true
				sm.backlight = Color(0.25, 0.3, 0.12) if n.contains("palm") else Color(0.3, 0.2, 0.15)
			else:
				sm.cull_mode = BaseMaterial3D.CULL_BACK

func _box(body: StaticBody3D, c: Vector3, half: Vector3, yaw := 0.0) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = half * 2.0
	cs.shape = b
	cs.position = c
	cs.rotation.y = yaw
	body.add_child(cs)

func _colliders() -> void:
	world_body = StaticBody3D.new()
	world_body.name = "WorldBody"
	world_body.collision_layer = 1
	world_body.collision_mask = 0
	add_child(world_body)
	props_body = StaticBody3D.new()
	props_body.name = "PropsBody"
	props_body.collision_layer = 1
	props_body.collision_mask = 0
	props_body.set_meta("wood", true)
	add_child(props_body)
	# земля и внешние границы
	_box(world_body, w(size.x / 2.0, size.y / 2.0, -0.5), Vector3(size.x / 2.0 + 80, 0.5, size.y / 2.0 + 80))
	for b in data["colliders"]:
		var c := w((b[0] + b[3]) / 2.0, (b[1] + b[4]) / 2.0, (b[2] + b[5]) / 2.0)
		_box(world_body, c, Vector3((b[3] - b[0]) / 2.0, (b[5] - b[2]) / 2.0, (b[4] - b[1]) / 2.0))
	for o in data["ocolliders"]:
		_box(props_body, w(o[0], o[1], o[2] + o[5] / 2.0), Vector3(o[3], o[5] / 2.0, o[4]), o[6])
	for r in data.get("ramps", []):
		# пандус: наклонная плита
		var x0: float = r[0]; var y0: float = r[1]; var x1: float = r[2]; var y1: float = r[3]; var z0: float = r[4]; var z1: float = r[5]
		var cs := CollisionShape3D.new()
		var shp := ConvexPolygonShape3D.new()
		var pts := PackedVector3Array()
		if String(r[6]) == "x":
			pts = PackedVector3Array([w(x0, y0, z0), w(x0, y1, z0), w(x1, y0, z1), w(x1, y1, z1), w(x1, y0, z0 - 0.2), w(x1, y1, z0 - 0.2), w(x0, y0, z0 - 0.2), w(x0, y1, z0 - 0.2)])
		else:
			pts = PackedVector3Array([w(x0, y0, z0), w(x1, y0, z0), w(x0, y1, z1), w(x1, y1, z1), w(x0, y1, z0 - 0.2), w(x1, y1, z0 - 0.2), w(x0, y0, z0 - 0.2), w(x1, y0, z0 - 0.2)])
		shp.points = pts
		cs.shape = shp
		world_body.add_child(cs)

func _nav() -> void:
	astar.region = Rect2i(0, 0, size.x, size.y)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	var rows: Array = data["nav"]
	for y in size.y:
		var row: String = rows[y]
		for x in size.x:
			if row[x] == "0":
				astar.set_point_solid(Vector2i(x, y), true)
	# клетки у стен дороже: боты идут по середине улиц
	for y in size.y:
		for x in size.x:
			if astar.is_point_solid(Vector2i(x, y)):
				continue
			var near := 0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x < 0 or q.y < 0 or q.x >= size.x or q.y >= size.y or astar.is_point_solid(q):
					near += 1
			if near > 0:
				astar.set_point_weight_scale(Vector2i(x, y), 1.0 + 0.9 * near)

func cell(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor(p.x)), 0, size.x - 1), clampi(int(floor(-p.z)), 0, size.y - 1))

func cell_center(c: Vector2i) -> Vector3:
	return Vector3(c.x + 0.5, 0.0, -(c.y + 0.5))

func free_cell(c: Vector2i) -> Vector2i:
	if not astar.is_point_solid(c):
		return c
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := c + Vector2i(dx, dy)
				if q.x >= 0 and q.y >= 0 and q.x < size.x and q.y < size.y and not astar.is_point_solid(q):
					return q
	return c

func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var a := free_cell(cell(from))
	var b := free_cell(cell(to))
	var ids := astar.get_id_path(a, b)
	var out := PackedVector3Array()
	for c in ids:
		out.append(cell_center(c))
	if out.size() > 0:
		out[out.size() - 1] = Vector3(clampf(to.x, b.x + 0.2, b.x + 0.8), 0.0, clampf(to.z, -(b.y + 0.8), -(b.y + 0.2)))
	return out

func path_len(from: Vector3, to: Vector3) -> float:
	var p := path(from, to)
	var l := 0.0
	for i in range(1, p.size()):
		l += p[i].distance_to(p[i - 1])
	return l

func in_rect(p: Vector3, r: Array) -> bool:
	var q := m(p)
	return q.x >= r[0] and q.x <= r[2] and q.y >= r[1] and q.y <= r[3]

func rect_center(r: Array) -> Vector3:
	return w((r[0] + r[2]) / 2.0, (r[1] + r[3]) / 2.0)

func rand_in(r: Array, rng: RandomNumberGenerator) -> Vector3:
	for i in 20:
		var p := w(rng.randf_range(r[0] + 0.5, r[2] - 0.5), rng.randf_range(r[1] + 0.5, r[3] - 0.5))
		if not astar.is_point_solid(cell(p)):
			return p
	return rect_center(r)

func site_at(p: Vector3) -> String:
	if in_rect(p, data["site_a"]):
		return "a"
	if in_rect(p, data["site_b"]):
		return "b"
	return ""

func surface_at(p: Vector3) -> String:
	var q := m(p)
	if p.y > 0.6:
		return "stone"
	for s in data["surfaces"]:
		if q.x >= s[0] and q.x <= s[2] and q.y >= s[1] and q.y <= s[3]:
			return String(s[4])
	return "sand"

func name_at(p: Vector3) -> String:
	var q := m(p)
	var best := ""
	var area := 1e9
	for n in data["names"]:
		if q.x >= n[1] and q.x <= n[3] and q.y >= n[2] and q.y <= n[4]:
			var a: float = (n[3] - n[1]) * (n[4] - n[2])
			if a < area:
				area = a
				best = String(n[0])
	return best

func spawn(team: String, i: int) -> Transform3D:
	var arr: Array = data["t_spawn"] if team == "t" else data["ct_spawn"]
	var s: Array = arr[i % arr.size()]
	var t := Transform3D()
	t.origin = w(s[0], s[1], 0.05)
	t.basis = Basis(Vector3.UP, deg_to_rad(float(s[2]) - 90.0))
	return t

func spawn_yaw(team: String, i: int) -> float:
	var arr: Array = data["t_spawn"] if team == "t" else data["ct_spawn"]
	var s: Array = arr[i % arr.size()]
	# угол в данных — азимут на плане (0 = восток, против часовой); yaw в Godot: 0 = взгляд на -Z (север)
	return deg_to_rad(float(s[2]) - 90.0)

func los(a: Vector3, b: Vector3, exclude: Array = []) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	q.exclude = exclude
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

# ------------------------------------------------------------------ свет и окружение
func _lights() -> void:
	var q := int(G.settings["quality"])
	env = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.16, 0.36, 0.72)
	sm.sky_horizon_color = Color(0.62, 0.72, 0.84)
	sm.ground_horizon_color = Color(0.74, 0.66, 0.52)
	sm.ground_bottom_color = Color(0.52, 0.44, 0.32)
	sm.sky_curve = 0.12
	sm.sun_angle_max = 22.0
	sm.sun_curve = 0.08
	sky.sky_material = sm
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.55
	env.ambient_light_color = Color(0.95, 0.84, 0.70)
	env.ambient_light_energy = 1.15
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	var pc := not G.mobile          # screen-space and volumetric effects exist only in the desktop renderer
	env.ssao_enabled = q >= 1 and pc
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssil_enabled = q >= 3 and pc
	env.sdfgi_enabled = q >= 2 and pc
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.4
	env.sdfgi_use_occlusion = true
	env.sdfgi_energy = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.15
	env.fog_enabled = true
	env.fog_light_color = Color(0.86, 0.78, 0.64)
	env.fog_density = 0.0028
	env.fog_sun_scatter = 0.25
	env.fog_aerial_perspective = 0.4
	env.volumetric_fog_enabled = q >= 3 and pc
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.95, 0.88, 0.75)
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.04
	env.adjustment_saturation = 0.96
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.93, 0.80)
	sun.light_energy = 1.9
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	var splits4: bool = q >= 1 if pc else q >= 2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if splits4 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = (110.0 if q >= 1 else 70.0) if pc else [45.0, 60.0, 80.0, 100.0][q]
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	# позднее утро, солнце с юго-запада: свет идёт на северо-восток и вниз
	sun.look_at_from_position(Vector3.ZERO, Vector3(0.55, -0.80, -0.62).normalized(), Vector3.UP)
	var n := 0
	for l in data.get("lamps", []):
		var o := OmniLight3D.new()
		o.position = w(l[0], l[1], l[2])
		o.omni_range = float(l[3])
		o.light_energy = float(l[4]) * 1.6
		o.light_color = Color(1.0, 0.68, 0.36)
		o.omni_attenuation = 1.4
		o.shadow_enabled = q >= 2 and n < 6 and pc
		o.distance_fade_enabled = true
		o.distance_fade_begin = 45.0
		o.distance_fade_length = 10.0
		add_child(o)
		n += 1

func golden_hour(haze := 1.0) -> void:
	## Вечерний свет для лобби и заставок: низкое солнце с запада, тёплая дымка, глубокое небо, холмы на горизонте.
	if env == null or sun == null:
		return
	_hills()
	var sm := env.sky.sky_material as ProceduralSkyMaterial
	sm.sky_top_color = Color(0.09, 0.17, 0.33)
	sm.sky_horizon_color = Color(0.98, 0.60, 0.34)
	sm.ground_horizon_color = Color(0.62, 0.42, 0.28)
	sm.ground_bottom_color = Color(0.22, 0.17, 0.13)
	sm.sky_curve = 0.18
	sm.sun_angle_max = 34.0
	sm.sun_curve = 0.12
	sm.sky_energy_multiplier = 1.1
	env.ambient_light_color = Color(0.78, 0.62, 0.55)
	env.ambient_light_energy = 0.85
	env.ambient_light_sky_contribution = 0.5
	env.fog_light_color = Color(0.92, 0.58, 0.38)
	env.fog_density = 0.0024 * haze
	env.fog_sun_scatter = 0.45
	env.fog_aerial_perspective = 0.25
	env.fog_sky_affect = 0.2
	env.tonemap_exposure = 0.9
	env.glow_intensity = 0.8
	env.glow_bloom = 0.12
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.08
	sun.light_color = Color(1.0, 0.66, 0.40)
	sun.light_energy = 2.1
	sun.look_at_from_position(Vector3.ZERO, Vector3(0.88, -0.24, -0.40).normalized(), Vector3.UP)

func _hills() -> void:
	## Кольцо далёких холмов вокруг карты: закрывает край плоскости, у заката появляется силуэт.
	if has_node("Hills"):
		return
	var c := w(size.x * 0.5, size.y * 0.5, 0.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 160
	for i in n:
		for k in 2:
			var a := TAU * float(i + k) / n
			var h := 14.0 + 10.0 * sin(a * 3.0 + 1.3) + 7.0 * sin(a * 7.0 + 0.4) + 4.0 * sin(a * 17.0 + 2.1) + 2.0 * sin(a * 37.0)
			var r := 230.0 + 30.0 * sin(a * 5.0 + 0.7)
			var dir := Vector3(cos(a), 0, sin(a))
			if k == 0:
				var a1 := TAU * float(i + 1) / n
				var h1 := 14.0 + 10.0 * sin(a1 * 3.0 + 1.3) + 7.0 * sin(a1 * 7.0 + 0.4) + 4.0 * sin(a1 * 17.0 + 2.1) + 2.0 * sin(a1 * 37.0)
				var r1 := 230.0 + 30.0 * sin(a1 * 5.0 + 0.7)
				var d1 := Vector3(cos(a1), 0, sin(a1))
				var p0 := c + dir * r + Vector3(0, -2, 0)
				var p1 := c + dir * (r + 40.0) + Vector3(0, maxf(h, 2.0), 0)
				var p2 := c + d1 * r1 + Vector3(0, -2, 0)
				var p3 := c + d1 * (r1 + 40.0) + Vector3(0, maxf(h1, 2.0), 0)
				for v in [p0, p1, p2, p2, p1, p3]:
					st.add_vertex(v)
	# ground skirt between the map and the hills
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(620, 620)
	g.mesh = pm
	g.position = c + Vector3(0, -0.05, 0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.55, 0.42, 0.30)
	gm.roughness = 1.0
	g.material_override = gm
	g.name = "Skirt"
	add_child(g)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Hills"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.36, 0.25, 0.20)
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _x_texture() -> ImageTexture:
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(s / 2.0, s / 2.0)
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5) - c
			var r := p.length()
			var a := 0.0
			if absf(r - 104.0) < 9.0:
				a = 1.0
			var d1 := absf(p.x - p.y) / 1.4142
			var d2 := absf(p.x + p.y) / 1.4142
			if r < 78.0 and (d1 < 10.0 or d2 < 10.0):
				a = 1.0
			if a > 0.0:
				var n := 0.75 + 0.25 * sin(x * 0.9) * sin(y * 1.3)
				img.set_pixel(x, y, Color(0.62, 0.10, 0.06, a * n))
	return ImageTexture.create_from_image(img)

func _marks() -> void:
	var tex := _x_texture()
	for key in ["site_a", "site_b"]:
		var r: Array = data[key]
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(4.2, 4.2)
		qm.orientation = PlaneMesh.FACE_Y
		mi.mesh = qm
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.95
		mat.render_priority = 1
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var c := rect_center(r)
		if key == "site_a":
			c += Vector3(-4.5, 0, 0)
		mi.position = c + Vector3(0, 0.015, 0)
		add_child(mi)
	var marks: Dictionary = data.get("site_marks", {})
	for k in marks:
		var d: Array = marks[k]
		var lab := Label3D.new()
		lab.text = String(d[4])
		lab.text_direction = TextServer.DIRECTION_RTL
		lab.font = UI.bold()
		lab.font_size = 400
		lab.pixel_size = 0.006
		lab.modulate = Color(0.55, 0.09, 0.05, 0.92)
		lab.outline_size = 0
		lab.shaded = true
		lab.double_sided = false
		lab.position = w(d[2], d[3], 3.0)
		lab.rotation.y = -PI / 2.0 if k == "a" else PI / 2.0
		add_child(lab)
