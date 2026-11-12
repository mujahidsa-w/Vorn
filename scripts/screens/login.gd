extends Control
## Sign-in screen: Google (opens the browser) or Guest.

const UI = preload("res://scripts/ui/ui.gd")
const NeonButton = preload("res://scripts/ui/neon_button.gd")

var main
var data := {}
var bg_dim := 0.35
var show_top := false
var t := 0.0
var b_google: Button
var b_guest: Button
var b_cancel: Button
var b_offline: Button
var status: Label
var busy := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := Game.label("VORN CITY", 96, Game.font_wide, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	Game.lay(title, [0.5, 0, 0.5, 0], [-700, 170, 700, 290])
	add_child(title)
	var sub := Game.label("COMPETITIVE  •  ONLINE  •  DAY & NIGHT", 22, Game.font_tag, Game.C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	Game.lay(sub, [0.5, 0, 0.5, 0], [-700, 296, 700, 330])
	add_child(sub)
	var paint := UI.paint(self, _draw_panel, Rect2(0, 0, 0, 0), true)
	Game.lay(paint, [0.5, 0.5, 0.5, 0.5], [-330, -150, 330, 290])
	var head := Game.label("SIGN IN", 34, Game.font_wide, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	Game.lay(head, [0.5, 0.5, 0.5, 0.5], [-300, -125, 300, -80])
	add_child(head)
	b_google = NeonButton.new()
	b_google.setup("SIGN IN WITH GOOGLE", "user", 30)
	b_google.primary = true
	Game.lay(b_google, [0.5, 0.5, 0.5, 0.5], [-270, -50, 270, 30])
	b_google.pressed.connect(_google)
	add_child(b_google)
	b_guest = NeonButton.new()
	b_guest.setup("PLAY AS GUEST", "play", 30)
	Game.lay(b_guest, [0.5, 0.5, 0.5, 0.5], [-270, 50, 270, 130])
	b_guest.pressed.connect(_guest)
	add_child(b_guest)
	b_offline = NeonButton.new()
	b_offline.setup("PLAY SOLO", "play", 26)
	Game.lay(b_offline, [0.5, 0.5, 0.5, 0.5], [-200, 150, 200, 212])
	b_offline.pressed.connect(_offline)
	add_child(b_offline)
	b_cancel = NeonButton.new()
	b_cancel.setup("CANCEL", "back", 26)
	Game.lay(b_cancel, [0.5, 0.5, 0.5, 0.5], [-160, 150, 160, 210])
	b_cancel.pressed.connect(_cancel)
	b_cancel.visible = false
	add_child(b_cancel)
	status = Game.label("Sign in to play VORN.", 19, Game.font_med, Game.C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Game.lay(status, [0.5, 0.5, 0.5, 0.5], [-310, 226, 310, 284])
	add_child(status)
	Online.signed_in.connect(_done)
	Online.auth_failed.connect(_failed)
	Game.quiet_focus(b_google)


func _process(delta: float) -> void:
	t += delta
	if Online.google_waiting():
		status.text = "Finish signing in on the browser page" + ".".repeat(int(t * 2.0) % 4) + "\nPage didn't open? Go to  " + Online.login_url()


func _draw_panel(c: Control) -> void:
	Game.draw_panel(c, Rect2(Vector2.ZERO, c.size), Game.C_CYAN)


func _set_busy(on: bool, waiting_browser := false) -> void:
	busy = on
	b_google.disabled = on
	b_guest.disabled = on
	b_cancel.visible = waiting_browser
	b_offline.visible = not waiting_browser
	b_offline.disabled = on


func _google() -> void:
	if busy:
		return
	_set_busy(true, true)
	Online.sign_in_google()


func _guest() -> void:
	if busy:
		return
	_set_busy(true)
	status.text = "Connecting..."
	Online.sign_in_guest()


func _offline() -> void:
	if busy:
		return
	Online.stop_google()
	Online.offline_mode = true
	Game.play_sfx("ready")
	main.toast("OFFLINE MODE  •  SOLO FREE ROAM", Game.C_CYAN)
	main.go("menu")


func _cancel() -> void:
	Online.stop_google()
	_set_busy(false)
	status.text = "Sign-in cancelled."
	Game.quiet_focus(b_google)


func _done() -> void:
	status.text = "Welcome, " + Online.display_name + "!"
	Game.play_sfx("ready")
	main.toast("SIGNED IN AS  " + Online.display_name, Game.C_GREEN)
	main.go("menu")


func _failed(msg: String) -> void:
	_set_busy(false)
	status.text = msg
	Game.play_sfx("back")


func on_back() -> void:
	if Online.google_waiting():
		_cancel()
	else:
		main.confirm("EXIT GAME?", "Close the game?", "EXIT", func(): Online._quit_cleanly())
