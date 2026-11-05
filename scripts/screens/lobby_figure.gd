extends Node3D
## Lobby character: a stylised man built from primitive meshes to match the lobby design
## (black hoodie with a white V, sunglasses, short beard, black cargo pants, white sneakers,
## M4 rifle held across the body). The figure stays in place; the pivot only turns it.

const SKIN := Color(0.66, 0.46, 0.34)
const BLACK := Color(0.07, 0.07, 0.08)
const DARK := Color(0.11, 0.1, 0.1)
const WHITE := Color(0.95, 0.95, 0.96)
const GUN := Color(0.12, 0.12, 0.13)


func _ready() -> void:
	# feet at y = 0, facing the camera (+Z)
	# legs and cargo pants
	for sx in [-1.0, 1.0]:
		_part(CylinderMesh.new(), Vector3(sx * 0.11, 0.5, 0.0), Vector3(0.16, 0.8, 0.16), BLACK)
		_part(BoxMesh.new(), Vector3(sx * 0.12, 0.5, 0.1), Vector3(0.09, 0.3, 0.05), DARK)  # cargo pocket
		_part(BoxMesh.new(), Vector3(sx * 0.11, 0.05, 0.03), Vector3(0.13, 0.08, 0.27), WHITE)  # sneaker
		_part(BoxMesh.new(), Vector3(sx * 0.11, 0.13, -0.08), Vector3(0.1, 0.02, 0.06), WHITE)  # sneaker sole line
	_part(BoxMesh.new(), Vector3(0.0, 0.94, 0.0), Vector3(0.42, 0.12, 0.25), BLACK)  # belt / hips

	# hoodie torso, hood and neck
	_part(BoxMesh.new(), Vector3(0.0, 1.32, 0.0), Vector3(0.46, 0.66, 0.27), BLACK)
	_part(BoxMesh.new(), Vector3(0.0, 1.7, -0.04), Vector3(0.34, 0.22, 0.2), BLACK)  # hood behind the head
	_part(CylinderMesh.new(), Vector3(0.0, 1.66, 0.0), Vector3(0.1, 0.12, 0.1), SKIN)
	# white V logo on the chest
	_part(BoxMesh.new(), Vector3(-0.045, 1.36, 0.142), Vector3(0.035, 0.13, 0.01), WHITE, Vector3(0, 0, 22))
	_part(BoxMesh.new(), Vector3(0.045, 1.36, 0.142), Vector3(0.035, 0.13, 0.01), WHITE, Vector3(0, 0, -22))

	# head, hair, beard, sunglasses
	_part(SphereMesh.new(), Vector3(0.0, 1.8, 0.0), Vector3(0.23, 0.26, 0.23), SKIN)
	_part(SphereMesh.new(), Vector3(0.0, 1.9, -0.01), Vector3(0.245, 0.14, 0.245), DARK)  # short hair
	_part(BoxMesh.new(), Vector3(0.0, 1.72, 0.07), Vector3(0.17, 0.09, 0.1), DARK)  # beard
	_part(BoxMesh.new(), Vector3(0.0, 1.82, 0.112), Vector3(0.2, 0.05, 0.03), BLACK)  # sunglasses

	# arms: sleeves reach forward to the rifle grip
	for sx in [-1.0, 1.0]:
		_bone(Vector3(sx * 0.3, 1.5, 0.0), Vector3(sx * 0.18, 1.2, 0.16), 0.065, BLACK)
		_bone(Vector3(sx * 0.18, 1.2, 0.16), Vector3(sx * 0.05, 1.12, 0.3), 0.055, BLACK)
		_part(SphereMesh.new(), Vector3(sx * 0.05, 1.12, 0.3), Vector3(0.09, 0.09, 0.09), SKIN)

	# M4 rifle across the body
	var rifle := Node3D.new()
	rifle.position = Vector3(0.02, 1.16, 0.3)
	rifle.rotation_degrees = Vector3(0.0, -8.0, 4.0)
	add_child(rifle)
	_part(BoxMesh.new(), Vector3(0.0, 0.0, 0.0), Vector3(0.07, 0.1, 0.42), GUN, Vector3.ZERO, rifle)  # receiver
	_part(BoxMesh.new(), Vector3(0.0, 0.0, -0.3), Vector3(0.05, 0.09, 0.2), GUN, Vector3.ZERO, rifle)  # stock
	_part(BoxMesh.new(), Vector3(0.0, -0.1, -0.02), Vector3(0.03, 0.14, 0.05), GUN, Vector3(-12, 0, 0), rifle)  # magazine
	_part(CylinderMesh.new(), Vector3(0.0, 0.0, 0.36), Vector3(0.025, 0.28, 0.025), GUN, Vector3(90, 0, 0), rifle)  # barrel
	_part(BoxMesh.new(), Vector3(0.0, 0.0, 0.25), Vector3(0.08, 0.09, 0.18), GUN, Vector3.ZERO, rifle)  # handguard


func _part(mesh: Mesh, pos: Vector3, size: Vector3, col: Color, rot := Vector3.ZERO, parent: Node3D = null) -> void:
	var mi := MeshInstance3D.new()
	var m := mesh
	if m is BoxMesh:
		(m as BoxMesh).size = size
	elif m is SphereMesh:
		(m as SphereMesh).radius = 0.5
		(m as SphereMesh).height = 1.0
	elif m is CylinderMesh:
		(m as CylinderMesh).top_radius = size.x * 0.5
		(m as CylinderMesh).bottom_radius = size.x * 0.5
		(m as CylinderMesh).height = size.y
	mi.mesh = m
	mi.position = pos
	if m is SphereMesh:
		mi.scale = size
	mi.rotation_degrees = rot
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.7
	mi.material_override = mat
	(parent if parent else self).add_child(mi)


## a limb segment from a to b with a radius r
func _bone(a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	var len := a.distance_to(b)
	cap.radius = r
	cap.height = len + r * 2.0
	mi.mesh = cap
	mi.position = (a + b) * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.7
	mi.material_override = mat
	add_child(mi)
	mi.look_at_from_position(mi.position, b, Vector3.UP)
	mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
