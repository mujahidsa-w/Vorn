extends Control
## Vorn City lobby: the design image itself, shown at full width. Transparent buttons sit over the
## image's menu items, PLAY, the city and community cards and the top icons, so they still work.

const IMG := preload("res://assets/img/lobby_design.jpg")
const IMG_W := 1670.0
const IMG_H := 588.0
const GOLD := Color(1.0, 0.76, 0.12)

var main
var data := {}
var bg_dim := 0.0
var show_top := false
var buttons: Array = []
var _s := 1.0
var _y0 := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# the app-wide background and rain are not shown behind the lobby image
	main.bg.visible = false
	main.rain.visible = false
	_s = 1920.0 / IMG_W
	_y0 = (1080.0 - IMG_H * _s) * 0.5

	# full-screen backdrop: the same design stretched to the screen and heavily dimmed,
	# so the screen is filled without cropping or distorting the sharp design in front
	var backdrop := TextureRect.new()
	backdrop.texture = IMG
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.modulate = Color(0.28, 0.3, 0.38)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(backdrop, 0, 0, 1920, 1080)
	add_child(backdrop)

	var pic := TextureRect.new()
	pic.texture = IMG
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(pic, 0, _y0, 1920, IMG_H * _s)
	add_child(pic)

	# menu items on the left, in image coordinates
	var nav := [["play", 222, 270, "city"], ["shop", 272, 320, "shop"], ["customize", 322, 370, "customize"],
		["jobs", 372, 420, "jobs"], ["rewards", 422, 468, "rewards"], ["settings", 470, 516, "settings"]]
	for n in nav:
		_hot(26, n[1], 178, n[2], n[3])
	# PLAY, city card and community card
	_hot(1296, 488, 1642, 578, "city")
	_hot(1336, 152, 1640, 290, "city")
	_hot(1336, 306, 1640, 462, "friends")
	# top icons: gifts, calendar, trophy, settings, power
	_hot(1340, 12, 1388, 56, "rewards")
	_hot(1412, 12, 1450, 56, "rewards")
	_hot(1478, 12, 1514, 56, "rewards")
	_hot(1546, 12, 1580, 56, "settings")
	_hot(1604, 12, 1646, 56, "exit")


func _place(c: Control, x: float, y: float, w: float, h: float) -> void:
	Game.lay(c, [0, 0, 0, 0], [x, y, x + w, y + h])


func _hot(x1: float, y1: float, x2: float, y2: float, target: String) -> void:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(GOLD, 0.12)
	hover.border_color = Color(GOLD, 0.9)
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(8)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", hover)
	_place(b, x1 * _s, _y0 + y1 * _s, (x2 - x1) * _s, (y2 - y1) * _s)
	b.pressed.connect(_on_item.bind(target))
	add_child(b)
	buttons.append(b)


func _on_item(target: String) -> void:
	if target == "exit":
		on_back()
		return
	if target == "rewards":
		main.toast("قريباً", GOLD)
		return
	if target == "city":
		if not Online.is_signed_in() and not Online.offline_mode:
			main.toast("سجّل الدخول للدخول إلى VORN CITY", Game.C_CYAN)
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
