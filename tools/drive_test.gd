extends Node
var world
var out := ""
func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new(); e.physical_keycode = k; e.keycode = k; e.pressed = down
	Input.parse_input_event(e)
func run() -> void:
	await get_tree().create_timer(2.0).timeout
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var car = world.cars[0]
	world.player.global_position = car.global_position + Vector3(2, 0.5, 0)
	await get_tree().create_timer(0.3).timeout
	world.toggle_car()
	car.global_transform = world._route_xf(300, 0.0).translated(Vector3(0, 0.6, 0))
	await get_tree().create_timer(0.5).timeout
	car.start_engine()
	await get_tree().create_timer(2.2).timeout
	print("engine_state=", car.engine_state)
	_key(KEY_W, true)
	for i in 16:
		await get_tree().create_timer(1.0).timeout
		print("t=%d  speed=%d km/h  gear=%d rpm=%.2f thr=%.2f" % [i + 1, car.kmh(), car.gear, car.rpm, car.throttle_v])
	_key(KEY_D, true)
	var y0: float = car.rotation.y
	for i in 4:
		await get_tree().create_timer(0.5).timeout
		print("steer t=%.1f  steer=%.3f yaw_rate=%.3f dyaw=%.2f" % [(i + 1) * 0.5, car.steer, car.yaw_rate, car.rotation.y - y0])
	_key(KEY_D, false)
	_key(KEY_W, false)
	_key(KEY_S, true)
	for i in 4:
		await get_tree().create_timer(1.0).timeout
		print("brake t=%d speed=%d" % [i + 1, car.kmh()])
	get_tree().quit()
