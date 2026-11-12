extends Control
## Pre-match waiting room: players join, ready up, chat, countdown.
## Only real players (online matchmaking through Firebase). No bots.

const UI = preload("res://scripts/ui/ui.gd")
const Slot = preload("res://scripts/ui/player_slot.gd")
const MapPreview = preload("res://scripts/ui/map_preview.gd")
const Icons = preload("res://scripts/ui/icons.gd")

var main
var data := {}
var bg_dim := 0.72
var show_top := true

const MAX_PER_TEAM := 4
const COUNTDOWN := 5.0

var teams := {"b": [], "a": []}
var slots := {"b": [], "a": []}
var my_team := "a"
var me := {}
var ready_btn: Button
var chat_log: RichTextLabel
var chat_input: LineEdit
var countdown := -1.0
var t := 0.0
var _last_beep := -1
var _leaving := false
# online
var db
var mid := ""
var players := {}            # uid -> data from the server
var _seen := {}              # uid -> [last heartbeat value, local time it changed]
var _poll_t := 0.0
var _hb_t := 0.0
var _chat_key := ""
var _ping := 0
var _state := "searching"    # searching | waiting | starting | playing
var _start_at := 0.0
var _host := ""
var _connected := false
var _merge_t := 3.0
var _merging := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	my_team = Online.match_team if Online.match_team in ["a", "b"] else "a"
	UI.back_button(self, on_back)
	UI.header(self, "VORN ARENA", "COMPETITIVE  •  4 VS 4  •  ARENA")

	# team columns
	var cols := {"a": [50.0, Game.C_BLUE, "TEAM A"], "b": [500.0, Game.C_RED, "TEAM B"]}
	for team in cols:
		var x: float = cols[team][0]
		var col: Color = cols[team][1]
		var nm: String = cols[team][2]
		UI.paint(self, _draw_team_header.bind(team, nm, col), Rect2(x, 240, 430, 48), true)
		for i in 4:
			var s := Slot.new()
			s.accent = col
			UI.rect(s, x, 298 + i * 86, 430, 76)
			add_child(s)
			slots[team].append(s)

	var map := MapPreview.new()
	Game.lay(map, [0, 0, 1, 0], [960, 240, -50, 708])
	add_child(map)
	var info := UI.paint(self, _draw_info, Rect2(0, 0, 0, 0))
	Game.lay(info, [0, 0, 1, 0], [960, 724, -50, 806])
	var status := UI.paint(self, _draw_status, Rect2(0, 0, 0, 0), true)
	Game.lay(status, [0, 0, 1, 0], [960, 822, -50, 918])

	ready_btn = UI.button(self, "READY", "check", 40, Rect2(0, 0, 0, 0), _toggle_ready, Game.C_GREEN)
	Game.lay(ready_btn, [0, 0, 1, 0], [960, 934, -50, 1030])
	ready_btn.set("hint", "F")
	ready_btn.set("primary", true)

	# chat
	UI.paint(self, _draw_chat_bg, Rect2(50, 656, 880, 374))
	chat_log = RichTextLabel.new()
	chat_log.bbcode_enabled = true
	chat_log.scroll_following = true
	chat_log.selection_enabled = false
	chat_log.add_theme_font_override("normal_font", Game.font_med)
	chat_log.add_theme_font_size_override("normal_font_size", 21)
	chat_log.add_theme_color_override("default_color", Game.C_TEXT)
	chat_log.mouse_filter = Control.MOUSE_FILTER_PASS
	UI.rect(chat_log, 70, 708, 840, 256)
	add_child(chat_log)
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Say something to the lobby..."
	chat_input.max_length = 120
	var le_n := Game.panel_style(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.12))
	var le_f := Game.panel_style(Color(0, 0, 0, 0.6), Color(Game.C_CYAN, 0.7))
	le_n.content_margin_top = 6
	le_n.content_margin_bottom = 6
	le_f.content_margin_top = 6
	le_f.content_margin_bottom = 6
	chat_input.add_theme_stylebox_override("normal", le_n)
	chat_input.add_theme_stylebox_override("focus", le_f)
	chat_input.add_theme_font_override("font", Game.font_med)
	chat_input.add_theme_font_size_override("font_size", 21)
	chat_input.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.3))
	UI.rect(chat_input, 66, 972, 848, 44)
	chat_input.text_submitted.connect(_on_chat)
	add_child(chat_input)

	me = {"name": str(Game.player.name), "level": int(Game.player.level), "ping": 0, "ready": false, "you": true}
	_refresh()
	Game.quiet_focus(ready_btn)
	db = Online.db
	if not Online.is_signed_in():
		_sys("[color=#ff5a6e]You are not signed in.[/color] Sign in from the main menu to play online.")
		return
	_sys("Searching for a match with real players...")
	_find_match()


