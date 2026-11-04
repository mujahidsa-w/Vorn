extends Node3D
## The open world around and inside the city ring: mountains, valleys, forest, lake, desert,
## a village, a ranch, a radio tower and the roads that connect them to the city.
## The landscape comes from assets/world (made by tools/gen_world.py) and is streamed in chunks:
## far away it is one coarse mesh per region, close by it gets full detail, trees and collision.

const CH := 32                 # cells per chunk (320 m)
const SUPER := 3               # chunks per region side (960 m)
const CARDS := {"pine": [Rect2(225, 0, 150, 228), 12.0, 6.5], "oak": [Rect2(775, 405, 240, 240), 10.0, 10.0],
	"elm": [Rect2(845, 815, 177, 207), 9.0, 7.5], "birch": [Rect2(250, 738, 175, 187), 8.5, 7.5], "bush": [Rect2(845, 672, 177, 140), 2.6, 3.2]}

var world
var Q := 1
var nx := 0
var nz := 0
var x0 := 0.0
var z0 := 0.0
var cell := 10.0
var H := PackedFloat32Array()
var B := PackedByteArray()
var info := {}
var roads: Array = []          # parsed roads: {name, kind, width, pts: PackedVector3Array, bridge: Array}
var places: Array = []
var lake_level := 41.0
var roadmask := PackedByteArray()   # 1 where trees must not grow (roads, buildings)

var mat_terrain: ShaderMaterial
var mat_veg: ShaderMaterial
var mat_vc: StandardMaterial3D
var mat_card: ShaderMaterial
var window_mat: StandardMaterial3D
var tower_light: OmniLight3D
var tower_bulb: StandardMaterial3D
var tree_mesh := {}
var regions := {}              # Vector2i -> {far: MeshInstance3D, near: bool, chunks: {Vector2i: Dictionary}}
var _col := {}                 # chunk -> StaticBody3D (terrain + tree trunks)
var _queue: Array = []
var _t := 0.0
var _update_t := 0.0
var near_r := 900.0
var col_r := 420.0
var tree_r := 520.0
var ready_ok := false


func _ready() -> void:
	Q = clampi(int(Game.settings.quality), 0, 2)
	if Game.touch:
		Q = 0
	near_r = [700.0, 900.0, 1100.0][Q]
	tree_r = [330.0, 480.0, 650.0][Q]
	col_r = [340.0, 420.0, 480.0][Q]
	if not _load_data():
		return
	_materials()
	_build_tree_meshes()
	_build_roads()
	_build_places()
	_build_far()
	ready_ok = true


# ---------------------------------------------------------------- data
func _load_data() -> bool:
	var jf := FileAccess.open("res://assets/world/world.json", FileAccess.READ)
	var hf := FileAccess.open("res://assets/world/height.bin", FileAccess.READ)
	var bf := FileAccess.open("res://assets/world/biome.bin", FileAccess.READ)
	if jf == null or hf == null or bf == null:
		push_warning("world data missing")
		return false
	info = JSON.parse_string(jf.get_as_text())
	nx = int(info.nx)
	nz = int(info.nz)
	x0 = float(info.x0)
	z0 = float(info.z0)
	cell = float(info.cell)
	lake_level = float(info.lake_level)
	H = hf.get_buffer(nx * nz * 4).to_float32_array()
	B = bf.get_buffer(nx * nz)
	roadmask.resize(nx * nz)
	for r in info.roads:
		var pts := PackedVector3Array()
		for p in r.pts:
			pts.append(Vector3(p[0], p[1], p[2]))
		roads.append({"name": r.name, "kind": r.kind, "width": float(r.width), "pts": pts, "bridge": r.bridge,
			"start_route": int(r.start_route), "end_route": int(r.end_route)})
		var rad := int(ceil((float(r.width) * 0.5 + 6.0) / cell))
		for p in pts:
			var ci := int(round((p.x - x0) / cell))
			var cj := int(round((p.z - z0) / cell))
			for dj in range(-rad, rad + 1):
				for di in range(-rad, rad + 1):
					var a := ci + di
					var b := cj + dj
					if a >= 0 and b >= 0 and a < nx and b < nz:
						roadmask[b * nx + a] = 1
	places = info.places
	for hs in info.houses + info.ranch:
		_mask_disc(hs[0], hs[1], 14.0)
	for p in places:
		if p.kind in ["gas", "tower", "lookout"]:
			_mask_disc(p.x, p.z, 26.0)
	return true


func _mask_disc(x: float, z: float, r: float) -> void:
	var rad := int(ceil(r / cell))
	var ci := int(round((x - x0) / cell))
	var cj := int(round((z - z0) / cell))
	for dj in range(-rad, rad + 1):
		for di in range(-rad, rad + 1):
			var a := ci + di
			var b := cj + dj
			if a >= 0 and b >= 0 and a < nx and b < nz:
				roadmask[b * nx + a] = 1


func _h(i: int, j: int) -> float:
	return H[clampi(j, 0, nz - 1) * nx + clampi(i, 0, nx - 1)]


func _b(i: int, j: int) -> int:
	return B[clampi(j, 0, nz - 1) * nx + clampi(i, 0, nx - 1)]


func height_at(x: float, z: float) -> float:
	var fx := (x - x0) / cell
	var fz := (z - z0) / cell
	var i := clampi(int(floor(fx)), 0, nx - 2)
	var j := clampi(int(floor(fz)), 0, nz - 2)
	var tx := clampf(fx - i, 0.0, 1.0)
	var tz := clampf(fz - j, 0.0, 1.0)
	return lerpf(lerpf(_h(i, j), _h(i + 1, j), tx), lerpf(_h(i, j + 1), _h(i + 1, j + 1), tx), tz)


func biome_at(x: float, z: float) -> int:
	return _b(int(round((x - x0) / cell)), int(round((z - z0) / cell)))


func in_world(x: float, z: float) -> bool:
	return x > x0 and z > z0 and x < x0 + (nx - 1) * cell and z < z0 + (nz - 1) * cell


