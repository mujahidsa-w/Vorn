extends SceneTree
## Local stand-ins for the first-person check when the original models are not unpacked (assets/models is git-ignored):
## a box rifle and a box pistol with the grip/muzzle markers, and bare arm skeletons.
##   godot --headless --path . --script res://tools/checks/make_fakes.gd

func _own(n: Node, o: Node) -> void:
	for c in n.get_children():
		c.owner = o
		_own(c, o)

func _box(parent: Node3D, sz: Vector3, pos: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = sz
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	b.material = m
	mi.mesh = b
	mi.position = pos
	parent.add_child(mi)

func _gun(name: String, pistol: bool) -> void:
	var root := Node3D.new()
	root.name = name
	var model := Node3D.new()
	model.name = "model"
	root.add_child(model)
	var c := Color(0.25, 0.26, 0.28)
	if pistol:
		var slide := Node3D.new()
		slide.name = "mv_slide"
		model.add_child(slide)
		_box(slide, Vector3(0.03, 0.035, 0.19), Vector3(0, 0.03, -0.05), c)
		_box(model, Vector3(0.028, 0.11, 0.045), Vector3(0, -0.04, 0.01), c.darkened(0.3))
		for p in [["p_grip_r", Vector3(0, -0.03, 0.01)], ["p_muzzle", Vector3(0, 0.03, -0.15)]]:
			var n := Node3D.new()
			n.name = p[0]
			n.position = p[1]
			model.add_child(n)
	else:
		_box(model, Vector3(0.05, 0.07, 0.42), Vector3(0, 0.0, -0.05), c)
		_box(model, Vector3(0.03, 0.03, 0.40), Vector3(0, 0.01, -0.45), c.darkened(0.2))
		_box(model, Vector3(0.04, 0.10, 0.22), Vector3(0, -0.02, 0.27), c.darkened(0.3))
		_box(model, Vector3(0.03, 0.10, 0.04), Vector3(0, -0.08, 0.05), c.darkened(0.4))
		var mag := Node3D.new()
		mag.name = "mv_mag"
		model.add_child(mag)
		_box(mag, Vector3(0.025, 0.12, 0.05), Vector3(0, -0.09, -0.06), c.darkened(0.5))
		for p in [["p_grip_r", Vector3(0, -0.06, 0.05)], ["p_grip_l", Vector3(0, -0.03, -0.25)], ["p_muzzle", Vector3(0, 0.01, -0.66)]]:
			var n := Node3D.new()
			n.name = p[0]
			n.position = p[1]
			model.add_child(n)
	_own(root, root)
	var ps := PackedScene.new()
	ps.pack(root)
	DirAccess.make_dir_recursive_absolute("res://assets/models/weapons")
	ResourceSaver.save(ps, "res://assets/models/weapons/%s.scn" % name)
	root.free()

func _arms(team: String) -> void:
	var root := Node3D.new()
	root.name = "arms"
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	root.add_child(sk)
	for b in ["forearm_r", "hand_r", "forearm_l", "hand_l"]:
		sk.add_bone(b)
	sk.set_bone_parent(1, 0)
	sk.set_bone_parent(3, 2)
	sk.set_bone_rest(1, Transform3D(Basis(), Vector3(0, 0.28, 0)))
	sk.set_bone_rest(3, Transform3D(Basis(), Vector3(0, 0.28, 0)))
	_own(root, root)
	var ps := PackedScene.new()
	ps.pack(root)
	DirAccess.make_dir_recursive_absolute("res://assets/models/chars")
	ResourceSaver.save(ps, "res://assets/models/chars/arms_%s.scn" % team)
	root.free()

func _init() -> void:
	for w in ["ak", "m4", "awp", "shotgun", "mac10", "mp9"]:
		_gun(w, false)
	for w in ["glock", "usp", "deagle"]:
		_gun(w, true)
	_arms("ct")
	_arms("t")
	print("fakes written")
	quit(0)
