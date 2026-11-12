extends CanvasLayer
## Match statistics and their screens: kill feed (top right), scoreboard (hold TAB), and the
## end-of-match results with the MVP. Fed by comp_mode through kill() and add_player().

const FEED_TIME := 6.0
const C_A := Color(0.35, 0.62, 1.0)
const C_B := Color(1.0, 0.55, 0.25)

var players := {}            # name -> {team, kills, deaths, score, me}
var feed: Array = []         # [{text parts}, age]
var my_side := "a"
var over := false
var winner := ""
var score := {"a": 0, "b": 0}
var paint: Control
var results: Control
var on_leave: Callable


func _ready() -> void:
	layer = 6
	paint = Control.new()
	paint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paint.draw.connect(_draw)
	add_child(paint)


func add_player(pname: String, team: String, me := false) -> void:
	if not players.has(pname):
		players[pname] = {"team": team, "kills": 0, "deaths": 0, "score": 0, "me": me}


func kill(killer: String, victim: String, weapon: String, headshot: bool) -> void:
	if players.has(victim):
		players[victim].deaths += 1
	if killer != "" and players.has(killer) and killer != victim:
		players[killer].kills += 1
		players[killer].score += 2 if headshot else 1
	feed.push_front({"k": killer, "v": victim, "w": weapon, "hs": headshot, "t": 0.0})
	if feed.size() > 5:
		feed.pop_back()


func mvp() -> String:
	var best := ""
	var bs := -1
	for n in players:
		var p: Dictionary = players[n]
		var s := int(p.score) * 10 + int(p.kills) * 3 - int(p.deaths)
		if s > bs:
			bs = s
			best = n
	return best


func show_results(win: String, sc: Dictionary) -> void:
	over = true
	winner = win
	score = sc
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	results = Control.new()
	results.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(results)
	var b := Button.new()
	b.text = "BACK TO LOBBY"
	b.add_theme_font_override("font", Game.font_wide)
	b.add_theme_font_size_override("font_size", 26)
	b.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	b.offset_left = -170
	b.offset_right = 170
	b.offset_top = -120
	b.offset_bottom = -60
	b.pressed.connect(func(): if on_leave.is_valid(): on_leave.call())
	results.add_child(b)


func _process(delta: float) -> void:
	for f in feed:
		f.t += delta
	while feed.size() > 0 and feed[feed.size() - 1].t > FEED_TIME:
		feed.pop_back()
	paint.queue_redraw()


func _team_col(team: String) -> Color:
	return C_A if team == "a" else C_B


