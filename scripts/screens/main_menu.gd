extends Control
## VORN City main menu: gold-highlight side menu, big PLAY button, city skyline backdrop.

const UI = preload("res://scripts/ui/ui.gd")

const GOLD := Color(1.0, 0.76, 0.12)
const GOLD_DIM := Color(1.0, 0.76, 0.12, 0.18)

var main
var data := {}
var bg_dim := 0.0
var show_top := true
var buttons: Array = []
var t := 0.0
var _sky: Control
var _ui: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky = UI.paint(self, _draw_sky, Rect2(0, 0, 0, 0), true)
	Game.lay(_sky, [0, 0, 1, 1], [0, 0, 0, 0])
	_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# logo and tagline
	var logo := Game.label("VORN", 150, Game.font_wide, GOLD)
	UI.rect(logo, 120, 96, 700, 170)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	var city := Game.label("CITY", 64, Game.font_wide, Color.WHITE)
	UI.rect(city, 124, 262, 400, 80)
	city.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(city)
	var tag := Game.label("CITY  •  ROLEPLAY  •  SURVIVAL", 22, Game.font_tag, Game.C_DIM)
	UI.rect(tag, 124, 344, 800, 40)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tag)
	var live := Game.label("Live the Real Life...", 46, Game.font_wide, Color(1, 1, 1, 0.92))
	UI.rect(live, 120, 400, 900, 70)
	live.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(live)

	# side menu
	var items := [
		["PLAY ONLINE", "play", "team"],
		["PLAY OFFLINE", "play", "offline"],
		["OUTFITS", "customize", "customize"],
		["SHOP", "shop", "shop"],
		["FRIENDS", "friends", "friends"],
		["SETTINGS", "settings", "settings"],
		["EXIT", "exit", "exit"],
	]
	var y := 500.0
	for i in items.size():
		var it: Array = items[i]
		var b := _menu_button(it[0], i == 0)
		b.position = Vector2(60, y)
		b.size = Vector2(420, 72)
		b.pressed.connect(_on_item.bind(it[2]))
		add_child(b)
		buttons.append(b)
		b.modulate.a = 0.0
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.08 + i * 0.05)
		tw.tween_property(b, "modulate:a", 1.0, 0.3)
		y += 84.0

	# big PLAY button (same as PLAY ONLINE)
	var play := Button.new()
	play.text = "PLAY"
	play.add_theme_font_override("font", Game.font_wide)
	play.add_theme_font_size_override("font_size", 56)
	play.add_theme_color_override("font_color", Color(0.06, 0.05, 0.02))
	play.add_theme_color_override("font_hover_color", Color(0.06, 0.05, 0.02))
	play.add_theme_color_override("font_pressed_color", Color(0.06, 0.05, 0.02))
	play.add_theme_stylebox_override("normal", _style(GOLD, GOLD, 16))
	play.add_theme_stylebox_override("hover", _style(Color(1.0, 0.84, 0.3), GOLD, 16))
	play.add_theme_stylebox_override("pressed", _style(Color(0.9, 0.66, 0.08), GOLD, 16))
	play.add_theme_stylebox_override("focus", _style(GOLD, Color.WHITE, 16))
	play.position = Vector2(1400, 860)
	play.size = Vector2(440, 130)
	play.pressed.connect(_on_item.bind("team"))
	add_child(play)
	buttons.append(play)

	var ver := Game.label("v0.8", 14, Game.font_tag, Color(1, 1, 1, 0.3), HORIZONTAL_ALIGNMENT_RIGHT)
	Game.lay(ver, [1, 1, 1, 1], [-430, -32, -30, -8])
	add_child(ver)

	Game.quiet_focus(buttons[0])


func _style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 28
	s.content_margin_right = 20
	return s


func _menu_button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", Game.font_bold)
	b.add_theme_font_size_override("font_size", 30)
	var on := Color(0.06, 0.05, 0.02)
	var off := Color(0.93, 0.96, 1.0)
	b.add_theme_color_override("font_color", on if primary else off)
	b.add_theme_color_override("font_hover_color", on if primary else GOLD)
	b.add_theme_color_override("font_pressed_color", on if primary else GOLD)
	b.add_theme_stylebox_override("normal", _style(GOLD if primary else Color(0.03, 0.05, 0.09, 0.78), GOLD if primary else Color(1, 1, 1, 0.12), 12))
	b.add_theme_stylebox_override("hover", _style(Color(1.0, 0.84, 0.3) if primary else GOLD_DIM, GOLD, 12))
	b.add_theme_stylebox_override("pressed", _style(Color(0.9, 0.66, 0.08) if primary else GOLD_DIM, GOLD, 12))
	b.add_theme_stylebox_override("focus", _style(GOLD if primary else GOLD_DIM, Color.WHITE, 12))
	return b


func _process(delta: float) -> void:
	t += delta


func _draw_sky(c: Control) -> void:
	var s := c.size
	# sunset gradient
	var top := Color(0.13, 0.07, 0.22)
	var mid := Color(0.55, 0.24, 0.42)
	var low := Color(0.98, 0.52, 0.32)
	for i in 40:
		var f := float(i) / 40.0
		var col := top.lerp(mid, minf(f * 1.6, 1.0)) if f < 0.6 else mid.lerp(low, (f - 0.6) / 0.4)
		c.draw_rect(Rect2(0, s.y * f * 0.7, s.x, s.y * 0.7 / 40.0 + 1.0), col)
	c.draw_rect(Rect2(0, s.y * 0.7, s.x, s.y * 0.3), Color(0.03, 0.03, 0.06))
	# city skyline silhouette (right side), lit windows
	var base := s.y * 0.7
	var rs := 7
	var x := s.x * 0.40
	while x < s.x:
		rs = (rs * 1103515245 + 12345) & 0x7fffffff
		var w := 40.0 + float(rs % 60)
		var h := 120.0 + float((rs >> 3) % 340)
		c.draw_rect(Rect2(x, base - h, w, h), Color(0.07, 0.06, 0.12))
		for wy in range(int(base - h) + 14, int(base) - 10, 26):
			for wx in range(int(x) + 8, int(x + w) - 8, 18):
				if (wx * 31 + wy * 17 + rs) % 5 == 0:
					c.draw_rect(Rect2(wx, wy, 6, 10), Color(1.0, 0.83, 0.45, 0.7))
		x += w + 6.0



func _on_item(target: String) -> void:
	if target == "exit":
		on_back()
		return
	if target == "team" and not Online.is_signed_in():
		main.toast("SIGN IN TO PLAY ONLINE", Game.C_CYAN)
		main.go("login")
		return
	if target == "offline":
		main.go("team", {"offline": true})
		return
	main.go(target)


func on_back() -> void:
	main.confirm("EXIT GAME?", "Leave the city and close the game?", "EXIT", func(): Online._quit_cleanly())
