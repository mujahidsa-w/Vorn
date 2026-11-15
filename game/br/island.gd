class_name BRIsland
extends BRLand
## The second battle royale map: the green island of Last Circle (Borovaya region), baked into assets/island by
## tools/island/bake_island.gd — terrain, houses with their furniture, barns, roads, trees, grass and every collider —
## plus its data: heights, ground types, places, roads, buildings and loot points with the walk in from outside.
## The rest of the battle royale (plane, storm, loot, bots, vehicles, drops) runs on it unchanged.

const DIR := "res://assets/island"
const PLACE_AR := {"BOROVAYA": "بوروفايا", "NORTH FARM": "المزرعة الشمالية", "RADIO HILL": "تل الراديو", "FORESTRY": "الغابة"}

var idata: Dictionary
var gn := 257
var gstep := 3.90625
var surf := PackedByteArray()
var surf_names := {}

static func available() -> bool:
	return ResourceLoader.exists(DIR + "/island_static.scn") and FileAccess.file_exists(DIR + "/island_data.json")

func build(seed_v: int) -> void:
	var t0 := Time.get_ticks_msec()
	rng.seed = seed_v
	data = {}
	idata = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/island_data.json"))
	gn = int(idata["n"])
	gstep = float(idata["step"])
	heights = PackedFloat32Array(idata["heights"])
	surf.resize(gn * gn)
	var codes: Array = idata["surface"]
	for i in codes.size():
		surf[i] = int(codes[i])
	for k in idata["surface_codes"]:
		surf_names[int(idata["surface_codes"][k])] = k
	world_body = StaticBody3D.new()
	world_body.name = "WorldBody"
	add_child(world_body)
	props_body = StaticBody3D.new()
	props_body.name = "PropsBody"
	props_body.set_meta("wood", true)
	add_child(props_body)
	for part in ["terrain", "static", "foliage", "collision"]:
		var ps := load("%s/island_%s.scn" % [DIR, part]) as PackedScene
		var n := ps.instantiate()
		add_child(n)
		if part == "foliage" and G.mobile:
			# phones: grass only right around the player
			for mm in n.find_children("*", "MultiMeshInstance3D", true, false):
				var g := mm as MultiMeshInstance3D
				if g.visibility_range_end < 100.0:
					g.visibility_range_end = 45.0
	_sea()
	_places()
	_island_loot()
	_lights()
	_map_image()
	print("[br] island built in %d ms: %d places, %d buildings, %d loot points" % [Time.get_ticks_msec() - t0, towns.size(), footprints.size(), loot_points.size()])

const WATER := "shader_type spatial;
render_mode cull_disabled, shadows_disabled;
uniform vec3 deep : source_color = vec3(0.07, 0.20, 0.27);
uniform vec3 shallow : source_color = vec3(0.16, 0.36, 0.40);
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float t = TIME * 0.6;
	vec2 p = wp.xz * 0.05;
	vec3 n = normalize(vec3(sin(p.x * 3.1 + t) * 0.06 + sin(p.y * 2.3 - t * 1.3) * 0.05, 1.0, cos(p.y * 3.7 + t * 0.8) * 0.06 + sin((p.x + p.y) * 1.7 + t) * 0.04));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float far = clamp(length(wp.xz) / 1400.0, 0.0, 1.0);
	ALBEDO = mix(shallow, deep, far);
	ROUGHNESS = 0.06;
	SPECULAR = 0.65;
	METALLIC = 0.0;
}"

