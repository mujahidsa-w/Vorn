extends Node3D
## In-world Vorn City Business District: storefronts with real interaction points.

var world
var locations: Array = []
var _font: Font

const BUSINESS_DATA := [
	{"id": "dealership", "name": "ROYAL MOTORS", "subtitle": "VEHICLE DEALERSHIP", "screen": "market", "color": Color(1.0, 0.72, 0.2)},
	{"id": "estate", "name": "VORN ESTATES", "subtitle": "HOMES & PROPERTY", "screen": "market", "color": Color(0.35, 0.85, 1.0)},
	{"id": "jobs", "name": "CITY HALL", "subtitle": "CAREERS & SERVICES", "screen": "jobs", "color": Color(0.35, 1.0, 0.6)},
	{"id": "fashion", "name": "VORN STYLE", "subtitle": "CLOTHES & OUTFITS", "screen": "customize", "color": Color(0.85, 0.45, 1.0)},
	{"id": "gang_hq", "name": "VORN CREW HQ", "subtitle": "GANGS & TERRITORIES", "screen": "gangs", "color": Color(1.0, 0.3, 0.45)},
	{"id": "police_hq", "name": "VORN POLICE HQ", "subtitle": "PUBLIC SAFETY & LICENSING", "screen": "security", "color": Color(0.3, 0.55, 1.0)},
	{"id": "court_house", "name": "VORN COURT HOUSE", "subtitle": "CASES & HEARINGS", "screen": "court", "color": Color(0.9, 0.85, 0.65)},
]

func _ready() -> void:
	_font = Game.font_wide
	_build_district()

func _build_district() -> void:
	if world == null or world.spawn_xf == Transform3D():
		return
	var origin: Vector3 = world.spawn_xf.origin
	var forward: Vector3 = -world.spawn_xf.basis.z.normalized()
	var side: Vector3 = world.spawn_xf.basis.x.normalized()
	for i in BUSINESS_DATA.size():
		var data: Dictionary = BUSINESS_DATA[i]
		var pos: Vector3 = origin + forward * 13.0 + side * ((i - 1.5) * 14.0)
		var g: Dictionary = world._ground(pos + Vector3(0, 40, 0))
		if not g.is_empty():
			pos.y = g.position.y
		_build_store(data, pos, forward)
		locations.append({"data": data, "pos": pos})
		world.poi.append({"name": str(data.name), "pos": pos, "color": data.color})
	var title := Label3D.new()
	title.text = "VORN CITY  •  BUSINESS DISTRICT"
	title.font = _font
	title.font_size = 72
	title.pixel_size = 0.008
	title.modulate = Color(0.75, 0.9, 1.0)
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.position = origin + forward * 10.0 + Vector3(0, 5.2, 0)
	add_child(title)

func _build_store(data: Dictionary, pos: Vector3, forward: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	var basis := Basis.looking_at(forward, Vector3.UP)
	root.basis = basis
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.055, 0.075, 0.12)
	mat.metallic = 0.35
	mat.roughness = 0.35
	_world_box(root, Vector3(10, 4.8, 5.0), Vector3(0, 2.4, 0), mat)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(data.color, 0.36)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.7
	_world_box(root, Vector3(7.5, 2.7, 0.12), Vector3(0, 2.1, -2.53), glass)
	var sign := Label3D.new()
	sign.text = str(data.name)
	sign.font = _font
	sign.font_size = 58
	sign.pixel_size = 0.008
	sign.modulate = data.color
	sign.outline_size = 12
	sign.outline_modulate = Color(0.01, 0.02, 0.04, 0.95)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position = Vector3(0, 4.65, -2.7)
	root.add_child(sign)
	var sub := Label3D.new()
	sub.text = str(data.subtitle)
	sub.font = Game.font_tag
	sub.font_size = 30
	sub.pixel_size = 0.008
	sub.modulate = Color(0.86, 0.9, 0.96)
	sub.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sub.position = Vector3(0, 3.85, -2.7)
	root.add_child(sub)
	var lamp := OmniLight3D.new()
	lamp.light_color = data.color
	lamp.light_energy = 2.2
	lamp.omni_range = 8.0
	lamp.position = Vector3(0, 3.2, -3.5)
	root.add_child(lamp)

func _world_box(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mi.mesh = box
	mi.position = pos
	parent.add_child(mi)

func nearest(from: Vector3, max_distance := 7.0) -> Dictionary:
	var best := {}
	var distance := max_distance
	for location in locations:
		var d: float = from.distance_to(location.pos)
		if d < distance:
			distance = d
			best = location
	return best

func interact(from: Vector3) -> bool:
	var target := nearest(from)
	if target.is_empty():
		return false
	var data: Dictionary = target.data
	Game.next_screen = str(data.screen)
	Game.play_sfx("door")
	if world.hud:
		world.hud.notify("ENTERING  " + str(data.name))
	world.back_to_lobby()
	return true
