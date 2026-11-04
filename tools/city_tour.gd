extends Node
var world
var out := ""
func _shot(n: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + n + ".png")
	print("shot ", n)
func _w(s: float) -> void:
	await get_tree().create_timer(s).timeout
func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new(); e.physical_keycode = k; e.keycode = k; e.pressed = down
	Input.parse_input_event(e)
func run() -> void:
	var pl = world.player
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _w(3.0)
	await _shot("e1_spawn")
	pl.yaw += PI * 0.9
	await _w(0.6)
	await _shot("e2_back")
	pl.yaw -= PI * 0.9
	_key(KEY_W, true)
	await _w(1.6)
	pl.yaw += 1.2
	await _w(0.4)
	await _shot("e3_walking_side")
	_key(KEY_W, false)
	pl.yaw -= 1.2
	await _w(1.0)
	# station view: look toward base side from distance
	var b: Dictionary = world.bases[world.team]
	pl.global_position = b.pos
	await _w(0.3)
	var sgn: Vector3 = (b.sign - b.pos); sgn.y = 0
	pl.yaw = atan2(-sgn.x, -sgn.z)
	pl.pitch = 0.15
	await _w(0.8)
	await _shot("e4_base_side")
	pl.pitch = -0.1
	# drive: wheels
	var car = world.cars[0] if world.team == "cops" else world.cars[2]
	pl.global_position = car.global_position + Vector3(2, 0.5, 0)
	await _w(0.3)
	world.toggle_car()
	car.global_transform = world._route_xf(300, 0.0).translated(Vector3(0, 0.6, 0))
	car.start_engine()
	await _w(2.6)
	_key(KEY_W, true)
	await _w(3.0)
	_key(KEY_A, true)
	car.cam_yaw_off = 1.9
	await _w(0.4)
	await _shot("e5_drive_wheels")
	_key(KEY_A, false)
	_key(KEY_W, false)
	print("speed after 3.4s: ", car.kmh())
	get_tree().quit()
