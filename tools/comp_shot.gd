extends Node
## Screenshot of the competitive HUD in the city: offline login -> city, then the comp mode runs
## with fake alive counts so buy, live and end phases show up in the HUD.
var main
var out := ""
var _fake := {"a": 3, "b": 3}


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
	main.current._on_item("city")
	await _w(6.0)
	for k in 120:
		await _w(2.0)
		var w = get_tree().current_scene
		if w and w.get("player") != null and w.player != null:
			break
	await _w(3.0)
	var world = get_tree().current_scene
	var cm: Node = load("res://scripts/game3d/comp_mode.gd").new()
	cm.set("world", world)
	world.add_child(cm)
	cm.rules.alive_of = func(t: String) -> int: return _fake[t]
	await _w(1.0)
	await _shot("comp_buy")
	# overview of the arena from above, from the side of team a
	var cam := Camera3D.new()
	cam.fov = 60
	world.add_child(cam)
	var o: Vector3 = cm.arena.global_position
	cam.global_position = o + Vector3(-30, 58, -68)
	cam.look_at_from_position(cam.global_position, o + Vector3(0, 0, 0), Vector3.UP)
	cam.make_current()
	await _w(1.0)
	await _shot("arena_top")
	if world.player:
		world.player.visible = false
	cm.rules.phase = "live"
	cm.rules.phase_left = 100.0
	cm.rules.phase_changed.emit("live")
	await _w(1.0)
	await _shot("comp_live")
	_fake["b"] = 0
	await _w(0.3)
	await _shot("comp_round_end")
	get_tree().quit()
