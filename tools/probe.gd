extends SceneTree
# Dev: print AABBs of models and render views.

func aabb_of(n: Node) -> AABB:
	var out := AABB(); var first := true
	var stack := [n]
	while stack.size() > 0:
		var c = stack.pop_back()
		if c is MeshInstance3D and c.mesh:
			var a: AABB = c.global_transform * c.mesh.get_aabb()
			if first: out = a; first = false
			else: out = out.merge(a)
		for k in c.get_children(): stack.append(k)
	return out

func _initialize() -> void:
	var root := Node3D.new(); get_root().add_child(root)
	for p in ["res://assets/models/map/la.glb","res://assets/models/cars/police_gt500.glb","res://assets/models/cars/mustang69.glb","res://assets/models/chars/human.obj"]:
		var r = load(p)
		var inst: Node3D
		if r is PackedScene: inst = r.instantiate()
		else:
			inst = MeshInstance3D.new(); inst.mesh = r
		root.add_child(inst)
		var a := aabb_of(inst)
		var cnt := 0
		print(p, "  AABB pos=", a.position, " size=", a.size)
		inst.queue_free()
	quit()
