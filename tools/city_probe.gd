extends Node
var world
var out := ""
func run() -> void:
	await get_tree().create_timer(2.5).timeout
	var b: Dictionary = world.bases["cops"]
	var cam := Camera3D.new(); world.add_child(cam); cam.far = 3000
	cam.global_position = b.pos + Vector3(60, 70, 60)
	cam.look_at(b.pos + (b.sign - b.pos).normalized() * 40.0)
	cam.current = true
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/claude-0/-home-claude/a976d2d3-e9c4-5848-9832-049a49e542d8/scratchpad/shots/hq_aerial.png")
	get_tree().quit()
