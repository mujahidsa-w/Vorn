extends Node3D
## Competitive arena: a walled map with two spawn pads, two bomb sites, lane walls, buildings and cover.
## It floats above the city so it never overlaps the map's terrain or buildings.

const ORIGIN := Vector3(0.0, 420.0, 0.0)
const HALF_X := 100.0
const HALF_Z := 56.0
const SPAWN_X := 86.0
const WALL_H := 8.0
## arena meshes and its lights sit on their own layer, so the morning sun lights only the arena
const ARENA_LAYER := 1 << 10

# local spawn info per side: position on the pad and the yaw that looks at the middle
const SPAWN := {
	"a": {"pos": Vector3(-SPAWN_X, 0.1, 0.0), "yaw": -PI * 0.5},
	"b": {"pos": Vector3(SPAWN_X, 0.1, 0.0), "yaw": PI * 0.5},
}

const COVER := [
	Vector3(-34, 0, -22), Vector3(-34, 0, 22), Vector3(0, 0, 0),
	Vector3(34, 0, -22), Vector3(34, 0, 22), Vector3(-10, 0, -36), Vector3(10, 0, 36),
	Vector3(-60, 0, 0), Vector3(60, 0, 0),
]

# bomb sites (floor markers)
const SITES := {"A": Vector3(-48, 0, -24), "B": Vector3(48, 0, 24)}

# lane walls that split the middle
const LANE_WALLS := [
	[Vector3(-20, 2.0, -34), Vector3(1.0, 4.0, 26.0)],
	[Vector3(-20, 2.0, 34), Vector3(1.0, 4.0, 26.0)],
	[Vector3(20, 2.0, -34), Vector3(1.0, 4.0, 26.0)],
	[Vector3(20, 2.0, 34), Vector3(1.0, 4.0, 26.0)],
]

# buildings: [centre, size] (their roofs are darker boxes on top)
const BUILDINGS := [
	[Vector3(-68, 0, -38), Vector3(18, 12, 12)],
	[Vector3(-68, 0, 36), Vector3(18, 10, 14)],
	[Vector3(68, 0, -36), Vector3(16, 11, 14)],
	[Vector3(68, 0, 38), Vector3(18, 12, 12)],
	[Vector3(0, 0, -48), Vector3(26, 9, 8)],
	[Vector3(0, 0, 48), Vector3(26, 9, 8)],
]


func _ready() -> void:
	position = ORIGIN
	_build()


func spawn_world(side: String) -> Vector3:
	return ORIGIN + SPAWN[side].pos


func spawn_yaw(side: String) -> float:
	return SPAWN[side].yaw


func _build() -> void:
	var floor_col := Color(0.62, 0.45, 0.28)  # wood floor
	_box(Vector3(HALF_X * 2.0, 1.0, HALF_Z * 2.0), Vector3(0, -0.5, 0), floor_col)
	var wall_col := Color(0.66, 0.64, 0.6)  # stone walls
	_box(Vector3(HALF_X * 2.0, WALL_H, 1.0), Vector3(0, WALL_H * 0.5, -HALF_Z), wall_col)
	_box(Vector3(HALF_X * 2.0, WALL_H, 1.0), Vector3(0, WALL_H * 0.5, HALF_Z), wall_col)
	_box(Vector3(1.0, WALL_H, HALF_Z * 2.0), Vector3(-HALF_X, WALL_H * 0.5, 0), wall_col)
	_box(Vector3(1.0, WALL_H, HALF_Z * 2.0), Vector3(HALF_X, WALL_H * 0.5, 0), wall_col)

	# spawn pads: blue for side a on the left, red for side b on the right
	_pad(Vector3(-SPAWN_X, 0.02, 0.0), Vector3(16, 0.04, 26), Color(0.2, 0.45, 0.95), "A")
	_pad(Vector3(SPAWN_X, 0.02, 0.0), Vector3(16, 0.04, 26), Color(0.95, 0.3, 0.25), "B")

	var crate_col := Color(0.55, 0.38, 0.2)  # wooden crates
	for c in COVER:
		_box(Vector3(3.0, 2.5, 3.0), c + Vector3(0, 1.25, 0), crate_col)

	# buildings with darker roofs
	var bld_col := Color(0.7, 0.66, 0.6)  # stone buildings
	var roof_col := Color(0.4, 0.36, 0.32)
	for b in BUILDINGS:
		var sz: Vector3 = b[1]
		var pos: Vector3 = b[0]
		_box(sz, pos + Vector3(0, sz.y * 0.5, 0), bld_col)
		_box(Vector3(sz.x + 0.6, 0.6, sz.z + 0.6), pos + Vector3(0, sz.y + 0.3, 0), roof_col)

	# lane walls and the bomb sites
	var wall_mid := Color(0.6, 0.56, 0.5)  # stone lane walls
	for w in LANE_WALLS:
		_box(w[1], w[0], wall_mid)
	for k in SITES:
		_pad(SITES[k] + Vector3(0, 0.02, 0), Vector3(12, 0.04, 12), Color(0.9, 0.75, 0.25), "SITE " + k)

	# morning sun from the east: low warm light with shadows, only on the arena
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28, 55, 0)
	sun.light_color = Color(1.0, 0.86, 0.66)
	sun.light_energy = 2.4
	sun.shadow_enabled = true
	sun.light_cull_mask = ARENA_LAYER
	add_child(sun)

	# shadowed lights: one key light over the middle and one over each side for depth
	var light := OmniLight3D.new()
	light.position = Vector3(0, 9.0, 0)
	light.light_energy = 3.5
	light.omni_range = 140.0
	light.light_color = Color(1.0, 0.95, 0.85)
	light.shadow_enabled = true
	light.light_cull_mask = ARENA_LAYER
	add_child(light)
	for x in [-50.0, 50.0]:
		var side_light := OmniLight3D.new()
		side_light.position = Vector3(x, 7.0, 0)
		side_light.light_energy = 2.0
		side_light.omni_range = 60.0
		side_light.light_color = Color(1.0, 0.92, 0.8)
		side_light.shadow_enabled = true
		side_light.light_cull_mask = ARENA_LAYER
		add_child(side_light)


## shared grain texture, generated in code (no downloaded files); triplanar so every box gets the same scale
var _noise: NoiseTexture2D


func _mat(col: Color, rough: float) -> StandardMaterial3D:
	if _noise == null:
		_noise = NoiseTexture2D.new()
		_noise.width = 256
		_noise.height = 256
		_noise.seamless = true
		var fn := FastNoiseLite.new()
		fn.frequency = 0.04
		fn.fractal_octaves = 4
		_noise.noise = fn
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.albedo_texture = _noise
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.12, 0.12, 0.12)
	return m


func _box(size: Vector3, pos: Vector3, col: Color) -> void:
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
	mi.material_override = _mat(col, 0.85)
	mi.layers = ARENA_LAYER
	body.add_child(mi)


func _pad(pos: Vector3, size: Vector3, col: Color, txt: String) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.4
	m.material_override = mat
	m.layers = ARENA_LAYER
	add_child(m)
	var lbl := Label3D.new()
	lbl.text = txt
	lbl.font_size = 180
	lbl.pixel_size = 0.02
	lbl.position = pos + Vector3(0, 0.6, 0)
	lbl.rotation_degrees = Vector3(-90, 0, 0)
	lbl.layers = ARENA_LAYER
	add_child(lbl)
