extends Control
## Real friends: your friend code, add by code, incoming requests, online status.

const UI = preload("res://scripts/ui/ui.gd")
const Icons = preload("res://scripts/ui/icons.gd")

var main
var data := {}
var bg_dim := 0.65
var show_top := true

var add_input: LineEdit
var list_root: Control
var msg := ""
var msg_col := Game.C_DIM
var t := 0.0
var busy := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.back_button(self, on_back)
	UI.header(self, "FRIENDS", "ADD REAL PLAYERS WITH THEIR FRIEND CODE")
	list_root = Control.new()
	list_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.rect(list_root, 50, 236, 960, 800)
	add_child(list_root)
	var code_panel := UI.paint(self, _draw_code, Rect2(0, 0, 0, 0), true)
	Game.lay(code_panel, [0, 0, 1, 0], [1050, 236, -50, 520])
	var add_lbl := Game.label("ADD FRIEND (ENTER THEIR CODE)", 18, Game.font_tag, Game.C_DIM)
	Game.lay(add_lbl, [0, 0, 1, 0], [1050, 560, -50, 590])
	add_child(add_lbl)
	add_input = LineEdit.new()
	add_input.placeholder_text = "e.g.  A1B2C3"
	add_input.max_length = 6
	var n := Game.panel_style(Color(0, 0, 0, 0.5), Color(1, 1, 1, 0.14))
	var f := Game.panel_style(Color(0, 0, 0, 0.65), Color(Game.C_CYAN, 0.7))
	add_input.add_theme_stylebox_override("normal", n)
	add_input.add_theme_stylebox_override("focus", f)
	add_input.add_theme_font_size_override("font_size", 30)
	add_input.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.3))
	Game.lay(add_input, [0, 0, 1, 0], [1050, 596, -250, 660])
	add_input.text_submitted.connect(func(_s): _add_friend())
	add_child(add_input)
	var ab := UI.button(self, "SEND", "", 26, Rect2(0, 0, 0, 0), _add_friend)
	ab.set("centered", true)
	Game.lay(ab, [1, 0, 1, 0], [-236, 596, -50, 660])
	var msg_paint := UI.paint(self, _draw_msg, Rect2(0, 0, 0, 0), true)
	Game.lay(msg_paint, [0, 0, 1, 0], [1050, 670, -50, 710])
	var rb := UI.button(self, "REFRESH", "back", 22, Rect2(0, 0, 0, 0), func(): Online.refresh_friends())
	rb.set("centered", true)
	Game.lay(rb, [1, 0, 1, 0], [-300, 730, -50, 790])
	Online.friends_changed.connect(_build_list)
	_build_list()
	if Online.is_signed_in():
		Online.refresh_friends()


func _process(delta: float) -> void:
	t += delta


