extends Node3D
## Lobby character: the realistic man model (Character Creator base mesh, static OBJ).
## It is recoloured by material name to match the design: black jacket and pants, white sneakers,
## dark hair. The model stays in place; the pivot only turns it left and right.

const MODEL := preload("res://assets/models/lobby/realistic_man.obj")
const BLACK := Color(0.06, 0.06, 0.07)
const DARK := Color(0.08, 0.06, 0.05)
const WHITE := Color(0.95, 0.95, 0.96)
const SKIN := Color(0.62, 0.42, 0.3)


func _ready() -> void:
	var m := MeshInstance3D.new()
	m.mesh = MODEL
	add_child(m)
	_recolor(m)
	_add_sunglasses()


## sunglasses in front of the eyes (eyes sit at y 1.72, z about 0.06 in the model)
func _add_sunglasses() -> void:
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.02, 0.02, 0.03)
	frame.roughness = 0.15
	frame.metallic = 0.3
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color(0.01, 0.01, 0.015)
	lens.roughness = 0.05
	lens.metallic = 0.2
	var y := 1.722
	var z := 0.088
	for sx in [-1.0, 1.0]:
		_box(Vector3(sx * 0.042, y, z), Vector3(0.078, 0.036, 0.008), lens)
		_box(Vector3(sx * 0.042, y + 0.02, z + 0.002), Vector3(0.082, 0.006, 0.01), frame)
		_box(Vector3(sx * 0.042, y - 0.02, z + 0.002), Vector3(0.082, 0.006, 0.01), frame)
		_box(Vector3(sx * 0.084, y + 0.006, 0.02), Vector3(0.008, 0.008, 0.11), frame)  # temple arm
	_box(Vector3(0.0, y + 0.006, z), Vector3(0.016, 0.008, 0.008), frame)  # bridge


func _box(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	add_child(mi)


func _recolor(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i) as StandardMaterial3D
			if src == null:
				continue
			var key := src.resource_name
			var col = null
			if key in ["Jacket", "Vest", "Chachi_Momma_Pants"]:
				col = BLACK
			elif key == "Sneaker":
				col = WHITE
			elif key in ["Hair_Transparency", "Scalp_Transparency"]:
				col = DARK
			elif key.begins_with("Std_Skin"):
				col = SKIN
			if col != null:
				var mat := src.duplicate() as StandardMaterial3D
				mat.albedo_texture = null
				mat.albedo_color = col
				mi.set_surface_override_material(i, mat)
	for ch in n.get_children():
		_recolor(ch)
