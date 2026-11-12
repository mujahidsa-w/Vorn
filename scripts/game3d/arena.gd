extends Node3D
## Competitive arena: a walled desert-town map with two spawns, two bomb sites, lanes, buildings and cover.
## Surfaces use real CC0 PBR textures (ambientCG, in assets/textures/arena). The arena floats above the
## city so it never overlaps the map's terrain or buildings.

const ORIGIN := Vector3(0.0, 420.0, 0.0)
const HALF_X := 100.0
const HALF_Z := 56.0
const SPAWN_X := 86.0
const WALL_H := 9.0
## arena meshes and its lights sit on their own layer, so the morning sun lights only the arena
const ARENA_LAYER := 1 << 10
const TEX := "res://assets/textures/arena/"

# local spawn info per side: position on the pad and the yaw that looks at the middle
const SPAWN := {
	"a": {"pos": Vector3(-SPAWN_X, 0.1, 0.0), "yaw": -PI * 0.5},
	"b": {"pos": Vector3(SPAWN_X, 0.1, 0.0), "yaw": PI * 0.5},
}

# crates: [position on the ground, size]; a few are stacked
const CRATES := [
	[Vector3(-34, 0, -22), Vector3(2.4, 2.4, 2.4)], [Vector3(-31.6, 0, -22), Vector3(1.6, 1.6, 1.6)],
	[Vector3(-34, 0, 22), Vector3(2.4, 2.4, 2.4)], [Vector3(-34, 2.4, 22), Vector3(1.6, 1.6, 1.6)],
	[Vector3(0, 0, 0), Vector3(2.8, 2.8, 2.8)], [Vector3(2.8, 0, 0.6), Vector3(1.8, 1.8, 1.8)],
	[Vector3(34, 0, -22), Vector3(2.4, 2.4, 2.4)], [Vector3(34, 2.4, -22), Vector3(1.6, 1.6, 1.6)],
	[Vector3(34, 0, 22), Vector3(2.4, 2.4, 2.4)], [Vector3(31.6, 0, 22), Vector3(1.6, 1.6, 1.6)],
	[Vector3(-10, 0, -36), Vector3(2.4, 2.4, 2.4)], [Vector3(10, 0, 36), Vector3(2.4, 2.4, 2.4)],
	[Vector3(-60, 0, 0), Vector3(2.4, 2.4, 2.4)], [Vector3(60, 0, 0), Vector3(2.4, 2.4, 2.4)],
	[Vector3(-46, 0, -20), Vector3(2.0, 2.0, 2.0)], [Vector3(-51, 0, -28), Vector3(2.4, 2.4, 2.4)],
	[Vector3(46, 0, 20), Vector3(2.0, 2.0, 2.0)], [Vector3(51, 0, 28), Vector3(2.4, 2.4, 2.4)],
]

# bomb sites (painted on the ground)
const SITES := {"A": Vector3(-48, 0, -24), "B": Vector3(48, 0, 24)}

# lane walls that split the middle: [centre on the ground, size]
const LANE_WALLS := [
	[Vector3(-20, 0, -34), Vector3(1.2, 4.0, 26.0)],
	[Vector3(-20, 0, 34), Vector3(1.2, 4.0, 26.0)],
	[Vector3(20, 0, -34), Vector3(1.2, 4.0, 26.0)],
	[Vector3(20, 0, 34), Vector3(1.2, 4.0, 26.0)],
]

# buildings: [centre on the ground, size, surface]
const BUILDINGS := [
	[Vector3(-68, 0, -38), Vector3(18, 12, 12), "plaster"],
	[Vector3(-68, 0, 36), Vector3(18, 10, 14), "brick"],
	[Vector3(68, 0, -36), Vector3(16, 11, 14), "brick"],
	[Vector3(68, 0, 38), Vector3(18, 12, 12), "plaster"],
	[Vector3(0, 0, -48), Vector3(26, 9, 8), "plaster"],
	[Vector3(0, 0, 48), Vector3(26, 9, 8), "plaster"],
]

# texture scale per surface (world metres per tile = 1 / scale)
const SCALE := {
	"ground": 0.18, "sand": 0.12, "plaster": 0.22, "brick": 0.3, "concrete": 0.25, "crate": 0.42, "roof": 0.3,
}

# per-surface brightness so bright scans (sand) do not wash out in the sun
const TINT := {"sand": Color(0.5, 0.45, 0.38), "ground": Color(0.85, 0.8, 0.72)}

var _mats := {}


func _ready() -> void:
	position = ORIGIN
	_build()


func spawn_world(side: String) -> Vector3:
	return ORIGIN + SPAWN[side].pos


func spawn_yaw(side: String) -> float:
	return SPAWN[side].yaw


