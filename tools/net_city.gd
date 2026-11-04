extends Node
## Network test inside the city: both clients spawn, see each other, one shoots the other.
var world
var shooter := false
func run() -> void:
	shooter = OS.get_cmdline_user_args().has("--shooter")
	var pl = world.player
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	world.hud.show_help = false
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	pl.global_position += Vector3(2.0 if shooter else -2.0, 0, 0)
	var w0 := 0.0
	while world.net.remotes.is_empty() and w0 < 40.0:
		await get_tree().create_timer(0.5).timeout
		w0 += 0.5
	await get_tree().create_timer(2.0).timeout
	print("NET remotes=", world.net.remotes.size(), " ping=", world.net.ping_ms)
	for r in world.net.remotes.values():
		print("NET sees ", r.pname, " at ", r.global_position, " team ", r.team, " my pos ", pl.global_position)
	if shooter and world.net.remotes.size() > 0:
		pl.give_weapon("akm")
		await get_tree().create_timer(1.5).timeout
		var r = world.net.remotes.values()[0]
		var to: Vector3 = r.global_position - pl.global_position
		pl.yaw = atan2(-to.x, -to.z)
		pl.pitch = -0.15
		await get_tree().create_timer(0.6).timeout
		for k in 3:
			var o: Vector3 = pl.global_position + Vector3(0, 1.5, 0)
			var tgt: Vector3 = r.global_position + Vector3(0, 1.1, 0)
			var end: Vector3 = world.fire_bullet(pl, o, (tgt - o).normalized(), pl.muzzle_pos(), 30.0)
			print("NET shot end ", end, " target ", tgt)
			await get_tree().create_timer(0.3).timeout
		if out != "":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out)
	var wait_t := 0.0
	while wait_t < (6.0 if shooter else 40.0) and (shooter or pl.hp >= 100.0):
		await get_tree().create_timer(0.5).timeout
		wait_t += 0.5
	await get_tree().create_timer(2.0).timeout
	print("NET final hp=", pl.hp, " dead=", pl.dead, " remotes=", world.net.remotes.size())
	for r in world.net.remotes.values():
		print("NET remote ", r.pname, " hp ", r.hp, " weapon ", r.weapon_id)
	if not shooter and out != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
