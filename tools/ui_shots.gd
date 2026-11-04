extends Node
## Screenshots for the character, sniper scope, on-foot and in-car touch controls.
## Run: godot --path . -- --uishots <out_dir>
var world
var out := ""


func _shot(n: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + n + ".png")
	print("shot ", n)


func _w(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _key(k: Key, on: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = on
	Input.parse_input_event(e)


func _rmb(on: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = on
	e.position = get_viewport().get_visible_rect().size * 0.5
	Input.parse_input_event(e)


func run() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	world.hud.show_help = false
	world.hud.help_t = 0.0
	var pl = world.player
	await _w(3.0)
	if world.npcs.size() > 0:
		var n = world.npcs[0]
		pl.global_position = n.global_position + Vector3(0, 0.5, 3.5)
		await _w(0.8)
		n.run_over(Vector3(0, 0, -14))
		await _w(0.25)
		await _shot("08_launch")
		await _w(1.5)
		await _shot("09_landed")
		print("RAGDOLL state=", n.state, " rot=", n.rotation.x, " launch=", n._launch)
		pl.global_position = n.global_position + Vector3(0, 0.5, 3.5)
		await _w(0.6)
	await _shot("01_unarmed")
	pl.give_weapon("akm")
	pl.equip("akm")
	await _w(1.0)
	await _shot("02_rifle_idle")
	_rmb(true)
	await _w(1.5)
	await _shot("03_rifle_aim")
	_rmb(false)
	await _w(0.5)
	pl.give_weapon("sniper")
	pl.equip("sniper")
	await _w(0.5)
	_rmb(true)
	await _w(2.5)
	await _shot("04_scope")
	_rmb(false)
	await _w(0.5)
	pl.equip("")
	_key(KEY_W, true)
	await _w(0.9)
	await _shot("05_walk")
	_key(KEY_W, false)
	var tc = load("res://scripts/game3d/touch_controls.gd").new()
	tc.world = world
	world.add_child(tc)
	await _w(0.4)
	await _shot("06_touch_foot")
	if world.cars.size() > 0:
		var car = world.cars[0]
		pl.global_position = car.global_position + Vector3(2.2, 1.0, 0.0)
		await _w(0.6)
		world.toggle_car()
		await _w(1.5)
		await _shot("07_touch_car")
	get_tree().quit()
