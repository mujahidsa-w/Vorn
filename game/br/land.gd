class_name BRLand
extends World
## «Golden Valley» — the battle royale map, generated from a seed: 1 km of desert with dunes and border
## mountains, villages of enterable mud-brick houses (some with stairs to the roof), market stalls,
## watchtowers, town walls, roads between villages, boulders, and loot points everywhere.
## World coordinates: x east, z south, y up; the map spans -500..500 on x and z.

const HALF := 500.0
const N := 201                      # terrain vertices per side
const STEP := 5.0                   # metres between vertices
const TEX := "res://assets/maps/kasbah_%s.jpg"
const TOWN_NAMES := ["واحة الذهب", "البلدة القديمة", "سوق الملح", "قرية الصخور", "المحطة", "التلال الحمراء", "عين النخيل", "الوادي العميق"]

var heights := PackedFloat32Array()
var towns: Array = []               # {name, c: Vector2, r, h}
var hamlets: Array = []             # {c, r, h}
var roads: Array = []               # [Vector2, Vector2, h_a, h_b]
var loot_points: Array = []         # {pos: Vector3, door: Vector3 (or pos), inside: bool, path: [waypoints to walk first]}
var footprints: Array = []          # {c: Vector2, half: Vector2, rot: float}  (houses, for the map)
var map_tex: ImageTexture
var rng := RandomNumberGenerator.new()
var _nb := FastNoiseLite.new()
var _nd := FastNoiseLite.new()
var _mats := {}

# ------------------------------------------------------------------ entry
func build(seed_v: int) -> void:
	var t0 := Time.get_ticks_msec()
	rng.seed = seed_v
	_nb.seed = seed_v
	_nb.frequency = 0.0022
	_nb.fractal_octaves = 3
	_nd.seed = seed_v + 7
	_nd.frequency = 0.013
	_nd.fractal_octaves = 2
	data = {}
	var tt := [Time.get_ticks_msec()]
	var prof := func(n: String):
		if G.args.has("brprof"):
			print("[br]   %s %d ms" % [n, Time.get_ticks_msec() - tt[0]])
		tt[0] = Time.get_ticks_msec()
	_sites()
	prof.call("sites")
	_heights()
	prof.call("heights")
	_terrain()
	prof.call("terrain")
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
	_ground_collision()
	for t in towns:
		_town(t, true)
	for hm in hamlets:
		_town(hm, false)
	prof.call("towns")
	_rocks()
	prof.call("rocks")
	_open_crates()
	_lights()
	_map_image()
	prof.call("map")
	print("[br] land built in %d ms: %d towns, %d hamlets, %d loot points" % [Time.get_ticks_msec() - t0, towns.size(), hamlets.size(), loot_points.size()])

# ------------------------------------------------------------------ layout
func _sites() -> void:
	var names := TOWN_NAMES.duplicate()
	var tries := 0
	while towns.size() < 6 and tries < 400:
		tries += 1
		var c := Vector2(rng.randf_range(-360, 360), rng.randf_range(-360, 360))
		var ok := true
		for t in towns:
			if c.distance_to(t["c"]) < 210.0:
				ok = false
				break
		if ok:
			var r := rng.randf_range(52.0, 78.0) if towns.size() > 0 else 88.0
			towns.append({"name": names[towns.size()], "c": c, "r": r, "h": clampf(_raw(c.x, c.y), 4.0, 26.0)})
	tries = 0
	while hamlets.size() < 12 and tries < 600:
		tries += 1
		var c2 := Vector2(rng.randf_range(-400, 400), rng.randf_range(-400, 400))
		var ok2 := true
		for t in towns:
			if c2.distance_to(t["c"]) < float(t["r"]) + 60.0:
				ok2 = false
		for hm in hamlets:
			if c2.distance_to(hm["c"]) < 80.0:
				ok2 = false
		if ok2:
			hamlets.append({"name": "", "c": c2, "r": rng.randf_range(16.0, 24.0), "h": clampf(_raw(c2.x, c2.y), 3.0, 28.0)})
	# roads: a tree joining the towns (each new town to its nearest connected one)
	var linked := [0]
	while linked.size() < towns.size():
		var best := Vector2i(-1, -1)
		var bd := INF
		for i in linked:
			for j in towns.size():
				if j in linked:
					continue
				var d: float = (towns[i]["c"] as Vector2).distance_to(towns[j]["c"])
				if d < bd:
					bd = d
					best = Vector2i(i, j)
		linked.append(best.y)
		roads.append([towns[best.x]["c"], towns[best.y]["c"], towns[best.x]["h"], towns[best.y]["h"]])