# ---------------------------------------------------------------- materials
func _materials() -> void:
	mat_terrain = ShaderMaterial.new()
	mat_terrain.shader = load("res://assets/fx/terrain.gdshader")
	mat_terrain.set_shader_parameter("grass_tex", load("res://assets/models/map/la_3.png"))
	mat_terrain.set_shader_parameter("rock_tex", load("res://assets/world/rock.png"))
	mat_terrain.set_shader_parameter("sand_tex", load("res://assets/models/map/la_13.png"))
	mat_veg = ShaderMaterial.new()
	mat_veg.shader = load("res://assets/fx/vegetation.gdshader")
	mat_card = ShaderMaterial.new()
	mat_card.shader = load("res://assets/fx/foliage.gdshader")
	mat_card.set_shader_parameter("albedo_tex", load("res://assets/models/map/la_0.png"))
	mat_card.set_shader_parameter("albedo_col", Color(0.92, 0.95, 0.88))
	if world and world.sky:
		world.sky.foliage_mats.append(mat_card)
	mat_vc = StandardMaterial3D.new()
	mat_vc.vertex_color_use_as_albedo = true
	mat_vc.roughness = 0.75
	window_mat = StandardMaterial3D.new()
	window_mat.albedo_color = Color(0.15, 0.17, 0.2)
	window_mat.roughness = 0.1
	window_mat.metallic = 0.4
	window_mat.emission_enabled = true
	window_mat.emission = Color(1.0, 0.78, 0.45)
	window_mat.emission_energy_multiplier = 0.0


func _vertex_look(i: int, j: int, n: Vector3) -> Array:
	# returns [Color weights (grass, rock, sand, snow), darkness]
	var b := _b(i, j)
	var hh := _h(i, j)
	var slope := 1.0 - n.y
	var grass := 1.0
	var rock := 0.0
	var sand := 0.0
	var snow := 0.0
	var dark := 0.0
	match b:
		2:
			dark = 1.0
		3:
			rock = 1.0
			grass = 0.2
		4:
			snow = 1.0
			grass = 0.0
		5:
			sand = 1.0
			grass = 0.0
		6:
			sand = 0.8
			grass = 0.4
		7:
			sand = 1.0
			grass = 0.0
			dark = 0.6
	rock = maxf(rock, smoothstep(0.22, 0.42, slope))
	if hh > 520.0:
		snow = maxf(snow, smoothstep(520.0, 600.0, hh) * (1.0 - smoothstep(0.35, 0.6, slope)))
	return [Color(grass * (1.0 - rock), rock, sand * (1.0 - rock * 0.6), snow), dark]


func _normal(i: int, j: int) -> Vector3:
	var dx := _h(i + 1, j) - _h(i - 1, j)
	var dz := _h(i, j + 1) - _h(i, j - 1)
	return Vector3(-dx, 2.0 * cell, -dz).normalized()