func _draw() -> void:
	var sz := paint.size
	# kill feed
	var y := 110.0
	for f in feed:
		var a := clampf((FEED_TIME - float(f.t)) / 0.6, 0.0, 1.0)
		var kc := _team_col(players[f.k].team) if players.has(f.k) else Color.WHITE
		var vc := _team_col(players[f.v].team) if players.has(f.v) else Color.WHITE
		var mid: String = "  [" + str(f.w) + ("  HS" if f.hs else "") + "]  "
		var fs := 18
		var w1 := Game.font_bold.get_string_size(str(f.k), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var w2 := Game.font_bold.get_string_size(mid, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var w3 := Game.font_bold.get_string_size(str(f.v), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := sz.x - 30.0 - (w1 + w2 + w3) - 20.0
		var mine: bool = players.has(f.k) and players[f.k].me
		paint.draw_rect(Rect2(x - 10, y - 22, w1 + w2 + w3 + 30, 32), Color(0, 0, 0, 0.55 * a))
		if mine:
			paint.draw_rect(Rect2(x - 10, y - 22, w1 + w2 + w3 + 30, 32), Color(1, 0.2, 0.2, 0.8 * a), false, 2.0)
		Game.dtext(paint, str(f.k), Vector2(x, y), fs, Color(kc, a), Game.font_bold)
		Game.dtext(paint, mid, Vector2(x + w1, y), fs, Color(1, 1, 1, 0.8 * a), Game.font_bold)
		Game.dtext(paint, str(f.v), Vector2(x + w1 + w2, y), fs, Color(vc, a), Game.font_bold)
		y += 38.0
	if over:
		_draw_results(sz)
	elif Input.is_key_pressed(KEY_TAB):
		_draw_board(sz, sz.y * 0.18)


func _rows(team: String) -> Array:
	var out := []
	for n in players:
		if players[n].team == team:
			out.append(n)
	out.sort_custom(func(x, z): return int(players[x].score) * 100 + int(players[x].kills) > int(players[z].score) * 100 + int(players[z].kills))
	return out


func _draw_board(sz: Vector2, top: float) -> void:
	var w := 820.0
	var x0 := (sz.x - w) * 0.5
	var y := top
	paint.draw_rect(Rect2(x0, y, w, 52), Color(0.02, 0.03, 0.05, 0.92))
	Game.dtext(paint, "SCOREBOARD", Vector2(x0 + 24, y + 35), 24, Color.WHITE, Game.font_wide)
	for i in 4:
		Game.dtext(paint, ["K", "D", "SCORE", ""][i], Vector2(x0 + 520 + i * 90, y + 35), 16, Game.C_DIM, Game.font_tag)
	y += 60.0
	for team in ["a", "b"]:
		var col := _team_col(team)
		paint.draw_rect(Rect2(x0, y, w, 38), Color(col, 0.25))
		Game.dtext(paint, ("TEAM A" if team == "a" else "TEAM B") + ("   (YOU)" if team == my_side else ""), Vector2(x0 + 24, y + 27), 18, col, Game.font_bold)
		Game.dtext(paint, str(int(score.get(team, 0))), Vector2(x0 + w - 40, y + 28), 24, Color.WHITE, Game.font_wide, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 42.0
		for n in _rows(team):
			var p: Dictionary = players[n]
			paint.draw_rect(Rect2(x0, y, w, 36), Color(1, 1, 1, 0.08) if p.me else Color(0.02, 0.03, 0.05, 0.85))
			Game.dtext(paint, n, Vector2(x0 + 24, y + 25), 18, Color.WHITE, Game.font_bold)
			Game.dtext(paint, str(p.kills), Vector2(x0 + 520, y + 25), 18, Color.WHITE, Game.font_bold)
			Game.dtext(paint, str(p.deaths), Vector2(x0 + 610, y + 25), 18, Color.WHITE, Game.font_bold)
			Game.dtext(paint, str(p.score), Vector2(x0 + 700, y + 25), 18, Color.WHITE, Game.font_bold)
			y += 38.0
		y += 12.0


func _draw_results(sz: Vector2) -> void:
	paint.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.72))
	var won := winner == my_side
	var title := "VICTORY" if won else ("DRAW" if winner == "" else "DEFEAT")
	var tc := Color(0.4, 0.95, 0.5) if won else Color(1.0, 0.35, 0.3)
	Game.dtext(paint, title, Vector2(sz.x * 0.5, 120), 72, tc, Game.font_wide, HORIZONTAL_ALIGNMENT_CENTER)
	Game.dtext(paint, "%d  :  %d" % [int(score.get("a", 0)), int(score.get("b", 0))], Vector2(sz.x * 0.5, 175), 36, Color.WHITE, Game.font_wide, HORIZONTAL_ALIGNMENT_CENTER)
	var m := mvp()
	if m != "":
		var mp: Dictionary = players[m]
		var mw := 520.0
		var mr := Rect2((sz.x - mw) * 0.5, 200, mw, 70)
		paint.draw_rect(mr, Color(1.0, 0.78, 0.2, 0.18))
		paint.draw_rect(mr, Color(1.0, 0.78, 0.2, 0.9), false, 2.0)
		Game.dtext(paint, "MVP   " + m + "   %d K / %d D" % [int(mp.kills), int(mp.deaths)], Vector2(sz.x * 0.5, 245), 24, Color(1.0, 0.85, 0.4), Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_board(sz, 300.0)
