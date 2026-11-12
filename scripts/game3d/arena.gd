extends Node3D
## Competitive arena: a walled square with a spawn pad for each side and cover in the middle.
## It floats above the city so it never overlaps the map's terrain or buildings.

const ORIGIN := Vector3(0.0, 420.0, 0.0)
const HALF_X := 60.0
const HALF_Z := 30.0
const SPAWN_X := 44.0
const WALL_H := 6.0

# local spawn info per side: position on the pad and the yaw that looks at the middle
const SPAWN := {
	"a": {"pos": Vector3(-SPAWN_X, 0.1, 0.0), "yaw": -PI * 0.5},
	"b": {"pos": Vector3(SPAWN_X, 0.1, 0.0), "yaw": PI * 0.5},
}

const COVER := [
	Vector3(-20, 0, -12), Vector3(-20, 0, 12), Vector3(0, 0, 0),
	Vector3(20, 0, -12), Vector3(20, 0, 12), Vector3(-6, 0, -20), Vector3(6, 0, 20),
]


# bomb sites (floor markers) and the walls that split the arena into lanes
const SITES := {"A": Vector3(-30, 0, -17), "B": Vector3(30, 0, 17)}
const LANE_WALLS := [
	[Vector3(-12, 1.5, -19), Vector3(1.0, 3.0, 20.0)],
	[Vector3(-12, 1.5, 19), Vector3(1.0, 3.0, 20.0)],
	[Vector3(12, 1.5, -19), Vector3(1.0, 3.0, 20.0)],
	[Vector3(12, 1.5, 19), Vector3(1.0, 3.0, 20.0)],
]


func _ready() -> void:
	position = ORIGIN
	_build()


func spawn_world(side: String) -> Vector3:
	return ORIGIN + SPAWN[side].pos


func spawn_yaw(side: String) -> float:
	return SPAWN[side].yaw


func _build() -> void:
	var floor_col := Color(0.16, 0.17, 0.19)
	_box(Vector3(HALF_X * 2.0, 1.0, HALF_Z * 2.0), Vector3(0, -0.5, 0), floor_col)
	var wall_col := Color(0.55, 0.57, 0.6)
	_box(Vector3(HALF_X * 2.0, WALL_H, 1.0), Vector3(0, WALL_H * 0.5, -HALF_Z), wall_col)
	_box(Vector3(HALF_X * 2.0, WALL_H, 1.0), Vector3(0, WALL_H * 0.5, HALF_Z), wall_col)
	_box(Vector3(1.0, WALL_H, HALF_Z * 2.0), Vector3(-HALF_X, WALL_H * 0.5, 0), wall_col)
	_box(Vector3(1.0, WALL_H, HALF_Z * 2.0), Vector3(HALF_X, WALL_H * 0.5, 0), wall_col)

	# spawn pads: blue for side a on the left, red for side b on the right
	_pad(Vector3(-SPAWN_X, 0.02, 0.0), Vector3(16, 0.04, 26), Color(0.2, 0.45, 0.95), "A")
	_pad(Vector3(SPAWN_X, 0.02, 0.0), Vector3(16, 0.04, 26), Color(0.95, 0.3, 0.25), "B")

	var crate_col := Color(0.42, 0.33, 0.22)
	for c in COVER:
		_box(Vector3(3.0, 2.5, 3.0), c + Vector3(0, 1.25, 0), crate_col)

	# lane walls and the bomb sites
	var wall_mid := Color(0.48, 0.44, 0.38)
	for w in LANE_WALLS:
		_box(w[1], w[0], wall_mid)
	for k in SITES:
		_pad(SITES[k] + Vector3(0, 0.02, 0), Vector3(12, 0.04, 12), Color(0.9, 0.75, 0.25), "SITE " + k)

	# shadowed lights: one key light over the middle and one over each side for depth
	var light := OmniLight3D.new()
	light.position = Vector3(0, 5.5, 0)
	light.light_energy = 1.6
	light.omni_range = 90.0
	light.light_color = Color(1.0, 0.95, 0.85)
	light.shadow_enabled = true
	add_child(light)
	for x in [-30.0, 30.0]:
		var side_light := OmniLight3D.new()
		side_light.position = Vector3(x, 5.0, 0)
		side_light.light_energy = 1.0
		side_light.omni_range = 40.0
		side_light.light_color = Color(1.0, 0.92, 0.8)
		side_light.shadow_enabled = true
		add_child(side_light)


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
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.8
	mi.material_override = mat
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
	add_child(m)
	var lbl := Label3D.new()
	lbl.text = txt
	lbl.font_size = 180
	lbl.pixel_size = 0.02
	lbl.position = pos + Vector3(0, 0.6, 0)
	lbl.rotation_degrees = Vector3(-90, 0, 0)
	add_child(lbl)
