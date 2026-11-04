extends Control
## Police HQ: licensing, wanted status and conflict information.

const UI = preload("res://scripts/ui/ui.gd")
var main
var data := {}
var bg_dim := 0.78
var show_top := true
var status := ""
var status_col := Game.C_DIM

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.back_button(self, on_back)
	UI.header(self, "POLICE HQ", "PUBLIC SAFETY  •  WEAPON LICENSING  •  INCIDENT CONTROL")
	var panel := UI.paint(self, _draw_panel, Rect2(0, 0, 0, 0), true)
	Game.lay(panel, [0, 0, 1, 0], [50, 230, -50, 900])
	var buy := UI.button(self, "APPLY FOR WEAPON LICENSE", "badge", 22, Rect2(80, 520, 440, 68), _license, Game.C_CYAN)
	buy.set("centered", true)
	var clear := UI.button(self, "CLEAR WANTED STATUS", "check", 22, Rect2(80, 610, 440, 68), _clear, Game.C_GREEN)
	clear.set("centered", true)
	var test := UI.button(self, "DRIVING TEST  $300", "car", 20, Rect2(80, 700, 440, 62), _driving_test, Game.C_GOLD)
	test.set("centered", true)
	var pay := UI.button(self, "PAY TRAFFIC FINES", "wallet", 20, Rect2(80, 780, 440, 62), _pay_fines, Game.C_CYAN)
	pay.set("centered", true)
	var arrest := UI.button(self, "BOOK INTO JAIL", "lock", 20, Rect2(80, 850, 440, 48), _book_jail, Game.C_RED)
	arrest.set("centered", true)
	Game.quiet_focus(buy)

func _draw_panel(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	Game.draw_panel(c, r, Game.C_CYAN)
	Game.dtext(c, "VORN CITY POLICE", Vector2(30, 48), 32, Color.WHITE, Game.font_wide)
	Game.dtext(c, "SECURITY STATUS", Vector2(32, 82), 17, Game.C_DIM, Game.font_tag)
	Game.dtext(c, Security.wanted_text(), Vector2(32, 132), 32, Game.C_RED if Security.wanted_level > 0 else Game.C_GREEN, Game.font_wide)
	Game.dtext(c, "Weapon license: " + ("ACTIVE" if Security.weapon_license else "NOT ISSUED"), Vector2(32, 174), 20, Game.C_CYAN if Security.weapon_license else Game.C_DIM, Game.font_med)
	Game.dtext(c, "Shots reported: %d" % Security.shots_fired, Vector2(32, 210), 18, Game.C_TEXT, Game.font_med)
	Game.dtext(c, "Active incident: " + (Security.active_incident if Security.active_incident != "" else "None"), Vector2(32, 246), 18, Game.C_GOLD, Game.font_med)
	Game.dtext(c, "Driving license: " + (Driving.license_level if Driving.license_valid else "NOT ISSUED"), Vector2(32, 286), 20, Game.C_GREEN if Driving.license_valid else Game.C_RED, Game.font_med)
	Game.dtext(c, "Penalty points: %d   •   Unpaid fines: $%d" % [Driving.penalty_points, Driving.unpaid_total()], Vector2(32, 322), 18, Game.C_GOLD, Game.font_med)
	Game.dtext(c, "Detention: " + ("ACTIVE" if Justice.detained else "CLEAR"), Vector2(32, 350), 18, Game.C_RED if Justice.detained else Game.C_GREEN, Game.font_med)
	Game.dtext(c, "Weapon use in public areas can trigger a police response.", Vector2(32, 366), 19, Game.C_TEXT, Game.font_med)
	Game.dtext(c, "Speeding and driving without a license create automatic fines.", Vector2(32, 402), 19, Game.C_TEXT, Game.font_med)
	Game.dtext(c, status, Vector2(32, 420), 20, status_col, Game.font_med)

func _license() -> void:
	if Security.buy_weapon_license():
		status = "Weapon license issued. Carry responsibly."
		status_col = Game.C_GREEN
		main.toast(status, Game.C_GREEN)
	else:
		status = "License application failed. Check your bank balance."
		status_col = Game.C_RED
		main.toast(status, Game.C_RED)
	queue_redraw()

func _clear() -> void:
	Security.clear_wanted()
	status = "Wanted status cleared at Police HQ."
	status_col = Game.C_GREEN
	main.toast(status, Game.C_GREEN)
	queue_redraw()

func _driving_test() -> void:
	if Driving.take_driving_test():
		status = "Class B driving license issued."
		status_col = Game.C_GREEN
		main.toast(status, Game.C_GREEN)
	else:
		status = "Driving test failed or bank balance is too low."
		status_col = Game.C_RED
		main.toast(status, Game.C_RED)
	queue_redraw()

func _pay_fines() -> void:
	if Driving.pay_fines():
		status = "All traffic fines paid."
		status_col = Game.C_GREEN
		main.toast(status, Game.C_GREEN)
	else:
		status = "Unable to pay traffic fines."
		status_col = Game.C_RED
		main.toast(status, Game.C_RED)
	queue_redraw()

func _book_jail() -> void:
	if Security.wanted_level <= 0:
		status = "No active wanted status to book."
		status_col = Game.C_DIM
	else:
		var case_charges := ["Public weapons violation"] if Security.wanted_level < 3 else ["Armed incident", "Gang conflict"]
		if Justice.detain_current_player(case_charges, 180.0 + Security.wanted_level * 60.0, 600 + Security.wanted_level * 300, "Vorn City Police"):
			Security.clear_wanted()
			status = "Citizen booked into Vorn City Jail."
			status_col = Game.C_RED
			main.toast(status, Game.C_RED)
	queue_redraw()

func on_back() -> void:
	Game.play_sfx("back")
	main.go("menu")