func _draw_chat_bg(c: Control) -> void:
	Game.draw_panel(c, Rect2(Vector2.ZERO, c.size))
	Icons.draw(c, "chat", Vector2(30, 30), 20, Game.C_DIM)
	Game.dtext(c, "LOBBY CHAT", Vector2(50, 37), 18, Game.C_DIM, Game.font_tag)
	Game.dtext(c, "T  TO TYPE", Vector2(c.size.x - 18, 37), 15, Color(1, 1, 1, 0.35), Game.font_tag, HORIZONTAL_ALIGNMENT_RIGHT)


func _team_col(team: String) -> Color:
	return Game.C_BLUE if team == "a" else Game.C_RED


func _draw_team_header(c: Control, team: String, nm: String, col: Color) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(r, Color(col, 0.22))
	c.draw_rect(Rect2(0, r.size.y - 2, r.size.x, 2), col)
	Game.dtext(c, nm, Vector2(16, 34), 28, Color.WHITE, Game.font_wide)
	Game.dtext(c, "%d / 4" % teams[team].size(), Vector2(r.size.x - 16, 33), 22, Color(1, 1, 1, 0.8), Game.font_semi, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_info(c: Control) -> void:
	var items := [["MAP SIZE", "LARGE"], ["TIME", "NIGHT"], ["WEATHER", "RAIN"], ["ROUND", "10 MIN"]]
	var gap := 12.0
	var w := (c.size.x - gap * 3) / 4.0
	for i in 4:
		var r := Rect2(i * (w + gap), 0, w, c.size.y)
		Game.draw_panel(c, r)
		Game.dtext(c, items[i][0], r.position + Vector2(16, 30), 15, Game.C_DIM, Game.font_tag)
		Game.dtext(c, items[i][1], r.position + Vector2(16, 64), 26, Color.WHITE, Game.font_wide)


func _draw_status(c: Control) -> void:
	var total: int = teams.cops.size() + teams.robbers.size()
	var readyc := 0
	for team in teams:
		for p in teams[team]:
			if p.ready:
				readyc += 1
	var cy := c.size.y * 0.5
	if countdown >= 0.0:
		Game.dtext(c, "MATCH STARTING IN", Vector2(0, cy + 8), 26, Game.C_TEXT, Game.font_tag)
		var n := str(int(ceil(countdown)))
		var pulse := 1.0 - fmod(countdown, 1.0)
		Game.dtext(c, n, Vector2(c.size.x, cy + 30), int(84 + 10 * pulse), Game.C_GREEN, Game.font_wide, HORIZONTAL_ALIGNMENT_RIGHT)
	elif _state == "searching":
		Game.dtext(c, ("CONNECTING" if not _connected else "FINDING A MATCH") + ".".repeat(int(t * 2.0) % 4), Vector2(0, cy - 4), 26, Game.C_TEXT, Game.font_tag)
		Game.dtext(c, "REAL PLAYERS ONLY  •  NO BOTS", Vector2(0, cy + 28), 19, Game.C_DIM, Game.font_tag)
	elif total < 2:
		Game.dtext(c, "WAITING FOR PLAYERS" + ".".repeat(int(t * 2.0) % 4), Vector2(0, cy - 4), 26, Game.C_TEXT, Game.font_tag)
		Game.dtext(c, "%d / 8  •  NEED AT LEAST 2 REAL PLAYERS" % total, Vector2(0, cy + 28), 19, Game.C_DIM, Game.font_tag)
	else:
		Game.dtext(c, "WAITING FOR READY", Vector2(0, cy - 4), 26, Game.C_TEXT, Game.font_tag)
		Game.dtext(c, "%d / %d READY  •  STARTS WHEN EVERYONE IS READY" % [readyc, total], Vector2(0, cy + 28), 19, Game.C_DIM, Game.font_tag)
	if countdown < 0.0 and total > 0:
		var bw := c.size.x * 0.3
		var bx := c.size.x - bw
		c.draw_rect(Rect2(bx, cy - 4, bw, 8), Color(1, 1, 1, 0.1))
		c.draw_rect(Rect2(bx, cy - 4, bw * readyc / float(maxi(total, 2)), 8), Game.C_GREEN)


# ---------------------------------------------------------------- online matchmaking
func _find_match() -> void:
	# make sure we have a fresh login token before talking to the database
	if not Online.mock:
		var tok: String = await Online.get_token()
		if _leaving:
			return
		if tok == "":
			_problem("Login expired or blocked (%s). Go to SETTINGS → SIGN OUT, then sign in again." % (Online.last_error if Online.last_error != "" else "no token"))
			await get_tree().create_timer(5.0).timeout
			if not _leaving:
				_find_match()
			return
	var r: Array = await db.call_async("lobby", HTTPClient.METHOD_GET, "open", null, "shallow=true")
	if _leaving:
		return
	if not r[1]:
		var why := "no answer from the server (check your internet)"
		if r[0] is Dictionary and r[0].has("error"):
			why = str(r[0].error)
		if why.to_lower().contains("permission"):
			_problem("The database refused access (Permission denied). In Firebase → Realtime Database → Rules set  \".read\": \"auth != null\", \".write\": \"auth != null\"  and press Publish.")
		else:
			_problem("Can't reach the game server: " + why)
		await get_tree().create_timer(4.0).timeout
		if not _leaving:
			_find_match()
		return
	_connected = true
	var opens: Array = (r[0] as Dictionary).keys() if r[0] is Dictionary else []
	for m in opens:
		var mr: Array = await db.call_async("lobby", HTTPClient.METHOD_GET, "matches/" + str(m))
		if _leaving:
			return
		var md = mr[0]
		if md is Dictionary and str(md.get("state", "")) == "waiting":
			var pl: Dictionary = md.get("players", {}) if md.get("players") is Dictionary else {}
			if pl.size() < MAX_PER_TEAM * 2:
				await _join(str(m), pl)
				return
		elif md == null:
			db.request("lobby", HTTPClient.METHOD_DELETE, "open/" + str(m))
	# nobody waiting: open a new match
	var cr: Array = await db.call_async("lobby", HTTPClient.METHOD_POST, "matches", {"state": "waiting", "created": {".sv": "timestamp"}, "map": "la", "host": Online.uid})
	if _leaving or not cr[1] or not (cr[0] is Dictionary):
		return
	var new_id := str(cr[0].name)
	db.request("lobby", HTTPClient.METHOD_PUT, "open/" + new_id, true)
	await _join(new_id, {})


func _join(m: String, existing: Dictionary) -> void:
	mid = m
	var counts := {"b": 0, "a": 0}
	for k in existing:
		var tm := str(existing[k].get("team", "a"))
		counts[tm] = int(counts.get(tm, 0)) + 1
	if int(counts[my_team]) >= MAX_PER_TEAM:
		my_team = "b" if my_team == "a" else "a"
		_sys("Your team was full — you joined the %s." % my_team)
	await db.call_async("lobby", HTTPClient.METHOD_PUT, "matches/%s/players/%s" % [mid, Online.uid],
		{"name": str(Game.player.name), "team": my_team, "level": int(Game.player.level), "ready": false, "t": {".sv": "timestamp"}, "j": {".sv": "timestamp"}})
	Online.match_id = mid
	Online.match_team = my_team
	Online.set_status("lobby")
	_state = "waiting"
	_sys("Joined lobby [b]DOWNTOWN HEIST[/b] as [color=#%s]%s[/color]." % [_team_col(my_team).to_html(false), my_team.to_upper()])
	_sys("Waiting for real players. Press [b]F[/b] to ready up — the match starts when 2+ players are all ready.")
	if OS.get_cmdline_user_args().has("--nettest"):
		await get_tree().create_timer(2.0).timeout
		_toggle_ready()
	_say_net("joined the lobby")


## Two players who searched at the same moment can each open a lobby. Everyone
## moves to the oldest open lobby (push ids sort by creation time), so they meet.
func _try_merge() -> void:
	_merging = true
	var r: Array = await db.call_async("lobby", HTTPClient.METHOD_GET, "open", null, "shallow=true")
	if _leaving or mid == "" or not (r[0] is Dictionary):
		_merging = false
		return
	var ks: Array = (r[0] as Dictionary).keys()
	ks.sort()
	for k in ks:
		if str(k) >= mid:
			break
		var mr: Array = await db.call_async("lobby", HTTPClient.METHOD_GET, "matches/" + str(k))
		var md = mr[0]
		if md is Dictionary and str(md.get("state", "")) == "waiting":
			var pl: Dictionary = md.get("players", {}) if md.get("players") is Dictionary else {}
			if pl.size() > 0 and pl.size() < MAX_PER_TEAM * 2:
				var old := mid
				var alone := players.size() <= 1
				db.request("lobby", HTTPClient.METHOD_DELETE, "matches/%s/players/%s" % [old, Online.uid])
				if alone:
					db.request("lobby", HTTPClient.METHOD_DELETE, "matches/" + old)
					db.request("lobby", HTTPClient.METHOD_DELETE, "open/" + old)
				players = {}
				_seen = {}
				_chat_key = ""
				me.ready = false
				await _join(str(k), pl)
				break
		elif md == null:
			db.request("lobby", HTTPClient.METHOD_DELETE, "open/" + str(k))
	_merging = false


var _last_problem := ""


func _problem(msg: String) -> void:
	# show each different problem once instead of spamming the chat
	if msg == _last_problem:
		return
	_last_problem = msg
	_sys("[color=#ff5a6e]%s[/color]  Retrying automatically..." % _esc(msg))


func _say_net(m: String) -> void:
	if mid == "":
		return
	db.request("lobby", HTTPClient.METHOD_POST, "matches/%s/chat" % mid, {"n": str(Game.player.name), "tm": my_team, "m": m})


func _poll() -> void:
	if mid == "" or db.pending("poll") > 0:
		return
	var t0 := Time.get_ticks_msec()
	var m := mid
	db.request("poll", HTTPClient.METHOD_GET, "matches/" + mid, null, func(res, ok):
		if ok and m == mid and not _merging:
			_ping = Time.get_ticks_msec() - t0
			_on_match(res))


func _on_match(md) -> void:
	if _leaving:
		return
	if not (md is Dictionary):
		_sys("[color=#ff5a6e]The lobby was closed.[/color] Searching again...")
		mid = ""
		_state = "searching"
		_find_match()
		return
	players = md.get("players", {}) if md.get("players") is Dictionary else {}
	_state = str(md.get("state", "waiting"))
	_start_at = float(md.get("start_at", 0))
	# chat
	var chat: Dictionary = md.get("chat", {}) if md.get("chat") is Dictionary else {}
	var keys := chat.keys()
	keys.sort()
	for k in keys:
		if str(k) > _chat_key:
			_chat_key = str(k)
			var c: Dictionary = chat[k]
			if str(c.get("n", "")) != str(Game.player.name) or str(c.get("m", "")) != "joined the lobby":
				if str(c.get("m", "")) == "joined the lobby" or str(c.get("m", "")) == "left the lobby":
					_sys("[color=#%s]%s[/color] %s." % [_team_col(str(c.get("tm", ""))).to_html(false), _esc(str(c.get("n", ""))), str(c.m)])
				elif str(c.get("n", "")) != str(Game.player.name):
					_say(str(c.get("n", "")), _team_col(str(c.get("tm", ""))), str(c.get("m", "")))
	# heartbeats -> drop players that stopped answering
	var now := Time.get_ticks_msec() / 1000.0
	var order: Array = []
	for u in players:
		var hb := str(players[u].get("t", ""))
		if not _seen.has(u) or _seen[u][0] != hb:
			_seen[u] = [hb, now]
		order.append([float(players[u].get("j", 0)), u])
	order.sort()
	_host = str(order[0][1]) if order.size() > 0 else ""
	if _host == Online.uid:
		for u in players:
			if u != Online.uid and now - float(_seen[u][1]) > 9.0:
				db.request("lobby", HTTPClient.METHOD_DELETE, "matches/%s/players/%s" % [mid, u])
		_host_logic()
	if not players.has(Online.uid) and _state != "playing":
		# we were dropped (e.g. connection hiccup): re-join
		_join(mid, players)


func _host_logic() -> void:
	var n := players.size()
	var all_ready := n >= 2
	for u in players:
		if not bool(players[u].get("ready", false)):
			all_ready = false
	if _state == "waiting" and all_ready:
		db.request("lobby", HTTPClient.METHOD_PATCH, "matches/" + mid, {"state": "starting", "start_at": Online.now_ms() + COUNTDOWN * 1000.0})
	elif _state == "starting" and not all_ready:
		db.request("lobby", HTTPClient.METHOD_PATCH, "matches/" + mid, {"state": "waiting"})
	elif _state == "starting" and Online.now_ms() >= _start_at:
		db.request("lobby", HTTPClient.METHOD_PATCH, "matches/" + mid, {"state": "playing"})
		db.request("lobby", HTTPClient.METHOD_DELETE, "open/" + mid)


func _refresh() -> void:
	teams = {"b": [], "a": []}
	var order: Array = []
	for u in players:
		order.append([float(players[u].get("j", 0)), u])
	order.sort()
	for it in order:
		var u: String = it[1]
		var d: Dictionary = players[u]
		var tm := str(d.get("team", "a"))
		if not teams.has(tm):
			continue
		teams[tm].append({"name": str(d.get("name", "PLAYER")), "level": int(d.get("level", 1)), "ping": _ping if u == Online.uid else 0,
			"ready": bool(d.get("ready", false)), "you": u == Online.uid})
	for team in teams:
		for i in 4:
			var s = slots[team][i]
			s.set_info(teams[team][i] if i < teams[team].size() else {})
	ready_btn.set("caption", "CANCEL READY" if me.ready else "READY")
	ready_btn.set("accent", Game.C_RED if me.ready else Game.C_GREEN)
	ready_btn.set("icon_kind", "back" if me.ready else "check")


func _process(delta: float) -> void:
	if _leaving:
		return
	t += delta
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = 0.7
		_poll()
	_merge_t -= delta
	if _merge_t <= 0.0 and mid != "" and _state == "waiting" and not _merging:
		_merge_t = 3.0
		_try_merge()
	_hb_t -= delta
	if _hb_t <= 0.0 and mid != "":
		_hb_t = 2.5
		db.request("lobby", HTTPClient.METHOD_PATCH, "matches/%s/players/%s" % [mid, Online.uid], {"t": {".sv": "timestamp"}}, Callable(), "", "hb")
	if _state == "starting" or _state == "playing":
		var left := maxf(0.0, (_start_at - Online.now_ms()) / 1000.0)
		if countdown < 0.0:
			_sys("[color=#4df280]Everyone is ready — match starting![/color]")
			Game.play_sfx("go")
		countdown = left
		var sec := int(ceil(countdown))
		if sec != _last_beep and sec > 0:
			_last_beep = sec
			Game.play_sfx("beep", 1.0 if sec > 3 else 1.35)
		if countdown <= 0.0 or _state == "playing":
			_start()
	elif countdown >= 0.0:
		countdown = -1.0
		_sys("Countdown cancelled.")
	_refresh()


func _toggle_ready() -> void:
	if mid == "":
		return
	me.ready = not me.ready
	Game.play_sfx("ready" if me.ready else "back")
	db.request("lobby", HTTPClient.METHOD_PATCH, "matches/%s/players/%s" % [mid, Online.uid], {"ready": me.ready})
	_refresh()


func _start() -> void:
	if _leaving:
		return
	_leaving = true
	if _host == Online.uid:
		db.request("lobby", HTTPClient.METHOD_PATCH, "matches/" + mid, {"state": "playing"})
		db.request("lobby", HTTPClient.METHOD_DELETE, "open/" + mid)
	Game.play_sfx("whoosh")
	Game.player.team = my_team
	Online.match_id = mid
	Online.match_team = my_team
	Online.set_status("in_match")
	main.go("loading", {"team": my_team, "match": mid})


func _leave_match() -> void:
	if mid == "":
		return
	_say_net("left the lobby")
	db.request("lobby", HTTPClient.METHOD_DELETE, "matches/%s/players/%s" % [mid, Online.uid])
	if players.size() <= 1:
		db.request("lobby", HTTPClient.METHOD_DELETE, "matches/" + mid)
		db.request("lobby", HTTPClient.METHOD_DELETE, "open/" + mid)
	Online.match_id = ""
	mid = ""


func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


func _say(nm: String, col: Color, msg: String) -> void:
	chat_log.append_text("[color=#%s][b]%s:[/b][/color] %s\n" % [col.to_html(false), _esc(nm), _esc(msg)])


func _sys(msg: String) -> void:
	chat_log.append_text("[color=#6b7c92]» %s[/color]\n" % msg)


func _on_chat(txt: String) -> void:
	var s := txt.strip_edges()
	chat_input.clear()
	chat_input.release_focus()
	Game.quiet_focus(ready_btn)
	if s == "":
		return
	_say(str(Game.player.name), Game.C_CYAN, s)
	_say_net(s)
	Game.play_sfx("hover", 1.2, -4.0)


func _unhandled_input(event: InputEvent) -> void:
	if _leaving or chat_input.has_focus():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			_toggle_ready()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_T:
			chat_input.grab_focus()
			get_viewport().set_input_as_handled()


func on_back() -> void:
	if chat_input.has_focus():
		chat_input.release_focus()
		Game.quiet_focus(ready_btn)
		return
	Game.play_sfx("back")
	_leaving = true
	_leave_match()
	main.go("team")
