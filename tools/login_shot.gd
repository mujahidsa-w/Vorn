extends Node
func _ready() -> void:
	var iv: Control = load("res://scripts/ui/intro_video.gd").new()
	iv.set_anchors_preset(Control.PRESET_FULL_RECT)
	var cl := CanvasLayer.new()
	add_child(cl)
	cl.add_child(iv)
	await get_tree().create_timer(4.0).timeout
	print("playing=", iv.player.is_playing(), " pos=", iv.player.stream_position)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	get_tree().quit()
