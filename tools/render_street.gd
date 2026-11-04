extends SceneTree
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var s := float(args[1])
	var idx := int(args[2])
	var root := Node3D.new(); get_root().add_child(root)
	var map: Node3D = load("res://assets/models/map/la.glb").instantiate()
	map.scale = Vector3.ONE * s
	root.add_child(map)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.5,0.6,0.8)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(1,1,1); e.ambient_light_energy = 0.8
	env.environment = e; root.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 30, 0); root.add_child(sun)
	await process_frame
	var pts := PackedVector3Array()
	var stack: Array = [map]
	var mats := {}
	while stack.size() > 0:
		var c = stack.pop_back()
		if c is MeshInstance3D:
			for si in c.mesh.get_surface_count():
				var mn := str(c.mesh.surface_get_material(si).resource_name) if c.mesh.surface_get_material(si) else "?"
				mats[mn] = mats.get(mn, 0) + 1
				if mn.begins_with("road"):
					var va: PackedVector3Array = c.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
					for k in range(0, va.size(), 7): pts.append(c.global_transform * va[k])
		for k in c.get_children(): stack.append(k)
	print("mats ", mats)
	print("road pts ", pts.size())
	var p: Vector3 = pts[idx % pts.size()]
	var q: Vector3 = p
	for k in pts:
		var d := k.distance_to(p)
		if d > 15.0 and d < 25.0: q = k; break
	print("p=", p, " q=", q)
	var car: Node3D = load("res://assets/models/cars/police_gt500.glb").instantiate()
	root.add_child(car)
	var dir := (q - p); dir.y = 0; dir = dir.normalized()
	car.global_position = p + Vector3(0, 0.3, 0)
	car.look_at(car.global_position - dir, Vector3.UP)
	var cam := Camera3D.new(); root.add_child(cam); cam.far = 5000
	cam.global_position = p - dir * 10.0 + Vector3(0, 4, 0)
	cam.look_at(p + dir * 10.0, Vector3.UP)
	cam.current = true
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out)
	quit()
