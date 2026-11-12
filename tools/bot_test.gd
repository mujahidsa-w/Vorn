extends Node
## Bots behaviour test: goes live and runs the round at 4x speed, logging how close the bots get
## and whether the player takes damage. Started by the world with --bottest <dir>.
var world
var out := ""


func _w(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func run() -> void:
	await _w(3.0)
	var cm: Node = null
	for c in world.get_children():
		if c.get("rules") != null:
			cm = c
	cm.rules.phase = "live"
	cm.rules.phase_left = 300.0
	cm.rules.phase_changed.emit("live")
	world.player.frozen = true      # stand still at the spawn so we can watch them come
	Engine.time_scale = 4.0
	# put them 35 m away (in the open middle) to check that they engage and shoot
	var pp: Vector3 = world.player.global_position
	for k in cm.bots.size():
		cm.bots[k].global_position = pp + Vector3(35.0, 0.3, (k - 1) * 3.0)
	for i in 4:
		await _w(2.5)
		var ds := []
		for b in cm.bots:
			if is_instance_valid(b):
				ds.append("%s:%.0fm v=%.1f sp=%.1f stuck=%.1f det=%.1f" % [b.bot_name.substr(4), b.global_position.distance_to(world.player.global_position), Vector2(b.velocity.x, b.velocity.z).length(), b.speed, b._stuck_t, b._detour_t])
		print("BOTTEST t=%ds hp=%.0f dead=%s  %s" % [(i + 1) * 10, world.player.hp, world.player.dead, ", ".join(ds)])
		if world.player.dead:
			break
	Engine.time_scale = 1.0
	get_viewport().get_texture().get_image().save_png(out + "/bot_end.png")
	get_tree().quit()