func _raw(x: float, z: float) -> float:
	var b := _nb.get_noise_2d(x, z)
	var d := _nd.get_noise_2d(x, z)
	var h := 9.0 + b * 26.0 + (1.0 - absf(d)) * 3.2
	var e := maxf(absf(x), absf(z))
	if e > 360.0:
		h += pow((e - 360.0) / 140.0, 2.0) * 85.0
	return h

func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	## (distance, t along the segment)
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return Vector2(p.distance_to(a + ab * t), t)

func _shaped(x: float, z: float) -> float:
	var h := _raw(x, z)
	var p := Vector2(x, z)
	for rd in roads:
		var sd := _seg_dist(p, rd[0], rd[1])
		if sd.x < 14.0:
			var rh: float = lerpf(rd[2], rd[3], sd.y)
			h = lerpf(h, rh, smoothstep(14.0, 5.0, sd.x) * 0.85)
	for s in towns + hamlets:
		var d := p.distance_to(s["c"])
		var r: float = s["r"]
		if d < r + 34.0:
			h = lerpf(h, s["h"], smoothstep(r + 34.0, r + 4.0, d))
	return h

func _heights() -> void:
	heights.resize(N * N)
	for j in N:
		var z := -HALF + j * STEP
		for i in N:
			heights[j * N + i] = _shaped(-HALF + i * STEP, z)

func height_at(x: float, z: float) -> float:
	var fx := clampf((x + HALF) / STEP, 0.0, N - 1.001)
	var fz := clampf((z + HALF) / STEP, 0.0, N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var h00 := heights[j * N + i]
	var h10 := heights[j * N + i + 1]
	var h01 := heights[(j + 1) * N + i]
	var h11 := heights[(j + 1) * N + i + 1]
	# the same diagonal split as the mesh and the collision
	if tx + tz <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)

func ground_at(x: float, z: float, from_y := 400.0) -> float:
	## highest solid surface (roofs included) under a point
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, -50, z), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit["position"] as Vector3).y if not hit.is_empty() else height_at(x, z)

# ------------------------------------------------------------------ terrain
func _tex(n: String) -> Texture2D:
	var p := TEX % n
	return load(p) as Texture2D if ResourceLoader.exists(p) else null

func _terrain() -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var tans := PackedFloat32Array()
	var uvs := PackedVector2Array()
	verts.resize(N * N)
	norms.resize(N * N)
	uvs.resize(N * N)
	tans.resize(N * N * 4)
	for j in N:
		for i in N:
			var k := j * N + i
			var h := heights[k]
			verts[k] = Vector3(-HALF + i * STEP, h, -HALF + j * STEP)
			var hl := heights[j * N + maxi(i - 1, 0)]
			var hr := heights[j * N + mini(i + 1, N - 1)]
			var hd := heights[maxi(j - 1, 0) * N + i]
			var hu := heights[mini(j + 1, N - 1) * N + i]
			var nrm := Vector3(hl - hr, 2.0 * STEP, hd - hu).normalized()
			norms[k] = nrm
			var tg := Vector3(2.0 * STEP, hr - hl, 0).normalized()
			tans[k * 4] = tg.x
			tans[k * 4 + 1] = tg.y
			tans[k * 4 + 2] = tg.z
			tans[k * 4 + 3] = 1.0
			uvs[k] = Vector2(i, j)
	var idx := PackedInt32Array()
	idx.resize((N - 1) * (N - 1) * 6)
	var n := 0
	for j in N - 1:
		for i in N - 1:
			var a := j * N + i
			var b := a + 1
			var c := a + N
			var d := c + 1
			# clockwise seen from above (Godot front faces); split along b-c like the height lookup
			idx[n] = a; idx[n + 1] = b; idx[n + 2] = c
			idx[n + 3] = b; idx[n + 4] = d; idx[n + 5] = c
			n += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TANGENT] = tans
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	mi.material_override = _terrain_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)

