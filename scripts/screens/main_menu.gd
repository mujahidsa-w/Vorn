extends Control
## Vorn City lobby: hero scene, account bar, Arabic navigation, service cards and bottom HUD preview.

const UI = preload("res://scripts/ui/ui.gd")
const NeonButton = preload("res://scripts/ui/neon_button.gd")

var main
var data := {}
var bg_dim := 0.0
var show_top := false
var buttons: Array = []
var character: TextureRect
var character_name: Label
var rotation_side := 0
var t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_background()
	_build_top_bar()
	_build_left_navigation()
	_build_hero()
	_build_right_cards()
	_build_bottom_strip()
	Game.quiet_focus(buttons[0])

func _build_background() -> void:
	var image := TextureRect.new()
	image.texture = preload("res://assets/img/lobby_bg.jpg")
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	Game.lay(image, [0, 0, 1, 1], [0, 0, 0, 0])
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image)
	var tint := ColorRect.new()
	tint.color = Color(0.015, 0.02, 0.055, 0.34)
	Game.lay(tint, [0, 0, 1, 1], [0, 0, 0, 0])
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tint)
	var shade := UI.paint(self, _draw_shade, Rect2(0, 0, 0, 0), true)
	Game.lay(shade, [0, 0, 1, 1], [0, 0, 0, 0])

func _draw_shade(c: Control) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.01, 0.015, 0.04, 0.16))
	c.draw_rect(Rect2(0, 0, 300, c.size.y), Color(0.01, 0.015, 0.03, 0.78))
	c.draw_rect(Rect2(c.size.x - 390, 0, 390, c.size.y), Color(0.01, 0.015, 0.03, 0.45))
	c.draw_rect(Rect2(0, c.size.y - 360, c.size.x, 360), Color(0.01, 0.015, 0.03, 0.56))
	c.draw_rect(Rect2(0, 0, c.size.x, 3), Color(Game.C_GOLD, 0.72))

func _panel(parent: Control, rect: Rect2, border: Color, alpha := 0.84) -> Control:
	var p := UI.paint(parent, func(c: Control):
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.015, 0.02, 0.055, alpha))
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(border, 0.72), false, 1.5)
	, Rect2(0, 0, 0, 0), true)
	UI.rect(p, rect.position.x, rect.position.y, rect.end.x, rect.end.y)
	parent.add_child(p)
	return p