## Mesh for a block of cells [i0, i0 + n] x [j0, j0 + n] sampled every `step` cells.
func _terrain_mesh(i0: int, j0: int, n: int, step: int, faces_out: Array = []) -> ArrayMesh:
	var cnt := n / step + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var keep := PackedByteArray()
	var want_faces := faces_out.size() > 0
	var fa := PackedVector3Array()
	verts.resize(cnt * cnt)
	norms.resize(cnt * cnt)
	cols.resize(cnt * cnt)
	uv2.resize(cnt * cnt)
	keep.resize(cnt * cnt)
	for b in cnt:
		for a in cnt:
			var i := mini(i0 + a * step, nx - 1)
			var j := mini(j0 + b * step, nz - 1)
			var k := b * cnt + a
			verts[k] = Vector3(x0 + i * cell, _h(i, j), z0 + j * cell)
			var nn := _normal(i, j)
			norms[k] = nn
			var look := _vertex_look(i, j, nn)
			cols[k] = look[0]
			uv2[k] = Vector2(look[1], 0.0)
			keep[k] = 1 if _b(i, j) != 0 else 0
	for b in cnt - 1:
		for a in cnt - 1:
			var k00 := b * cnt + a
			var k10 := k00 + 1
			var k01 := k00 + cnt
			var k11 := k01 + 1
			if keep[k00] + keep[k10] + keep[k01] + keep[k11] == 0:
				continue
			idx.append_array([k00, k10, k11, k00, k11, k01])
			if want_faces:
				fa.append_array([verts[k00], verts[k10], verts[k11], verts[k00], verts[k11], verts[k01]])
	if want_faces:
		faces_out[0] = fa
	# skirts hide cracks between neighbours of different detail
	var edges := [[0, 1, 0, 0], [0, 1, cnt - 1, 0], [0, 0, 0, 1], [cnt - 1, 0, 0, 1]]
	for e in [0, 1, 2, 3]:
		for s in cnt - 1:
			var a1: int
			var a2: int
			match e:
				0:
					a1 = s; a2 = s + 1
				1:
					a1 = (cnt - 1) * cnt + s; a2 = a1 + 1
				2:
					a1 = s * cnt; a2 = a1 + cnt
				_:
					a1 = s * cnt + cnt - 1; a2 = a1 + cnt
			if keep[a1] + keep[a2] == 0:
				continue
			var base := verts.size()
			verts.append(verts[a1] - Vector3(0, 9, 0))
			verts.append(verts[a2] - Vector3(0, 9, 0))
			norms.append(norms[a1]); norms.append(norms[a2])
			cols.append(cols[a1]); cols.append(cols[a2])
			uv2.append(uv2[a1]); uv2.append(uv2[a2])
			idx.append_array([a1, a2, base + 1, a1, base + 1, base, a1, base + 1, a2, a1, base, base + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	if idx.size() > 0:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# ---------------------------------------------------------------- streaming
func _region_count() -> Vector2i:
	return Vector2i(int(ceil(float(nx - 1) / (CH * SUPER))), int(ceil(float(nz - 1) / (CH * SUPER))))


func _build_far() -> void:
	var rc := _region_count()
	for rz in rc.y:
		for rx in rc.x:
			var key := Vector2i(rx, rz)
			var m := _terrain_mesh(rx * CH * SUPER, rz * CH * SUPER, CH * SUPER, [6, 4, 4][Q])
			if m.get_surface_count() == 0:
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.material_override = mat_terrain
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			regions[key] = {"far": mi, "near": false, "chunks": {}}


func _focus() -> Vector3:
	if world.active_car:
		return world.active_car.global_position
	var cam: Camera3D = world.current_camera()
	if world.player and not (world.spec_cam and cam == world.spec_cam):
		return world.player.global_position
	return cam.global_position if cam else Vector3.ZERO


func _process(delta: float) -> void:
	if not ready_ok:
		return
	_t += delta
	_update_t -= delta
	if _update_t <= 0.0:
		_update_t = 0.35
		_update_streaming()
	# build at most a couple of pieces per frame
	var budget := 2
	while budget > 0 and _queue.size() > 0:
		var job: Callable = _queue.pop_front()
		job.call()
		budget -= 1
	if world.sky:
		mat_terrain.set_shader_parameter("wet", world.sky.wet)
		mat_veg.set_shader_parameter("wind", world.sky.wind)
		window_mat.emission_energy_multiplier = 1.6 if world.sky.night > 0.4 else 0.0
	_keep_above_ground()
	if tower_light:
		var on := fmod(_t, 1.6) < 0.25
		tower_light.visible = on
		tower_bulb.emission_energy_multiplier = 8.0 if on else 0.5


## Make sure the ground under a point is solid right now (teleports, respawns, fast cars).
func ensure_collision(p: Vector3) -> void:
	if not ready_ok or not in_world(p.x, p.z):
		return
	var ck := Vector2i(int((p.x - x0) / (CH * cell)), int((p.z - z0) / (CH * cell)))
	if not _col.has(ck) or _col[ck] == null:
		_col[ck] = null
		_build_collision(ck)


func _update_streaming() -> void:
	var f := _focus()
	ensure_collision(f)
	if world.active_car:
		ensure_collision(f + world.active_car.velocity * 1.5)
	var rsize := CH * SUPER * cell
	for key in regions:
		var r: Dictionary = regions[key]
		var c := Vector3(x0 + (key.x + 0.5) * rsize, f.y, z0 + (key.y + 0.5) * rsize)
		var d := Vector2(f.x - c.x, f.z - c.z).length() - rsize * 0.5
		var want_near := d < near_r * 0.55
		if want_near and not r.near:
			r.near = true
			for cz in SUPER:
				for cx in SUPER:
					var ck := Vector2i(key.x * SUPER + cx, key.y * SUPER + cz)
					r.chunks[ck] = {"mi": null, "step": 0, "trees": null}
		elif not want_near and r.near and d > near_r * 0.7:
			r.near = false
			for ck in r.chunks:
				_free_chunk(r.chunks[ck])
				_drop_collision(ck)
			r.chunks.clear()
			r.far.visible = true
		if r.near:
			var all_ready := true
			for ck in r.chunks:
				var ch: Dictionary = r.chunks[ck]
				var cc := Vector3(x0 + (ck.x + 0.5) * CH * cell, 0, z0 + (ck.y + 0.5) * CH * cell)
				var cd := Vector2(f.x - cc.x, f.z - cc.z).length() - CH * cell * 0.5
				var step := 1 if cd < 250.0 else (2 if cd < 600.0 else 4)
				if Q == 0 and step == 1 and cd > 120.0:
					step = 2
				if ch.step != step and not ch.get("pending", false):
					ch.pending = true
					_queue.append(_build_chunk.bind(ck, step, ch))
				if ch.mi == null and ch.step == 0:
					all_ready = false
				var want_trees := cd < tree_r
				if want_trees and ch.trees == null and not ch.get("tpending", false):
					ch.tpending = true
					_queue.append(_build_trees.bind(ck, ch))
				elif not want_trees and ch.trees != null:
					ch.trees.queue_free()
					ch.trees = null
					ch.tpending = false
				var want_col := cd < col_r
				if want_col and not _col.has(ck):
					_col[ck] = null
					_queue.push_front(_build_collision.bind(ck))
				elif not want_col and _col.has(ck) and cd > col_r + 80.0:
					_drop_collision(ck)
			r.far.visible = not all_ready


func _build_chunk(ck: Vector2i, step: int, ch: Dictionary) -> void:
	ch.pending = false
	var m := _terrain_mesh(ck.x * CH, ck.y * CH, CH, step)
	if ch.mi:
		ch.mi.queue_free()
		ch.mi = null
	ch.step = step
	if m.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat_terrain
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	ch.mi = mi


func _free_chunk(ch: Dictionary) -> void:
	if ch.mi:
		ch.mi.queue_free()
	if ch.trees:
		ch.trees.queue_free()


func _build_collision(ck: Vector2i) -> void:
	if not _col.has(ck):
		return
	var holder: Array = [PackedVector3Array()]
	_terrain_mesh(ck.x * CH, ck.y * CH, CH, 1, holder)
	var faces: PackedVector3Array = holder[0]
	if faces.is_empty():
		return
	var sb := StaticBody3D.new()
	sb.set_meta("surface", "gerass_country")
	var cs := CollisionShape3D.new()
	var sh := ConcavePolygonShape3D.new()
	sh.set_faces(faces)
	sh.backface_collision = true
	cs.shape = sh
	sb.add_child(cs)
	# tree trunks and rocks in this chunk
	for tr in _trees_in(ck, true):
		if tr[0] in ["pine", "oak", "elm", "birch", "cactus", "rock"]:
			var tc := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.35 * tr[3] if tr[0] != "rock" else 1.1 * tr[3]
			cyl.height = 4.0 if tr[0] != "rock" else 1.6 * tr[3]
			tc.shape = cyl
			tc.position = tr[1] + Vector3(0, cyl.height * 0.5, 0)
			sb.add_child(tc)
	add_child(sb)
	_col[ck] = sb


func _drop_collision(ck: Vector2i) -> void:
	if _col.has(ck):
		if _col[ck]:
			_col[ck].queue_free()
		_col.erase(ck)


# ---------------------------------------------------------------- vegetation
func _bake(parts: Array) -> ArrayMesh:
	# parts: [mesh, transform, colour]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for p in parts:
		var arr: Array = (p[0] as Mesh).surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var ii = arr[Mesh.ARRAY_INDEX]
		var xf: Transform3D = p[1]
		var nb := xf.basis.inverse().transposed()
		var base := verts.size()
		for k in v.size():
			verts.append(xf * v[k])
			norms.append((nb * nn[k]).normalized())
			var c: Color = p[2]
			cols.append(c * (0.85 + 0.3 * fposmod(sin(float(k) * 12.9898) * 43758.5453, 1.0)) if p.size() > 3 else c)
		if ii == null or ii.is_empty():
			for k in v.size():
				idx.append(base + k)
		else:
			for k in ii:
				idx.append(base + k)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = norms
	out[Mesh.ARRAY_COLOR] = cols
	out[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return m


func _cone(r: float, hh: float, seg := 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = hh
	c.radial_segments = seg
	c.rings = 1
	return c


func _cylm(r1: float, r2: float, hh: float, seg := 6) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r1
	c.bottom_radius = r2
	c.height = hh
	c.radial_segments = seg
	c.rings = 1
	return c


func _sph(r: float, hh: float, seg := 8, rings := 5) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = hh
	s.radial_segments = seg
	s.rings = rings
	return s


## Crossed picture cards cut from the city's own foliage atlas (the sprites are stored upside down).
func _card_mesh(region: Rect2, hgt: float, wid: float, planes := 3) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var u0 := region.position.x / 1024.0
	var u1 := region.end.x / 1024.0
	var v_top := region.end.y / 1024.0
	var v_bot := region.position.y / 1024.0
	for k in planes:
		var a := PI * k / planes
		var d := Vector3(cos(a), 0, sin(a)) * wid * 0.5
		var nrm := Vector3(-sin(a), 0.6, cos(a)).normalized()
		var base := verts.size()
		verts.append_array([-d, d, d + Vector3(0, hgt, 0), -d + Vector3(0, hgt, 0)])
		norms.append_array([nrm, nrm, Vector3.UP, Vector3.UP])
		uvs.append_array([Vector2(u0, v_bot), Vector2(u1, v_bot), Vector2(u1, v_top), Vector2(u0, v_top)])
		idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _build_tree_meshes() -> void:
	for kind in CARDS:
		var c: Array = CARDS[kind]
		tree_mesh[kind] = _card_mesh(c[0], c[1], c[2], 2 if kind == "bush" else 3)
	var bark := Color(0.28, 0.19, 0.12)
	var pine := Color(0.12, 0.26, 0.13)
	tree_mesh["pine"] = _bake([
		[_cylm(0.18, 0.32, 4.0), Transform3D(Basis(), Vector3(0, 2.0, 0)), bark],
		[_cone(2.4, 4.0), Transform3D(Basis(), Vector3(0, 4.6, 0)), pine, 1],
		[_cone(1.9, 3.4), Transform3D(Basis(), Vector3(0, 6.6, 0)), pine * 1.08, 1],
		[_cone(1.3, 3.0), Transform3D(Basis(), Vector3(0, 8.5, 0)), pine * 1.15, 1],
		[_cone(0.7, 2.2), Transform3D(Basis(), Vector3(0, 10.1, 0)), pine * 1.2, 1]])
	var leaf := Color(0.2, 0.36, 0.14)
	tree_mesh["oak"] = _bake([
		[_cylm(0.22, 0.38, 4.2), Transform3D(Basis(), Vector3(0, 2.1, 0)), bark],
		[_sph(2.6, 4.2), Transform3D(Basis(), Vector3(0, 5.6, 0)), leaf, 1],
		[_sph(1.9, 3.2), Transform3D(Basis(), Vector3(1.4, 4.9, 0.6)), leaf * 1.1, 1],
		[_sph(1.8, 3.0), Transform3D(Basis(), Vector3(-1.2, 5.1, -0.8)), leaf * 0.92, 1]])
	var cac := Color(0.22, 0.42, 0.2)
	tree_mesh["cactus"] = _bake([
		[_cylm(0.3, 0.34, 3.6, 8), Transform3D(Basis(), Vector3(0, 1.8, 0)), cac],
		[_sph(0.3, 0.3, 8, 4), Transform3D(Basis(), Vector3(0, 3.6, 0)), cac],
		[_cylm(0.18, 0.18, 1.0, 6), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.6, 1.8, 0)), cac],
		[_cylm(0.18, 0.18, 1.2, 6), Transform3D(Basis(), Vector3(1.05, 2.4, 0)), cac],
		[_cylm(0.16, 0.16, 0.8, 6), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.5, 2.3, 0)), cac],
		[_cylm(0.16, 0.16, 0.9, 6), Transform3D(Basis(), Vector3(-0.85, 2.8, 0)), cac]])
	var rk := Color(0.42, 0.4, 0.37)
	tree_mesh["rock"] = _bake([
		[_sph(1.3, 1.6, 7, 4), Transform3D(Basis(Vector3(0.3, 1, 0.2).normalized(), 0.6).scaled(Vector3(1.3, 0.8, 1.0)), Vector3(0, 0.4, 0)), rk, 1],
		[_sph(0.8, 1.0, 6, 3), Transform3D(Basis(), Vector3(0.9, 0.3, 0.4)), rk * 0.9, 1]])
	tree_mesh["bush"] = _bake([
		[_sph(0.9, 1.2, 7, 4), Transform3D(Basis(), Vector3(0, 0.5, 0)), leaf * 0.95, 1],
		[_sph(0.7, 1.0, 6, 4), Transform3D(Basis(), Vector3(0.6, 0.4, 0.3)), leaf * 1.1, 1]])


