extends Node
## Glue for the competitive mode: feeds the round rules with the real alive counts,
## respawns the dead at the start of each buy phase and draws the round HUD.

const Rules = preload("res://scripts/game3d/comp_rounds.gd")
const Arena = preload("res://scripts/game3d/arena.gd")

var world
var rules
var layer: CanvasLayer
var label: Label
var _sub: Label
var side := "a"          # our side: a or b, from the lobby's team choice
const Rig = preload("res://scripts/game3d/rig.gd")
const Npc = preload("res://scripts/game3d/npc.gd")
const BOT_COUNT := 3
var bots: Array = []           # practice match (no online match): armed bots on the enemy side
var arena


func _ready() -> void:
	side = "b" if Online.match_team == "b" else "a"
	world.comp_side = side
	if world.player and world.player.rig:
		world.player.rig.set_team_color(Rig.team_color(side))
	arena = Arena.new()
	world.add_child(arena)
	_setup_match_world()
	_to_spawn()
	rules = Rules.new()
	rules.alive_of = Callable(self, "_alive")
	rules.phase_changed.connect(_on_phase)
	rules.match_over.connect(_on_over)
	rules.round_ended.connect(_on_round_ended)
	_build_hud()
	rules.start()


func _process(delta: float) -> void:
	if rules.is_over():
		return
	rules.tick(delta)
	_refresh()


# alive players on a side: the local player counts for our side, remotes count by the side they send
func _alive(team: String) -> int:
	var n := 0
	if team == side:
		if world.player and not world.player.dead:
			n += 1
	for r in _remotes():
		if r.side == team and not r.dead:
			n += 1
	if team == _enemy_side():
		for b in bots:
			if is_instance_valid(b) and b.state != Npc.DEAD:
				n += 1
	return n


func _enemy_side() -> String:
	return "b" if side == "a" else "a"


func _practice() -> bool:
	return Online.match_id == ""


## practice bots: fresh each round on the enemy spawn, held still in the buy phase
func _spawn_bots() -> void:
	for b in bots:
		if is_instance_valid(b):
			b.queue_free()
	bots.clear()
	var es := _enemy_side()
	var base: Vector3 = arena.spawn_world(es)
	for i in BOT_COUNT:
		var bot = Npc.new()
		bot.world = world
		bot.role = "guard"
		world.add_child(bot)
		bot.global_position = base + Vector3(0, 0.2, (i - 1) * 4.0)
		bot.rotation.y = arena.spawn_yaw(es)
		bot.face_yaw = bot.rotation.y
		bot.hp = 100.0
		bot.timer = 999.0
		bot.rig.set_team_color(Rig.team_color(es))
		bots.append(bot)


func _wake_bots() -> void:
	for b in bots:
		if is_instance_valid(b) and b.state != Npc.DEAD:
			b.enemy = world.player
			b.state = Npc.COMBAT
			b.fire_cd = randf_range(1.0, 2.5)


func _remotes() -> Array:
	var out := []
	if world.get("net") and world.net:
		for r in world.net.remotes.values():
			if is_instance_valid(r):
				out.append(r)
	return out


## competitive look and feel: clear morning, no rain, CS-style HUD, first person
func _setup_match_world() -> void:
	if world.sky:
		world.sky.set_hour(9.0)
		world.sky.set_weather(1)
	if world.rain:
		world.rain.emitting = false
		world.rain.visible = false
	if world.hud:
		world.hud.comp = true
	if world.player:
		world.player.first_person = true


## round loadout: pistol for everyone, rifle by side (a: M4, b: AKM), full health and armor
func _loadout() -> void:
	var pl = world.player
	if pl == null:
		return
	pl.hp = 100.0
	pl.armor = 50.0
	pl.give_weapon("glock")
	var rifle := "m4" if side == "a" else "akm"
	pl.give_weapon(rifle)
	pl.equip(rifle)


func _to_spawn() -> void:
	var pl = world.player
	if pl == null:
		return
	pl.global_position = arena.spawn_world(side) + Vector3(0, 1.0, 0)
	pl.yaw = arena.spawn_yaw(side)
	pl.velocity = Vector3.ZERO


func _on_phase(p: String) -> void:
	if p == "buy":
		if world.player and world.player.dead:
			world.respawn_player()
		_to_spawn()
		_loadout()
		if _practice():
			_spawn_bots()
		if world.player:
			world.player.frozen = true
		world.hud.notify("BUY PHASE  -  ROUND %d" % rules.round_no)
	if p == "live":
		if world.player:
			world.player.frozen = false
		if _practice():
			_wake_bots()
		world.hud.notify("ROUND %d  -  GO" % rules.round_no)


func _on_round_ended(winner: String) -> void:
	var txt := "ROUND DRAW" if winner == "" else ("YOUR TEAM WINS THE ROUND" if winner == side else "ENEMY WINS THE ROUND")
	world.hud.notify(txt)


func _on_over(winner: String) -> void:
	world.hud.notify("MATCH OVER  -  " + ("YOUR TEAM WINS" if winner == side else "ENEMY TEAM WINS"))


func _build_hud() -> void:
	layer = CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	label.position.y = 16
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	layer.add_child(label)
	_sub = Label.new()
	_sub.add_theme_font_size_override("font_size", 22)
	_sub.add_theme_color_override("font_outline_color", Color.BLACK)
	_sub.add_theme_constant_override("outline_size", 6)
	_sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_sub.position.y = 64
	_sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	layer.add_child(_sub)


func _refresh() -> void:
	var secs := int(ceil(maxf(rules.phase_left, 0.0)))
	var phase_name: String = {"buy": "BUY TIME", "live": "LIVE", "end": "ROUND OVER", "over": "MATCH OVER"}.get(rules.phase, "")
	label.text = "%d : %d" % [int(rules.score["a"]), int(rules.score["b"])]
	_sub.text = "ROUND %d   |   %s   %02d:%02d   |   ALIVE %d vs %d" % [
		rules.round_no, phase_name, secs / 60, secs % 60, _alive("a"), _alive("b")]
