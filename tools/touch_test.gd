extends Node
var world
var out := ""
func _w(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout
func _touch(idx: int, p: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new(); e.index = idx; e.position = p; e.pressed = down
	Input.parse_input_event(e)
func _drag(idx: int, p: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new(); e.index = idx; e.position = p; e.relative = rel
	Input.parse_input_event(e)
func run() -> void:
	var pl = world.player
	await _w(3.0)
	var sc: float = DisplayServer.window_get_size().x / 1920.0
	var p0: Vector3 = pl.global_position
	# joystick: press at (330,790) canvas, drag up
	_touch(0, Vector2(330, 790) * sc, true)
	await _w(0.1)
	_drag(0, Vector2(330, 640) * sc, Vector2(0, -150) * sc)
	await _w(2.0)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("TOUCH moved ", pl.global_position.distance_to(p0), " running=", pl.running)
	_touch(0, Vector2(330, 640) * sc, false)
	# look drag on right side
	var y0: float = pl.yaw
	_touch(1, Vector2(1200, 400) * sc, true)
	_drag(1, Vector2(1300, 400) * sc, Vector2(100, 0) * sc)
	_touch(1, Vector2(1300, 400) * sc, false)
	await _w(0.2)
	print("TOUCH yaw change ", pl.yaw - y0)
	# take weapon via fire button test: give rifle and press fire
	pl.give_weapon("akm")
	await _w(1.2)
	var a0: int = int(pl.ammo.get("akm", 0))
	_touch(2, Vector2(1660, 790) * sc, true)
	await _w(0.6)
	_touch(2, Vector2(1660, 790) * sc, false)
	await _w(0.2)
	print("TOUCH ammo before ", a0, " after ", pl.ammo.get("akm", 0))
	get_tree().quit()
