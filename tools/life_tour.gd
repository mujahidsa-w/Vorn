extends Node
## Street life check: traffic, signals, pedestrians, props, skids, rain, bank doors.
var world
var out := ""
func _shot(n: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + n + ".png")
	var L = world.life
	print("shot ", n, " fps ", Engine.get_frames_per_second(), " cars ", L.traffic.size(), " peds ", L.peds.size(), " chunks ", L.chunks.size(), " phase ", L.phase)
func _w(s: float) -> void:
	await get_tree().create_timer(s).timeout
func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new(); e.physical_keycode = k; e.keycode = k; e.pressed = down
	Input.parse_input_event(e)
func _look(pl, target: Vector3, pitch := -0.05) -> void:
	var d: Vector3 = target - pl.global_position; d.y = 0
	pl.yaw = atan2(-d.x, -d.z)
	pl.pitch = pitch
func run() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	world.hud.show_help = false
	var pl = world.player
	var L = world.life
	world.sky.set_hour(13.0)
	world.sky.set_weather(1)
	# 1) beside a signal
	var s: Dictionary = L.signals[1] if L.signals.size() > 1 else L.signals[0]
	var sp = L._sidewalk(s.i - 3, 1, 1.0)
	pl.global_position = (sp if sp != null else world.route[s.i - 3]) + Vector3(0, 0.3, 0)
	await _w(0.5)
	_look(pl, world.route[s.i + 4])
	await _w(8.0)
	await _shot("l01_signal_day")
	await _w(7.0)
	await _shot("l02_signal_day_b")
	# 2) traffic view down the road
	var i: int = L.player_i
	var tp: Vector3 = world.route[clampi(i - 8, 2, world.route.size() - 3)]
	pl.global_position = L._lane_point(i - 2, 1) + world.route[i].direction_to(world.route[i + 1]).cross(Vector3.UP) * 6.0 + Vector3(0, 0.3, 0)
	_look(pl, tp)
	await _w(5.0)
	await _shot("l03_traffic")
	# 3) evening, rain
	world.sky.set_hour(19.2)
	world.sky.set_weather(2)
	await _w(4.0)
	await _shot("l04_rain_dusk")
	world.sky.set_hour(23.0)
	await _w(3.0)
	await _shot("l05_rain_night")
	# 4) drive + handbrake for skid marks
	world.sky.set_weather(1)
	world.sky.set_hour(15.0)
	world.sky.wet = 0.0
	var car = world.cars[2]
	pl.global_position = car.global_position + Vector3(2, 0.5, 0)
	await _w(0.3)
	world.toggle_car()
	car.global_transform = world._route_xf(L.player_i + 30, 0.0).translated(Vector3(0, 0.6, 0))
	car.engine_state = car.ON
	car.engine.play()
	car._set_lights(true)
	_key(KEY_W, true)
	await _w(5.0)
	_key(KEY_A, true)
	_key(KEY_SPACE, true)
	await _w(1.1)
	_key(KEY_SPACE, false)
	_key(KEY_A, false)
	_key(KEY_W, false)
	car.cam_yaw_off = 2.2
	await _w(0.25)
	await _shot("l06_skid")
	await _w(2.0)
	# 5) carjack the nearest traffic car
	var tc = null
	for t in L.traffic:
		if is_instance_valid(t.car):
			tc = t.car
			break
	world.toggle_car()
	await _w(0.3)
	if tc:
		pl.global_position = tc.global_position + tc.global_transform.basis.x * 2.5 + Vector3(0, 0.5, 0)
		await _w(0.1)
		world.toggle_car()
		await _w(1.0)
		print("carjacked: ", world.active_car == tc, " traffic now ", L.traffic.size())
		await _shot("l07_carjack")
		world.toggle_car()
	# 6) bank doors
	var b = world.bank
	pl.global_position = b.global_transform * Vector3(0, 0.9, 19.0)
	await _w(0.3)
	_look(pl, b.global_transform * Vector3(0, 1.5, 10.0), -0.1)
	world.sky.set_hour(21.0)
	await _w(1.0)
	await _shot("l08_bank_closed")
	pl.global_position = b.global_transform * Vector3(0, 0.9, 17.0)
	await _w(2.0)
	await _shot("l09_bank_open")
	print("door open ", b.door_open)
	get_tree().quit()
