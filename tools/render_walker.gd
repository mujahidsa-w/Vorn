extends SceneTree
func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var root := Node3D.new(); get_root().add_child(root)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.45,0.5,0.55)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(1,1,1); e.ambient_light_energy = 0.9
	env.environment = e; root.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-30, 40, 0); root.add_child(sun)
	for i in 3:
		var w: Node3D = load("res://assets/models/chars/walker_raw.glb").instantiate(); root.add_child(w)
		w.position = Vector3(-1.2 + i * 1.2, 0, 0); w.rotation.y = [0.0, PI/2, PI][i]
		var ap: AnimationPlayer = w.find_children("*", "AnimationPlayer", true, false)[0]
		print("anims ", ap.get_animation_list())
		ap.play(ap.get_animation_list()[0]); ap.seek(0.3 + i * 0.5, true)
		if i == 0:
			var a := ap.get_animation(ap.get_animation_list()[0])
			print("len ", a.length, " tracks ", a.get_track_count(), " loop ", a.loop_mode)
			for k in min(6, a.get_track_count()): print("  ", a.track_get_path(k), " type ", a.track_get_type(k))
	var h: Node3D = load("res://assets/models/chars/hero.glb").instantiate(); root.add_child(h); h.position = Vector3(2.4, 0, 0)
	var cam := Camera3D.new(); root.add_child(cam); cam.position = Vector3(0.6, 1.2, 5.5); cam.look_at(Vector3(0.6, 1.0, 0)); cam.current = true
	for k in 3: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out)
	quit()