func _trees_in(ck: Vector2i, solid_only := false) -> Array:
	# deterministic list of [kind, position, yaw, scale] for one chunk
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = ck.x * 73856093 ^ ck.y * 19349663
	var dens: float = [0.45, 0.7, 1.0][Q]
	for j in range(ck.y * CH, mini((ck.y + 1) * CH, nz - 1)):
		for i in range(ck.x * CH, mini((ck.x + 1) * CH, nx - 1)):
			var b := _b(i, j)
			var r := rng.randf()
			var kind := ""
			match b:
				1:
					if r < 0.035 * dens: kind = "oak"
					elif r < 0.06 * dens: kind = "bush"
					elif r < 0.07 * dens: kind = "pine"
				2:
					if r < 0.42 * dens: kind = "pine"
					elif r < 0.5 * dens: kind = "oak"
					elif r < 0.56 * dens: kind = "bush"
				3:
					if r < 0.06 * dens: kind = "rock"
				5:
					if r < 0.012 * dens: kind = "cactus"
					elif r < 0.02 * dens: kind = "rock"
				6:
					if r < 0.02 * dens: kind = "bush"
			var jx := rng.randf()
			var jz := rng.randf()
			var yaw := rng.randf() * TAU
			var sc := rng.randf_range(0.75, 1.35)
			if kind == "oak":
				var v := rng.randf()
				kind = "oak" if v < 0.4 else ("elm" if v < 0.7 else "birch")
			if kind == "" or roadmask[j * nx + i] == 1:
				continue
			var x := x0 + (i + jx) * cell
			var z := z0 + (j + jz) * cell
			var y := height_at(x, z)
			if kind != "rock" and _normal(i, j).y < 0.78:
				continue
			out.append([kind, Vector3(x, y - 0.15, z), yaw, sc])
	return out