func _draw_code(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	Game.draw_panel(c, r, Color(Game.C_CYAN, 0.6))
	Game.dtext(c, "YOUR FRIEND CODE", Vector2(24, 44), 22, Game.C_DIM, Game.font_tag)
	var code := Online.friend_code if Online.friend_code != "" else "------"
	Game.dtext(c, code, Vector2(r.size.x * 0.5, 150), 92, Color.WHITE, Game.font_wide, HORIZONTAL_ALIGNMENT_CENTER)
	Game.dtext(c, "Send this code to your friends so they can add you.", Vector2(r.size.x * 0.5, 210), 20, Game.C_TEXT, Game.font_med, HORIZONTAL_ALIGNMENT_CENTER)
	Game.dtext(c, "%d ONLINE  •  %d FRIENDS" % [Online.online_friends(), Online.friends.size()], Vector2(r.size.x * 0.5, 252), 18, Game.C_GREEN, Game.font_tag, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_msg(c: Control) -> void:
	Game.dtext(c, msg, Vector2(4, 28), 20, msg_col, Game.font_med)


func _build_list() -> void:
	if not is_inside_tree():
		return
	for ch in list_root.get_children():
		ch.queue_free()
	var y := 0.0
	if not Online.is_signed_in():
		var l := Game.label("Sign in to add friends.", 24, Game.font_med, Game.C_DIM)
		UI.rect(l, 10, 10, 900, 40)
		list_root.add_child(l)
		return
	for rq in Online.requests:
		var row := UI.paint(list_root, _draw_row.bind({"name": rq.name, "status": "WANTS TO BE YOUR FRIEND", "kind": "pending"}), Rect2(0, y, 960, 80))
		row.name = "rq"
		var b1 := UI.button(list_root, "ACCEPT", "check", 20, Rect2(620, y + 16, 160, 48), _accept.bind(str(rq.uid)), Game.C_GREEN)
		b1.set("centered", true)
		var b2 := UI.button(list_root, "DECLINE", "", 20, Rect2(790, y + 16, 150, 48), _decline.bind(str(rq.uid)), Game.C_RED)
		b2.set("centered", true)
		y += 92.0
	if Online.friends.is_empty() and Online.requests.is_empty():
		var l2 := Game.label("No friends yet — share your code or enter a friend's code.", 22, Game.font_med, Game.C_DIM)
		UI.rect(l2, 10, 10, 940, 40)
		list_root.add_child(l2)
	for fr in Online.friends:
		if y > 720:
			break
		var st := "OFFLINE"
		var kind := "offline"
		if fr.online:
			kind = "match" if fr.status == "in_match" else "online"
			st = "IN A MATCH" if fr.status == "in_match" else "ONLINE  •  IN LOBBY"
		UI.paint(list_root, _draw_row.bind({"name": fr.name, "status": st, "kind": kind}), Rect2(0, y, 960, 80))
		var b := UI.button(list_root, "REMOVE", "", 20, Rect2(790, y + 16, 150, 48), _remove.bind(str(fr.uid), str(fr.name)), Game.C_RED)
		b.set("centered", true)
		y += 92.0


func _status_col(kind: String) -> Color:
	match kind:
		"online":
			return Game.C_GREEN
		"match":
			return Game.C_GOLD
		"pending":
			return Game.C_CYAN
	return Color(1, 1, 1, 0.3)


func _draw_row(c: Control, fr: Dictionary) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	Game.draw_panel(c, r)
	var col := _status_col(str(fr.kind))
	var ac := Vector2(44, r.size.y * 0.5)
	c.draw_circle(ac, 26, Color(0.1, 0.13, 0.2))
	c.draw_arc(ac, 26, 0, TAU, 32, col, 2.5, true)
	Game.dtext(c, str(fr.name).substr(0, 1), ac + Vector2(0, 10), 28, Color.WHITE, Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	Game.dtext(c, str(fr.name), Vector2(88, 36), 27, Color.WHITE, Game.font_bold)
	c.draw_circle(Vector2(94, 56), 4, col)
	Game.dtext(c, str(fr.status), Vector2(106, 62), 17, col if fr.kind != "offline" else Game.C_DIM, Game.font_tag)


func _say(m: String, col: Color) -> void:
	msg = m
	msg_col = col


func _add_friend() -> void:
	if busy:
		return
	var s := add_input.text.strip_edges()
	if s == "":
		return
	if not Online.is_signed_in():
		_say("Sign in first.", Game.C_RED)
		return
	busy = true
	_say("Sending...", Game.C_DIM)
	var err: String = await Online.send_friend_request(s)
	busy = false
	if err == "":
		add_input.clear()
		add_input.release_focus()
		Game.play_sfx("ready")
		_say("Friend request sent!", Game.C_GREEN)
	else:
		Game.play_sfx("back")
		_say(err, Game.C_RED)


func _accept(fid: String) -> void:
	Game.play_sfx("ready")
	await Online.accept_friend(fid)
	main.toast("FRIEND ADDED", Game.C_GREEN)


func _decline(fid: String) -> void:
	Game.play_sfx("back")
	Online.decline_friend(fid)


func _remove(fid: String, nm: String) -> void:
	main.confirm("REMOVE FRIEND?", "Remove %s from your friends?" % nm, "REMOVE", func(): Online.remove_friend(fid))


func on_back() -> void:
	if add_input.has_focus():
		add_input.release_focus()
		return
	Game.play_sfx("back")
	main.go("menu")
