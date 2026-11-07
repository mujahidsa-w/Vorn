extends Node3D
## City centre: a large open pedestrian plaza with an animated water fountain, trees and benches,
## a four-storey public garage with ramps, and neon signs and lights.
## Local frame: origin at plaza level, Y up. The plaza is about 124 m square.

const PLAZA := 124.0
const FOUNTAIN_R := 11.0

var world
var mats := {}
var jets: Array = []          # {node, phase, base}
var water_mat: StandardMaterial3D
var t := 0.0


func _m(name: String, col: Color, rough := 0.6, metal := 0.0, emis := 0.0, alpha := 1.0) -> StandardMaterial3D:
	if mats.has(name):
		return mats[name]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.roughness = rough
	m.metallic = metal
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emis > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emis
	mats[name] = m
	return m


func box(size: Vector3, pos: Vector3, mat: Material, collide := true, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	mi.rotation.y = rot_y
	add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


func cyl(r: float, h: float, pos: Vector3, mat: Material, collide := true, seg := 24) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.material = mat
	mi.mesh = c
	mi.position = pos
	add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = r
		sh.height = h
		cs.shape = sh
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


func label(text: String, pos: Vector3, size: int, col: Color, rot_y := 0.0, px := 0.01) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.position = pos
	l.rotation.y = rot_y
	add_child(l)
	return l


func light(pos: Vector3, col: Color, energy: float, rng: float) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.position = pos
	o.light_color = col
	o.light_energy = energy
	o.omni_range = rng
	add_child(o)
	return o


func build() -> void:
	var stone := _m("plaza", Color(0.62, 0.6, 0.57), 0.85)
	var stone_dark := _m("plaza_dark", Color(0.42, 0.42, 0.45), 0.8)
	var concrete := _m("concrete", Color(0.5, 0.5, 0.52), 0.75)
	var glass := _m("glass", Color(0.2, 0.3, 0.38), 0.15, 0.4, 0.0, 0.85)
	var neon_cyan := _m("neon_cyan", Color(0.25, 0.9, 1.0), 0.3, 0.0, 3.0)
	var neon_pink := _m("neon_pink", Color(1.0, 0.25, 0.7), 0.3, 0.0, 3.0)
	var neon_gold := _m("neon_gold", Color(1.0, 0.8, 0.3), 0.3, 0.0, 3.0)
	var wood := _m("wood", Color(0.36, 0.24, 0.14), 0.8)
	var leaf := _m("leaf", Color(0.16, 0.42, 0.2), 0.9)
	var metal_dark := _m("metal_dark", Color(0.12, 0.13, 0.15), 0.4, 0.6)

	# plaza slab (its top sits 0.1 m above the road level)
	box(Vector3(PLAZA, 0.2, PLAZA), Vector3(0, 0.1, 0), stone)
	# inlaid paving bands
	for i in 3:
		cyl(22.0 + i * 12.0, 0.02, Vector3(0, 0.21, 0), stone_dark, false, 64)
	# outer kerb of the plaza
	for s in [-1.0, 1.0]:
		box(Vector3(PLAZA + 1.0, 0.5, 1.0), Vector3(0, 0.25, s * (PLAZA * 0.5 + 0.5)), concrete)
		box(Vector3(1.0, 0.5, PLAZA + 1.0), Vector3(s * (PLAZA * 0.5 + 0.5), 0.25, 0), concrete)

	_build_fountain(stone, stone_dark, glass)
	_build_trees_and_benches(wood, leaf, metal_dark)
	_build_garage(concrete, glass, neon_cyan, neon_pink, metal_dark)
	_build_neon(neon_cyan, neon_pink, neon_gold)


func _build_fountain(stone: Material, stone_dark: Material, glass: Material) -> void:
	# basin rim, water and jets; the water and jets are animated in _process
	cyl(FOUNTAIN_R + 1.2, 0.9, Vector3(0, 0.45, 0), stone)
	cyl(FOUNTAIN_R, 0.2, Vector3(0, 0.9, 0), _m("basin_water", Color(0.05, 0.25, 0.35), 0.1, 0.0, 0.0), false)
	water_mat = _m("water", Color(0.3, 0.75, 1.0), 0.05, 0.1, 0.6, 0.7)
	var water := cyl(FOUNTAIN_R - 0.2, 0.05, Vector3(0, 0.99, 0), water_mat, false)
	water.name = "Water"
	# centre column and a ring of jets
	cyl(1.6, 2.2, Vector3(0, 1.8, 0), stone, true, 32)
	cyl(1.1, 0.2, Vector3(0, 3.0, 0), stone, false, 32)
	var jet_mat := _m("jet", Color(0.8, 0.95, 1.0), 0.05, 0.0, 0.8, 0.6)
	for i in 12:
		var a := TAU * float(i) / 12.0
		var p := Vector3(cos(a) * 6.0, 1.0, sin(a) * 6.0)
		var j := cyl(0.08, 1.0, p, jet_mat, false, 8)
		jets.append({"node": j, "phase": float(i) * 0.5, "base": 1.0})
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.3
		var p := Vector3(cos(a) * 3.2, 1.0, sin(a) * 3.2)
		var j2 := cyl(0.06, 1.2, p, jet_mat, false, 8)
		jets.append({"node": j2, "phase": float(i) * 0.9 + 1.0, "base": 1.2})
	light(Vector3(0, 2.0, 0), Color(0.5, 0.85, 1.0), 2.5, 16.0)


func _build_trees_and_benches(wood: Material, leaf: Material, metal_dark: Material) -> void:
	# trees in a ring between the fountain and the kerb, benches in front of them
	for i in 16:
		var a := TAU * float(i) / 16.0
		var r := 32.0
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		cyl(0.35, 3.2, p + Vector3(0, 1.6, 0), wood, true, 10)
		var canopy := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 2.4
		sph.height = 4.2
		sph.material = leaf
		canopy.mesh = sph
		canopy.position = p + Vector3(0, 4.4, 0)
		add_child(canopy)
		# bench facing the fountain
		var bp := Vector3(cos(a) * (r - 3.2), 0.0, sin(a) * (r - 3.2))
		var rot := atan2(-cos(a), -sin(a))
		box(Vector3(2.4, 0.12, 0.7), bp + Vector3(0, 0.45, 0), wood, true, rot)
		box(Vector3(2.4, 0.5, 0.08), bp + Vector3(0, 0.75, 0.3).rotated(Vector3.UP, rot), wood, false, rot)
		box(Vector3(0.12, 0.45, 0.6), bp + Vector3(0.9, 0.22, 0).rotated(Vector3.UP, rot), metal_dark, false, rot)
		box(Vector3(0.12, 0.45, 0.6), bp + Vector3(-0.9, 0.22, 0).rotated(Vector3.UP, rot), metal_dark, false, rot)
	# lamp posts on the ring
	var lamp := _m("lamp", Color(1.0, 0.92, 0.7), 0.3, 0.0, 2.0)
	for i in 8:
		var a := TAU * (float(i) + 0.5) / 8.0
		var p := Vector3(cos(a) * 44.0, 0, sin(a) * 44.0)
		cyl(0.12, 6.0, p + Vector3(0, 3.0, 0), metal_dark, true, 8)
		var head := box(Vector3(0.6, 0.15, 0.4), p + Vector3(0, 6.1, 0), lamp, false)
		light(p + Vector3(0, 5.8, 0), Color(1.0, 0.9, 0.7), 1.2, 14.0)
		head.name = "LampHead"


func _build_garage(concrete: Material, glass: Material, neon_cyan: Material, neon_pink: Material, metal_dark: Material) -> void:
	# four-storey public garage on the +X side of the plaza
	var gx := 88.0   # front of the garage sits 8 m outside the plaza kerb
	var w := 26.0    # along Z
	var d := 36.0    # along X
	var floor_h := 4.2
	var floors := 4
	for f in floors:
		var y0 := f * floor_h
		# floor slab
		box(Vector3(d, 0.35, w), Vector3(gx, y0 + 0.2, 0), concrete)
		# open-side ribs with glass panels on the front (facing the plaza, -X)
		for k in 9:
			var z := -w * 0.5 + 1.5 + k * (w - 3.0) / 8.0
			box(Vector3(0.5, floor_h - 0.4, 0.5), Vector3(gx - d * 0.5, y0 + floor_h * 0.5, z), concrete)
		box(Vector3(0.3, floor_h - 1.2, w - 1.0), Vector3(gx - d * 0.5 + 0.1, y0 + floor_h * 0.5, 0), glass, false)
		# ceiling light strip
		var strip := box(Vector3(d - 4.0, 0.08, 0.4), Vector3(gx, y0 + floor_h - 0.1, 0), neon_cyan, false)
		strip.name = "GarageStrip"
		light(Vector3(gx, y0 + floor_h - 0.5, 0), Color(0.7, 0.9, 1.0), 0.9, 12.0)
	# roof and parapet
	var top := floors * floor_h
	box(Vector3(d, 0.4, w), Vector3(gx, top + 0.2, 0), concrete)
	box(Vector3(d, 1.0, 0.4), Vector3(gx, top + 0.9, w * 0.5), concrete, false)
	box(Vector3(d, 1.0, 0.4), Vector3(gx, top + 0.9, -w * 0.5), concrete, false)
	# spiral ramp at the back: a sloped slab that links the floors
	var ramp_len := 14.0
	for f in floors - 1:
		var ramp := box(Vector3(5.0, 0.3, ramp_len), Vector3(gx + d * 0.5 + 3.5, f * floor_h + floor_h * 0.5 + 0.05, -w * 0.25), concrete, true)
		ramp.rotation.x = -atan2(floor_h, ramp_len)
	# entrance on the plaza side with a bright sign
	box(Vector3(0.3, 4.0, 8.0), Vector3(gx - d * 0.5 - 0.1, 2.0, w * 0.5 - 4.0), glass, false)
	label("PARKING", Vector3(gx - d * 0.5 - 0.3, top - 0.8, 0), 180, Color(0.6, 0.95, 1.0), -PI * 0.5, 0.012)
	label("P", Vector3(gx - d * 0.5 - 0.3, 3.2, -w * 0.5 + 4.0), 120, Color(1.0, 0.8, 0.3), -PI * 0.5, 0.012)
	# neon trim on the roof edge
	box(Vector3(d + 0.4, 0.12, 0.12), Vector3(gx, top + 0.5, w * 0.5 + 0.2), neon_pink, false)
	box(Vector3(d + 0.4, 0.12, 0.12), Vector3(gx, top + 0.5, -w * 0.5 - 0.2), neon_pink, false)


func _build_neon(cyan: Material, pink: Material, gold: Material) -> void:
	# neon strips along the plaza edge and a large centre sign
	for s in [-1.0, 1.0]:
		box(Vector3(PLAZA - 6.0, 0.12, 0.12), Vector3(0, 0.6, s * (PLAZA * 0.5 - 1.0)), cyan, false)
		box(Vector3(0.12, 0.12, PLAZA - 6.0), Vector3(s * (PLAZA * 0.5 - 1.0), 0.6, 0), pink, false)
	# flagpoles with gold tops
	for i in 4:
		var a := TAU * (float(i) + 0.5) / 4.0
		var p := Vector3(cos(a) * 56.0, 0, sin(a) * 56.0)
		cyl(0.1, 10.0, p + Vector3(0, 5.0, 0), _m("pole", Color(0.8, 0.8, 0.85), 0.3, 0.8), true, 8)
		cyl(0.22, 0.4, p + Vector3(0, 10.2, 0), gold, false, 12)
	# big sign above the fountain
	label("VORN CITY CENTER", Vector3(0, 9.5, -FOUNTAIN_R - 1.5), 220, Color(1.0, 0.85, 0.4), 0.0, 0.02)
	light(Vector3(0, 8.0, 0), Color(1.0, 0.8, 0.5), 1.4, 30.0)


func _process(delta: float) -> void:
	# the fountain: jets rise and fall in waves, the water glows gently
	t += delta
	for j in jets:
		var s := 1.0 + 0.9 * (0.5 + 0.5 * sin(t * 2.4 + float(j.phase)))
		var node: MeshInstance3D = j.node
		node.scale = Vector3(1.0, s * float(j.base), 1.0)
	if water_mat:
		water_mat.emission_energy_multiplier = 0.5 + 0.2 * sin(t * 1.3)