func _build() -> void:
	# ground: paving stones, with sand in the open middle and in front of each spawn
	_box(Vector3(HALF_X * 2.0, 1.0, HALF_Z * 2.0), Vector3(0, -0.5, 0), "ground")
	_slab(Vector3(0, 0, 0), Vector3(36, 0.04, 30), "sand")
	_slab(Vector3(-SPAWN_X, 0, 0), Vector3(16, 0.04, 26), "sand")
	_slab(Vector3(SPAWN_X, 0, 0), Vector3(16, 0.04, 26), "sand")

	# outer walls: plaster, with a concrete cap
	for w in [
		[Vector3(0, 0, -HALF_Z), Vector3(HALF_X * 2.0, WALL_H, 1.2)],
		[Vector3(0, 0, HALF_Z), Vector3(HALF_X * 2.0, WALL_H, 1.2)],
		[Vector3(-HALF_X, 0, 0), Vector3(1.2, WALL_H, HALF_Z * 2.0)],
		[Vector3(HALF_X, 0, 0), Vector3(1.2, WALL_H, HALF_Z * 2.0)],
	]:
		var sz: Vector3 = w[1]
		_box(sz, w[0] + Vector3(0, sz.y * 0.5, 0), "plaster")
		_box(Vector3(sz.x + 0.4, 0.35, sz.z + 0.4), w[0] + Vector3(0, sz.y + 0.17, 0), "concrete")

	for c in CRATES:
		var sz: Vector3 = c[1]
		_box(sz, c[0] + Vector3(0, sz.y * 0.5, 0), "crate")

	for b in BUILDINGS:
		_building(b[0], b[1], b[2])

	for w in LANE_WALLS:
		var sz: Vector3 = w[1]
		_box(sz, w[0] + Vector3(0, sz.y * 0.5, 0), "concrete")

	for k in SITES:
		_site(SITES[k], k)
	_spawn_mark(Vector3(-SPAWN_X, 0, 0), "A", Color(0.35, 0.6, 1.0))
	_spawn_mark(Vector3(SPAWN_X, 0, 0), "B", Color(1.0, 0.45, 0.3))

	# morning sun from the east: low warm light with long shadows, only on the arena
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32, 58, 0)
	sun.light_color = Color(1.0, 0.88, 0.7)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 220.0
	sun.light_cull_mask = ARENA_LAYER
	add_child(sun)
	# soft sky fill from the opposite side (no shadows) so shaded faces are not black
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-50, -120, 0)
	fill.light_color = Color(0.62, 0.72, 0.9)
	fill.light_energy = 0.2
	fill.light_cull_mask = ARENA_LAYER
	add_child(fill)


## a block building with a wooden roof overhang, dark window recesses and a doorway on each long side
func _building(pos: Vector3, sz: Vector3, surface: String) -> void:
	_box(sz, pos + Vector3(0, sz.y * 0.5, 0), surface)
	_box(Vector3(sz.x + 1.2, 0.4, sz.z + 1.2), pos + Vector3(0, sz.y + 0.2, 0), "roof")
	var dark := _flat(Color(0.05, 0.05, 0.06))
	var floors := int(sz.y / 3.6)
	for side in [-1.0, 1.0]:
		var z: float = pos.z + side * (sz.z * 0.5 + 0.02)
		var n := int(sz.x / 4.0)
		for f in floors:
			for i in n:
				var x: float = pos.x - sz.x * 0.5 + 2.0 + i * (sz.x - 4.0) / max(1, n - 1)
				if f == 0 and i == n / 2:
					_deco(Vector3(1.8, 2.6, 0.06), Vector3(x, pos.y + 1.3, z), dark)  # doorway
				else:
					_deco(Vector3(1.2, 1.5, 0.06), Vector3(x, pos.y + 2.2 + f * 3.6, z), dark)


func _site(pos: Vector3, letter: String) -> void:
	# painted outline and letter on the ground, like spray paint
	var paint := _flat(Color(0.95, 0.55, 0.12, 0.85))
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var h := 6.0
	for e in [[Vector3(0, 0, -h), Vector3(12, 0.02, 0.3)], [Vector3(0, 0, h), Vector3(12, 0.02, 0.3)],
			[Vector3(-h, 0, 0), Vector3(0.3, 0.02, 12)], [Vector3(h, 0, 0), Vector3(0.3, 0.02, 12)]]:
		_deco(e[1], pos + e[0] + Vector3(0, 0.03, 0), paint)
	_ground_label(pos, letter, Color(0.95, 0.55, 0.12), 520)


func _spawn_mark(pos: Vector3, letter: String, col: Color) -> void:
	_ground_label(pos, letter, col, 360)


func _ground_label(pos: Vector3, txt: String, col: Color, size: int) -> void:
	var lbl := Label3D.new()
	lbl.text = txt
	lbl.font_size = size
	lbl.pixel_size = 0.012
	lbl.modulate = Color(col, 0.8)
	lbl.outline_size = 0
	lbl.position = pos + Vector3(0, 0.06, 0)
	lbl.rotation_degrees = Vector3(-90, 0, 0)
	lbl.layers = ARENA_LAYER
	add_child(lbl)


## real PBR material for a surface, cached; triplanar in world space so every box tiles at the same scale
func _mat(surface: String) -> StandardMaterial3D:
	if _mats.has(surface):
		return _mats[surface]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + surface + "_col.jpg")
	m.albedo_color = TINT.get(surface, Color(0.8, 0.78, 0.75))
	m.normal_enabled = true
	m.normal_texture = load(TEX + surface + "_nrm.jpg")
	m.roughness_texture = load(TEX + surface + "_rgh.jpg")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.metallic_specular = 0.15  # dusty surfaces: no sun glare
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	var s: float = SCALE.get(surface, 0.2)
	m.uv1_scale = Vector3(s, s, s)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[surface] = m
	return m


func _flat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	return m


func _box(size: Vector3, pos: Vector3, surface: String) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(surface)
	mi.layers = ARENA_LAYER
	body.add_child(mi)


## thin ground cover with no collision (sand patches)
func _slab(pos: Vector3, size: Vector3, surface: String) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos + Vector3(0, size.y * 0.5, 0)
	mi.material_override = _mat(surface)
	mi.layers = ARENA_LAYER
	add_child(mi)


## visual-only detail with a plain material (windows, doors, paint)
func _deco(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	mi.layers = ARENA_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