func _terrain_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = "shader_type spatial;
render_mode cull_back;
uniform sampler2D sand_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D road_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cob_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D splat : filter_linear;
uniform sampler2D macro : filter_linear_mipmap, repeat_enable;
uniform float half_size = 500.0;
varying vec3 wpos;
varying vec3 wn;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec2 uv = wpos.xz / 7.0;
	float m1 = texture(macro, wpos.xz / 210.0).r;
	float m2 = texture(macro, wpos.xz / 37.0).r;
	vec3 sand = texture(sand_a, uv).rgb * mix(0.62, 0.86, m1) * mix(0.92, 1.05, m2);
	sand = mix(sand, sand * vec3(1.06, 0.95, 0.84), smoothstep(0.45, 0.8, m1));
	vec4 sp = texture(splat, wpos.xz / (half_size * 2.0) + 0.5);
	vec3 road = texture(road_a, wpos.xz / 5.0).rgb;
	vec3 cob = texture(cob_a, wpos.xz / 3.5).rgb;
	vec3 col = mix(sand, road, sp.r * 0.9);
	col = mix(col, cob, sp.g);
	float slope = 1.0 - wn.y;
	vec3 rock = texture(rock_a, wpos.xz / 11.0 + wpos.y / 23.0).rgb * vec3(0.78, 0.66, 0.55) * mix(0.75, 1.1, m2);
	float rk = smoothstep(0.16, 0.34, slope + (m2 - 0.5) * 0.08);
	col = mix(col, rock, rk);
	ALBEDO = col;
	ROUGHNESS = mix(0.93, 0.85, rk);
	NORMAL_MAP = texture(sand_n, uv).rgb;
	NORMAL_MAP_DEPTH = mix(0.9, 0.5, sp.g);
}"
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("sand_a", _tex("sand_base"))
	m.set_shader_parameter("sand_n", _tex("sand_normal"))
	m.set_shader_parameter("road_a", _tex("dirt_road_base"))
	m.set_shader_parameter("cob_a", _tex("cobblestone_base"))
	m.set_shader_parameter("rock_a", _tex("plaster_damaged_base"))
	m.set_shader_parameter("half_size", HALF)
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	var fn := FastNoiseLite.new()
	fn.seed = rng.randi()
	fn.frequency = 0.02
	nt.noise = fn
	m.set_shader_parameter("macro", nt)
	m.set_shader_parameter("splat", _splat())
	return m

func _splat() -> ImageTexture:
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var p := Vector2((x + 0.5) / s * HALF * 2.0 - HALF, (y + 0.5) / s * HALF * 2.0 - HALF)
			var r := 0.0
			for rd in roads:
				var d := _seg_dist(p, rd[0], rd[1]).x
				r = maxf(r, smoothstep(5.5, 2.5, d))
			var g := 0.0
			for t in towns:
				g = maxf(g, smoothstep(float(t["r"]) * 0.32, float(t["r"]) * 0.22, p.distance_to(t["c"])))
				r = maxf(r, smoothstep(float(t["r"]) + 6.0, float(t["r"]) - 6.0, p.distance_to(t["c"])) * 0.55)
			for hm in hamlets:
				r = maxf(r, smoothstep(float(hm["r"]) + 4.0, float(hm["r"]) - 6.0, p.distance_to(hm["c"])) * 0.45)
			img.set_pixel(x, y, Color(r, g, 0, 1))
	return ImageTexture.create_from_image(img)

func _ground_collision() -> void:
	var cs := CollisionShape3D.new()
	var hs := HeightMapShape3D.new()
	hs.map_width = N
	hs.map_depth = N
	hs.map_data = heights
	cs.shape = hs
	cs.scale = Vector3(STEP, 1.0, STEP)
	world_body.add_child(cs)

# ------------------------------------------------------------------ buildings
func _mat(key: String, tex: String, tint := Color.WHITE, rough := 0.9, normal := false) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(tex + "_base")
	m.albedo_color = tint
	var nt := _tex(tex + "_normal") if normal else null
	if nt:
		m.normal_enabled = true
		m.normal_texture = nt
	m.roughness = rough
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m

