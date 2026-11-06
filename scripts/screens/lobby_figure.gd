extends Node3D
## Lobby character: the realistic man model with its diffuse textures.
## The model stays in place (feet fixed); the pivot turns it left and right, and it breathes slowly.

const MODEL := preload("res://assets/models/lobby/realistic_man.obj")
const BREATH_HZ := 0.26   # about one breath every 4 seconds

var _mesh: MeshInstance3D
var _t := 0.0


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = MODEL
	add_child(_mesh)


func _process(delta: float) -> void:
	# the model's origin is at its feet, so scaling keeps the feet on the ground
	_t += delta
	var b := sin(_t * TAU * BREATH_HZ)
	_mesh.scale = Vector3(1.0 - 0.002 * b, 1.0 + 0.005 * b, 1.0 - 0.002 * b)