func _build_trees(ck: Vector2i, ch: Dictionary) -> void:
	ch.tpending = false
	if ch.trees != null:
		return
	var list := _trees_in(ck)
	var holder := Node3D.new()
	add_child(holder)
	var by := {}
	for tr in list:
		if not by.has(tr[0]):
			by[tr[0]] = []
		by[tr[0]].append(tr)
	for kind in by:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = tree_mesh[kind]
		mm.instance_count = by[kind].size()
		for k in by[kind].size():
			var tr: Array = by[kind][k]
			var s: float = tr[3]
			mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, tr[2]).scaled(Vector3(s, s * randf_range(0.9, 1.1), s)), tr[1]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat_card if CARDS.has(kind) else mat_veg
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if Q >= 2 and kind in ["pine", "oak"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = tree_r + 60.0
		holder.add_child(mmi)
	ch.trees = holder


# ---------------------------------------------------------------- roads
func _road_mat(kind: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/models/map/la_13.png" if kind == "dirt" else "res://assets/models/map/la_14.png")
	m.roughness = 0.85
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if kind == "dirt":
		m.albedo_color = Color(0.85, 0.75, 0.62)
	if world and world.sky:
		world.sky.wet_mats.append({"mat": m, "col": m.albedo_color})
	return m


func _build_roads() -> void:
	var mats := {"highway": _road_mat("highway"), "road": _road_mat("road"), "dirt": _road_mat("dirt")}
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.58, 0.57, 0.55)
	concrete.roughness = 0.9
	var rail := StandardMaterial3D.new()
	rail.albedo_color = Color(0.7, 0.72, 0.74)
	rail.metallic = 0.7
	rail.roughness = 0.35
	for rd in roads:
		var pts: PackedVector3Array = rd.pts
		var w: float = rd.width
		var n := pts.size()
		var first := 0
		var last := n - 1
		# leave the city road surface alone where our road joins it
		if rd.start_route >= 0:
			while first < n - 2 and pts[first].distance_to(pts[0]) < 9.0:
				first += 1
		if rd.end_route >= 0:
			while last > 1 and pts[last].distance_to(pts[n - 1]) < 9.0:
				last -= 1
		var seg := 24
		var s := first
		var dist_acc := 0.0
		while s < last:
			var e := mini(s + seg, last)
			var verts := PackedVector3Array()
			var uvs := PackedVector2Array()
			var norms := PackedVector3Array()
			var idx := PackedInt32Array()
			var faces := PackedVector3Array()
			var bridge_parts: Array = []
			for k in range(s, e + 1):
				var p := pts[k]
				var t := (pts[mini(k + 1, n - 1)] - pts[maxi(k - 1, 0)])
				t.y = 0
				t = t.normalized()
				var side := t.cross(Vector3.UP).normalized()
				if k > s:
					dist_acc += pts[k].distance_to(pts[k - 1])
				var y := p.y + 0.05
				var a := Vector3(p.x, y, p.z) - side * w * 0.5
				var b := Vector3(p.x, y, p.z) + side * w * 0.5
				verts.append(a)
				verts.append(b)
				norms.append(Vector3.UP)
				norms.append(Vector3.UP)
				var u := dist_acc / (14.0 if rd.kind != "dirt" else 8.0)
				if rd.kind == "dirt":
					uvs.append(Vector2(u, 0.0))
					uvs.append(Vector2(u, 1.0))
				else:
					uvs.append(Vector2(u, 0.78))
					uvs.append(Vector2(u, 0.78))
				if k > s:
					var bi := verts.size() - 4
					idx.append_array([bi, bi + 2, bi + 1, bi + 1, bi + 2, bi + 3])
					faces.append_array([verts[bi], verts[bi + 2], verts[bi + 1], verts[bi + 1], verts[bi + 2], verts[bi + 3]])
				if int(rd.bridge[k]) == 1:
					bridge_parts.append([p, t, side])
			# centre line: duplicate verts for the middle so the texture's centre line sits in the middle
			if rd.kind != "dirt":
				var verts2 := PackedVector3Array()
				var uvs2 := PackedVector2Array()
				var norms2 := PackedVector3Array()
				var idx2 := PackedInt32Array()
				for k in range(0, verts.size(), 2):
					var mid := (verts[k] + verts[k + 1]) * 0.5
					var u2 := uvs[k].x
					verts2.append_array([verts[k], mid, mid, verts[k + 1]])
					uvs2.append_array([Vector2(u2, 0.8), Vector2(u2, 0.02), Vector2(u2, 0.02), Vector2(u2, 0.8)])
					norms2.append_array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
					if k > 0:
						var bi2 := verts2.size() - 8
						idx2.append_array([bi2, bi2 + 4, bi2 + 1, bi2 + 1, bi2 + 4, bi2 + 5, bi2 + 2, bi2 + 6, bi2 + 3, bi2 + 3, bi2 + 6, bi2 + 7])
				verts = verts2
				uvs = uvs2
				norms = norms2
				idx = idx2
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = verts
			arr[Mesh.ARRAY_NORMAL] = norms
			arr[Mesh.ARRAY_TEX_UV] = uvs
			arr[Mesh.ARRAY_INDEX] = idx
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.material_override = mats[rd.kind]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = [700.0, 1000.0, 1400.0][Q]
			add_child(mi)
			var sb := StaticBody3D.new()
			sb.set_meta("surface", "road_country" if rd.kind != "dirt" else "sand_dirt")
			var cs := CollisionShape3D.new()
			var sh := ConcavePolygonShape3D.new()
			sh.set_faces(faces)
			sh.backface_collision = true
			cs.shape = sh
			sb.add_child(cs)
			add_child(sb)
			_bridge(bridge_parts, w, concrete, rail)
			s = e


func _bridge(parts: Array, w: float, concrete: Material, rail: Material) -> void:
	if parts.is_empty():
		return
	var k := 0
	for bp in parts:
		var p: Vector3 = bp[0]
		var t: Vector3 = bp[1]
		var side: Vector3 = bp[2]
		var b := Basis(side, Vector3.UP, -t)
		# deck slab under the road
		_box(Vector3(w + 0.6, 0.9, 8.6), Transform3D(b, p + Vector3(0, -0.45, 0)), concrete)
		for sgn in [-1.0, 1.0]:
			_box(Vector3(0.25, 0.9, 8.6), Transform3D(b, p + side * sgn * (w * 0.5 + 0.2) + Vector3(0, 0.45, 0)), rail, true)
		if k % 3 == 0:
			var g := height_at(p.x, p.z)
			var hh := p.y - g
			if hh > 2.0:
				_box(Vector3(1.6, hh, 1.6), Transform3D(b, Vector3(p.x, g + hh * 0.5 - 0.9, p.z)), concrete, true)
		k += 1


func _box(size: Vector3, xf: Transform3D, mat: Material, collide := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = [600.0, 900.0, 1300.0][Q]
	add_child(mi)
	mi.global_transform = xf
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


# ---------------------------------------------------------------- places
func _mat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _build_places() -> void:
	var walls := [Color(0.86, 0.82, 0.72), Color(0.72, 0.78, 0.82), Color(0.82, 0.68, 0.55), Color(0.92, 0.9, 0.86)]
	var roofs := [Color(0.42, 0.18, 0.14), Color(0.2, 0.22, 0.26), Color(0.35, 0.27, 0.2), Color(0.3, 0.12, 0.1)]
	for hs in info.houses:
		_house(Vector3(hs[0], 0, hs[1]), hs[2], walls[int(hs[3])], roofs[int(hs[3])], false)
	for hs in info.ranch:
		_house(Vector3(hs[0], 0, hs[1]), hs[2], Color(0.62, 0.16, 0.12) if int(hs[3]) % 2 == 0 else Color(0.8, 0.74, 0.62), Color(0.25, 0.22, 0.2), true)
	for p in places:
		match str(p.kind):
			"tower":
				_radio_tower(Vector3(p.x, height_at(p.x, p.z), p.z))
			"gas":
				_gas_station(Vector3(p.x, p.y, p.z), float(p.yaw))
			"lake":
				_lake(Vector3(p.x, lake_level, p.z), float(p.r))
			"lookout":
				_lookout(Vector3(p.x, p.y, p.z))
	# a water tower in the village and a few street lights
	var v := Vector3(-470, 0, -120)
	_water_tower(Vector3(v.x - 60, height_at(v.x - 60, v.z + 80), v.z + 80))
	for rd in roads:
		if rd.name != "VALLEY ROAD":
			continue
		var pts: PackedVector3Array = rd.pts
		for k in range(0, pts.size(), 9):
			if Vector2(pts[k].x - v.x, pts[k].z - v.z).length() < 260.0:
				var t: Vector3 = (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
				var side: Vector3 = t.cross(Vector3.UP).normalized() * (float(rd.width) * 0.5 + 1.2)
				_street_light(pts[k] + side * (1 if (k / 9) % 2 == 0 else -1))
	_road_signs()


func _house(pos: Vector3, yaw: float, wall_c: Color, roof_c: Color, barn: bool) -> void:
	var g := height_at(pos.x, pos.z)
	var root := Node3D.new()
	add_child(root)
	root.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, g, pos.z))
	var w := 9.0 if not barn else 12.0
	var d := 8.0 if not barn else 14.0
	var hh := 3.2 if not barn else 5.5
	var wall := _mat(wall_c, 0.85)
	var roof := _mat(roof_c, 0.7)
	var trim := _mat(Color(0.95, 0.95, 0.93), 0.6)
	# foundation + walls
	_lbox(root, Vector3(w + 0.4, 1.2, d + 0.4), Vector3(0, -0.4, 0), _mat(Color(0.45, 0.44, 0.42)))
	_lbox(root, Vector3(w, hh, d), Vector3(0, hh * 0.5 + 0.2, 0), wall, true)
	# gable roof: two slanted slabs
	var ang := 0.55 if not barn else 0.7
	var half := w * 0.5 + 0.5
	var slab := half / cos(ang)
	for sgn in [-1.0, 1.0]:
		var rb := Basis(Vector3.FORWARD, sgn * ang)
		_lbox(root, Vector3(slab, 0.22, d + 1.0), Vector3(sgn * half * 0.5, hh + 0.2 + tan(ang) * half * 0.5, 0), roof, false, rb)
	# gable ends
	var tri_h := tan(ang) * half
	for sz in [-1.0, 1.0]:
		var pm := PrismMesh.new()
		pm.size = Vector3(w, tri_h, 0.2)
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = wall
		mi.position = Vector3(0, hh + 0.2 + tri_h * 0.5, sz * d * 0.5)
		mi.visibility_range_end = [500.0, 800.0, 1100.0][Q]
		root.add_child(mi)
	# door and windows on the front (-Z faces the road)
	_lbox(root, Vector3(1.2 if not barn else 4.0, 2.2 if not barn else 4.2, 0.1), Vector3(0, (1.3 if not barn else 2.3), -d * 0.5 - 0.05), _mat(Color(0.35, 0.22, 0.14) if not barn else Color(0.4, 0.1, 0.08)))
	if not barn:
		for wx in [-2.9, 2.9]:
			_lbox(root, Vector3(1.4, 1.2, 0.08), Vector3(wx, 1.9, -d * 0.5 - 0.04), window_mat)
			_lbox(root, Vector3(1.6, 0.12, 0.14), Vector3(wx, 1.25, -d * 0.5 - 0.06), trim)
		for wz in [-1.8, 1.8]:
			for sx in [-1.0, 1.0]:
				_lbox(root, Vector3(0.08, 1.2, 1.3), Vector3(sx * (w * 0.5 + 0.04), 1.9, wz), window_mat)
		# porch light
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.55)
		l.light_energy = 1.2
		l.omni_range = 7.0
		l.position = Vector3(0, 2.8, -d * 0.5 - 0.6)
		l.distance_fade_enabled = true
		l.distance_fade_begin = 60.0
		l.distance_fade_length = 20.0
		root.add_child(l)
		if world and world.sky:
			world.sky.lamps.append(l)


