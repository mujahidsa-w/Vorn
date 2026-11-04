extends Button
## Animated menu button drawn by hand (hover sweep, accent bar, icon, key hint).

const Icons = preload("res://scripts/ui/icons.gd")

var caption := ""
var icon_kind := ""
var accent := Color(0.25, 0.85, 1.0)
var primary := false
var font_size := 40
var centered := false
var hint := ""
var _h := 0.0
var _p := 0.0


func setup(cap: String, ic := "", fs := 40, acc := Color(0.25, 0.85, 1.0)) -> Button:
	caption = cap
	icon_kind = ic
	font_size = fs
	accent = acc
	return self


func _ready() -> void:
	text = ""
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	mouse_entered.connect(_on_mouse_entered)
	focus_entered.connect(_on_focus)
	button_down.connect(func(): _p = 1.0)
	pressed.connect(func(): Game.play_sfx("click"))


func _on_mouse_entered() -> void:
	if not disabled and not has_focus():
		grab_focus()


func _on_focus() -> void:
	Game.play_sfx("hover", randf_range(0.96, 1.04), -5.0)


func _process(delta: float) -> void:
	var target := 1.0 if ((has_focus() or is_hovered()) and not disabled) else 0.0
	_h = lerpf(_h, target, 1.0 - exp(-delta * 14.0))
	_p = lerpf(_p, 0.0, 1.0 - exp(-delta * 8.0))
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var am := 0.4 if disabled else 1.0
	var hl := maxf(_h, 0.5 if primary else 0.0)
	draw_rect(r, Color(0.035, 0.06, 0.1, 0.8))
	var sw := size.x * (0.3 + 0.7 * _h)
	var c0 := Color(accent, (0.26 * hl + 0.3 * _p) * am)
	var c1 := Color(accent, 0.0)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(sw, 0), Vector2(sw, size.y), Vector2(0, size.y)]), PackedColorArray([c0, c1, c1, c0]))
	draw_rect(r, Color(accent, (0.12 + 0.55 * hl) * am), false, 1.5)
	draw_rect(Rect2(0, 0, 3.0 + 3.0 * hl, size.y), Color(accent, (0.25 + 0.75 * hl) * am))

	var f: Font = Game.font_wide
	var txt_col := Game.C_TEXT.lerp(Color.WHITE, _h)
	txt_col.a = am
	var icon_col := Color(1, 1, 1, 0.75).lerp(accent.lightened(0.25), maxf(_h, 1.0 if primary else 0.0))
	icon_col.a *= am
	var asc := f.get_ascent(font_size)
	var desc := f.get_descent(font_size)
	var base_y := size.y * 0.5 + (asc - desc) * 0.5 - font_size * 0.04
	var off := 10.0 * _h
	if centered:
		var tw := f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var iw := font_size * 1.1 if icon_kind != "" else 0.0
		var x0 := (size.x - tw - iw) * 0.5
		if icon_kind != "":
			Icons.draw(self, icon_kind, Vector2(x0 + font_size * 0.4, size.y * 0.5), font_size * 0.7, icon_col)
		draw_string(f, Vector2(x0 + iw, base_y), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, txt_col)
	else:
		var x := 26.0 + off
		if icon_kind != "":
			Icons.draw(self, icon_kind, Vector2(x + font_size * 0.42, size.y * 0.5), font_size * 0.78, icon_col)
			x += font_size * 1.35
		draw_string(f, Vector2(x, base_y), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, txt_col)
	if hint != "":
		var hf: Font = Game.font_bold
		var hs := 18
		var hw := maxf(34.0, hf.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hs).x + 16.0)
		var hr := Rect2(size.x - hw - 16.0, size.y * 0.5 - 16.0, hw, 32.0)
		draw_rect(hr, Color(1, 1, 1, (0.06 + 0.08 * _h) * am))
		draw_rect(hr, Color(1, 1, 1, 0.3 * am), false, 1.0)
		Game.dtext(self, hint, Vector2(hr.get_center().x, hr.position.y + 23.0), hs, Color(1, 1, 1, 0.85 * am), hf, HORIZONTAL_ALIGNMENT_CENTER)
