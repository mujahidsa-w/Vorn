extends Control
## Vorn City lobby: the design image as a full-screen background (cover, sides cropped), with real
## buttons for navigation, PLAY and the top-right icons, since the cropped image hides them.

const IMG := preload("res://assets/img/lobby_design.jpg")
const GOLD := Color(1.0, 0.76, 0.12)
const CYAN := Color(0.25, 0.85, 1.0)

var main
var data := {}
var bg_dim := 0.0
var show_top := false
var buttons: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# the app-wide background and rain are not shown behind the lobby image
	main.bg.visible = false
	main.rain.visible = false

	var pic := TextureRect.new()
	pic.texture = IMG
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(pic, 0, 0, 1920, 1080)
	add_child(pic)

	var nav := [["اللعب", "city", true], ["المتجر", "shop", false], ["الملابس", "customize", false],
		["المهام", "jobs", false], ["الجوائز", "rewards", false], ["الإعدادات", "settings", false]]
	var y := 580.0
	for n in nav:
		_button(str(n[0]), 24, y, 280, 66, str(n[1]), bool(n[2]), 26)
		y += 78.0
	_button("بــدء اللعب  »", 1480, 880, 380, 120, "city", true, 40)
	_button("⚙", 1760, 20, 64, 64, "settings", false, 30)
	_button("⏻", 1836, 20, 64, 64, "exit", false, 30)


func _place(c: Control, x: float, y: float, w: float, h: float) -> void:
	Game.lay(c, [0, 0, 0, 0], [x, y, x + w, y + h])


func _button(text: String, x: float, y: float, w: float, h: float, target: String, primary: bool, fs: int) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", Game.font_wide if primary else Game.font_bold)
	b.add_theme_font_size_override("font_size", fs)
	var dark := Color(0.06, 0.05, 0.02)
	b.add_theme_color_override("font_color", dark if primary else Color(0.94, 0.96, 1.0))
	b.add_theme_color_override("font_hover_color", dark if primary else GOLD)
	b.add_theme_color_override("font_focus_color", dark if primary else GOLD)
	b.add_theme_color_override("font_pressed_color", dark if primary else GOLD)
	b.add_theme_stylebox_override("normal", _style(GOLD if primary else Color(0.02, 0.03, 0.07, 0.8), GOLD if primary else Color(CYAN, 0.4)))
	b.add_theme_stylebox_override("hover", _style(Color(1.0, 0.84, 0.3) if primary else Color(0.06, 0.08, 0.13, 0.92), GOLD))
	b.add_theme_stylebox_override("pressed", _style(Color(0.9, 0.66, 0.08) if primary else Color(0.02, 0.03, 0.06, 0.95), GOLD))
	b.add_theme_stylebox_override("focus", _style(GOLD if primary else Color(0.06, 0.08, 0.13, 0.92), Color.WHITE, 2))
	_place(b, x, y, w, h)
	b.pressed.connect(_on_item.bind(target))
	add_child(b)
	buttons.append(b)


func _style(bg: Color, border: Color, width := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(8)
	return s


func _on_item(target: String) -> void:
	if target == "exit":
		on_back()
		return
	if target == "rewards":
		main.toast("قريباً", GOLD)
		return
	if target == "city":
		if not Online.is_signed_in() and not Online.offline_mode:
			main.toast("سجّل الدخول للدخول إلى VORN CITY", CYAN)
			main.go("login")
			return
		Online.match_id = ""
		Online.match_team = ""
		main.go("loading", {"roleplay": true, "online": Online.is_signed_in()})
		return
	main.go(target)


func on_back() -> void:
	main.confirm("خروج", "هل تريد مغادرة Vorn City؟", "خروج", func(): Online._quit_cleanly())


func _exit_tree() -> void:
	if main:
		main.bg.visible = true
		main.rain.visible = Game.settings.rain