func _lbox(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, collide := false, basis_ := Basis()) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = Transform3D(basis_, pos)
	mi.visibility_range_end = [500.0, 800.0, 1100.0][Q]
	parent.add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


func _radio_tower(base: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = base
	var steel := _mat(Color(0.75, 0.2, 0.15), 0.5, 0.6)
	var white := _mat(Color(0.9, 0.9, 0.9), 0.5, 0.6)
	var hgt := 90.0
	var segs := 9
	for s in segs:
		var y0 := s * hgt / segs
		var wb := lerpf(6.0, 1.2, float(s) / segs)
		var wt := lerpf(6.0, 1.2, float(s + 1) / segs)
		var m := steel if s % 2 == 0 else white
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var a := Vector3(c.x * wb * 0.5, y0, c.y * wb * 0.5)
			var b := Vector3(c.x * wt * 0.5, y0 + hgt / segs, c.y * wt * 0.5)
			var mid := (a + b) * 0.5
			var len := a.distance_to(b)
			var bas := Basis.looking_at((b - a).normalized(), Vector3.FORWARD)
			var mi := _lbox(root, Vector3(0.25, 0.25, len), mid, m, false, bas)
			mi.visibility_range_end = 6000.0
		_lbox(root, Vector3(wt, 0.18, 0.18), Vector3(0, y0 + hgt / segs, wt * 0.5), m).visibility_range_end = 3000.0
		_lbox(root, Vector3(wt, 0.18, 0.18), Vector3(0, y0 + hgt / segs, -wt * 0.5), m).visibility_range_end = 3000.0
	# blinking red aviation light, visible from the whole city
	tower_bulb = StandardMaterial3D.new()
	tower_bulb.albedo_color = Color(1, 0.1, 0.05)
	tower_bulb.emission_enabled = true
	tower_bulb.emission = Color(1, 0.08, 0.04)
	tower_bulb.emission_energy_multiplier = 8.0
	var sm := SphereMesh.new()
	sm.radius = 0.6
	sm.height = 1.2
	var bulb := MeshInstance3D.new()
	bulb.mesh = sm
	bulb.material_override = tower_bulb
	bulb.position = Vector3(0, hgt + 0.8, 0)
	root.add_child(bulb)
	tower_light = OmniLight3D.new()
	tower_light.light_color = Color(1, 0.1, 0.05)
	tower_light.light_energy = 6.0
	tower_light.omni_range = 30.0
	tower_light.position = Vector3(0, hgt + 1.0, 0)
	root.add_child(tower_light)
	var hy := height_at(base.x + 9, base.z) - base.y
	_lbox(root, Vector3(5, 3, 4), Vector3(9, hy + 1.5, 0), _mat(Color(0.6, 0.6, 0.58)), true)
	var lb := Label3D.new()
	lb.text = "MOUNT SIERRA  •  RADIO"
	lb.font = Game.font_wide
	lb.font_size = 96
	lb.pixel_size = 0.01
	lb.position = Vector3(9, hy + 3.6, -2.05)
	lb.rotation.y = PI
	root.add_child(lb)


func _gas_station(p: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_transform = Transform3D(Basis(Vector3.UP, yaw), p)
	var white := _mat(Color(0.92, 0.92, 0.9), 0.5)
	var red := _mat(Color(0.8, 0.1, 0.08), 0.4)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1, 1, 1)
	glow.emission_enabled = true
	glow.emission = Color(0.95, 0.97, 1.0)
	glow.emission_energy_multiplier = 2.5
	_lbox(root, Vector3(26, 0.3, 20), Vector3(0, -0.1, 0), _mat(Color(0.32, 0.32, 0.33), 0.7))
	_lbox(root, Vector3(14, 0.7, 9), Vector3(0, 5.4, 0), white)
	_lbox(root, Vector3(14.2, 0.35, 9.2), Vector3(0, 5.0, 0), red)
	_lbox(root, Vector3(12, 0.08, 7), Vector3(0, 5.0, 0), glow)
	for x in [-4.5, 4.5]:
		_lbox(root, Vector3(0.5, 5.0, 0.5), Vector3(x, 2.5, 0), white, true)
		for z in [-1.4, 1.4]:
			_lbox(root, Vector3(0.7, 1.5, 0.5), Vector3(x + (1.2 if x < 0 else -1.2), 0.75, z), red, true)
	_lbox(root, Vector3(10, 3.6, 6), Vector3(0, 1.8, 9.5), white, true)
	_lbox(root, Vector3(6, 2.0, 0.1), Vector3(0, 1.8, 6.45), window_mat)
	var lb := Label3D.new()
	lb.text = "PINE VALLEY GAS"
	lb.font = Game.font_wide
	lb.font_size = 120
	lb.pixel_size = 0.012
	lb.modulate = Color(1, 0.3, 0.2)
	lb.position = Vector3(0, 4.3, 6.4)
	lb.rotation.y = PI
	root.add_child(lb)
	var l := OmniLight3D.new()
	l.light_color = Color(0.95, 0.97, 1.0)
	l.light_energy = 2.5
	l.omni_range = 16.0
	l.position = Vector3(0, 4.5, 0)
	root.add_child(l)
	if world and world.sky:
		world.sky.lamps.append(l)


func _lake(c: Vector3, r: float) -> void:
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.08, 0.2, 0.26, 0.86)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.04
	water.metallic = 0.25
	water.metallic_specular = 0.9
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.1
	cm.radial_segments = 48
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = water
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = c
	# small wooden pier
	var wood := _mat(Color(0.4, 0.28, 0.18), 0.85)
	var pier_dir := Vector3(-1, 0, -0.3).normalized()
	var start := c - pier_dir * (r * 0.98)
	var bas := Basis.looking_at(pier_dir, Vector3.UP)
	_box(Vector3(3.0, 0.3, 24), Transform3D(bas, start + pier_dir * 10.0 + Vector3(0, 0.9, 0)), wood, true)


