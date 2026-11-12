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
# burning oil barrels: flames, smoke and a flickering light (also cover)
const FIRES := [
	Vector3(-26, 0, -8), Vector3(26, 0, 8), Vector3(-6, 0, -30), Vector3(6, 0, 30),
	Vector3(-56, 0, 12), Vector3(56, 0, -12),
]
var _flames: Array = []
var _t := 0.0

const SCALE := {
	"ground": 0.18, "metal": 0.9, "sand": 0.12, "plaster": 0.22, "brick": 0.3, "concrete": 0.25, "crate": 0.42, "roof": 0.3,
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

	for f in FIRES:
		_fire_barrel(f)

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
## a rusted oil drum on fire: solid barrel (collision), flame and smoke particles, warm flickering light
func _fire_barrel(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos + Vector3(0, 0.45, 0)
	add_child(body)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.3
	cyl.height = 0.9
	cs.shape = cyl
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.3
	cm.bottom_radius = 0.3
	cm.height = 0.9
	mi.mesh = cm
	mi.material_override = _mat("metal")
	mi.layers = ARENA_LAYER
	body.add_child(mi)
	# glowing embers inside the rim
	var ember := StandardMaterial3D.new()
	ember.albedo_color = Color(0.1, 0.03, 0.0)
	ember.emission_enabled = true
	ember.emission = Color(1.0, 0.35, 0.05)
	ember.emission_energy_multiplier = 3.0
	_deco(Vector3(0.5, 0.02, 0.5), pos + Vector3(0, 0.88, 0), ember)

	var flame := CPUParticles3D.new()
	flame.position = pos + Vector3(0, 0.95, 0)
	flame.amount = 46
	flame.lifetime = 0.75
	flame.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flame.emission_sphere_radius = 0.18
	flame.direction = Vector3.UP
	flame.spread = 12.0
	flame.gravity = Vector3(0, 2.2, 0)
	flame.initial_velocity_min = 0.6
	flame.initial_velocity_max = 1.4
	flame.scale_amount_min = 0.35
	flame.scale_amount_max = 0.7
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.6))
	sc.add_point(Vector2(0.35, 1.0))
	sc.add_point(Vector2(1, 0.0))
	flame.scale_amount_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	g.set_color(1, Color(0.9, 0.15, 0.0, 0.0))
	g.add_point(0.45, Color(1.0, 0.45, 0.08, 0.85))
	flame.color_ramp = g
	var qm := QuadMesh.new()
	qm.size = Vector2(0.5, 0.7)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.vertex_color_use_as_albedo = true
	fm.albedo_texture = _soft_dot()
	qm.material = fm
	flame.mesh = qm
	flame.layers = ARENA_LAYER
	add_child(flame)

	var smoke := CPUParticles3D.new()
	smoke.position = pos + Vector3(0, 1.6, 0)
	smoke.amount = 26
	smoke.lifetime = 4.5
	smoke.direction = Vector3.UP
	smoke.spread = 18.0
	smoke.gravity = Vector3(0.35, 0.9, 0.15)
	smoke.initial_velocity_min = 0.5
	smoke.initial_velocity_max = 1.0
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 1.8
	var ssc := Curve.new()
	ssc.add_point(Vector2(0, 0.4))
	ssc.add_point(Vector2(1, 2.4))
	smoke.scale_amount_curve = ssc
	var sg := Gradient.new()
	sg.set_color(0, Color(0.12, 0.11, 0.1, 0.55))
	sg.set_color(1, Color(0.35, 0.34, 0.33, 0.0))
	smoke.color_ramp = sg
	var sq := QuadMesh.new()
	sq.size = Vector2(1.2, 1.2)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.vertex_color_use_as_albedo = true
	sm.albedo_texture = _soft_dot()
	sq.material = sm
	smoke.mesh = sq
	smoke.layers = ARENA_LAYER
	add_child(smoke)

	var light := OmniLight3D.new()
	light.position = pos + Vector3(0, 1.4, 0)
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 2.2
	light.omni_range = 9.0
	light.shadow_enabled = false
	light.light_cull_mask = ARENA_LAYER
	add_child(light)
	_flames.append(light)


var _dot: Texture2D


## soft round sprite for flames and smoke, generated once
func _soft_dot() -> Texture2D:
	if _dot:
		return _dot
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_dot = ImageTexture.create_from_image(img)
	return _dot


func _process(delta: float) -> void:
	# fire light flicker
	_t += delta
	for i in _flames.size():
		var l: OmniLight3D = _flames[i]
		l.light_energy = 2.0 + 0.5 * sin(_t * 13.0 + i * 1.7) + 0.35 * sin(_t * 23.0 + i)


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
