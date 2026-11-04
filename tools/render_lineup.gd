extends SceneTree
func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var root := Node3D.new(); get_root().add_child(root)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.35,0.4,0.45)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(1,1,1); e.ambient_light_energy = 0.8
	env.environment = e; root.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 40, 0); root.add_child(sun)
	var cars := ["police_gt500","charger_police","mustang69","mustang_gt","mustang_rtr"]
	for i in cars.size():
		var c: Node3D = load("res://assets/models/cars/%s.glb" % cars[i]).instantiate(); root.add_child(c)
		c.position = Vector3(-7.5 + i * 3.0, 0, 0)
	var w := ["glock","akm","m4","sniper","rpg","c4"]
	for i in w.size():
		var g: Node3D = load("res://assets/models/weapons/%s.glb" % w[i]).instantiate(); root.add_child(g)
		g.position = Vector3(-5 + i * 2.0, 1.0, 5)
		g.scale = Vector3.ONE * 2.0
	var s: Node3D = load("res://assets/models/props/swat_guard.glb").instantiate(); root.add_child(s); s.position = Vector3(9, 0, 3)
	var h: Node3D = load("res://assets/models/chars/hero.glb").instantiate(); root.add_child(h); h.position = Vector3(10.5, 0, 3)
	var cam := Camera3D.new(); root.add_child(cam); cam.fov = 55
	if OS.get_cmdline_user_args().size() > 1:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.size = 22; cam.position = Vector3(1, 30, 3); cam.rotation_degrees = Vector3(-90, 0, 0)
	else:
		cam.position = Vector3(1, 4.5, 14); cam.look_at(Vector3(1, 0.8, 2))
	cam.current = true
	for k in 4: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out)
	quit()