func _lookout(p: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = p + Vector3(9, 0, 9)
	var wood := _mat(Color(0.4, 0.28, 0.18), 0.85)
	_lbox(root, Vector3(8, 0.3, 6), Vector3(0, height_at(p.x + 9, p.z + 9) - p.y, 0), wood, true)
	var lb := Label3D.new()
	lb.text = "RIDGE LOOKOUT"
	lb.font = Game.font_wide
	lb.font_size = 90
	lb.pixel_size = 0.012
	lb.position = Vector3(0, 2.5, 0)
	lb.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	root.add_child(lb)


func _water_tower(p: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = p
	var metal := _mat(Color(0.7, 0.72, 0.74), 0.45, 0.6)
	for c in [Vector2(-2, -2), Vector2(2, -2), Vector2(2, 2), Vector2(-2, 2)]:
		_lbox(root, Vector3(0.35, 18, 0.35), Vector3(c.x, 9, c.y), metal, true)
	var tank := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 4.0
	cm.bottom_radius = 4.0
	cm.height = 6.0
	tank.mesh = cm
	tank.material_override = metal
	tank.position = Vector3(0, 21, 0)
	tank.visibility_range_end = 2500.0
	root.add_child(tank)
	var lb := Label3D.new()
	lb.text = "PINE VALLEY"
	lb.font = Game.font_wide
	lb.font_size = 160
	lb.pixel_size = 0.012
	lb.modulate = Color(0.2, 0.3, 0.5)
	lb.position = Vector3(0, 21, 4.05)
	root.add_child(lb)


func _street_light(p: Vector3) -> void:
	var pole := _mat(Color(0.15, 0.16, 0.17), 0.5, 0.6)
	var root := Node3D.new()
	add_child(root)
	root.global_position = Vector3(p.x, height_at(p.x, p.z), p.z)
	_lbox(root, Vector3(0.18, 7, 0.18), Vector3(0, 3.5, 0), pole, true)
	var bulb := StandardMaterial3D.new()
	bulb.albedo_color = Color(1, 0.85, 0.6)
	bulb.emission_enabled = true
	bulb.emission = Color(1, 0.8, 0.5)
	bulb.emission_energy_multiplier = 4.0
	_lbox(root, Vector3(0.5, 0.15, 0.5), Vector3(0, 7.0, 0), bulb)
	var l := OmniLight3D.new()
	l.light_color = Color(1, 0.75, 0.45)
	l.light_energy = 2.6
	l.omni_range = 18.0
	l.position = Vector3(0, 6.8, 0)
	l.distance_fade_enabled = true
	l.distance_fade_begin = 90.0
	l.distance_fade_length = 30.0
	root.add_child(l)
	if world and world.sky:
		world.sky.lamps.append(l)
		world.sky.lamp_mats.append(bulb)


func _sign(p: Vector3, face: Vector3, lines: String) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_transform = Transform3D(Basis.looking_at(face, Vector3.UP), Vector3(p.x, height_at(p.x, p.z), p.z))
	var pole := _mat(Color(0.6, 0.62, 0.64), 0.4, 0.7)
	var green := _mat(Color(0.05, 0.35, 0.18), 0.5)
	_lbox(root, Vector3(0.15, 4.2, 0.15), Vector3(-1.6, 2.1, 0), pole, true)
	_lbox(root, Vector3(0.15, 4.2, 0.15), Vector3(1.6, 2.1, 0), pole, true)
	_lbox(root, Vector3(4.2, 1.6, 0.08), Vector3(0, 3.6, 0), green)
	var lb := Label3D.new()
	lb.text = lines
	lb.font = Game.font_bold
	lb.font_size = 64
	lb.pixel_size = 0.008
	lb.position = Vector3(0, 3.6, -0.06)
	lb.rotation.y = PI
	lb.width = 500
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(lb)


func _road_signs() -> void:
	var dest := {"VALLEY ROAD": "PINE VALLEY  •  BLUE LAKE", "SIERRA PASS": "MOUNT SIERRA  •  RADIO TOWER",
		"TIMBER TRAIL": "TIMBER FOREST", "HIGHWAY 7": "REDSTONE DESERT  •  SANDY RANCH",
		"NORTH RIDGE ROAD": "NORTH RIDGE  •  LOOKOUT", "RANCH ROAD": "SANDY RANCH"}
	for rd in roads:
		var pts: PackedVector3Array = rd.pts
		if pts.size() < 8:
			continue
		for end in [0, 1]:
			var k: int = 4 if end == 0 else pts.size() - 5
			var k2: int = k + 1 if end == 0 else k - 1
			var t: Vector3 = (pts[k2] - pts[k]).normalized()
			var side: Vector3 = t.cross(Vector3.UP).normalized()
			var p: Vector3 = pts[k] + side * (float(rd.width) * 0.5 + 2.5)
			_sign(p, -t, "%s\n%s" % [rd.name, dest.get(rd.name, "")])


## Safety net: nothing should ever end up under the landscape.
func _keep_above_ground() -> void:
	for body in [world.player, world.active_car]:
		if body == null or not is_instance_valid(body):
			continue
		var p: Vector3 = body.global_position
		if not in_world(p.x, p.z) or biome_at(p.x, p.z) == 0:
			continue
		var g := height_at(p.x, p.z)
		if p.y < g - 2.5:
			ensure_collision(p)
			body.global_position = Vector3(p.x, g + 1.0, p.z)
			body.velocity = Vector3.ZERO


## Name of the countryside zone at a point ("" when in the city).
func zone_at(x: float, z: float) -> String:
	var best := ""
	var bd := INF
	for p in places:
		if p.kind != "zone":
			continue
		var d := Vector2(x - p.x, z - p.z).length() / float(p.r)
		if d < 1.0 and d < bd:
			bd = d
			best = p.name
	return best
