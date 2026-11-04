extends Control
## Root: background layers, screen manager, transitions, toasts and dialogs.

const BgLayer = preload("res://scripts/fx/bg_layer.gd")
const RainLayer = preload("res://scripts/fx/rain_layer.gd")
const TopBar = preload("res://scripts/ui/top_bar.gd")
const NeonButton = preload("res://scripts/ui/neon_button.gd")

const SCREENS := {
	"menu": preload("res://scripts/screens/main_menu.gd"),
		"match": preload("res://scripts/screens/match_lobby.gd"),
	"loading": preload("res://scripts/screens/loading.gd"),
	"customize": preload("res://scripts/screens/customize.gd"),
		"shop": preload("res://scripts/screens/shop.gd"),
		"jobs": preload("res://scripts/screens/jobs.gd"),
		"market": preload("res://scripts/screens/market.gd"),
		"gangs": preload("res://scripts/screens/gangs.gd"),
		"security": preload("res://scripts/screens/security.gd"),
		"admin": preload("res://scripts/screens/admin.gd"),
		"court": preload("res://scripts/screens/court.gd"),
		"friends": preload("res://scripts/screens/friends.gd"),
	"settings": preload("res://scripts/screens/settings.gd"),
	"login": preload("res://scripts/screens/login.gd"),
}

var bg: Control
var rain: Control
var host: Control
var top_bar: Control
var overlay: Control
var fade: ColorRect
var fps_label: Label
var current: Control
var current_name := ""
var modal: Control
var _busy := false


func _ready() -> void:
	var th := Theme.new()
	th.default_font = Game.font_med
	th.default_font_size = 22
	theme = th

	bg = BgLayer.new()
	_full(bg)
	add_child(bg)
	rain = RainLayer.new()
	_full(rain)
	add_child(rain)
	host = Control.new()
	_full(host)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(host)
	top_bar = TopBar.new()
	add_child(top_bar)
	overlay = Control.new()
	_full(overlay)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	fps_label = Game.label("", 16, Game.font_bold, Game.C_GREEN)
	Game.lay(fps_label, [0, 1, 0, 1], [8, -26, 200, -4])
	add_child(fps_label)
	fade = ColorRect.new()
	fade.color = Color(0.01, 0.015, 0.03, 1.0)
	_full(fade)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)

	Game.settings_changed.connect(_on_settings)
	_on_settings()
	if not Game.intro_shown and OS.get_cmdline_user_args().is_empty():
		Game.intro_shown = true
		var iv: Control = load("res://scripts/ui/intro_video.gd").new()
		_full(iv)
		add_child(iv)
		await iv.finished
		iv.queue_free()
	Game.start_ambience()
	if OS.get_cmdline_user_args().has("--nettest"):
		go("loading", {"roleplay": true})
		return
	var start_screen := Game.next_screen if Game.next_screen != "" else ("menu" if Online.is_signed_in() or Online.offline_mode else "login")
	Game.next_screen = ""
	go(start_screen)
	if Online.is_signed_in():
		_check_session()
	create_tween().tween_property(fade, "color:a", 0.0, 1.4).set_delay(0.15)
	var args := OS.get_cmdline_user_args()
	var tool_scripts := {"--tour": "res://tools/tour.gd", "--flow": "res://tools/flow.gd", "--offline": "res://tools/offline_flow.gd"}
	if args.size() >= 2 and tool_scripts.has(args[0]) and ResourceLoader.exists(tool_scripts[args[0]]):
		var tour: Node = load(tool_scripts[args[0]]).new()
		tour.set("main", self)
		tour.set("out", args[1])
		add_child(tour)
		tour.call("run")


func _check_session() -> void:
	var ok: bool = await Online.resume()
	if not ok and Online.is_signed_in():
		toast("OFFLINE - COULD NOT REACH THE SERVER", Game.C_RED)


func _full(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_d: float) -> void:
	if fps_label.visible:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()


func _on_settings() -> void:
	rain.visible = Game.settings.rain
	fps_label.visible = Game.settings.show_fps


