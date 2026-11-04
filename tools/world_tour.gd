extends Node
## Open world check: screenshots in the countryside.
var world
var out := ""
func _shot(n: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + n + ".png")
	print("shot ", n, " fps ", Engine.get_frames_per_second(), " pos ", world.player.global_position.round(), " floor ", world.player.is_on_floor())
func _w(s: float) -> void:
	await get_tree().create_timer(s).timeout
func _go(x: float, z: float, look: Vector3, pitch := -0.05) -> void:
	var C = world.country
	var pl = world.player
	var y: float = C.height_at(x, z) + 1.2
	if C.biome_at(x, z) == 0:
		y = world._ray(Vector3(x, 450, z), Vector3(x, -50, z)).position.y + 1.0
	pl.global_position = Vector3(x, y, z)
	C.ensure_collision(pl.global_position)
	pl.velocity = Vector3.ZERO
	var d: Vector3 = look - pl.global_position
	pl.yaw = atan2(-d.x, -d.z)
	pl.pitch = pitch
	await _w(4.0)
func run() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	world.hud.show_help = false
	world.sky.set_hour(float(OS.get_cmdline_user_args()[2]) if OS.get_cmdline_user_args().size() > 2 else 15.0)
	world.sky.set_weather(1)
	await _w(1.0)
	var C = world.country
	print("country ok ", C.ready_ok, " regions ", C.regions.size())
	# city view toward the mountain
	await _go(world.route[480].x, world.route[480].z, Vector3(60, 300, -330), 0.15)
	await _shot("w1_city_to_mountain")
	await _go(-430, -160, Vector3(-470, 90, -40))
	await _shot("w2_village")
	var rd = null
	for r in C.roads:
		if r.name == "SIERRA PASS":
			rd = r
	var p: Vector3 = rd.pts[rd.pts.size() - 60]
	await _go(p.x + 6, p.z, Vector3(-470, 90, -120), -0.15)
	await _shot("w3_mountain_road")
	await _go(60, -300, Vector3(60, 420, -330), 0.25)
	await _shot("w4_tower")
	await _go(420, 0, Vector3(520, 41, 140))
	await _shot("w5_lake")
	await _go(1760, -1440, Vector3(1700, 90, -1400))
	await _shot("w6_ranch")
	for r in C.roads:
		if r.name == "HIGHWAY 7":
			rd = r
	p = rd.pts[120]
	await _go(p.x + 8, p.z, rd.pts[160])
	await _shot("w7_highway")
	var fp := Vector2(-260, -780)
	for k in 400:
		var q := Vector2(-260 + randf_range(-300, 300), -780 + randf_range(-300, 300))
		if C.biome_at(q.x, q.y) == 2:
			fp = q
			break
	await _go(fp.x, fp.y, Vector3(fp.x + 30, C.height_at(fp.x + 30, fp.y) + 3, fp.y + 10))
	await _shot("w8_forest")
	world.sky.set_hour(21.5)
	await _go(-430, -160, Vector3(-470, 90, -40))
	await _shot("w9_village_night")
	get_tree().quit()
