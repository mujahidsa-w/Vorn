extends Node
var world
var out := ""
func _shot(n: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + n + ".png")
	print("shot ", n)
func _w(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout
func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new(); e.physical_keycode = k; e.keycode = k; e.pressed = down
	Input.parse_input_event(e)
func _tap(k: Key) -> void:
	_key(k, true); await _w(0.05); _key(k, false)
func _mouse(down: bool, b := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new(); e.button_index = b; e.pressed = down
	Input.parse_input_event(e)
func run() -> void:
	var pl = world.player
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	world.hud.show_help = false
	await _w(3.0)
	# side view while walking / running
	_key(KEY_W, true)
	await _w(1.5)
	pl.yaw = pl.rotation.y + PI * 0.5
	await _w(0.4)
	await _shot("q01_walk_side")
	_key(KEY_SHIFT, true)
	await _w(2.5)
	print("run speed ", Vector2(pl.velocity.x, pl.velocity.z).length())
	pl.yaw = pl.rotation.y + PI * 0.5
	await _w(0.3)
	await _shot("q02_run_side")
	_key(KEY_SHIFT, false)
	_key(KEY_W, false)
	await _w(1.0)
	# punches (front view)
	pl.yaw = pl.rotation.y + PI * 0.75
	_mouse(true); await _w(0.08); _mouse(false)
	await _w(0.3)
	_mouse(true); await _w(0.08); _mouse(false)
	await _w(0.15)
	await _shot("q03_punch")
	await _w(1.5)
	# rifle
	pl.give_weapon("m4" if world.team == "cops" else "akm")
	await _w(1.0)
	pl.yaw = pl.rotation.y + PI * 0.6
	await _w(0.6)
	await _shot("q04_rifle_idle")
	await _tap(KEY_C)
	await _w(1.0)
	pl.yaw = pl.rotation.y + PI * 0.35
	await _w(0.3)
	_mouse(true)
	await _w(0.2)
	await _shot("q05_crouch_fire")
	_mouse(false)
	await _w(0.3)
	pl.yaw = pl.rotation.y
	await _w(0.3)
	_mouse(true)
	await _w(0.25)
	await _shot("q06_crouch_fire_back")
	_mouse(false)
	await _tap(KEY_C)
	await _w(0.8)
	pl.yaw = pl.rotation.y + PI * 0.55
	await _w(0.3)
	await _tap(KEY_R)
	await _w(0.65)
	await _shot("q07_reload")
	await _w(1.5)
	# strafe with rifle
	_key(KEY_A, true)
	await _w(1.2)
	await _shot("q08_strafe")
	_key(KEY_A, false)
	# car
	pl.equip("")
	var car = world.nearest_car(50.0)
	pl.global_position = car.global_position + car.global_transform.basis.x * 2.5
	await _w(0.4)
	world.toggle_car()
	await _w(1.0)
	await _shot("q09_car_cam")
	car.start_engine()
	await _w(2.6)
	_key(KEY_W, true)
	await _w(4.0)
	await _shot("q10_car_drive")
	_key(KEY_W, false)
	print("car kmh after 4s ", car.kmh())
	get_tree().quit()
