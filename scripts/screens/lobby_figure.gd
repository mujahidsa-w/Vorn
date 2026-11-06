extends Node3D
## Lobby character: the realistic man model, unchanged, with its diffuse textures.
## The model stays in place; the pivot only turns it left and right.

const MODEL := preload("res://assets/models/lobby/realistic_man.obj")


func _ready() -> void:
	var m := MeshInstance3D.new()
	m.mesh = MODEL
	add_child(m)
