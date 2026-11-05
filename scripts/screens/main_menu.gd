extends Control
## Vorn City lobby. Layout is 1920x1080: top account bar, left navigation, hero (logo, character,
## city cards, PLAY) and a bottom strip with GPS, map preview and outfits. Every block has a fixed
## rectangle so nothing overlaps.

const UI = preload("res://scripts/ui/ui.gd")
const Icons = preload("res://scripts/ui/icons.gd")

const GOLD := Color(1.0, 0.76, 0.12)
const CYAN := Color(0.25, 0.85, 1.0)
const PANEL_BG := Color(0.02, 0.03, 0.07, 0.86)
const DIM := Color(0.72, 0.78, 0.86)

var main
var data := {}
var bg_dim := 0.0
var show_top := false
var buttons: Array = []
var t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_background()
	_build_top_bar()
	_build_navigation()
	_build_hero()
	_build_city_cards()
	_build_bottom_strip()
	Game.quiet_focus(buttons[0])


# ---------------------------------------------------------------- helpers
func _r(c: Control, x: float, y: float, w: float, h: float) -> Control:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return UI.rect(c, x, y, w, h)


func _label(text: String, x: float, y: float, w: float, h: float, size: int, font: Font, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Game.label(text, size, font, col, align)
	l.clip_text = true
	_r(l, x, y, w, h)
	add_child(l)
	return l


func _panel(x: float, y: float, w: float, h: float, border: Color, bg := PANEL_BG) -> Panel:
	var p := Panel.new()
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = Color(border, 0.7)
	s.set_border_width_all(2)
	s.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel", s)
	_r(p, x, y, w, h)
	add_child(p)
	return p


func _picture(path: String, x: float, y: float, w: float, h: float, mode := TextureRect.STRETCH_KEEP_ASPECT_COVERED) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = load(path)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = mode
	_r(tr, x, y, w, h)
	add_child(tr)
	return tr


func _icon(kind: String, x: float, y: float, s: float, col: Color) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func(): Icons.draw(c, kind, Vector2(s * 0.5, s * 0.5), s * 0.9, col))
	_r(c, x, y, s, s)
	add_child(c)
	c.queue_redraw()
	return c


func _button(text: String, x: float, y: float, w: float, h: float, primary := false, fs := 24) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", Game.font_wide if primary else Game.font_bold)
	b.add_theme_font_size_override("font_size", fs)
	var dark := Color(0.06, 0.05, 0.02)
	var off := Color(0.92, 0.95, 1.0)
	b.add_theme_color_override("font_color", dark if primary else off)
	b.add_theme_color_override("font_hover_color", dark if primary else GOLD)
	b.add_theme_color_override("font_pressed_color", dark if primary else GOLD)
	b.add_theme_stylebox_override("normal", _style(GOLD if primary else Color(0.03, 0.05, 0.09, 0.82), GOLD if primary else Color(CYAN, 0.35)))
	b.add_theme_stylebox_override("hover", _style(Color(1.0, 0.84, 0.3) if primary else Color(0.06, 0.08, 0.13, 0.9), GOLD))
	b.add_theme_stylebox_override("pressed", _style(Color(0.9, 0.66, 0.08) if primary else Color(0.02, 0.03, 0.06, 0.95), GOLD))
	b.add_theme_stylebox_override("focus", _style(GOLD if primary else Color(0.06, 0.08, 0.13, 0.9), Color.WHITE, 2))
	_r(b, x, y, w, h)
	add_child(b)
	return b