const FACE_AXES := [[Vector3.RIGHT, Vector3.BACK, Vector3.UP], [Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
	[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
	[Vector3.BACK, Vector3.LEFT, Vector3.UP], [Vector3.FORWARD, Vector3.RIGHT, Vector3.UP]]

static func add_box(st: SurfaceTool, xf: Transform3D, center: Vector3, size: Vector3, tile := 2.4) -> void:
	## an axis-aligned box in the local frame of xf; UVs in metres / tile so textures keep their scale
	var h := size * 0.5
	for fa in FACE_AXES:
		var n: Vector3 = fa[0]
		var u: Vector3 = fa[1]
		var v: Vector3 = fa[2]
		var hn := absf(n.x) * h.x + absf(n.y) * h.y + absf(n.z) * h.z
		var hu := absf(u.x) * h.x + absf(u.y) * h.y + absf(u.z) * h.z
		var hv := absf(v.x) * h.x + absf(v.y) * h.y + absf(v.z) * h.z
		var c := center + n * hn
		var pts := [c - u * hu - v * hv, c + u * hu - v * hv, c + u * hu + v * hv, c - u * hu + v * hv]
		var uvs := [Vector2(-hu, hv), Vector2(hu, hv), Vector2(hu, -hv), Vector2(-hu, -hv)]
		var wn := (xf.basis * n).normalized()
		var tri := [[0, 2, 1], [0, 3, 2]]
		# keep clockwise winding as seen from outside
		var a: Vector3 = pts[0]
		var e1: Vector3 = (pts[2] as Vector3) - a
		var e2: Vector3 = (pts[1] as Vector3) - a
		if e1.cross(e2).dot(n) > 0.0:          # front faces wind clockwise as seen from outside
			tri = [[0, 1, 2], [0, 2, 3]]
		for t in tri:
			for k in t:
				var p: Vector3 = pts[k]
				var uvp: Vector2 = uvs[k]
				st.set_normal(wn)
				st.set_uv(uvp / tile + Vector2(center.x * 0.37 + center.z * 0.23, center.y * 0.31) / tile)
				st.add_vertex(xf * p)

func _collide(xf: Transform3D, center: Vector3, size: Vector3, body: StaticBody3D = null) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = xf * Transform3D(Basis.IDENTITY, center)
	(body if body else world_body).add_child(cs)

func _solid(sts: Dictionary, key: String, xf: Transform3D, center: Vector3, size: Vector3, tile := 2.4, body: StaticBody3D = null) -> void:
	add_box(sts[key], xf, center, size, tile)
	_collide(xf, center, size, body)

func _town(t: Dictionary, big: bool) -> void:
	var c: Vector2 = t["c"]
	var base: float = t["h"]
	var r: float = t["r"]
	var wall_keys := ["plaster_ochre", "mud_brick", "plaster_white", "sandstone_blocks"]
	var wk: String = wall_keys[rng.randi() % wall_keys.size()]
	var sts := {}
	for key in ["wall", "wall2", "roof", "floor", "wood", "fabric"]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts[key] = st
	var axis := rng.randf() * TAU
	var placed: Array = []
	var count := int(r / 5.5) if big else rng.randi_range(1, 3)
	var tries := 0
	while placed.size() < count and tries < count * 30:
		tries += 1
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(r * 0.36, r - 7.0) if big else rng.randf_range(0.0, r - 6.0)
		var p := c + Vector2(cos(ang), sin(ang)) * dist
		var w := rng.randf_range(6.5, 10.5)
		var d := rng.randf_range(6.0, 9.0)
		var rad := Vector2(w, d).length() * 0.5 + 2.6
		var ok := true
		for q in placed:
			if p.distance_to(q[0]) < rad + float(q[1]):
				ok = false
				break
		if not ok:
			continue
		placed.append([p, rad])
		var face := c - p
		# doors (local -z) look towards the square
		var rot: float = axis + round((atan2(-face.x, -face.y) - axis) / (PI / 2.0)) * (PI / 2.0)
		_house(sts, Transform3D(Basis(Vector3.UP, rot), Vector3(p.x, base, p.y)), w, d, rng.randf() < 0.55, rng.randf() < 0.5)
	if big:
		# watchtower in the square, stalls around it, broken town wall
		_tower(sts, Transform3D(Basis(Vector3.UP, axis), Vector3(c.x, base, c.y) + Basis(Vector3.UP, axis) * Vector3(r * 0.12, 0, -r * 0.1)))
		for i in rng.randi_range(3, 5):
			var a2 := axis + TAU * i / 5.0 + rng.randf_range(-0.3, 0.3)
			var sp := c + Vector2(cos(a2), sin(a2)) * rng.randf_range(r * 0.18, r * 0.28)
			_stall(sts, Transform3D(Basis(Vector3.UP, a2), Vector3(sp.x, base, sp.y)))
		_town_wall(sts, c, r + 3.0, base)
	var parent := Node3D.new()
	parent.name = "Town" if big else "Hamlet"
	add_child(parent)
	var mats := {"wall": _mat("wall_" + wk, wk), "wall2": _mat("wall2", "plaster_white", Color(0.96, 0.93, 0.86)),
		"roof": _mat("roof", "concrete", Color(0.86, 0.82, 0.76)), "floor": _mat("floor", "floor_tiles"),
		"wood": _mat("wood", "wood_dark"), "fabric": _mat("fabric", "fabric_stripes")}
	for key in sts:
		var st: SurfaceTool = sts[key]
		var mesh := st.commit()
		if mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mats[key]
		if key == "fabric":
			(mats[key] as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.visibility_range_end = 900.0
		parent.add_child(mi)

func _house(sts: Dictionary, xf: Transform3D, w: float, d: float, stairs: bool, alt: bool) -> void:
	var hgt := 3.3
	var th := 0.3
	var wk := "wall2" if alt else "wall"
	var hw := w * 0.5
	var hd := d * 0.5
	# floor and roof
	_solid(sts, "floor", xf, Vector3(0, 0.1, 0), Vector3(w, 0.2, d), 2.0)
	_solid(sts, "roof", xf, Vector3(0, hgt + 0.13, 0), Vector3(w + 0.3, 0.26, d + 0.3), 3.0)
	# door in the south wall (local -z), windows in the east and west walls
	var door_x := rng.randf_range(-hw + 1.4, hw - 1.4)
	var dw := 1.3
	var dh := 2.3
	_wall_with_hole(sts, wk, xf, Vector3(0, 0, -hd + th * 0.5), Vector3.RIGHT, w, hgt, th, door_x, dw, 0.0, dh)
	_wall_with_hole(sts, wk, xf, Vector3(0, 0, hd - th * 0.5), Vector3.RIGHT, w, hgt, th, rng.randf_range(-hw + 1.4, hw - 1.4), 1.1, 1.1, 2.1)
	_wall_with_hole(sts, wk, xf, Vector3(hw - th * 0.5, 0, 0), Vector3.BACK, d - th * 2.0, hgt, th, rng.randf_range(-hd + 1.6, hd - 1.6), 1.1, 1.1, 2.1)
	_wall_with_hole(sts, wk, xf, Vector3(-hw + th * 0.5, 0, 0), Vector3.BACK, d - th * 2.0, hgt, th, rng.randf_range(-hd + 1.6, hd - 1.6), 1.1, 1.1, 2.1)
	# parapet on the roof (with a gap where the stairs arrive)
	var py := hgt + 0.26 + 0.3
	_solid(sts, wk, xf, Vector3(0, py, -hd - 0.05), Vector3(w + 0.3, 0.6, 0.25))
	_solid(sts, wk, xf, Vector3(0, py, hd + 0.05), Vector3(w + 0.3, 0.6, 0.25))
	_solid(sts, wk, xf, Vector3(-hw - 0.05, py, 0), Vector3(0.25, 0.6, d + 0.3))
	if stairs and d >= 6.0:
		# masonry stairs along the outside of the east wall, from the back corner up to the roof
		var run := 5.4
		var rise := hgt + 0.26
		var n := 14
		var z0 := hd - 0.2
		for i in n:
			var top := rise * (i + 1) / n
			var zc := z0 - run * (i + 0.5) / n
			add_box(sts[wk], xf, Vector3(hw + 0.6, top * 0.5, zc), Vector3(1.1, top, run / n + 0.01))
			# solid masonry under the ramp, a little below its surface (nothing to walk into from the side)
			var ct := maxf(0.05, rise * i / n - 0.12)
			_collide(xf, Vector3(hw + 0.6, ct * 0.5, zc), Vector3(1.1, ct, run / n + 0.01))
		var ang := atan2(rise, run)
		var ln := sqrt(run * run + rise * rise)
		var ramp := Transform3D(Basis(Vector3.RIGHT, ang), Vector3(hw + 0.6, rise * 0.5 - 0.06, z0 - run * 0.5))
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.1, 0.12, ln)
		cs.shape = bs
		cs.transform = xf * ramp
		world_body.add_child(cs)
		# parapet on the east side only where the stairs are not
		var free := d - run
		_solid(sts, wk, xf, Vector3(hw + 0.05, py, -hd + free * 0.5 - 0.15), Vector3(0.25, 0.6, maxf(0.3, free)))
		var top_z := z0 - run + 0.4
		_loot(xf * Vector3(rng.randf_range(-hw + 1.0, hw - 1.0), hgt + 0.5, rng.randf_range(-hd + 1.0, hd - 1.0)), xf * Vector3(hw + 0.6, 0.3, hd + 1.2), false,
			[xf * Vector3(hw + 0.6, 0.3, hd + 1.2), xf * Vector3(hw + 0.6, rise + 0.2, top_z), xf * Vector3(hw - 1.0, rise + 0.2, top_z)])
	else:
		_solid(sts, wk, xf, Vector3(hw + 0.05, py, 0), Vector3(0.25, 0.6, d + 0.3))
	# loot inside
	var door := xf * Vector3(door_x, 0.3, -hd - 1.6)
	var in_door := xf * Vector3(door_x, 0.3, -hd + 1.0)
	for i in rng.randi_range(1, 3):
		_loot(xf * Vector3(rng.randf_range(-hw + 0.9, hw - 0.9), 0.35, rng.randf_range(-hd + 0.9, hd - 0.9)), door, true, [door, in_door])
	var c := xf.origin
	footprints.append({"c": Vector2(c.x, c.z), "half": Vector2(hw, hd), "rot": xf.basis.get_euler().y})

func _wall_with_hole(sts: Dictionary, wk: String, xf: Transform3D, center: Vector3, along: Vector3, length: float, hgt: float, th: float,
		hx: float, hw: float, y0: float, y1: float) -> void:
	## a wall along `along` (local x or z) with one opening [hx-hw/2, hx+hw/2] x [y0, y1]
	var across := Vector3(absf(along.z), 0, absf(along.x))
	var a0 := -length * 0.5
	var l0 := hx - hw * 0.5 - a0
	var l1 := length * 0.5 - (hx + hw * 0.5)
	var parts := []
	if l0 > 0.02:
		parts.append([a0 + l0 * 0.5, l0, 0.0, hgt])
	if l1 > 0.02:
		parts.append([hx + hw * 0.5 + l1 * 0.5, l1, 0.0, hgt])
	parts.append([hx, hw, y1, hgt])
	if y0 > 0.02:
		parts.append([hx, hw, 0.0, y0])
	for pt in parts:
		var mid: float = pt[0]
		var len_: float = pt[1]
		var b0: float = pt[2]
		var b1: float = pt[3]
		var sz := along * len_ + across * th + Vector3.UP * (b1 - b0)
		_solid(sts, wk, xf, center + along * mid + Vector3.UP * (b0 + b1) * 0.5, sz)

func _tower(sts: Dictionary, xf: Transform3D) -> void:
	_solid(sts, "wall", xf, Vector3(0, 6.0, 0), Vector3(3.4, 12.0, 3.4))
	_solid(sts, "roof", xf, Vector3(0, 12.2, 0), Vector3(4.2, 0.4, 4.2), 3.0)
	for s in [-1.0, 1.0]:
		_solid(sts, "wall", xf, Vector3(s * 1.95, 12.9, 0), Vector3(0.3, 1.0, 4.2))
		_solid(sts, "wall", xf, Vector3(0, 12.9, s * 1.95), Vector3(4.2, 1.0, 0.3))
	add_box(sts["wood"], xf, Vector3(0, 13.6, 0), Vector3(4.4, 0.15, 4.4))

func _stall(sts: Dictionary, xf: Transform3D) -> void:
	for p in [Vector2(-1.4, -0.9), Vector2(1.4, -0.9), Vector2(-1.4, 0.9), Vector2(1.4, 0.9)]:
		_solid(sts, "wood", xf, Vector3(p.x, 1.2, p.y), Vector3(0.12, 2.4, 0.12), 1.2, props_body)
	add_box(sts["fabric"], xf, Vector3(0, 2.45, 0), Vector3(3.3, 0.04, 2.3), 3.3)
	_solid(sts, "wood", xf, Vector3(0, 0.45, -0.4), Vector3(2.6, 0.9, 0.8), 1.5, props_body)
	_loot(xf * Vector3(0, 0.95, -0.4), xf * Vector3(0, 0.3, 1.6), false, [xf * Vector3(0, 0.3, 0.6)])

func _town_wall(sts: Dictionary, c: Vector2, r: float, base: float) -> void:
	var segs := int(TAU * r / 9.0)
	for i in segs:
		if rng.randf() < 0.38:
			continue          # breaches and gates
		var a := TAU * (i + 0.5) / segs
		var p := c + Vector2(cos(a), sin(a)) * r
		var on_road := false
		for rd in roads:
			if _seg_dist(p, rd[0], rd[1]).x < 9.0:
				on_road = true
		if on_road:
			continue          # gates where the roads come in
		var xf := Transform3D(Basis(Vector3.UP, -a + PI / 2.0), Vector3(p.x, base, p.y))
		_solid(sts, "wall", xf, Vector3(0, 1.1, 0), Vector3(TAU * r / segs + 0.2, 2.6, 0.6))

# ------------------------------------------------------------------ rocks, crates, loot
func _rock_mesh(seed_v: int) -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 10
	sm.rings = 6
	var arr := sm.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var fn := FastNoiseLite.new()
	fn.seed = seed_v
	fn.frequency = 1.1
	for i in v.size():
		var p := v[i]
		v[i] = p * (1.0 + fn.get_noise_3dv(p * 1.3) * 0.32)
	arr[Mesh.ARRAY_VERTEX] = v
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	for i in idx:
		st.set_uv(uv[i] * Vector2(3.0, 1.5))
		st.add_vertex(v[i])
	st.generate_normals()
	st.generate_tangents()
	return st.commit()

func _rocks() -> void:
	var meshes := []
	var shapes := []
	for i in 5:
		var rm := _rock_mesh(rng.randi())
		meshes.append(rm)
		shapes.append(rm.create_convex_shape(true, false))
	var mat := _mat("rock", "plaster_damaged", Color(0.82, 0.70, 0.58), 0.95)
	var placed := 0
	var tries := 0
	while placed < 90 and tries < 900:
		tries += 1
		var x := rng.randf_range(-430, 430)
		var z := rng.randf_range(-430, 430)
		var p := Vector2(x, z)
		var ok := true
		for s in towns + hamlets:
			if p.distance_to(s["c"]) < float(s["r"]) + 12.0:
				ok = false
				break
		for rd in roads:
			if _seg_dist(p, rd[0], rd[1]).x < 8.0:
				ok = false
		if not ok:
			continue
		var sc := rng.randf_range(1.2, 4.2)
		var vi := rng.randi() % meshes.size()
		var mesh: ArrayMesh = meshes[vi]
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc * rng.randf_range(0.9, 1.5), sc * rng.randf_range(0.55, 0.9), sc)), Vector3(x, height_at(x, z) - sc * 0.2, z))
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.transform = xf
		mi.visibility_range_end = 700.0
		add_child(mi)
		var cs := CollisionShape3D.new()
		cs.shape = shapes[vi]
		cs.transform = xf
		world_body.add_child(cs)
		if sc > 2.4 and rng.randf() < 0.45:
			var side := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * (sc * 1.6 + 1.0)
			var lp := Vector3(x, 0, z) + side
			lp.y = height_at(lp.x, lp.z) + 0.3
			_loot(lp, lp, false)
		placed += 1

