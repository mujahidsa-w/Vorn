extends Node
## Glue for the competitive mode: feeds the round rules with the real alive counts,
## respawns the dead at the start of each buy phase and draws the round HUD.

const Rules = preload("res://scripts/game3d/comp_rounds.gd")

var world
var rules
var layer: CanvasLayer
var label: Label
var _sub: Label


func _ready() -> void:
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


# the local player is on team "a" (their side) and remote players with the same world team are on "a" too
func _alive(team: String) -> int:
	var n := 0
	var local_side := "a"
	if team == local_side:
		if world.player and not world.player.dead:
			n += 1
		for r in _remotes():
			if r.team == world.team and not r.dead:
				n += 1
	else:
		for r in _remotes():
			if r.team != world.team and not r.dead:
				n += 1
	return n


func _remotes() -> Array:
	var out := []
	if world.get("net") and world.net:
		for r in world.net.remotes.values():
			if is_instance_valid(r):
				out.append(r)
	return out


func _on_phase(p: String) -> void:
	if p == "buy" and world.player and world.player.dead:
		world.respawn_player()
	if p == "live":
		world.hud.notify("ROUND %d  -  GO" % rules.round_no)


func _on_round_ended(winner: String) -> void:
	var txt := "ROUND DRAW" if winner == "" else ("YOUR TEAM WINS THE ROUND" if winner == "a" else "ENEMY WINS THE ROUND")
	world.hud.notify(txt)


func _on_over(winner: String) -> void:
	world.hud.notify("MATCH OVER  -  " + ("YOUR TEAM WINS" if winner == "a" else "ENEMY TEAM WINS"))


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
