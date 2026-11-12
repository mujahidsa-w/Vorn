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
	var pl = world.player
	if pl.fpvm:
		var mains = pl.fpvm.model.find_children("*Main_M4*", "", true, false)
		var hands = pl.fpvm.model.find_children("*Hand_Mesh*", "", true, false)
		print("FPVM cam_node=", pl.fpvm.cam_node, " anim=", pl.fpvm.anim, " clips=", pl.fpvm.anim.get_animation_list() if pl.fpvm.anim else [])
		for m in mains + hands:
			var mi := m as MeshInstance3D
			if mi:
				var c: Vector3 = mi.global_transform * mi.get_aabb().get_center()
				print("FPVM ", mi.name, " center_in_cam=", pl.cam.to_local(c), " size=", mi.get_aabb().size, " scale=", mi.global_transform.basis.get_scale())
		print("FPVM bone=", pl.fpvm.cam_bone, " ", pl.fpvm.skel.get_bone_name(pl.fpvm.cam_bone) if pl.fpvm.cam_bone >= 0 else "", " bones=", pl.fpvm.skel.get_bone_count())
	var W = load("res://scripts/game3d/weapons.gd")
	var mz: Vector3 = pl.weapon_node.global_transform * W.muzzle_local(pl.current, pl.weapon_node)
	print("VM muzzle_in_cam=", pl.cam.to_local(mz), " weapon_in_cam=", pl.cam.to_local(pl.weapon_node.global_position))
	for k in pl.rig.grips:
		print("VM grip ", k, " in_cam=", pl.cam.to_local(pl.weapon_node.global_transform * pl.rig.grips[k]))
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
	# the player kills two bots (one headshot), then a bot kills the player
	cm.bots[0].last_hs = true
	cm.bots[0].take_damage(500.0, world.player, Vector3.FORWARD)
	cm.bots[1].take_damage(500.0, world.player, Vector3.FORWARD)
	await _w(0.5)
	await _shot("match_killfeed")
	print("FEED ", cm.stats.feed.size(), " me=", cm.stats.players[cm.my_name])
	cm.rules.score[cm.side] = 7
	cm.rules.score[cm._enemy_side()] = 3
	cm.bots[2].take_damage(500.0, world.player, Vector3.FORWARD)
	await _w(6.0)
	await _shot("match_results")
	print("OVER phase=", cm.rules.phase, " mvp=", cm.stats.mvp())
	print("MATCH TEST OK fps=", Engine.get_frames_per_second())
	get_tree().quit()
