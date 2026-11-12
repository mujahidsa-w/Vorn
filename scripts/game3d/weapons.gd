extends RefCounted
## Weapon definitions. pos/rot place the model in the character's model space
## (character faces +Z, its right side is -X). muzzle = local offset of the barrel tip.

const DATA := {
	"glock": {
		"name": "GLOCK 19", "path": "res://assets/models/weapons/glock.glb", "type": "pistol",
		"pos": Vector3(-0.02, 1.36, 0.36), "rot": Vector3(0, -90, 0), "muzzle": 0.11,
		"mag": 17, "rate": 0.2, "auto": false, "sound": "shot_pistol", "spread": 0.006, "recoil": 0.012, "damage": 22.0,
	},
	"m4": {
		"name": "M4 CARBINE", "path": "res://assets/models/weapons/m4.glb", "type": "rifle",
		"pos": Vector3(-0.05, 1.36, 0.3), "rot": Vector3(0, -90, 0), "muzzle": 0.44,
		"mag": 30, "rate": 0.095, "auto": true, "sound": "shot_rifle", "spread": 0.01, "recoil": 0.008, "damage": 28.0,
	},
	"akm": {
		"name": "AKM", "path": "res://assets/models/weapons/akm.glb", "type": "rifle",
		"pos": Vector3(-0.05, 1.36, 0.3), "rot": Vector3(0, -90, 0), "muzzle": 0.46,
		"mag": 30, "rate": 0.105, "auto": true, "sound": "shot_ak", "spread": 0.014, "recoil": 0.011, "damage": 32.0,
	},
	"sniper": {
		"name": "LONGBOW DMR", "path": "res://assets/models/weapons/sniper.glb", "type": "rifle",
		"pos": Vector3(-0.08, 1.38, 0.36), "rot": Vector3(0, 0, 0), "muzzle": 0.6,
		"mag": 5, "rate": 1.1, "auto": false, "sound": "shot_sniper", "spread": 0.0, "recoil": 0.035, "scope": true, "damage": 95.0,
	},
	"rpg": {
		"name": "RPG-7", "path": "res://assets/models/weapons/rpg.glb", "type": "rpg",
		"pos": Vector3(-0.17, 1.58, 0.12), "rot": Vector3(0, 90, 0), "muzzle": 0.5, "flip": true,
		"mag": 1, "rate": 1.6, "auto": false, "sound": "rocket", "spread": 0.0, "recoil": 0.04,
	},
	"c4": {
		"name": "C4 CHARGE", "path": "res://assets/models/weapons/c4.glb", "type": "c4",
		"pos": Vector3(-0.22, 1.02, 0.3), "rot": Vector3(0, 0, 0), "muzzle": 0.0,
		"mag": 3, "rate": 0.6, "auto": false, "sound": "", "spread": 0.0, "recoil": 0.0,
	},
}


static func _local_aabb(node: Node3D) -> AABB:
	var ab := AABB()
	var first := true
	var inv := node.global_transform.affine_inverse()
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = (inv * mi.global_transform) * (mi as MeshInstance3D).get_aabb()
		if first:
			ab = a
			first = false
		else:
			ab = ab.merge(a)
	return ab


## Hand grip points (weapon-local) derived from the model bounds.
static func grips_for(id: String, node: Node3D) -> Dictionary:
	var d: Dictionary = DATA[id]
	var ab := _local_aabb(node)
	var z_axis: bool = id == "sniper"
	var L: float = ab.size.z if z_axis else ab.size.x
	var mn: float = ab.position.z if z_axis else ab.position.x
	var c := ab.get_center()
	var h := ab.size.y
	var lat := 1.0
	var out := {}
	var flip: bool = d.get("flip", false)
	var mk := func(f: float, dy: float, dl: float) -> Vector3:
		var along := (mn + L - f * L) if flip else (mn + f * L)
		return Vector3(c.x + dl, c.y + dy * h, along) if z_axis else Vector3(along, c.y + dy * h, c.z + dl)
	match d.type:
		"pistol":
			out["R"] = mk.call(0.3, -0.2, 0.0)
			out["L"] = mk.call(0.34, -0.25, 0.03 * lat)
		"rpg":
			out["R"] = mk.call(0.42, -0.45, 0.0)
			out["L"] = mk.call(0.66, -0.35, 0.0)
		"c4":
			out["R"] = c
		_:
			out["R"] = mk.call(0.36, -0.3, 0.0)
			out["L"] = mk.call(0.54, -0.2, 0.0)
	return out


static func muzzle_local(id: String, node: Node3D) -> Vector3:
	var ab := _local_aabb(node)
	var c := ab.get_center()
	if id == "sniper":
		return Vector3(c.x, c.y + ab.size.y * 0.15, ab.end.z)
	if DATA[id].get("flip", false):
		return Vector3(ab.position.x, c.y + ab.size.y * 0.15, c.z)
	return Vector3(ab.end.x, c.y + ab.size.y * 0.15, c.z)
