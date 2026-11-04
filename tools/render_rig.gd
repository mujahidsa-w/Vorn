extends SceneTree
const Rig = preload("res://scripts/game3d/rig.gd")
func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var root := Node3D.new(); get_root().add_child(root)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.45,0.5,0.55)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(1,1,1); e.ambient_light_energy = 0.9
	env.environment = e; root.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-30, 40, 0); root.add_child(sun)
	await process_frame
	var rigs := []
	var cfg := [[false, 0.0, ""], [false, 0.0, ""], [false, 0.0, ""], [true, 0.0, ""], [true, 0.0, ""], [true, 0.0, ""]]
	for i in cfg.size():
		var holder := Node3D.new(); root.add_child(holder)
		holder.position = Vector3(-3.0 + i * 1.2, 0, 0)
		holder.rotation.y = PI / 2
		var r := Rig.new(); holder.add_child(r); r.rotation.y = PI
		r.setup(cfg[i][0])
		rigs.append([r, cfg[i]])
	await process_frame
	for k in 40:
		var idx := 0
		for rr in rigs:
			var c = rr[1]
			rr[0].update(0.033 + (idx % 3) * 0.012, 1.45, true, c[2], 0.0, 0.0)
			idx += 1
		await process_frame
	var cam := Camera3D.new(); root.add_child(cam); cam.position = Vector3(-1.8, 0.9, 2.6); cam.look_at(Vector3(-1.8, 0.85, 0)); cam.current = true
	await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out)
	quit()
