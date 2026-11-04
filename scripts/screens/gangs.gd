extends Control
## Gang HQ: choose a crew, build reputation and expand territory influence.

const UI = preload("res://scripts/ui/ui.gd")

var main
var data := {}
var bg_dim := 0.78
var show_top := true
var list_root: Control
var status := ""
var status_col := Game.C_DIM

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.back_button(self, on_back)
	UI.header(self, "GANG HQ", "IDENTITY  •  REPUTATION  •  TERRITORY CONTROL")
	var profile := UI.paint(self, _draw_profile, Rect2(0, 0, 0, 0), true)
	Game.lay(profile, [1, 0, 1, 0], [-610, 220, -50, 400])
	list_root = Control.new()
	list_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.rect(list_root, 50, 220, 1120, 760)
	add_child(list_root)
	var territories := UI.paint(self, _draw_territories, Rect2(0, 0, 0, 0), true)
	Game.lay(territories, [1, 0, 1, 0], [-610, 430, -50, 960])
	_build_gangs()
	Game.quiet_focus(list_root.get_child(1) if list_root.get_child_count() > 1 else list_root)

func _build_gangs() -> void:
	for child in list_root.get_children():
		child.queue_free()
	var y := 0.0
	for gang in Gangs.GANGS:
		var row := UI.paint(list_root, _draw_gang.bind(gang), Rect2(0, y, 1120, 145), true)
		var active := Gangs.current_gang == str(gang.id)
		var button := UI.button(list_root, "MEMBER" if active else "JOIN", "check" if active else "play", 20, Rect2(910, y + 44, 180, 52), _join.bind(str(gang.id)), gang.color)
		button.set("centered", true)
		y += 158.0
	var leave := UI.button(list_root, "LEAVE GANG", "back", 18, Rect2(910, y + 10, 180, 46), _leave, Game.C_RED)
	leave.set("centered", true)

func _draw_gang(c: Control, gang: Dictionary) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	Game.draw_panel(c, r, gang.color)
	Game.dtext(c, str(gang.name), Vector2(28, 40), 31, Color.WHITE, Game.font_wide)
	Game.dtext(c, str(gang.motto), Vector2(30, 70), 17, gang.color, Game.font_tag)
	Game.dtext(c, "CREW ID  " + str(gang.id).to_upper(), Vector2(30, 104), 16, Game.C_DIM, Game.font_tag)
	Game.dtext(c, "REPUTATION  " + str(Gangs.reputation if Gangs.current_gang == str(gang.id) else 0), Vector2(520, 55), 18, Game.C_GOLD, Game.font_semi)

func _draw_profile(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	Game.draw_panel(c, r, Game.C_CYAN)
	var gang := Gangs.gang_by_id(Gangs.current_gang)
	Game.dtext(c, "YOUR CREW", Vector2(22, 34), 17, Game.C_DIM, Game.font_tag)
	Game.dtext(c, str(gang.get("name", "Independent Citizen")), Vector2(22, 70), 27, Color.WHITE, Game.font_wide)
	Game.dtext(c, "REP  " + str(Gangs.reputation), Vector2(22, 104), 19, Game.C_GOLD, Game.font_semi)
	Game.dtext(c, "Build influence by contributing to territories.", Vector2(22, 140), 15, Game.C_TEXT, Game.font_med)
	Game.dtext(c, status, Vector2(22, 174), 16, status_col, Game.font_med)

func _draw_territories(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	Game.draw_panel(c, r, Game.C_GOLD)
	Game.dtext(c, "TERRITORY CONTROL", Vector2(22, 34), 24, Color.WHITE, Game.font_wide)
	var y := 72.0
	for territory in Gangs.TERRITORIES:
		var id := str(territory.id)
		var owner := Gangs.controller_for(id)
		var gang := Gangs.gang_by_id(owner)
		var col: Color = gang.get("color", Game.C_DIM)
		Game.dtext(c, str(territory.name), Vector2(24, y), 18, Color.WHITE, Game.font_semi)
		Game.dtext(c, str(gang.get("name", "Neutral")), Vector2(260, y), 16, col, Game.font_tag)
		Game.dtext(c, "INFLUENCE  %d" % int(Gangs.influence.get(id, 0)), Vector2(470, y), 16, Game.C_TEXT, Game.font_tag)
		var b := UI.button(c, "CONTRIBUTE", "plus", 16, Rect2(680, y - 23, 170, 40), _contribute.bind(id), col)
		b.set("centered", true)
		y += 58.0

func _join(id: String) -> void:
	if Gangs.join_gang(id):
		status = "You joined " + str(Gangs.gang_by_id(id).name) + "."
		status_col = Game.C_GREEN
		main.toast(status, Game.C_GREEN)
		_build_gangs()

func _leave() -> void:
	Gangs.leave_gang()
	status = "You are now an independent citizen."
	status_col = Game.C_GOLD
	main.toast(status, Game.C_GOLD)
	_build_gangs()

func _contribute(id: String) -> void:
	if Gangs.contribute(id):
		status = "Influence increased in " + str(Gangs.territory_by_id(id).name) + "."
		status_col = Game.C_GREEN
		main.toast(status, Game.C_GREEN)
	else:
		status = "Join a gang first."
		status_col = Game.C_RED
		main.toast(status, Game.C_RED)

func on_back() -> void:
	Game.play_sfx("back")
	main.go("menu")
