extends Node
## Offline flow check: login -> PLAY OFFLINE -> menu -> PLAY OFFLINE -> team -> city.
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
	await _shot("o1_login")
	main.current._offline()
	await _w(1.5)
	await _shot("o2_menu")
	main.current._on_item("city")
	await _w(1.5)
	await _shot("o3_loading")
	await _w(4.0)
	print("screen: match_id='", Online.match_id, "'")
	for k in 120:
		await _w(2.0)
		if get_tree().current_scene and get_tree().current_scene.get("player") != null and get_tree().current_scene.player != null:
			break
	await _w(5.0)
	var w = get_tree().current_scene
	print("scene: ", w.name, " net=", w.get("net"), " life=", w.get("life") != null)
	await _shot("o4_city")
	get_tree().quit()
