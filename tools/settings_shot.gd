extends Node
var main
var out := ""
func _w(s: float) -> void:
	await get_tree().create_timer(s).timeout
func _shot(n: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + n + ".png")
func run() -> void:
	await _w(2.5)
	main.go("settings")
	await _w(1.5)
	main.current._set_tab(3)
	await _w(1.0)
	await _shot("settings_mobile")
	main.current._set_tab(0)
	await _w(1.0)
	await _shot("settings_graphics")
	get_tree().quit()