func _style(bg: Color, border: Color, width := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(6)
	s.content_margin_left = 66
	s.content_margin_right = 16
	return s


# ---------------------------------------------------------------- background
func _build_background() -> void:
	_picture("res://assets/img/lobby_bg.jpg", 0, 0, 1920, 1080)
	var shade := UI.paint(self, _draw_shade, Rect2(0, 0, 0, 0), false)
	_r(shade, 0, 0, 1920, 1080)


func _draw_shade(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	# left side and bottom darkened so the navigation and strip read clearly
	for i in 24:
		var f := float(i) / 24.0
		c.draw_rect(Rect2(f * 520.0, 0, 520.0 / 24.0 + 1.0, h), Color(0.01, 0.015, 0.035, 0.82 * (1.0 - f)))
	for i in 24:
		var f2 := float(i) / 24.0
		c.draw_rect(Rect2(0, h * 0.58 + f2 * h * 0.42, w, h * 0.42 / 24.0 + 1.0), Color(0.01, 0.015, 0.035, 0.12 + 0.78 * f2))
	c.draw_rect(Rect2(0, 0, w, 96), Color(0.01, 0.015, 0.035, 0.7))
	c.draw_rect(Rect2(0, 0, w, 2), Color(GOLD, 0.8))


# ---------------------------------------------------------------- top bar (y 0..96)
func _build_top_bar() -> void:
	var avatar := _picture("res://assets/img/avatar.png", 24, 14, 68, 68, TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	avatar.modulate = Color.WHITE
	_panel(22, 12, 72, 72, GOLD, Color(0, 0, 0, 0))
	_label(str(Game.player.get("name", "CITIZEN")), 108, 14, 260, 34, 24, Game.font_wide, Color.WHITE)
	_label("LV %02d" % int(Game.player.get("level", 1)), 108, 50, 150, 24, 16, Game.font_tag, DIM)
	var xp := UI.paint(self, func(c: Control):
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0, 0, 0, 0.5))
		c.draw_rect(Rect2(Vector2.ZERO, Vector2(c.size.x * float(Game.player.get("xp", 0.62)), c.size.y)), GOLD)
	, Rect2(0, 0, 0, 0), false)
	_r(xp, 108, 78, 210, 6)

	_chip("coin", "%s" % Game.fmt(int(Game.player.get("coins", 0))), 420, 22, 190, GOLD)
	_chip("gem", "%s" % Game.fmt(int(Game.player.get("gems", 0))), 626, 22, 160, CYAN)
	var plus := _button("+", 796, 24, 44, 44, true, 26)
	plus.alignment = HORIZONTAL_ALIGNMENT_CENTER
	plus.pressed.connect(func(): main.toast("قريباً", GOLD))

	var right := [["gift", "الجوائز"], ["badge", "المهام"], ["bolt", "الإنجازات"], ["settings", "الإعدادات"], ["exit", "الخروج"]]
	for i in right.size():
		var spec: Array = right[i]
		var x := 1440.0 + i * 88.0
		var b := Button.new()
		b.tooltip_text = str(spec[1])
		b.flat = true
		b.add_theme_stylebox_override("normal", _style(Color(0.03, 0.05, 0.09, 0.7), Color(CYAN, 0.25)))
		b.add_theme_stylebox_override("hover", _style(Color(0.06, 0.08, 0.13, 0.9), GOLD))
		b.add_theme_stylebox_override("pressed", _style(Color(0.02, 0.03, 0.06, 0.95), GOLD))
		b.add_theme_stylebox_override("focus", _style(Color(0.06, 0.08, 0.13, 0.9), GOLD, 2))
		_r(b, x, 18, 60, 60)
		add_child(b)
		var icon_kind := str(spec[0])
		_icon(icon_kind, x + 14, 32, 32, Color.WHITE)
		if icon_kind == "settings":
			b.pressed.connect(_on_item.bind("settings"))
		elif icon_kind == "exit":
			b.pressed.connect(_on_item.bind("exit"))
		else:
			b.pressed.connect(func(): main.toast("قريباً", GOLD))


func _chip(icon_kind: String, value: String, x: float, y: float, w: float, col: Color) -> void:
	_panel(x, y, w, 52, col, Color(0.02, 0.03, 0.07, 0.85))
	_icon(icon_kind, x + 12, y + 12, 28, col)
	_label(value, x + 48, y + 10, w - 56, 32, 22, Game.font_bold, Color.WHITE)


# ---------------------------------------------------------------- left navigation (x 24..286)
func _build_navigation() -> void:
	var items := [
		["اللعب", "play", "city", true],
		["المتجر", "shop", "shop", false],
		["الملابس", "customize", "customize", false],
		["المهام", "badge", "jobs", false],
		["الجوائز", "gift", "rewards", false],
		["الإعدادات", "settings", "settings", false],
	]
	var y := 120.0
	for it in items:
		var b := _button(str(it[0]), 24, y, 262, 60, bool(it[3]), 24)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var icon := _icon(str(it[1]), 36, y + 16, 28, Color(0.06, 0.05, 0.02) if bool(it[3]) else Color.WHITE)
		icon.z_index = 2
		b.pressed.connect(_on_item.bind(str(it[2])))
		buttons.append(b)
		y += 70.0
	_build_chat(540)


func _build_chat(y: float) -> void:
	_panel(24, y, 262, 88, CYAN, Color(0.02, 0.03, 0.07, 0.8))
	_label("[عام]  KING", 40, y + 12, 230, 26, 18, Game.font_bold, GOLD)
	_label("مرحباً بالجميع! تجول • اعمل", 40, y + 42, 240, 30, 17, Game.font_semi, Color.WHITE)


# ---------------------------------------------------------------- hero (x 300..1380, y 0..700)
func _build_hero() -> void:
	var logo := _picture("res://assets/img/vorn_logo.png", 300, 92, 430, 300, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label("Live the Real Life...", 300, 396, 460, 44, 30, Game.font_tag, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_picture("res://assets/img/robber_art.jpg", 790, 120, 360, 580, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	_label("CITIZEN 01  •  DOWNTOWN", 790, 706, 360, 30, 17, Game.font_tag, DIM, HORIZONTAL_ALIGNMENT_CENTER)

	var play := _button("بــدء اللعب   »", 1400, 556, 496, 110, true, 40)
	play.alignment = HORIZONTAL_ALIGNMENT_CENTER
	play.pressed.connect(_on_item.bind("city"))
	buttons.append(play)


# ---------------------------------------------------------------- city cards (x 1400..1896)
func _build_city_cards() -> void:
	_panel(1400, 120, 496, 178, CYAN)
	_picture("res://assets/img/lobby_bg.jpg", 1416, 136, 150, 146)
	_label("مدينة VORN", 1586, 140, 290, 40, 26, Game.font_wide, Color.WHITE)
	_label("عالم مفتوح منظم بانتظارك!", 1586, 186, 290, 30, 18, Game.font_semi, DIM)
	_label("تجوّل • اعمل • ابنِ حياتك", 1586, 220, 290, 30, 18, Game.font_semi, DIM)

	_panel(1400, 316, 496, 196, GOLD)
	_picture("res://assets/img/cop_art.jpg", 1416, 332, 150, 164)
	_label("انضم إلى مجتمعنا", 1586, 336, 290, 40, 24, Game.font_bold, GOLD)
	_label("وظائف • شركات • عصابات", 1586, 384, 290, 30, 18, Game.font_semi, Color.WHITE)
	_label("فعاليات ومسؤولون حقيقيون", 1586, 418, 290, 30, 18, Game.font_semi, Color.WHITE)


# ---------------------------------------------------------------- bottom strip (y 700..1064)
func _build_bottom_strip() -> void:
	# GPS
	_panel(24, 700, 536, 364, CYAN)
	_label("GPS  •  خريطة المدينة", 48, 720, 500, 36, 24, Game.font_wide, Color.WHITE)
	_label("موقعك الحالي: وسط المدينة", 48, 766, 500, 30, 18, Game.font_semi, DIM)
	_label("الوجهة: الوجهة الرئيسية", 48, 796, 500, 30, 18, Game.font_semi, DIM)
	var gps := UI.paint(self, _draw_mini_map, Rect2(0, 0, 0, 0), false)
	_r(gps, 48, 838, 488, 210)

	# map preview
	_panel(580, 700, 620, 364, CYAN)
	_label("الخريطة", 604, 720, 300, 36, 24, Game.font_wide, Color.WHITE)
	var legend := [["منزل", Color(0.98, 0.78, 0.25)], ["متجر", Color(0.4, 0.8, 1.0)], ["مستشفى", Color(1.0, 0.4, 0.4)], ["شرطة", Color(0.45, 0.6, 1.0)]]
	var lx := 604.0
	for item in legend:
		var it: Array = item
		var dot := UI.paint(self, func(c: Control): c.draw_circle(Vector2(8, 8), 7, it[1]), Rect2(0, 0, 0, 0), false)
		_r(dot, lx, 770, 16, 16)
		_label(str(it[0]), lx + 22, 764, 110, 28, 17, Game.font_semi, DIM)
		lx += 130.0
	var map := UI.paint(self, _draw_map_preview, Rect2(0, 0, 0, 0), false)
	_r(map, 604, 808, 572, 240)

	# outfits
	_panel(1220, 700, 676, 364, GOLD)
	_label("الأزياء", 1244, 720, 300, 36, 24, Game.font_wide, Color.WHITE)
	var cats := ["cap", "mask", "glove", "pants", "shoe"]
	for i in cats.size():
		var cat_btn := _button("", 1244, 778 + i * 56, 48, 48)
		cat_btn.pressed.connect(_on_item.bind("customize"))
		_icon(cats[i], 1254, 788 + i * 56, 28, Color.WHITE)
	_picture("res://assets/img/cop_art.jpg", 1316, 776, 220, 260)
	_label("الشخصية", 1556, 790, 300, 30, 18, Game.font_semi, DIM)
	_label("تخصيص المظهر", 1556, 824, 300, 30, 18, Game.font_semi, DIM)
	var clothes := _button("الملابس   ›", 1556, 960, 300, 60, true, 22)
	clothes.alignment = HORIZONTAL_ALIGNMENT_CENTER
	clothes.pressed.connect(_on_item.bind("customize"))


func _draw_mini_map(c: Control) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.02, 0.09, 0.12, 0.9))
	for i in 9:
		var x := 20.0 + i * 54.0
		c.draw_line(Vector2(x, 0), Vector2(x + 30, c.size.y), Color(0.3, 0.65, 0.62, 0.25), 2.0)
	for i in 5:
		var y := 18.0 + i * 46.0
		c.draw_line(Vector2(0, y), Vector2(c.size.x, y - 14), Color(0.3, 0.65, 0.62, 0.25), 2.0)
	c.draw_polyline(PackedVector2Array([Vector2(60, 170), Vector2(180, 120), Vector2(260, 130), Vector2(380, 60)]), GOLD, 4.0, true)
	c.draw_circle(Vector2(60, 170), 8, Color.WHITE)
	c.draw_circle(Vector2(380, 60), 10, GOLD)


func _draw_map_preview(c: Control) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.03, 0.12, 0.14, 0.92))
	for i in 10:
		var x := 20.0 + i * 56.0
		c.draw_line(Vector2(x, 0), Vector2(x + 24, c.size.y), Color(0.3, 0.65, 0.62, 0.22), 2.0)
	for i in 6:
		var y := 16.0 + i * 38.0
		c.draw_line(Vector2(0, y), Vector2(c.size.x, y - 10), Color(0.3, 0.65, 0.62, 0.22), 2.0)
	var spots := [[0.2, 0.3, Color(0.98, 0.78, 0.25)], [0.45, 0.6, Color(0.4, 0.8, 1.0)], [0.7, 0.35, Color(1.0, 0.4, 0.4)], [0.82, 0.7, Color(0.45, 0.6, 1.0)], [0.55, 0.22, Color(0.98, 0.78, 0.25)]]
	for s in spots:
		var p := Vector2(c.size.x * float(s[0]), c.size.y * float(s[1]))
		c.draw_circle(p, 10, s[2])
		c.draw_circle(p, 18, Color(s[2], 0.2))


func _process(delta: float) -> void:
	t += delta


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