func _sea() -> void:
	## the island ends in a shore: grass running down to sand and under the water, then open sea to the horizon
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(7000, 7000)
	sea.mesh = pm
	sea.position = Vector3(0, -0.8, 0)
	var wm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = WATER
	wm.shader = sh
	sea.material_override = wm
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	# a closed loop round the edge of the height map, each point with its outward direction
	var loop: Array = []
	var last := gn - 1
	for i in gn:
		loop.append([i, 0, Vector2(0, -1)])
	for j in range(1, gn):
		loop.append([last, j, Vector2(1, 0)])
	for i in range(last - 1, -1, -1):
		loop.append([i, last, Vector2(0, 1)])
	for j in range(last - 1, 0, -1):
		loop.append([0, j, Vector2(-1, 0)])
	for k in loop.size():
		var a: Array = loop[k]
		if (a[0] == 0 or a[0] == last) and (a[1] == 0 or a[1] == last):
			a[2] = Vector2(-1.0 if a[0] == 0 else 1.0, -1.0 if a[1] == 0 else 1.0).normalized()
	var rings := [[0.0, 0.0], [30.0, 0.6], [55.0, -0.2], [110.0, -3.0], [260.0, -14.0], [700.0, -40.0]]
	var cols := [Color(0.33, 0.45, 0.22), Color(0.74, 0.68, 0.50), Color(0.58, 0.52, 0.38), Color(0.30, 0.30, 0.24), Color(0.12, 0.16, 0.16), Color(0.08, 0.1, 0.1)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := []
	for a in loop:
		var x := -HALF + int(a[0]) * gstep
		var z := -HALF + int(a[1]) * gstep
		var h0 := heights[int(a[1]) * gn + int(a[0])]
		var row := []
		for r in rings.size():
			var o: Vector2 = (a[2] as Vector2) * float(rings[r][0])
			var y: float = h0 if r == 0 else (lerpf(h0, float(rings[r][1]), 0.85) if r == 1 else float(rings[r][1]))
			row.append([Vector3(x + o.x, y, z + o.y), cols[r]])
		pts.append(row)
	for k in pts.size():
		var r0: Array = pts[k]
		var r1: Array = pts[(k + 1) % pts.size()]
		for r in rings.size() - 1:
			var q := [r0[r], r1[r], r1[r + 1], r0[r], r1[r + 1], r0[r + 1]]
			for v in q:
				st.set_color(v[1])
				st.set_normal(Vector3.UP)
				st.add_vertex(v[0])
	st.generate_normals()
	var shore := MeshInstance3D.new()
	shore.mesh = st.commit()
	var sm := StandardMaterial3D.new()
	sm.vertex_color_use_as_albedo = true
	sm.roughness = 0.95
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	shore.material_override = sm
	add_child(shore)
	# nobody walks off the edge of the battlefield
	for side in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(4.0 if side.x != 0.0 else HALF * 2.2, 400.0, 4.0 if side.z != 0.0 else HALF * 2.2)
		cs.shape = bs
		cs.position = side * (HALF + 2.0) + Vector3(0, 150.0, 0)
		world_body.add_child(cs)

func _v(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _places() -> void:
	for b in idata["buildings"]:
		footprints.append({"c": Vector2(b["c"][0], b["c"][1]), "half": Vector2(b["size"][0], b["size"][1]) * 0.5, "rot": float(b["rot"])})
	for p in idata["places"]:
		var c := Vector2(p["c"][0], p["c"][1])
		var r := 35.0
		for f in footprints:
			var d := c.distance_to(f["c"])
			if d < 170.0:
				r = maxf(r, d + 14.0)
		towns.append({"name": PLACE_AR.get(String(p["name"]), String(p["name"])), "c": c, "r": r, "h": height_at(c.x, c.y)})
	for rd in idata["roads"]:
		var pts: Array = rd["points"]
		for i in pts.size() - 1:
			var a := Vector2(pts[i][0], pts[i][1])
			var b := Vector2(pts[i + 1][0], pts[i + 1][1])
			roads.append([a, b, height_at(a.x, a.y), height_at(b.x, b.y)])

func _island_loot() -> void:
	## the island's own loot spots (indoors with the way in), then spots in the open: by cover, along roads, at houses
	for l in idata["loot"]:
		var p := _v(l["p"])
		var path: Array = []
		for q in l["path"]:
			path.append(_v(q))
		var inside := String(l["in"]) != ""
		_loot(p, path[0] if path.size() > 0 else p, inside, path)
	var cover: Array = idata["cover"]
	for i in range(0, cover.size(), 3):
		var c := _v(cover[i])
		_loot(c, c, false)
	for rd in roads:
		for k in 3:
			var t := rng.randf_range(0.15, 0.85)
			var a: Vector2 = rd[0]
			var b: Vector2 = rd[1]
			var p2 := a.lerp(b, t) + (b - a).normalized().orthogonal() * rng.randf_range(5.0, 9.0) * (1.0 if rng.randf() < 0.5 else -1.0)
			_loot(Vector3(p2.x, height_at(p2.x, p2.y) + 0.3, p2.y), Vector3(p2.x, 0, p2.y), false)

func height_at(x: float, z: float) -> float:
	var half: float = HALF
	var fx := clampf((x + half) / gstep, 0.0, gn - 1.001)
	var fz := clampf((z + half) / gstep, 0.0, gn - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var h00 := heights[j * gn + i]
	var h10 := heights[j * gn + i + 1]
	var h01 := heights[(j + 1) * gn + i]
	var h11 := heights[(j + 1) * gn + i + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)

func surface_at(p: Vector3) -> String:
	if p.y > height_at(p.x, p.z) + 0.35:
		return "tile"          # floors, stairs, roofs
	var i := clampi(int(round((p.x + HALF) / gstep)), 0, gn - 1)
	var j := clampi(int(round((p.z + HALF) / gstep)), 0, gn - 1)
	var s: String = surf_names.get(int(surf[j * gn + i]), "grass")
	return "stone" if s in ["gravel", "metal"] else "grass"

func _lights() -> void:
	## the same light rig as the desert, tuned for green country: bluer sky and haze, a whiter sun
	super._lights()
	var sm := env.sky.sky_material as ProceduralSkyMaterial
	sm.sky_top_color = Color(0.26, 0.46, 0.74)
	sm.sky_horizon_color = Color(0.70, 0.76, 0.80)
	sm.ground_horizon_color = Color(0.52, 0.58, 0.50)
	sm.ground_bottom_color = Color(0.28, 0.33, 0.26)
	env.ambient_light_color = Color(0.70, 0.76, 0.72)
	env.fog_light_color = Color(0.72, 0.78, 0.82)
	env.fog_density = 0.0011
	env.adjustment_saturation = 1.04
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.55
	# the island's storm is a wall of rain and grey cloud, not sand
	fog_base = Color(0.72, 0.78, 0.82)
	fog_dens = 0.0010
	storm_tint = Color(0.36, 0.42, 0.52)
	wall_dark = Color(0.22, 0.27, 0.36)
	wall_light = Color(0.62, 0.68, 0.78)

func _map_image() -> void:
	## the island map: grass shaded by slope, gravel, roads, houses
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var wx := (x + 0.5) / s * HALF * 2.0 - HALF
			var wz := (y + 0.5) / s * HALF * 2.0 - HALF
			var h := height_at(wx, wz)
			var hx := height_at(wx + 4.0, wz) - h
			var hz := height_at(wx, wz + 4.0) - h
			var shade := clampf(0.9 - hx * 0.06 - hz * 0.045, 0.55, 1.2)
			var col := Color(0.40, 0.55, 0.30) * shade
			if surface_at(Vector3(wx, h, wz)) == "stone":
				col = Color(0.55, 0.53, 0.48) * shade
			var p := Vector2(wx, wz)
			for rd in roads:
				if _seg_dist(p, rd[0], rd[1]).x < 4.5:
					col = Color(0.30, 0.30, 0.30)
			col.a = 1.0
			img.set_pixel(x, y, col)
	for f in footprints:
		var c: Vector2 = f["c"]
		var hh: Vector2 = f["half"]
		var b := Basis(Vector3.UP, float(f["rot"]))
		for i in 9:
			for j in 9:
				var lp := b * Vector3(-hh.x + 2.0 * hh.x * i / 8.0, 0, -hh.y + 2.0 * hh.y * j / 8.0)
				var px := int((c.x + lp.x + HALF) / (HALF * 2.0) * s)
				var py := int((c.y + lp.z + HALF) / (HALF * 2.0) * s)
				if px >= 0 and py >= 0 and px < s and py < s:
					img.set_pixel(px, py, Color(0.78, 0.74, 0.66))
	map_tex = ImageTexture.create_from_image(img)
