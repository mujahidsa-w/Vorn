extends Control
## Court House: defendant view for detention, bail and hearings.

const UI = preload("res://scripts/ui/ui.gd")
var main
var data := {}
var bg_dim := 0.8
var show_top := true
var status := ""
var status_col := Game.C_DIM

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.back_button(self, on_back)
	UI.header(self, "VORN COURT HOUSE", "DETENTION  •  BAIL  •  HEARINGS  •  CASE RECORDS")
	var panel := UI.paint(self, _draw_panel, Rect2(0, 0, 0, 0), true)
	Game.lay(panel, [0, 0, 1, 0], [50, 210, -50, 900])
	var bail := UI.button(self, "PAY BAIL", "wallet", 21, Rect2(80, 620, 360, 62), _bail, Game.C_GOLD)
	bail.set("centered", true)
	var hearing := UI.button(self, "REQUEST HEARING", "badge", 21, Rect2(80, 700, 360, 62), _hearing, Game.C_CYAN)
	hearing.set("centered", true)
	var release := UI.button(self, "RELEASE / CLOSE CASE", "check", 18, Rect2(80, 780, 360, 54), _release, Game.C_GREEN)
	release.set("centered", true)
	Game.quiet_focus(bail)

func _draw_panel(c: Control) -> void:
	Game.draw_panel(c, Rect2(Vector2.ZERO, c.size), Game.C_CYAN)
	Game.dtext(c, "CASE MANAGEMENT", Vector2(30, 42), 30, Color.WHITE, Game.font_wide)
	Game.dtext(c, "DEFENDANT  " + str(Game.player.get("name", "CITIZEN")), Vector2(32, 82), 18, Game.C_DIM, Game.font_tag)
	Game.dtext(c, "STATUS  " + ("DETAINED" if Justice.detained else "FREE"), Vector2(32, 125), 24, Game.C_RED if Justice.detained else Game.C_GREEN, Game.font_wide)
	Game.dtext(c, "TIME LEFT  " + Justice.time_left_text(), Vector2(32, 164), 21, Game.C_GOLD, Game.font_semi)
	Game.dtext(c, "BAIL  $" + Game.fmt(Justice.bail_amount), Vector2(300, 164), 21, Game.C_GOLD, Game.font_semi)
	Game.dtext(c, "CASE  " + Justice.case_status, Vector2(32, 205), 18, Game.C_CYAN, Game.font_med)
	Game.dtext(c, "CHARGES", Vector2(32, 260), 18, Game.C_DIM, Game.font_tag)
	var y := 296.0
	if Justice.charges.is_empty():
		Game.dtext(c, "No active charges.", Vector2(32, y), 18, Game.C_TEXT, Game.font_med)
	else:
		for charge in Justice.charges:
			Game.dtext(c, "• " + str(charge), Vector2(34, y), 19, Game.C_TEXT, Game.font_med)
			y += 32.0
	Game.dtext(c, status, Vector2(32, 510), 18, status_col, Game.font_med)

func _bail() -> void:
	if Justice.pay_bail():
		status = "Bail paid. You have been released."
		status_col = Game.C_GREEN
		main.toast(status, Game.C_GREEN)
	else:
		status = "Unable to pay bail."
		status_col = Game.C_RED
		main.toast(status, Game.C_RED)
	queue_redraw()

func _hearing() -> void:
	if Justice.request_hearing():
		status = "Hearing request submitted to the court."
		status_col = Game.C_CYAN
		main.toast(status, Game.C_CYAN)
	queue_redraw()

func _release() -> void:
	if not Administration.is_admin:
		status = "Only an authorized court administrator can close a case."
		status_col = Game.C_RED
		main.toast(status, Game.C_RED)
		queue_redraw()
		return
	Justice.release("Court administrator release")
	status = "Case closed and citizen released."
	status_col = Game.C_GREEN
	main.toast(status, Game.C_GREEN)
	queue_redraw()

func on_back() -> void:
	Game.play_sfx("back")
	main.go("menu")
