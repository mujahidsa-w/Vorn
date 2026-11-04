extends Control
## Sector administration panel. In production, actions must be confirmed by the server.

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
	UI.header(self, "SECTOR ADMINISTRATION", "MEMBERS  •  RANKS  •  SALARIES  •  AUDIT LOG")
	var profile := UI.paint(self, _draw_profile, Rect2(0, 0, 0, 0), true)
	Game.lay(profile, [1, 0, 1, 0], [-610, 220, -50, 430])
	list_root = Control.new()
	list_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.rect(list_root, 50, 220, 1120, 720)
	add_child(list_root)
	_build_list()
	Game.quiet_focus(list_root)

func _build_list() -> void:
	for child in list_root.get_children():
		child.queue_free()
	var y := 0.0
	for sector in Administration.SECTORS:
		var row := UI.paint(list_root, _draw_sector.bind(sector), Rect2(0, y, 1120, 104), true)
		var b := UI.button(list_root, "APPLY", "play", 18, Rect2(900, y + 25, 180, 48), _apply.bind(str(sector.id)), sector.color)
		b.set("centered", true)
		y += 116.0
	var audit := UI.paint(list_root, _draw_audit, Rect2(0, y + 10, 1120, 130), true)
	
func _draw_sector(c: Control, sector: Dictionary) -> void:
	Game.draw_panel(c, Rect2(Vector2.ZERO, c.size), sector.color)
	Game.dtext(c, str(sector.name), Vector2(26, 35), 25, Color.WHITE, Game.font_wide)
	Game.dtext(c, "BASE PAY  $%d / PAYDAY" % int(sector.salary), Vector2(28, 67), 17, Game.C_GOLD, Game.font_semi)
	Game.dtext(c, "Ranks: " + ", ".join(Administration.ranks_for(str(sector.id))), Vector2(330, 42), 15, Game.C_TEXT, Game.font_tag)
	Game.dtext(c, "Player-managed sector", Vector2(330, 70), 15, Game.C_DIM, Game.font_tag)

func _draw_profile(c: Control) -> void:
	Game.draw_panel(c, Rect2(Vector2.ZERO, c.size), Game.C_CYAN)
	var sector := Administration.sector_by_id(Administration.sector_id)
	Game.dtext(c, "YOUR ADMIN PROFILE", Vector2(22, 34), 18, Game.C_DIM, Game.font_tag)
	Game.dtext(c, str(sector.get("name", "Independent Citizen")), Vector2(22, 72), 25, Color.WHITE, Game.font_wide)
	Game.dtext(c, "RANK  " + Administration.rank, Vector2(22, 108), 18, Game.C_CYAN, Game.font_semi)
	Game.dtext(c, "SALARY  $%d" % Administration.salary, Vector2(22, 140), 18, Game.C_GOLD, Game.font_semi)
	Game.dtext(c, "ADMIN  " + ("ACTIVE" if Administration.is_admin else "MEMBER"), Vector2(22, 174), 15, Game.C_GREEN if Administration.is_admin else Game.C_DIM, Game.font_tag)
	Game.dtext(c, status, Vector2(22, 208), 15, status_col, Game.font_med)

func _draw_audit(c: Control) -> void:
	Game.draw_panel(c, Rect2(Vector2.ZERO, c.size), Game.C_GOLD)
	Game.dtext(c, "AUDIT LOG", Vector2(24, 30), 20, Color.WHITE, Game.font_wide)
	var logs: Array = Administration.audit_log
	var latest := "No administrative actions recorded."
	if not logs.is_empty():
		var entry: Dictionary = logs.back()
		latest = "%s  •  %s  •  %s" % [entry.get("action", ""), entry.get("detail", ""), entry.get("time", "")]
	Game.dtext(c, latest, Vector2(24, 68), 15, Game.C_TEXT, Game.font_med)
	Game.dtext(c, "Every promotion, membership action and sector change is logged.", Vector2(24, 102), 15, Game.C_DIM, Game.font_tag)

func _apply(id: String) -> void:
	if Administration.request_membership(id):
		status = "Application sent to " + str(Administration.sector_by_id(id).name) + "."
		status_col = Game.C_GREEN
		main.toast(status, Game.C_GREEN)
		_build_list()

func on_back() -> void:
	Game.play_sfx("back")
	main.go("menu")