func _open_crates() -> void:
	## loose supply crates in the open desert
	var sts := {"wood": SurfaceTool.new()}
	sts["wood"].begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 26:
		var x := rng.randf_range(-420, 420)
		var z := rng.randf_range(-420, 420)
		var h := height_at(x, z)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x, h, z))
		_solid(sts, "wood", xf, Vector3(0, 0.5, 0), Vector3(1.2, 1.0, 1.2), 1.2, props_body)
		if rng.randf() < 0.5:
			_solid(sts, "wood", xf, Vector3(1.0, 0.4, 0.4), Vector3(0.8, 0.8, 0.8), 1.2, props_body)
		_loot(xf * Vector3(0, 0.3, -1.3), xf * Vector3(0, 0.3, -1.3), false)
	var mi := MeshInstance3D.new()
	var st: SurfaceTool = sts["wood"]
	mi.mesh = st.commit()
	mi.material_override = _mat("crate", "wood_planks")
	add_child(mi)

func _loot(pos: Vector3, door: Vector3, inside: bool, path: Array = []) -> void:
	loot_points.append({"pos": pos, "door": door, "inside": inside, "path": path})

# ------------------------------------------------------------------ light and air
func _lights() -> void:
	env = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.20, 0.40, 0.70)
	sm.sky_horizon_color = Color(0.80, 0.74, 0.66)
	sm.ground_horizon_color = Color(0.74, 0.62, 0.48)
	sm.ground_bottom_color = Color(0.45, 0.37, 0.28)
	sm.sun_angle_max = 25.0
	sky.sky_material = sm
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.45
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.86, 0.76, 0.62)
	env.fog_density = 0.0009
	env.fog_sun_scatter = 0.25
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.35
	var pc := not G.mobile
	env.ssao_enabled = pc and int(G.settings["quality"]) >= 1
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.90, 0.76)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 140.0 if pc else 90.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, Vector3(0.45, -0.62, 0.64).normalized(), Vector3.UP)

