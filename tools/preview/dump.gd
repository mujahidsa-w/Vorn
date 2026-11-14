extends SceneTree
## CI diagnostics (needs the unpacked models): node tree, surfaces and the geometry the optics are mounted on.
##   godot --headless --path . --script res://tools/preview/dump.gd

func _rel(root: Node, n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var x: Node = n
	while x != root and x != null:
		if x is Node3D:
			t = (x as Node3D).transform * t
		x = x.get_parent()
	return t

func _init() -> void:
	for wid in ["awp", "ak", "m4", "mp9", "mac10", "shotgun", "glock", "usp", "deagle"]:
		var ps := load("res://assets/models/weapons/%s.scn" % wid) as PackedScene
		if ps == null:
			print("DUMP %s missing" % wid)
			continue
		var w := ps.instantiate() as Node3D
		root.add_child(w)
		var lines := []
		for n in w.find_children("*", "", true, false):
			var xf := _rel(w, n)
			var s := "%s<%s> at %s" % [n.name, n.get_class(), xf.origin.snapped(Vector3.ONE * 0.001)]
			if n is MeshInstance3D:
				var mi := n as MeshInstance3D
				var aabb := xf * mi.get_aabb()
				var mats := []
				for i in mi.mesh.get_surface_count():
					var m := mi.mesh.surface_get_material(i)
					var nv: int = (mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
					mats.append("%s:%d" % [m.resource_name if m else "-", nv])
				s += " aabb %s..%s mats %s" % [aabb.position.snapped(Vector3.ONE * 0.001), aabb.end.snapped(Vector3.ONE * 0.001), mats]
			lines.append(s)
		print("DUMP %s\n  %s" % [wid, "\n  ".join(lines)])
		# height profile along the barrel: max y every 2 cm (where an optic can sit, where the AWP scope is)
		var pts := PackedVector3Array()
		for mi in w.find_children("*", "MeshInstance3D", true, false):
			var m2 := mi as MeshInstance3D
			var xf2 := _rel(w, m2)
			for i in m2.mesh.get_surface_count():
				for v in (m2.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					pts.append(xf2 * v)
		var prof := {}
		for p in pts:
			var k := int(floor(p.z / 0.02))
			if not prof.has(k) or p.y > prof[k][0]:
				prof[k] = [p.y, p.x]
		var ks := prof.keys()
		ks.sort()
		var row := []
		for k in ks:
			row.append("%.2f:%.3f" % [k * 0.02, prof[k][0]])
		print("PROFILE %s %s" % [wid, " ".join(row)])
		w.queue_free()
	quit(0)