func _build_top_bar() -> void:
	var avatar := TextureRect.new()
	avatar.texture = preload("res://assets/img/avatar.png")
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	Game.lay(avatar, [0, 0, 0, 0], [28, 22, 108, 102])
	add_child(avatar)
	var profile := Game.label(str(Game.player.get("name", "Mujahid")) + "  ♛", 25, Game.font_wide, Color.WHITE)
	UI.rect(profile, 122, 34, 340, 68)
	add_child(profile)
	var level := Game.label("Lv. %02d" % int(Game.player.get("level", 1)), 16, Game.font_tag, Game.C_DIM)
	UI.rect(level, 124, 70, 250, 94)
	add_child(level)
	var xp := UI.paint(self, func(c: Control):
		c.draw_rect(Rect2(0, 0, c.size.x, c.size.y), Color(0, 0, 0, 0.45))
		c.draw_rect(Rect2(0, 0, c.size.x * float(Game.player.get("xp", 0.62)), c.size.y), Game.C_GOLD)
	, Rect2(0, 0, 0, 0), true)
	UI.rect(xp, 124, 100, 240, 8)
	add_child(xp)
	var cash := _resource_chip("▣  $" + Game.fmt(int(Game.player.get("coins", 245750))), Game.C_GREEN)
	UI.rect(cash, 585, 24, 820, 76)
	add_child(cash)
	var gems := _resource_chip("◆  " + Game.fmt(int(Game.player.get("gems", 12350))), Game.C_CYAN)
	UI.rect(gems, 835, 24, 1055, 76)
	add_child(gems)
	var plus := Game.label("+", 32, Game.font_wide, Game.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	UI.rect(plus, 1062, 28, 1100, 72)
	add_child(plus)
	var top_icons := [["▣", "الجــــوائز"], ["▦", "التقويم"], ["♜", "الإنجازات"], ["⚙", "الإعدادات"], ["⏻", "الخروج"]]
	for i in top_icons.size():
		var spec: Array = top_icons[i]
		var x := 1390.0 + i * 88.0
		var icon := Game.label(spec[0], 29, Game.font_wide, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		UI.rect(icon, x, 24, x + 66, 68)
		add_child(icon)

func _resource_chip(text: String, color: Color) -> Control:
	var p := _panel(self, Rect2(0, 0, 0, 0), color, 0.76)
	var l := Game.label(text, 22, Game.font_bold, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	Game.lay(l, [0, 0, 1, 1], [10, 0, -10, 0])
	p.add_child(l)
	return p

func _build_left_navigation() -> void:
	var items := [["اللعب", "play", "city"], ["المتجر", "shop", "shop"], ["الملابس", "customize", "customize"], ["المهام", "jobs", "jobs"], ["الجوائز", "rewards", "jobs"], ["الإعدادات", "settings", "settings"]]
	var y := 178.0
	for i in items.size():
		var it: Array = items[i]
		var b := NeonButton.new()
		b.setup("  " + str(it[0]), str(it[1]), 22, Game.C_GOLD if i == 0 else Color.WHITE)
		b.primary = i == 0
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		UI.rect(b, 24, y, 250, y + 58)
		b.pressed.connect(_on_item.bind(it[2]))
		add_child(b)
		buttons.append(b)
		y += 67.0
	var chat := _panel(self, Rect2(24, 610, 270, 70), Game.C_CYAN, 0.72)
	var chat_text := Game.label("▣  [عام]  KING  ♛\nمرحباً بالجميع!", 15, Game.font_semi, Color.WHITE)
	UI.rect(chat_text, 40, 622, 270, 674)
	add_child(chat_text)

func _build_hero() -> void:
	var logo := TextureRect.new()
	logo.texture = preload("res://assets/img/vorn_logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	Game.lay(logo, [0, 0, 0, 0], [310, 112, 700, 282])
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	var tagline := Game.label("Live the Real Life...", 30, Game.font_tag, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	UI.rect(tagline, 325, 282, 700, 330)
	add_child(tagline)
	var stage := UI.paint(self, _draw_stage, Rect2(0, 0, 0, 0), true)
	Game.lay(stage, [0, 0, 0, 0], [330, 120, 1220, 635])
	character = TextureRect.new()
	character.texture = preload("res://assets/img/robber_art.jpg")
	character.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	character.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	Game.lay(character, [0, 0, 0, 0], [570, 188, 1050, 650])
	character.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(character)
	var left := NeonButton.new()
	left.setup("‹", "", 48, Game.C_CYAN)
	left.centered = true
	UI.rect(left, 470, 400, 545, 475)
	left.pressed.connect(_rotate_character.bind(-1))
	add_child(left)
	var right := NeonButton.new()
	right.setup("›", "", 48, Game.C_CYAN)
	right.centered = true
	UI.rect(right, 1060, 400, 1135, 475)
	right.pressed.connect(_rotate_character.bind(1))
	add_child(right)
	character_name = Game.label("CITIZEN 01  •  DOWNTOWN", 18, Game.font_tag, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	UI.rect(character_name, 570, 620, 1050, 650)
	add_child(character_name)
	var play := NeonButton.new()
	play.setup("بــدء اللــعب  ❯❯", "play", 31, Game.C_GOLD)
	play.primary = true
	play.centered = true
	UI.rect(play, 1340, 770, 1870, 870)
	play.pressed.connect(_on_item.bind("city"))
	add_child(play)

func _draw_stage(c: Control) -> void:
	var center := Vector2(c.size.x * 0.5, c.size.y * 0.74)
	c.draw_circle(center + Vector2(0, 40), 260, Color(0.01, 0.02, 0.05, 0.45))
	for i in 5:
		c.draw_arc(center, 260.0 - i * 40.0, deg_to_rad(205), deg_to_rad(335), 64, Color(Game.C_CYAN, 0.12), 2.0, true)
	c.draw_line(Vector2(c.size.x * 0.5 - 300, c.size.y - 28), Vector2(c.size.x * 0.5 + 300, c.size.y - 28), Color(Game.C_GOLD, 0.55), 2.0)

func _build_right_cards() -> void:
	var city := _panel(self, Rect2(1370, 150, 1870, 320), Game.C_CYAN, 0.88)
	var city_title := Game.label("📍  مدينة VORN", 27, Game.font_wide, Color.WHITE)
	UI.rect(city_title, 1400, 180, 1835, 222)
	add_child(city_title)
	var city_info := Game.label("عالم مفتوح منظم بانتظارك!\nتجول • اعمل • ابنِ حياتك", 19, Game.font_semi, Game.C_DIM)
	UI.rect(city_info, 1400, 230, 1835, 300)
	add_child(city_info)
	var community := _panel(self, Rect2(1370, 338, 1870, 510), Game.C_GOLD, 0.88)
	var community_title := Game.label("انضم إلى مجتمعنا  👥", 24, Game.font_wide, Game.C_GOLD)
	UI.rect(community_title, 1400, 365, 1835, 410)
	add_child(community_title)
	var community_info := Game.label("وظائف • شركات • عصابات\nفعاليات ومسؤولون حقيقيون", 19, Game.font_semi, Color.WHITE)
	UI.rect(community_info, 1400, 420, 1835, 480)
	add_child(community_info)

func _build_bottom_strip() -> void:
	var gps := _panel(self, Rect2(24, 730, 520, 1030), Game.C_CYAN, 0.86)
	var gps_title := Game.label("◉  GPS  •  خريطة المدينة", 22, Game.font_wide, Color.WHITE)
	UI.rect(gps_title, 48, 755, 500, 792)
	add_child(gps_title)
	var gps_info := Game.label("موقعك الحالي\nالوجهة الرئيسية → وسط المدينة", 17, Game.font_semi, Game.C_DIM)
	UI.rect(gps_info, 48, 810, 500, 885)
	add_child(gps_info)
	var map := _panel(self, Rect2(555, 730, 1160, 1030), Game.C_CYAN, 0.86)
	var map_title := Game.label("⌖  الخريطة", 25, Game.font_wide, Color.WHITE)
	UI.rect(map_title, 585, 755, 850, 792)
	add_child(map_title)
	var map_hint := Game.label("⌂ المنازل     ◇ المتاجر     ✚ المستشفى     ⚑ الشرطة", 16, Game.font_semi, Game.C_DIM)
	UI.rect(map_hint, 585, 810, 1130, 850)
	add_child(map_hint)
	var map_art := UI.paint(self, _draw_map_preview, Rect2(0, 0, 0, 0), true)
	UI.rect(map_art, 580, 860, 1135, 1015)
	add_child(map_art)
	var clothes := _panel(self, Rect2(1175, 730, 1345, 1030), Game.C_GOLD, 0.86)
	var clothes_title := Game.label("←  الأزياء", 25, Game.font_wide, Color.WHITE)
	UI.rect(clothes_title, 1205, 755, 1320, 792)
	add_child(clothes_title)
	var clothes_info := Game.label("الشخصية\nتخصيص المظهر\nالدوران يمين / يسار", 18, Game.font_semi, Game.C_DIM)
	UI.rect(clothes_info, 1205, 820, 1320, 940)
	add_child(clothes_info)
	var clothes_btn := NeonButton.new()
	clothes_btn.setup("الملابس", "customize", 18, Game.C_GOLD)
	clothes_btn.centered = true
	UI.rect(clothes_btn, 1198, 950, 1322, 1010)
	clothes_btn.pressed.connect(_on_item.bind("customize"))
	add_child(clothes_btn)

func _draw_map_preview(c: Control) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.04, 0.12, 0.15, 0.72))
	for i in 7:
		var x := 30.0 + i * 110.0
		c.draw_line(Vector2(x, 0), Vector2(x + 40, c.size.y), Color(0.3, 0.65, 0.62, 0.3), 2.0)
	for i in 4:
		var y := 22.0 + i * 42.0
		c.draw_line(Vector2(0, y), Vector2(c.size.x, y - 18), Color(0.3, 0.65, 0.62, 0.3), 2.0)
	c.draw_circle(Vector2(c.size.x * 0.52, c.size.y * 0.55), 9.0, Game.C_GOLD)
	c.draw_circle(Vector2(c.size.x * 0.52, c.size.y * 0.55), 22.0, Color(Game.C_GOLD, 0.22))
	Game.dtext(c, "VORN CITY  •  DOWNTOWN", Vector2(c.size.x * 0.5, c.size.y - 18), 16, Color.WHITE, Game.font_tag, HORIZONTAL_ALIGNMENT_CENTER)

func _process(delta: float) -> void:
	t += delta

func _rotate_character(direction: int) -> void:
	rotation_side = clampi(rotation_side + direction, -1, 1)
	character.flip_h = rotation_side < 0
	character_name.text = "CITIZEN 01  •  FACING LEFT" if rotation_side < 0 else "CITIZEN 01  •  FACING RIGHT" if rotation_side > 0 else "CITIZEN 01  •  DOWNTOWN"
	Game.play_sfx("whoosh")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_LEFT:
			_rotate_character(-1)
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_RIGHT:
			_rotate_character(1)
			get_viewport().set_input_as_handled()

func _on_item(target: String) -> void:
	if target == "city" and not Online.is_signed_in():
		main.toast("سجّل الدخول للدخول إلى VORN CITY ONLINE", Game.C_CYAN)
		main.go("login")
		return
	if target == "city":
		Online.match_id = ""
		Online.match_team = ""
		main.go("loading", {"roleplay": true, "online": true})
		return
	main.go(target)

func on_back() -> void:
	main.confirm("خروج", "هل تريد مغادرة Vorn City؟", "خروج", func(): Online._quit_cleanly())
