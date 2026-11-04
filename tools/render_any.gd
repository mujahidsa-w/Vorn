extends SceneTree
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]; var path: String = a[1]; var s := float(a[2])
	var root := Node3D.new(); get_root().add_child(root)
	var m: Node3D = load(path).instantiate(); m.scale = Vector3.ONE * s; root.add_child(m)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.4,0.5,0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(1,1,1); e.ambient_light_energy = 0.9
	env.environment = e; root.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-55, 30, 0); root.add_child(sun)
	await process_frame
	var ab := AABB(); var first := true
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.mesh.get_aabb()
		if first: ab = b; first = false
		else: ab = ab.merge(b)
	print("AABB ", ab)
	var cam := Camera3D.new(); root.add_child(cam); cam.far = 20000
	var mode: String = a[3]
	if mode == "top":
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.size = maxf(ab.size.x, ab.size.z) * 1.05
		cam.position = ab.get_center() + Vector3(0, ab.size.y + 100, 0); cam.rotation_degrees = Vector3(-90, 0, 0)
	else:
		var p := Vector3(float(a[4]), float(a[5]), float(a[6]))
		cam.position = p; cam.look_at(p + Vector3(float(a[7]), -0.15, float(a[8])))
	if a.size() > 9:
		var car: Node3D = load("res://assets/models/cars/police_gt500.glb").instantiate(); car.scale = Vector3.ONE*100; root.add_child(car)
		car.position = Vector3(float(a[9]), float(a[10]), float(a[11]))
	cam.current = true
	for k in 4: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out)
	quit()
