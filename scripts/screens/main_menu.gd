extends Control
## Vorn lobby: the design image is the full-screen background. Its own panels and labels are
## painted in the image, so the controls are transparent buttons laid exactly over them.
## Positions are in the image's own pixels (1672 x 941) and scale with the window.

const IMG := preload("res://assets/img/lobby_reference.jpg")
const TURN_MAX := 1.2  # radians (about 70 degrees) either side
const GOLD := Color(1.0, 0.76, 0.12)
const CYAN := Color(0.25, 0.85, 1.0)
const REF := Vector2(1672.0, 941.0)

var main
var stage: Control
var data := {}
var bg_dim := 0.0
var show_top := false
var _pivot: Node3D
var _yaw := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# everything sits on a 16:9 stage so the image positions hold at any window size
	var arc := AspectRatioContainer.new()
	arc.ratio = REF.x / REF.y
	arc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(arc)
	stage = Control.new()
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arc.add_child(stage)
	# the app-wide background and rain are not shown behind the lobby image
	main.bg.visible = false
	main.rain.visible = false

	var pic := TextureRect.new()
	pic.texture = IMG
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(pic)

	_zero_profile()

	# top navigation (image positions)
	_hit(405, 4, 145, 70, "quick")        # PLAY tab
	_hit(565, 4, 130, 70, "customize")    # INVENTORY
	_hit(715, 4, 105, 70, "soon")         # STORE
	_hit(845, 4, 110, 70, "soon")         # SEASON
	_hit(990, 4, 95, 70, "soon")          # RANK
	_hit(1120, 4, 120, 70, "settings")    # SETTINGS
	_hit(1345, 14, 303, 72, "soon")       # profile
	# left column
	_hit(27, 123, 393, 182, "soon")       # season card
	_hit(27, 322, 386, 78, "quick")       # QUICK PLAY
	_hit(27, 410, 386, 68, "comp")        # COMPETITIVE
	_hit(27, 482, 386, 70, "custom")      # CUSTOM GAME
	_hit(27, 556, 386, 66, "soon")        # TRAINING
	_hit(27, 628, 386, 68, "soon")        # BATTLE PASS
	_hit(27, 740, 408, 108, "quick")      # PLAY
	# right column
	_hit(1290, 692, 358, 161, "soon")     # new map card


## the design image paints a profile, currency and friends list with sample values; they are
## covered and redrawn from the real (fresh) player data
func _zero_profile() -> void:
	var nm := str(Game.player.name) if bool(Game.player.name_set) else "—"
	_cover(1345, 14, 303, 72)            # profile card (avatar, name, level, xp bar)
	_text(nm, 1360, 24, 240, 26, 22, Game.font_bold, Color.WHITE)
	_text("LV %d" % int(Game.player.level), 1360, 52, 120, 20, 16, Game.font_bold, Game.C_DIM)
	_cover(1422, 90, 100, 34)             # coin amount
	_text(str(int(Game.player.coins)), 1427, 94, 90, 28, 22, Game.font_bold, Color.WHITE)
	_cover(1548, 90, 62, 34)             # gem amount
	_text(str(int(Game.player.gems)), 1550, 94, 60, 28, 22, Game.font_bold, Color.WHITE)
	_cover(1400, 152, 248, 476)          # online list
	# friends panel: real friends from the server (tap to open the friends screen)
	var fr: Array = Online.friends
	_text("FRIENDS (%d)" % fr.size(), 1416, 170, 220, 26, 20, Game.font_bold, Color.WHITE)
	if fr.is_empty():
		_text("لا يوجد أصدقاء بعد", 1416, 300, 216, 30, 20, Game.font_bold, Game.C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		_text("اضغط لإضافة صديق بالكود", 1416, 340, 216, 26, 16, Game.font_bold, Game.C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		var y := 215.0
		for f in fr.slice(0, 6):
			var st := "IN LOBBY" if str(f.get("lobby", "")) != "" else ("IN MATCH" if f.status == "in_match" else ("ONLINE" if f.online else "OFFLINE"))
			_text(str(f.name), 1430, y, 200, 26, 19, Game.font_bold, Color.WHITE if f.online else Game.C_DIM)
			_text(st, 1430, y + 26, 200, 20, 14, Game.font_bold, Color(0.4, 0.95, 0.5) if f.online else Game.C_DIM)
			y += 66.0
	_hit(1400, 152, 248, 476, "friends")


func _cover(x: float, y: float, w: float, h: float) -> void:
	var r := ColorRect.new()
	r.color = Color(0.035, 0.05, 0.08, 1.0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ref(r, x, y, w, h)
	stage.add_child(r)


func _text(t: String, x: float, y: float, w: float, h: float, fs: int, font: Font, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var l := Game.label(t, fs, font, col, align)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ref(l, x, y, w, h)
	stage.add_child(l)


func _on_figure_input(ev: InputEvent) -> void:
	var dx := 0.0
	if ev is InputEventScreenDrag:
		dx = (ev as InputEventScreenDrag).relative.x
	elif ev is InputEventMouseMotion and (ev as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		dx = (ev as InputEventMouseMotion).relative.x
	if dx == 0.0:
		return
	_yaw = clampf(_yaw + dx * 0.01, -TURN_MAX, TURN_MAX)
	_pivot.rotation.y = _yaw


## places a control by image pixel rectangle (anchors as fractions of the full screen)
func _ref(c: Control, x: float, y: float, w: float, h: float) -> void:
	c.anchor_left = x / REF.x
	c.anchor_top = y / REF.y
	c.anchor_right = (x + w) / REF.x
	c.anchor_bottom = (y + h) / REF.y
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0


func _hit(x: float, y: float, w: float, h: float, target: String) -> void:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	b.add_theme_stylebox_override("normal", empty)
	b.add_theme_stylebox_override("focus", empty)
	b.add_theme_stylebox_override("pressed", _glow())
	b.add_theme_stylebox_override("hover", _glow())
	_ref(b, x, y, w, h)
	b.pressed.connect(_on_item.bind(target))
	stage.add_child(b)


func _glow() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1.0, 0.76, 0.12, 0.06)
	s.border_color = Color(GOLD, 0.7)
	s.set_border_width_all(2)
	s.set_corner_radius_all(8)
	return s


func _on_item(target: String) -> void:
	match target:
		"soon":
			main.toast("قريباً", CYAN)
		"quick", "city", "comp", "custom":
			if not Online.is_signed_in() and not Online.offline_mode:
				main.toast("سجّل الدخول للدخول إلى VORN", CYAN)
				main.go("login")
				return
			if target == "comp" and not Online.is_signed_in():
				main.toast("الوضع التنافسي يحتاج تسجيل الدخول", CYAN)
				return
			if not Game.player.name_set:
				main.go("name")
				return
			Online.match_id = ""
			Online.match_team = ""
			# every mode is the arena match now (no city): PLAY / QUICK PLAY start a practice match
			# right away; COMPETITIVE and CUSTOM go through the team lobby for an online match
			Online.comp_mode = true
			if target == "quick" or target == "city":
				main.go("loading", {"online": false})
			else:
				main.go("match")
		_:
			main.go(target)


func on_back() -> void:
	main.confirm("خروج", "هل تريد مغادرة VORN؟", "خروج", func(): Online._quit_cleanly())


func _exit_tree() -> void:
	if main:
		main.bg.visible = true
		main.rain.visible = false
