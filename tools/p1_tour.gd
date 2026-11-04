extends Node
var world
var out := ""
func _shot(n: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + n + ".png")
	print("shot ", n, "  fps ", Engine.get_frames_per_second())
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
func _face(pl, target: Vector3) -> void:
	var d: Vector3 = target - pl.global_position; d.y = 0
	pl.yaw = atan2(-d.x, -d.z)
func run() -> void:
	if OS.get_cmdline_user_args().has("--probeonly"):
		get_tree().quit()
		return
	var pl = world.player
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	world.hud.show_help = false
	await _w(3.0)
	# idle front view: turn camera to see the face
	pl.yaw = pl.rotation.y + PI
	pl.pitch = -0.05
	await _w(1.0)
	await _shot("p01_idle_a")
	await _w(1.6)
	await _shot("p02_idle_b")
	await _tap(KEY_C)
	await _w(1.0)
	await _shot("p03_crouch")
	await _tap(KEY_Z)
	await _w(1.0)
	await _shot("p04_prone")
	await _tap(KEY_Z)
	await _w(0.8)
	pl.yaw = pl.rotation.y + PI * 0.6
	_mouse(true); await _w(0.12); _mouse(false)
	await _w(0.05)
	await _shot("p05_punch")
	await _w(0.8)
	pl.give_weapon("m4" if world.team == "cops" else "akm")
	await _w(1.0)
	pl.yaw = pl.rotation.y + PI * 0.55
	await _w(0.5)
	await _shot("p06_rifle_hold")
	pl.yaw = pl.rotation.y
	await _w(0.4)
	_mouse(true, MOUSE_BUTTON_RIGHT)
	await _w(0.5)
	_mouse(true)
	await _w(0.25)
	await _shot("p07_firing_tracers")
	_mouse(false)
	_mouse(false, MOUSE_BUTTON_RIGHT)
	await _tap(KEY_V)
	await _w(0.6)
	await _shot("p08_first_person")
	_mouse(true, MOUSE_BUTTON_RIGHT)
	await _w(0.5)
	_mouse(true)
	await _w(0.2)
	await _shot("p08b_fp_aim_fire")
	_mouse(false)
	_mouse(false, MOUSE_BUTTON_RIGHT)
	if OS.get_cmdline_user_args().has("--fponly"):
		get_tree().quit()
		return
	await _tap(KEY_V)
	# bank
	if world.bank:
		var bk = world.bank
		pl.global_position = bk.global_transform * Vector3(0, 0.5, 34)
		await _w(0.5)
		_face(pl, bk.global_position + Vector3(0, 0, 0))
		pl.pitch = 0.18
		world.hud.notify("")
		await _w(2.0)
		await _shot("p09_bank_front")
		pl.global_position = bk.global_transform * Vector3(0, 1.0, 10)
		await _w(0.5)
		_face(pl, bk.global_transform * Vector3(0, 1, -10))
		pl.pitch = 0.05
		await _w(1.5)
		await _shot("p10_bank_hall")
		pl.global_position = bk.global_transform * Vector3(32, 0.5, 22)
		await _w(0.5)
		_face(pl, bk.global_transform * Vector3(32, 0.5, 0))
		await _w(1.0)
		await _shot("p11_garage")
		# shoot near guards -> combat
		pl.global_position = bk.global_transform * Vector3(0, 0.5, 30)
		_face(pl, bk.global_transform * Vector3(0, 0.5, 15))
		await _w(0.5)
		_mouse(true); await _w(0.4); _mouse(false)
		await _w(1.5)
		await _shot("p12_bank_alert")
	# rocket into a car
	pl.give_weapon("rpg")
	var car = world.cars[1] if world.team == "robbers" else world.cars[3]
	pl.global_position = car.global_position + car.global_transform.basis.x * 22.0 + Vector3(0, 0.5, 0)
	await _w(0.6)
	_face(pl, car.global_position)
	pl.pitch = -0.02
	await _w(0.8)
	var mp: Vector3 = pl.muzzle_pos()
	world.fire_rocket(mp, (car.global_position + Vector3(0, 0.6, 0) - mp).normalized(), pl.get_rid(), pl)
	await _w(0.45)
	await _shot("p13_explosion")
	await _w(1.5)
	await _shot("p14_burning_wreck")
	print("car wrecked: ", car.wrecked, " hp ", car.hp)
	var car2 = world.cars[0]
	pl.global_position = car2.global_position + car2.global_transform.basis.x * 13.0 + Vector3(0, 0.5, 0)
	await _w(0.4)
	_face(pl, car2.global_position)
	await _w(0.4)
	world.explode(car2.global_position + Vector3(0, 0.5, 0), 9.0, pl, null)
	await _w(0.18)
	await _shot("p14b_close_blast")
	await _w(0.5)
	await _shot("p14c_close_blast2")
	pl.revive()
	await _tap(KEY_F11)
	await _w(0.3)
	await _shot("p15_bigmap")
	await _tap(KEY_F11)
	# death
	pl.take_damage(500.0, null, Vector3.FORWARD)
	await _w(1.2)
	await _shot("p16_wasted")
	await _w(3.5)
	await _shot("p17_spectate")
	pl.respawn_left = 0.1
	await _w(0.6)
	await _shot("p18_respawned")
	print("dead after respawn: ", pl.dead, " hp ", pl.hp)
	get_tree().quit()
