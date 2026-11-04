extends Button
## Settings row. Either cycles through `options` or acts as a 0..1 slider (is_slider).

signal changed(value)

var label_text := ""
var options: Array = []
var index := 0
var is_slider := false
var value_fmt: Callable    # optional: value(0..1) -> display string
var value := 0.5
var _h := 0.0
var _drag := false
const TRACK_W := 380.0


func _ready() -> void:
	text = ""
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	mouse_entered.connect(func():
		if not has_focus():
			grab_focus())
	focus_entered.connect(func(): Game.play_sfx("hover", 1.0, -6.0))
	if not is_slider:
		pressed.connect(func(): _step(1))


func _track_rect() -> Rect2:
	return Rect2(size.x - TRACK_W - 110, size.y * 0.5 - 4, TRACK_W, 8)


func _step(d: int) -> void:
	if is_slider:
		value = clampf(snappedf(value + d * 0.05, 0.05), 0.0, 1.0)
		changed.emit(value)
	else:
		index = posmod(index + d, options.size())
		changed.emit(index)
	Game.play_sfx("click", 1.2, -4.0)


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		_step(-1)
		accept_event()
	elif event.is_action_pressed("ui_right"):
		_step(1)
		accept_event()
	elif is_slider:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_drag = event.pressed
			if event.pressed:
				_set_from_x(event.position.x)
			else:
				Game.play_sfx("click", 1.2, -4.0)
			accept_event()
		elif event is InputEventMouseMotion and _drag:
			_set_from_x(event.position.x)
			accept_event()


func _set_from_x(x: float) -> void:
	var tr := _track_rect()
	var nv := clampf((x - tr.position.x) / tr.size.x, 0.0, 1.0)
	if absf(nv - value) > 0.001:
		value = nv
		changed.emit(value)


func _process(delta: float) -> void:
	_h = lerpf(_h, 1.0 if (has_focus() or is_hovered()) else 0.0, 1.0 - exp(-delta * 14.0))
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(1, 1, 1, 0.025 + 0.05 * _h))
	draw_rect(Rect2(0, 0, 3, size.y), Color(Game.C_CYAN, 0.15 + 0.85 * _h))
	draw_line(Vector2(0, size.y), Vector2(size.x, size.y), Color(1, 1, 1, 0.07), 1.0)
	var cy := size.y * 0.5 + 8.0
	Game.dtext(self, label_text, Vector2(28, cy), 26, Game.C_TEXT.lerp(Color.WHITE, _h), Game.font_semi)
	if is_slider:
		var tr := _track_rect()
		draw_rect(tr, Color(1, 1, 1, 0.12))
		draw_rect(Rect2(tr.position, Vector2(tr.size.x * value, tr.size.y)), Game.C_CYAN)
		var k := Vector2(tr.position.x + tr.size.x * value, tr.get_center().y)
		draw_circle(k, 10.0 + 2.0 * _h, Color.WHITE)
		draw_circle(k, 5.0, Game.C_CYAN)
		Game.dtext(self, value_fmt.call(value) if value_fmt.is_valid() else "%d%%" % int(round(value * 100.0)), Vector2(size.x - 28, cy), 24, Color.WHITE, Game.font_bold, HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		var v := str(options[index]) if options.size() > 0 else ""
		var vx := size.x - 170.0
		Game.dtext(self, v, Vector2(vx, cy), 24, Color.WHITE, Game.font_wide, HORIZONTAL_ALIGNMENT_CENTER)
		var ac := Color(1, 1, 1, 0.3 + 0.6 * _h)
		Game.dtext(self, "‹", Vector2(vx - 130, cy), 30, ac, Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
		Game.dtext(self, "›", Vector2(vx + 130, cy), 30, ac, Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
