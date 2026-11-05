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


func _recolor(n: Node) -> void:
	# the model's textures are not in the file, so materials get plain colours by name
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
