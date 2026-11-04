extends Control
## Choose COPS or ROBBERS.

const UI = preload("res://scripts/ui/ui.gd")
const TeamCard = preload("res://scripts/ui/team_card.gd")

var main
var data := {}
var bg_dim := 0.6
var show_top := true
var cards: Array = []
var _picking := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.back_button(self, on_back)
	var title := Game.label("CHOOSE YOUR SIDE", 64, Game.font_wide, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	Game.lay(title, [0.5, 0, 0.5, 0], [-500, 70, 500, 150])
	add_child(title)
	var sub := Game.label("TWO SIDES  •  ONE CITY  •  PICK WHO YOU PLAY THIS MATCH", 18, Game.font_tag, Game.C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	Game.lay(sub, [0.5, 0, 0.5, 0], [-500, 146, 500, 176])
	add_child(sub)

	var defs := [
		{
			"team": "cops", "title": "COPS", "tex": preload("res://assets/img/cop_art.jpg"),
			"accent": Game.C_BLUE, "role": "PROTECT  •  CHASE  •  ARREST",
			"desc": "Lock down the city and put every robber behind bars.",
			"stats": [["SPEED", 3], ["GEAR", 5], ["TEAMWORK", 4]], "online": 1284,
		},
		{
			"team": "robbers", "title": "ROBBERS", "tex": preload("res://assets/img/robber_art.jpg"),
			"accent": Game.C_RED, "role": "STEAL  •  HIDE  •  ESCAPE",
			"desc": "Hit the bank, grab the loot and lose the cops.",
			"stats": [["SPEED", 5], ["STEALTH", 4], ["GEAR", 2]], "online": 1517,
		},
	]
	for i in 2:
		var c := TeamCard.new()
		c.cfg = defs[i]
		var cx := -330.0 if i == 0 else 330.0
		Game.lay(c, [0.5, 0, 0.5, 0], [cx - 260, 205, cx + 260, 950])
		c.pressed.connect(_pick.bind(i))
		add_child(c)
		cards.append(c)

	var vs := UI.paint(self, _draw_vs, Rect2(0, 0, 0, 0), true)
	Game.lay(vs, [0.5, 0, 0.5, 0], [-70, 508, 70, 648])

	var hint := Game.label("LEFT / RIGHT  SELECT        ENTER  CONFIRM        ESC  BACK", 17, Game.font_tag, Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_CENTER)
	Game.lay(hint, [0.5, 0, 0.5, 0], [-500, 990, 500, 1020])
	add_child(hint)

	Game.quiet_focus(cards[0] if Game.player.team == "cops" else cards[1])


func _process(_d: float) -> void:
	var any := -1
	for i in cards.size():
		if cards[i].is_active():
			any = i
	for i in cards.size():
		cards[i].dimmed = any != -1 and any != i


func _draw_vs(c: Control) -> void:
	var ctr := c.size * 0.5
	var tt := Time.get_ticks_msec() / 1000.0
	var s := 56.0 + 3.0 * sin(tt * 3.0)
	var pts := PackedVector2Array([ctr + Vector2(0, -s), ctr + Vector2(s, 0), ctr + Vector2(0, s), ctr + Vector2(-s, 0)])
	c.draw_colored_polygon(pts, Color(0.03, 0.05, 0.09, 0.96))
	pts.append(pts[0])
	c.draw_polyline(pts, Color(1, 1, 1, 0.85), 2.0)
	Game.dtext(c, "VS", ctr + Vector2(0, 15), 44, Color.WHITE, Game.font_wide, HORIZONTAL_ALIGNMENT_CENTER)


func _pick(i: int) -> void:
	if _picking:
		return
	_picking = true
	Game.player.team = cards[i].cfg.team
	Game.save_data()
	Game.play_sfx("whoosh")
	cards[i].flash()
	await get_tree().create_timer(0.45).timeout
	if data.get("offline", false):
		# solo free roam: no lobby, straight into the city
		Online.match_id = ""
		Online.match_team = ""
		main.go("loading", {"team": Game.player.team})
		return
	main.go("match")


func on_back() -> void:
	Game.play_sfx("back")
	main.go("menu")
