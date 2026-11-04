extends Control
## Vorn City Job Center: browse companies, apply for work and manage shifts.

const UI = preload("res://scripts/ui/ui.gd")

var main
var data := {}
var bg_dim := 0.72
var show_top := true
var list_root: Control
var sector := "Government"
var status := ""
var status_col := Game.C_DIM

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.back_button(self, on_back)
	UI.header(self, "JOB CENTER", "BUILD YOUR CAREER  •  GOVERNMENT & PRIVATE COMPANIES")
	var gov := UI.button(self, "GOVERNMENT", "badge", 22, Rect2(50, 220, 260, 58), _set_sector.bind("Government"), Game.C_CYAN)
	gov.set("centered", true)
	var priv := UI.button(self, "PRIVATE", "shop", 22, Rect2(324, 220, 220, 58), _set_sector.bind("Private"), Game.C_GOLD)
	priv.set("centered", true)
	var admin := UI.button(self, "SECTOR ADMIN", "badge", 20, Rect2(566, 220, 260, 58), _open_admin, Game.C_RED)
	admin.set("centered", true)
	var profile := UI.paint(self, _draw_profile, Rect2(0, 0, 0, 0), true)
	Game.lay(profile, [1, 0, 1, 0], [-640, 220, -50, 420])
	list_root = Control.new()
	list_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.rect(list_root, 50, 310, 1120, 650)
	add_child(list_root)
	var info := UI.paint(self, _draw_info, Rect2(0, 0, 0, 0), true)
	Game.lay(info, [1, 0, 1, 0], [-690, 480, -50, 950])
	_build_list()
	Game.quiet_focus(gov)

func _set_sector(value: String) -> void:
	sector = value
	_build_list()

func _build_list() -> void:
	if list_root == null:
		return
	for child in list_root.get_children():
		child.queue_free()
	var y := 0.0
	for job in Roleplay.jobs_for_sector(sector):
		var row := UI.paint(list_root, _draw_job.bind(job), Rect2(0, y, 1120, 126), true)
		var active := str(Roleplay.current_job().get("id", "")) == str(job.id)
		var cap := "CURRENT JOB" if active else "APPLY"
		var col := Game.C_GREEN if active else Game.C_CYAN
		var b := UI.button(list_root, cap, "check" if active else "play", 20, Rect2(900, y + 38, 190, 52), _apply.bind(str(job.id)), col)
		b.set("centered", true)
		y += 140.0
	var empty := Game.label("No openings in this sector yet.", 24, Game.font_med, Game.C_DIM)
	if y == 0.0:
		UI.rect(empty, 24, 25, 700, 45)
		list_root.add_child(empty)

func _draw_job(c: Control, job: Dictionary) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	Game.draw_panel(c, r, Game.C_CYAN if str(job.sector) == "Government" else Game.C_GOLD)
	var company := str(job.get("company_name", "Independent"))
	Game.dtext(c, str(job.name), Vector2(26, 35), 27, Color.WHITE, Game.font_wide)
	Game.dtext(c, company + "  •  " + str(job.get("rank", "Citizen")), Vector2(28, 63), 17, Game.C_CYAN if str(job.sector) == "Government" else Game.C_GOLD, Game.font_tag)
	Game.dtext(c, str(job.get("description", "")), Vector2(28, 94), 17, Game.C_TEXT, Game.font_med)
	Game.dtext(c, "$%d / PAYDAY" % int(job.get("salary", 0)), Vector2(720, 45), 20, Game.C_GOLD, Game.font_semi)

func _draw_profile(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	Game.draw_panel(c, r, Game.C_CYAN)
	Game.dtext(c, "YOUR CAREER", Vector2(22, 35), 22, Game.C_DIM, Game.font_tag)
	Game.dtext(c, str(Roleplay.current_job().get("name", "Unemployed")), Vector2(22, 70), 27, Color.WHITE, Game.font_wide)
	Game.dtext(c, str(Roleplay.current_job().get("company_name", "Independent")), Vector2(22, 98), 17, Game.C_CYAN, Game.font_tag)
	Game.dtext(c, "RANK  " + str(Roleplay.current_job().get("rank", "Citizen")), Vector2(22, 126), 16, Game.C_TEXT, Game.font_med)
	Game.dtext(c, "SALARY  $%d" % int(Roleplay.current_job().get("salary", 0)), Vector2(22, 154), 18, Game.C_GOLD, Game.font_semi)

func _draw_info(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	Game.draw_panel(c, r, Game.C_GOLD)
	Game.dtext(c, "COMPANY POLICY", Vector2(24, 38), 24, Color.WHITE, Game.font_wide)
	Game.dtext(c, "Apply for a position to join a company.", Vector2(24, 78), 18, Game.C_TEXT, Game.font_med)
	Game.dtext(c, "Start your shift from the city HUD with [J].", Vector2(24, 112), 18, Game.C_TEXT, Game.font_med)
	Game.dtext(c, "Salary is deposited every 5 minutes while on duty.", Vector2(24, 146), 18, Game.C_TEXT, Game.font_med)
	var active: bool = Roleplay.shift_active
	var shift := UI.button(c, "END SHIFT" if active else "START SHIFT", "back" if active else "play", 21, Rect2(24, 188, 280, 58), _toggle_shift, Game.C_RED if active else Game.C_GREEN)
	shift.set("centered", true)
	Game.dtext(c, status, Vector2(24, 286), 18, status_col, Game.font_med)

func _apply(id: String) -> void:
	if Roleplay.apply_for_job(id):
		status = "You joined %s." % Roleplay.current_job().get("company_name", "the company")
		status_col = Game.C_GREEN
		main.toast("HIRED: " + str(Roleplay.current_job().get("name", "Citizen")), Game.C_GREEN)
		_build_list()
		queue_redraw()

func _toggle_shift() -> void:
	if Roleplay.shift_active:
		Roleplay.end_shift()
		status = "Shift ended."
		status_col = Game.C_GOLD
	else:
		Roleplay.start_shift()
		status = "Shift started."
		status_col = Game.C_GREEN
	queue_redraw()

func _open_admin() -> void:
	main.go("admin")

func on_back() -> void:
	Game.play_sfx("back")
	main.go("menu")
