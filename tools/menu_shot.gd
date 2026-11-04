extends Node
## Screenshot of the main menu. Run: godot --path . -- --menushot <out.png>
var main
var out := ""


func run() -> void:
	await get_tree().create_timer(2.0).timeout
	Online.offline_mode = true
	main.go("menu")
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("menu shot saved")
	get_tree().quit()