# ---------------------------------------------------------------- navigation
func go(screen_name: String, data := {}) -> void:
	if _busy or not SCREENS.has(screen_name):
		return
	_busy = true
	if current:
		var old := current
		old.mouse_filter = Control.MOUSE_FILTER_STOP
		old.process_mode = Node.PROCESS_MODE_DISABLED
		var tw := create_tween().set_parallel(true)
		tw.tween_property(old, "modulate:a", 0.0, 0.16)
		tw.tween_property(old, "position:x", -40.0, 0.16)
		await tw.finished
		old.queue_free()
	var scr: Control = SCREENS[screen_name].new()
	scr.set("main", self)
	scr.set("data", data)
	_full(scr)
	host.add_child(scr)
	current = scr
	current_name = screen_name
	bg.dim_target = float(scr.get("bg_dim"))
	var show_top: bool = scr.get("show_top")
	create_tween().tween_property(top_bar, "modulate:a", 1.0 if show_top else 0.0, 0.25)
	scr.modulate.a = 0.0
	scr.position.x = 40.0
	var tw2 := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw2.tween_property(scr, "modulate:a", 1.0, 0.3)
	tw2.tween_property(scr, "position:x", 0.0, 0.3)
	_busy = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER and event.alt_pressed:
			Game.set_setting("fullscreen", not Game.settings.fullscreen)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if modal:
			_close_modal()
		elif current and current.has_method("on_back") and not _busy:
			current.on_back()


# ---------------------------------------------------------------- toast
func toast(msg: String, col := Color(0.25, 0.85, 1.0)) -> void:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", Game.panel_style(Color(0.03, 0.05, 0.09, 0.96), Color(col, 0.8)))
	pc.add_child(Game.label(msg, 24, Game.font_semi, Color.WHITE))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(pc)
	await get_tree().process_frame
	var w := pc.get_combined_minimum_size().x
	pc.position = Vector2((size.x - w) * 0.5, size.y - 150.0)
	pc.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(pc, "modulate:a", 1.0, 0.2)
	tw.parallel().tween_property(pc, "position:y", size.y - 170.0, 0.2)
	tw.tween_interval(1.8)
	tw.tween_property(pc, "modulate:a", 0.0, 0.35)
	tw.tween_callback(pc.queue_free)


# ---------------------------------------------------------------- confirm dialog
func confirm(title: String, body: String, yes_text: String, on_yes: Callable) -> void:
	if modal:
		return
	modal = Control.new()
	_full(modal)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	_full(dim)
	modal.add_child(dim)
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", Game.panel_style(Color(0.03, 0.05, 0.09, 0.97), Color(Game.C_CYAN, 0.5)))
	Game.lay(panel, [0.5, 0.5, 0.5, 0.5], [-330, -160, 330, 160])
	modal.add_child(panel)
	var t := Game.label(title, 48, Game.font_wide, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	Game.lay(t, [0, 0, 1, 0], [0, 34, 0, 94])
	panel.add_child(t)
	var b := Game.label(body, 24, Game.font_med, Game.C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	Game.lay(b, [0, 0, 1, 0], [20, 104, -20, 144])
	panel.add_child(b)
	var yes := NeonButton.new()
	yes.setup(yes_text, "", 30, Game.C_RED)
	yes.centered = true
	Game.lay(yes, [0, 0, 0, 0], [40, 196, 310, 266])
	yes.pressed.connect(func():
		_close_modal()
		on_yes.call())
	panel.add_child(yes)
	var no := NeonButton.new()
	no.setup("CANCEL", "", 30)
	no.centered = true
	Game.lay(no, [0, 0, 0, 0], [350, 196, 620, 266])
	no.pressed.connect(_close_modal)
	panel.add_child(no)
	modal.modulate.a = 0.0
	create_tween().tween_property(modal, "modulate:a", 1.0, 0.18)
	Game.quiet_focus(no)


func _close_modal() -> void:
	if modal:
		Game.play_sfx("back")
		modal.queue_free()
		modal = null
		if current:
			for c in current.get_children():
				if c is Button:
					Game.quiet_focus(c)
					break
