extends Node
## Arena match test: started by the world with --matchshot <dir> when the game is launched straight
## into a practice match. Captures the first-person view in buy and live phases.
var world
var out := ""


func _w(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(n: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + n + ".png")
	print("shot ", n)


func run() -> void:
	await _w(3.0)
	await _shot("match_buy")
	var cm: Node = null
	for c in world.get_children():
		if c.get("rules") != null:
			cm = c
	if cm:
		cm.rules.phase = "live"
		cm.rules.phase_left = 100.0
		cm.rules.phase_changed.emit("live")
	await _w(6.0)
	await _shot("match_live")
	var alive := 0
	for b in cm.bots:
		if is_instance_valid(b) and b.state != 5:
			alive += 1
	print("BOTS alive=", alive, " player hp=", world.player.hp, " phase=", cm.rules.phase)
	print("MATCH TEST OK fps=", Engine.get_frames_per_second())
	get_tree().quit()
