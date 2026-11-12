extends Node
## Screenshot of the city centre: offline login -> PLAY OFFLINE -> city, then the player is moved near the centre.
var main
var out := ""
func _shot(n: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + n + ".png")
	print("shot ", n)
func _w(s: float) -> void:
	await get_tree().create_timer(s).timeout
func run() -> void:
	await _w(0.5)
	get_parent().remove_child.call_deferred(self)
	get_tree().root.add_child.call_deferred(self)
	await _w(2.0)
	main.current._offline()
	await _w(1.5)
	Game.player.name_set = true
	main.current._on_item("city")
	await _w(6.0)
	for k in 120:
		await _w(2.0)
		var w = get_tree().current_scene
		if w and w.get("player") != null and w.player != null and w.get("poi") != null:
			break
	await _w(4.0)
	var world = get_tree().current_scene
	var c := Vector3.ZERO
	for p in world.poi:
		if str(p.name) == "CITY CENTRE" or str(p.name) == "CITY CENTER":
			c = p.pos
	world.player.global_position = c + Vector3(0, 1.0, -46.0)
	# overview camera above and behind the plaza, looking at its middle
	var cam := Camera3D.new()
	cam.fov = 55
	world.add_child(cam)
	cam.global_position = c + Vector3(0, 55.0, -95.0)
	cam.look_at_from_position(cam.global_position, c + Vector3(0, 6.0, 0), Vector3.UP)
	cam.make_current()
	await _w(3.0)
	await _shot("c1_center")
	# close view from the plaza edge, looking at the fountain
	cam.global_position = c + Vector3(-30.0, 9.0, -30.0)
	cam.look_at_from_position(cam.global_position, c + Vector3(0, 4.0, 0), Vector3.UP)
	await _w(2.0)
	await _shot("c2_fountain")
	# from the east, looking back at the garage
	cam.global_position = c + Vector3(20.0, 50.0, -40.0)
	cam.look_at_from_position(cam.global_position, c + Vector3(88.0, 8.0, 0), Vector3.UP)
	await _w(2.0)
	await _shot("c3_garage")
	get_tree().quit()
