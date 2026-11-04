extends Control
## Vorn City social lobby: character preview, navigation rail and city entry.

const UI = preload("res://scripts/ui/ui.gd")
const NeonButton = preload("res://scripts/ui/neon_button.gd")
const Icons = preload("res://scripts/ui/icons.gd")

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
	_build_header()
	_build_navigation()
	_build_character_stage()
	_build_city_cards()
	_build_footer()
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
	tint.color = Color(0.015, 0.02, 0.055, 0.38)
	Game.lay(tint, [0, 0, 1, 1], [0, 0, 0, 0])
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tint)
	var vignette := UI.paint(self, _draw_vignette, Rect2(0, 0, 0, 0), true)
	Game.lay(vignette, [0, 0, 1, 1], [0, 0, 0, 0])

func _draw_vignette(c: Control) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.01, 0.015, 0.04, 0.28))
	c.draw_rect(Rect2(0, 0, 520, c.size.y), Color(0.01, 0.015, 0.03, 0.72))
	c.draw_rect(Rect2(c.size.x - 470, 0, 470, c.size.y), Color(0.01, 0.015, 0.03, 0.42))
	c.draw_rect(Rect2(0, 0, c.size.x, 3), Color(Game.C_CYAN, 0.65))

func _build_header() -> void:
	var logo := TextureRect.new()
	logo.texture = preload("res://assets/img/vorn_logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	Game.lay(logo, [0, 0, 0, 0], [46, 22, 190, 166])
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	var brand := Game.label("VORN CITY", 38, Game.font_wide, Color.WHITE)
	Game.lay(brand, [0, 0, 0, 0], [202, 48, 570, 92])
	add_child(brand)
	var tagline := Game.label("CITY  •  ROLEPLAY  •  SURVIVAL", 15, Game.font_tag, Game.C_CYAN)
	Game.lay(tagline, [0, 0, 0, 0], [205, 96, 600, 122])
	add_child(tagline)

	var profile := UI.paint(self, _draw_profile, Rect2(0, 0, 0, 0), true)
	Game.lay(profile, [1, 0, 1, 0], [-520, 22, -28, 116])

func _draw_profile(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(r, Color(0.02, 0.025, 0.065, 0.82))
	c.draw_rect(r, Color(1, 1, 1, 0.14), false, 1.0)
	var avatar := preload("res://assets/img/avatar.png")
	c.draw_texture_rect(avatar, Rect2(12, 12, 78, 78), false)
	c.draw_rect(Rect2(12, 72, 78, 18), Color(0, 0, 0, 0.65))
	Game.dtext(c, str(Game.player.get("name", "CITIZEN")), Vector2(106, 38), 24, Color.WHITE, Game.font_wide)
	Game.dtext(c, "LV. %d  •  CITIZEN" % int(Game.player.get("level", 1)), Vector2(106, 65), 15, Game.C_DIM, Game.font_tag)
	Game.dtext(c, "$" + Game.fmt(int(Game.player.get("coins", 0))), Vector2(106, 95), 21, Game.C_GOLD, Game.font_semi)
	Game.dtext(c, "BANK  $" + Game.fmt(int(Game.player.get("bank", 0))), Vector2(280, 95), 17, Game.C_CYAN, Game.font_semi)

func _build_navigation() -> void:
	var items := [
		["PLAY", "play", "city"],
		["CITY SERVICES", "home", "city"],
		["COMMUNITY", "friends", "friends"],
		["SETTINGS", "settings", "settings"],
		["EXIT", "exit", "exit"],
	]
	var y := 210.0
	for i in items.size():
		var it: Array = items[i]
		var b := NeonButton.new()
		b.setup(it[0], it[1], 25, Game.C_GOLD if i == 0 else Game.C_CYAN)
		b.primary = i == 0
		UI.rect(b, 30, y, 270, 64)
		b.pressed.connect(_on_item.bind(it[2]))
		add_child(b)
		buttons.append(b)
		y += 76.0
	var hint := Game.label("LIVE SERVER  •  %d CITIZENS ONLINE" % Online.online_friends(), 14, Game.font_tag, Color(1, 1, 1, 0.52))
	UI.rect(hint, 42, 705, 390, 26)
	add_child(hint)

func _build_character_stage() -> void:
	var stage := UI.paint(self, _draw_stage, Rect2(0, 0, 0, 0), true)
	Game.lay(stage, [0, 0, 0, 0], [350, 150, 1220, 950])
	character = TextureRect.new()
	character.texture = preload("res://assets/img/robber_art.jpg")
	character.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	character.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	Game.lay(character, [0, 0, 0, 0], [620, 195, 1040, 865])
	character.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(character)
	var left := NeonButton.new()
	left.setup("‹", "", 52, Game.C_CYAN)
	left.centered = true
	UI.rect(left, 525, 485, 78, 78)
	left.pressed.connect(_rotate_character.bind(-1))
	add_child(left)
	var right := NeonButton.new()
	right.setup("›", "", 52, Game.C_CYAN)
	right.centered = true
	UI.rect(right, 1055, 485, 78, 78)
	right.pressed.connect(_rotate_character.bind(1))
	add_child(right)
	character_name = Game.label("CITIZEN 01  •  DOWNTOWN", 21, Game.font_tag, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	UI.rect(character_name, 560, 886, 1040, 920)
	add_child(character_name)
	var rotate_hint := Game.label("← / →  ROTATE CHARACTER", 14, Game.font_tag, Color(1, 1, 1, 0.58), HORIZONTAL_ALIGNMENT_CENTER)
	UI.rect(rotate_hint, 560, 925, 1040, 952)
	add_child(rotate_hint)

func _draw_stage(c: Control) -> void:
	var center := Vector2(c.size.x * 0.5, c.size.y * 0.63)
	for i in 5:
		var rad := 260.0 - i * 42.0
		c.draw_arc(center, rad, deg_to_rad(205), deg_to_rad(335), 64, Color(Game.C_CYAN, 0.16 - i * 0.02), 2.0, true)
	c.draw_circle(center + Vector2(0, 180), 245, Color(0.01, 0.02, 0.06, 0.54))
	c.draw_line(Vector2(c.size.x * 0.5 - 280, c.size.y - 45), Vector2(c.size.x * 0.5 + 280, c.size.y - 45), Color(Game.C_GOLD, 0.38), 2.0)

func _build_city_cards() -> void:
	var city := UI.paint(self, _draw_city_card, Rect2(0, 0, 0, 0), true)
	Game.lay(city, [1, 0, 1, 0], [-430, 170, -35, 315])
	var community := UI.paint(self, _draw_community_card, Rect2(0, 0, 0, 0), true)
	Game.lay(community, [1, 0, 1, 0], [-430, 335, -35, 480])
	var play := NeonButton.new()
	play.setup("ENTER VORN CITY  ▶", "play", 28, Game.C_GOLD)
	play.primary = true
	UI.rect(play, 1420, 770, 430, 94)
	play.pressed.connect(_on_item.bind("city"))
	add_child(play)

func _draw_city_card(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(r, Color(0.02, 0.025, 0.065, 0.88))
	c.draw_rect(r, Color(Game.C_CYAN, 0.52), false, 1.5)
	Game.dtext(c, "VORN CITY", Vector2(24, 38), 28, Color.WHITE, Game.font_wide)
	Game.dtext(c, "DOWNTOWN  •  OPEN WORLD", Vector2(24, 68), 16, Game.C_CYAN, Game.font_tag)
	Game.dtext(c, "City Center is ready for your next chapter.", Vector2(24, 106), 18, Color(1, 1, 1, 0.84), Game.font_med)
	Game.dtext(c, "ACTIVE  •  %d CITIZENS" % Online.online_friends(), Vector2(24, 133), 14, Game.C_GREEN, Game.font_tag)

func _draw_community_card(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(r, Color(0.02, 0.025, 0.065, 0.88))
	c.draw_rect(r, Color(Game.C_GOLD, 0.48), false, 1.5)
	Game.dtext(c, "COMMUNITY", Vector2(24, 38), 27, Color.WHITE, Game.font_wide)
	Game.dtext(c, "MEET  •  WORK  •  LIVE", Vector2(24, 68), 16, Game.C_GOLD, Game.font_tag)
	Game.dtext(c, "Build your life with other citizens.", Vector2(24, 106), 18, Color(1, 1, 1, 0.84), Game.font_med)
	Game.dtext(c, "ROLEPLAY SERVER  •  ONLINE", Vector2(24, 133), 14, Game.C_GREEN, Game.font_tag)

func _build_footer() -> void:
	var footer := Game.label("ENTER THE CITY TO VISIT STORES  •  [E] INTERACT  •  [M] MAP", 15, Game.font_tag, Color(1, 1, 1, 0.62))
	UI.rect(footer, 350, 1012, 1000, 1040)
	add_child(footer)

func _process(delta: float) -> void:
	t += delta

func _rotate_character(direction: int) -> void:
	rotation_side = clampi(rotation_side + direction, -1, 1)
	character.flip_h = rotation_side < 0
	character_name.text = ("CITIZEN 01  •  FACING LEFT" if rotation_side < 0 else "CITIZEN 01  •  FACING RIGHT" if rotation_side > 0 else "CITIZEN 01  •  DOWNTOWN")
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
		main.toast("SIGN IN TO ENTER VORN CITY ONLINE", Game.C_CYAN)
		main.go("login")
		return
	if target == "city":
		Online.match_id = ""
		Online.match_team = ""
		main.go("loading", {"roleplay": true, "online": true})
		return
	if target == "offline":
		Online.match_id = ""
		Online.match_team = ""
		main.go("loading", {"roleplay": true, "offline": true})
		return
	main.go(target)

func on_back() -> void:
	main.confirm("EXIT GAME?", "Leave Vorn City and close the game?", "EXIT", func(): Online._quit_cleanly())
