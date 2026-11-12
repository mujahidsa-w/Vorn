extends Control
## Vorn lobby: the design image is the full-screen background. Its own panels and labels are
## painted in the image, so the controls are transparent buttons laid exactly over them.
## Positions are in the image's own pixels (1672 x 941) and scale with the window.

const IMG := preload("res://assets/img/lobby_reference.jpg")
const FIGURE := preload("res://scripts/screens/lobby_figure.gd")
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

	_build_figure()

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


func _build_figure() -> void:
	# the character is rendered in its own 3D view over the lobby; dragging turns it in place
	var vp := SubViewport.new()
	vp.size = Vector2i(560, 881)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.72)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 35, 0)
	sun.light_energy = 1.6
	vp.add_child(sun)
	_pivot = Node3D.new()
	_pivot.set_script(FIGURE)
	vp.add_child(_pivot)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 0.95, 4.2)
	vp.add_child(cam)
	cam.look_at(Vector3(0, 0.95, 0), Vector3.UP)
	cam.current = true
	var view := TextureRect.new()
	view.texture = vp.get_texture()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	view.gui_input.connect(_on_figure_input)
	_ref(view, 520, 60, 560, 881)
	stage.add_child(view)


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
		"quick", "comp", "custom":
			if not Online.is_signed_in() and not Online.offline_mode:
				main.toast("سجّل الدخول للدخول إلى VORN", CYAN)
				main.go("login")
				return
			if target == "comp" and not Online.is_signed_in():
				main.toast("الوضع التنافسي يحتاج تسجيل الدخول", CYAN)
				return
			Online.match_id = ""
			Online.match_team = ""
			Online.comp_mode = target == "comp"
			if target == "quick":
				main.go("loading", {"online": Online.is_signed_in()})
			else:
				main.go("match")
		_:
			main.go(target)


func on_back() -> void:
	main.confirm("خروج", "هل تريد مغادرة VORN؟", "خروج", func(): Online._quit_cleanly())


func _exit_tree() -> void:
	if main:
		main.bg.visible = true
		main.rain.visible = Game.settings.rain
