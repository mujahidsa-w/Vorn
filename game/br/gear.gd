class_name Gear
extends RefCounted
## Models of equipment: the wooden supply crate and the helmet (assets/gear).

const CRATE := "res://assets/gear/crate.fbx"
const HELMET := "res://assets/gear/helmet.glb"
# crate proportions (long side 1): width, height
const CRATE_W := 0.467
const CRATE_H := 0.234

static var _crate_mat: StandardMaterial3D
static var _crate_box := AABB()

static func _wood() -> StandardMaterial3D:
	if _crate_mat == null:
		_crate_mat = StandardMaterial3D.new()
		var t := "res://assets/maps/kasbah_wood_planks_%s.jpg"
		if ResourceLoader.exists(t % "base"):
			_crate_mat.albedo_texture = load(t % "base")
		if ResourceLoader.exists(t % "normal"):
			_crate_mat.normal_enabled = true
			_crate_mat.normal_texture = load(t % "normal")
		_crate_mat.albedo_color = Color(0.82, 0.70, 0.55)
		_crate_mat.roughness = 0.85
		# the source model carries no textures: planks are projected in world space, one board ~ 0.6 m
		_crate_mat.uv1_triplanar = true
		_crate_mat.uv1_world_triplanar = true
		_crate_mat.uv1_scale = Vector3.ONE * 0.9
		_crate_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return _crate_mat

static func _xf(root: Node, n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var x := n
	while x != root and x != null:
		if x is Node3D:
			t = (x as Node3D).transform * t
		x = x.get_parent()
	return t

## a crate with its long side `length` metres along local Z, standing on y = 0, centred
static func crate(length := 1.3, fade := 110.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Crate"
	if not ResourceLoader.exists(CRATE):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(length * CRATE_W, length * CRATE_H, length)
		mi.mesh = bm
		mi.position.y = length * CRATE_H * 0.5
		mi.material_override = _wood()
		root.add_child(mi)
		return root
	var inst := (load(CRATE) as PackedScene).instantiate() as Node3D
	for c in inst.find_children("*", "Light3D", true, false) + inst.find_children("*", "Camera3D", true, false):
		c.free()
	if _crate_box.size == Vector3.ZERO:
		var box := AABB()
		var first := true
		for c in inst.find_children("*", "MeshInstance3D", true, false):
			var ab := _xf(inst, c) * (c as MeshInstance3D).get_aabb()
			box = ab if first else box.merge(ab)
			first = false
		_crate_box = box
	var k := length / maxf(_crate_box.size.z, 0.001)
	inst.scale = Vector3.ONE * k
	inst.position = -Vector3(_crate_box.get_center().x, _crate_box.position.y, _crate_box.get_center().z) * k
	for c in inst.find_children("*", "MeshInstance3D", true, false):
		var g := c as MeshInstance3D
		g.material_override = _wood()
		g.visibility_range_end = fade
		g.visibility_range_end_margin = 8.0
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	root.add_child(inst)
	return root

static func crate_size(length: float) -> Vector3:
	return Vector3(length * CRATE_W, length * CRATE_H, length)

## the helmet, front towards -Z, rim at y = 0, ~0.24 m wide
static func helmet() -> Node3D:
	var root := Node3D.new()
	root.name = "Helmet"
	if not ResourceLoader.exists(HELMET):
		return root
	var inst := (load(HELMET) as PackedScene).instantiate() as Node3D
	inst.rotation.y = PI
	inst.position.y = 0.05
	root.add_child(inst)
	return root