func _map_image() -> void:
	## the minimap: sand shaded by slope, roads, square cobbles, houses as dark blocks
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var wx := (x + 0.5) / s * HALF * 2.0 - HALF
			var wz := (y + 0.5) / s * HALF * 2.0 - HALF
			var h := height_at(wx, wz)
			var hx := height_at(wx + 4.0, wz) - h
			var hz := height_at(wx, wz + 4.0) - h
			var shade := clampf(0.86 - hx * 0.05 - hz * 0.035, 0.5, 1.15)
			var col := Color(0.80, 0.68, 0.48) * shade
			col = col.lerp(Color(0.55, 0.45, 0.36), clampf((h - 40.0) / 60.0, 0.0, 0.7))
			var p := Vector2(wx, wz)
			for rd in roads:
				if _seg_dist(p, rd[0], rd[1]).x < 4.5:
					col = Color(0.62, 0.52, 0.38)
			col.a = 1.0
			img.set_pixel(x, y, col)
	for f in footprints:
		var c: Vector2 = f["c"]
		var hh: Vector2 = f["half"]
		var rot: float = f["rot"]
		var b := Basis(Vector3.UP, rot)
		var steps := 6
		for i in steps + 1:
			for j in steps + 1:
				var lp := b * Vector3(-hh.x + 2.0 * hh.x * i / steps, 0, -hh.y + 2.0 * hh.y * j / steps)
				var px := int((c.x + lp.x + HALF) / (HALF * 2.0) * s)
				var py := int((c.y + lp.z + HALF) / (HALF * 2.0) * s)
				if px >= 0 and py >= 0 and px < s and py < s:
					img.set_pixel(px, py, Color(0.36, 0.27, 0.20))
	map_tex = ImageTexture.create_from_image(img)

# ------------------------------------------------------------------ queries used by the shared match code
func surface_at(p: Vector3) -> String:
	return "stone" if p.y > height_at(p.x, p.z) + 0.25 else "sand"

func name_at(p: Vector3) -> String:
	var q := Vector2(p.x, p.z)
	for t in towns:
		if q.distance_to(t["c"]) < float(t["r"]) + 25.0:
			return t["name"]
	return "الصحراء"

func site_at(_p: Vector3) -> String:
	return ""
