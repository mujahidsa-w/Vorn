extends SceneTree
var out := ""
func _initialize() -> void:
	out = OS.get_cmdline_user_args()[0]
	var root := Node3D.new(); get_root().add_child(root)
	var map: Node3D = load("res://assets/models/map/la.glb").instantiate()
	map.scale = Vector3.ONE * 0.01
	root.add_child(map)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.3,0.4,0.6)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(1,1,1); e.ambient_light_energy = 1.0
	env.environment = e; root.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-60, 30, 0); root.add_child(sun)
	var cam := Camera3D.new(); root.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.size = 4800; cam.far = 20000
	cam.position = Vector3(580, 3000, 490); cam.rotation_degrees = Vector3(-90, 0, 0)
	cam.current = true
	# print road mesh names / centers
	var stack := [map]
	while stack.size() > 0:
		var c = stack.pop_back()
		if c is MeshInstance3D and c.name.contains("CENTER_ROUTE"):
			var a: AABB = c.global_transform * c.mesh.get_aabb()
			print("ROUTE ", c.name, " ", a)
		for k in c.get_children(): stack.append(k)
	await process_frame; await process_frame; await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out)
	print("saved")
	quit()
