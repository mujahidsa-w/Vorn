class_name Loot
extends Node3D
## An item lying on the ground: a weapon (its real model), ammunition, bandages and first-aid kits,
## vests, a helmet or a grenade. A faint coloured ring under it shows the rarity.

const AMMO_OF := {"pistol": "ammo_light", "smg": "ammo_light", "shotgun": "ammo_shell", "rifle": "ammo_rifle", "sniper": "ammo_sniper"}
const INFO := {
	"ammo_light": {"name": "ذخيرة خفيفة", "n": 45, "col": Color(0.95, 0.80, 0.35)},
	"ammo_rifle": {"name": "ذخيرة بنادق", "n": 40, "col": Color(0.55, 0.85, 0.40)},
	"ammo_shell": {"name": "خرطوش", "n": 14, "col": Color(0.95, 0.35, 0.25)},
	"ammo_sniper": {"name": "ذخيرة قنّاصة", "n": 8, "col": Color(0.40, 0.70, 1.0)},
	"bandage": {"name": "ضمادة", "n": 2, "col": Color(0.92, 0.92, 0.92)},
	"medkit": {"name": "حقيبة إسعاف", "n": 1, "col": Color(0.95, 0.25, 0.25)},
	"vest1": {"name": "سترة خفيفة", "n": 1, "col": Color(0.55, 0.65, 0.95)},
	"vest2": {"name": "سترة ثقيلة", "n": 1, "col": Color(0.75, 0.45, 1.0)},
	"helmet": {"name": "خوذة", "n": 1, "col": Color(0.55, 0.65, 0.95)},
}
const WEAPON_RANK := {"ak": 9, "m4": 9, "awp": 7, "mp9": 6, "mac10": 6, "shotgun": 5, "deagle": 4, "usp": 3, "glock": 3}

var id := ""
var count := 1
var kind := ""            # weapon, ammo, med, armor, nade
var taken := false

static func ammo_for(wid: String) -> String:
	var cls: String = DB.W.get(wid, {}).get("cls", "")
	return AMMO_OF.get(cls, "")

static func title(item_id: String) -> String:
	if DB.W.has(item_id):
		return String(DB.W[item_id]["name"])
	return String(INFO.get(item_id, {}).get("name", item_id))

static func kind_of(item_id: String) -> String:
	if item_id.begins_with("ammo_"):
		return "ammo"
	if item_id in ["bandage", "medkit"]:
		return "med"
	if item_id in ["vest1", "vest2", "helmet"]:
		return "armor"
	if DB.W.has(item_id) and DB.W[item_id]["cls"] == "nade":
		return "nade"
	return "weapon"

static func make(item_id: String, n := -1) -> Loot:
	var l := Loot.new()
	l.id = item_id
	l.kind = kind_of(item_id)
	l.count = n if n >= 0 else int(INFO.get(item_id, {}).get("n", 1))
	l.name = "Loot_" + item_id
	return l

func _ready() -> void:
	var col := Color(0.9, 0.85, 0.7)
	match kind:
		"weapon":
			var path := "res://assets/models/weapons/%s.scn" % id
			if ResourceLoader.exists(path):
				var w := (load(path) as PackedScene).instantiate() as Node3D
				add_child(w)
				Sight.attach(w, id, false)
				# lying on its side: barrel along the ground
				w.transform = Transform3D(Basis(Vector3.FORWARD, PI / 2.0), Vector3(0, 0.05, 0))
			else:
				_box(Vector3(0.12, 0.08, 0.7), Vector3(0, 0.05, 0), Color(0.15, 0.15, 0.16))
			col = Color(1.0, 0.82, 0.35) if WEAPON_RANK.get(id, 0) >= 7 else Color(0.85, 0.85, 0.85)
		"ammo":
			col = INFO[id]["col"]
			_box(Vector3(0.32, 0.18, 0.2), Vector3(0, 0.09, 0), Color(0.24, 0.27, 0.16))
			_box(Vector3(0.33, 0.03, 0.21), Vector3(0, 0.12, 0), col.darkened(0.2))
		"med":
			col = INFO[id]["col"]
			if id == "medkit":
				_box(Vector3(0.38, 0.14, 0.26), Vector3(0, 0.07, 0), Color(0.92, 0.92, 0.9))
				_box(Vector3(0.20, 0.02, 0.06), Vector3(0, 0.145, 0), Color(0.85, 0.08, 0.06))
				_box(Vector3(0.06, 0.02, 0.20), Vector3(0, 0.145, 0), Color(0.85, 0.08, 0.06))
			else:
				for i in 2:
					_box(Vector3(0.12, 0.07, 0.09), Vector3(-0.08 + i * 0.16, 0.035, 0), Color(0.93, 0.90, 0.84))
		"armor":
			col = INFO[id]["col"]
			if id == "helmet":
				var mi := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.16
				sm.height = 0.32
				sm.is_hemisphere = true
				mi.mesh = sm
				mi.position.y = 0.02
				var m := StandardMaterial3D.new()
				m.albedo_color = Color(0.26, 0.30, 0.20)
				m.roughness = 0.7
				mi.material_override = m
				add_child(mi)
			else:
				_box(Vector3(0.48, 0.10, 0.55), Vector3(0, 0.05, 0), Color(0.22, 0.26, 0.18) if id == "vest1" else Color(0.18, 0.18, 0.2))
				_box(Vector3(0.20, 0.03, 0.12), Vector3(0, 0.115, -0.18), Color(0.1, 0.1, 0.1))
		"nade":
			var p2 := "res://assets/models/weapons/%s.scn" % id
			if ResourceLoader.exists(p2):
				var g := (load(p2) as PackedScene).instantiate() as Node3D
				add_child(g)
				g.position.y = 0.06
			else:
				_box(Vector3(0.07, 0.11, 0.07), Vector3(0, 0.06, 0), Color(0.2, 0.25, 0.15))
			col = Color(0.95, 0.6, 0.3)
	# rarity ring
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.46
	tm.rings = 32
	tm.ring_segments = 4
	ring.mesh = tm
	ring.scale = Vector3(1, 0.05, 1)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(col.r, col.g, col.b, 0.55)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = 0.01
	add_child(ring)
	for c in find_children("*", "GeometryInstance3D", true, false):
		(c as GeometryInstance3D).visibility_range_end = 70.0

func _box(sz: Vector3, pos: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = sz
	mi.mesh = b
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.75
	mi.material_override = m
	add_child(mi)
