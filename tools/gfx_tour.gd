extends Node
## Visual check: screenshots along the street at a few times of day.
var world
var out := ""
func _shot(n: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + n + ".png")
	print("shot ", n, " fps ", Engine.get_frames_per_second())
func _w(s: float) -> void:
	await get_tree().create_timer(s).timeout
func _place(i: int, lat: float, look_back := false) -> void:
	var pl = world.player
	var xf: Transform3D = world._route_xf(i, lat)
	pl.global_position = xf.origin + Vector3(0, 0.3, 0)
	pl.velocity = Vector3.ZERO
	var f: Vector3 = -xf.basis.z
	if look_back:
		f = -f
	pl.yaw = atan2(-f.x, -f.z)
	pl.pitch = -0.05
func run() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	world.hud.show_help = false
	var hours: Array = [22.0]
	if world.get("sky") != null:
		hours = [7.0, 13.0, 17.85, 22.0]
		var ua := OS.get_cmdline_user_args()
		if ua.has("--hours"):
			hours = []
			for hs in ua[ua.find("--hours") + 1].split(","):
				hours.append(float(hs))
		if OS.get_cmdline_user_args().has("--rain"):
			world.sky.set_weather(2)
		else:
			world.sky.set_weather(1)
	for h in hours:
		if world.get("sky") != null:
			world.sky.set_hour(h)
		var tag := "h%02d" % int(h)
		await _w(2.5)
		await _shot(tag + "_spawn")
		for i in [220, 520, 900]:
			if i >= world.route.size() - 2:
				continue
			_place(i, 7.0)
			await _w(1.5)
			await _shot(tag + "_street%d" % i)
	get_tree().quit()
