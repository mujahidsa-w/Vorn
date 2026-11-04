extends Button
## Big selectable team card (Cops / Robbers).

var cfg := {}
var dimmed := false
var _h := 0.0
var _d := 0.0
var _flash := 0.0


func _ready() -> void:
	text = ""
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	mouse_entered.connect(func():
		if not has_focus():
			grab_focus())
	focus_entered.connect(func(): Game.play_sfx("hover", 0.8, -3.0))


func flash() -> void:
	_flash = 1.0


func is_active() -> bool:
	return has_focus() or is_hovered()


func _process(delta: float) -> void:
	var hov := is_active()
	_h = lerpf(_h, 1.0 if hov else 0.0, 1.0 - exp(-delta * 10.0))
	_d = lerpf(_d, 1.0 if (dimmed and not hov) else 0.0, 1.0 - exp(-delta * 8.0))
	_flash = maxf(0.0, _flash - delta * 2.5)
	pivot_offset = size * 0.5
	scale = Vector2.ONE * (1.0 + 0.03 * _h)
	queue_redraw()


func _draw() -> void:
	var acc: Color = cfg.accent
	var tex: Texture2D = cfg.tex
	var r := Rect2(Vector2.ZERO, size)
	for i in 4:
		draw_rect(r.grow(4.0 + i * 6.0), Color(acc, 0.1 * _h * (1.0 - i / 4.0)), false, 6.0)
	var ts := tex.get_size()
	var z := maxf(size.x / ts.x, size.y / ts.y) * (1.0 + 0.05 * _h)
	var src_size := size / z
	var src_pos := Vector2((ts.x - src_size.x) * 0.5, (ts.y - src_size.y) * 0.12)
	var b := 1.0 - 0.6 * _d
	draw_texture_rect_region(tex, r, Rect2(src_pos, src_size), Color(b, b, b, 1.0))
	draw_rect(r, Color(acc, 0.1 + 0.06 * _h))
	var gy := size.y * 0.4
	var d0 := Color(0.01, 0.015, 0.03, 0.0)
	var d1 := Color(0.01, 0.015, 0.03, 0.96)
	draw_polygon(PackedVector2Array([Vector2(0, gy), Vector2(size.x, gy), Vector2(size.x, size.y), Vector2(0, size.y)]), PackedColorArray([d0, d0, d1, d1]))
	draw_rect(r, Color(acc, 0.35 + 0.65 * _h), false, 2.0)
	var L := 30.0
	var bw := 4.0
	for cx in [0.0, size.x]:
		for cy in [0.0, size.y]:
			var sx := 1.0 if cx == 0.0 else -1.0
			var sy := 1.0 if cy == 0.0 else -1.0
			draw_line(Vector2(cx, cy), Vector2(cx + L * sx, cy), acc, bw)
			draw_line(Vector2(cx, cy), Vector2(cx, cy + L * sy), acc, bw)

	# online badge
	var on_txt := "%s PLAYING" % Game.fmt(int(cfg.online))
	var ow := Game.font_bold.get_string_size(on_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_rect(Rect2(22, 24, ow + 40, 30), Color(0, 0, 0, 0.6))
	draw_circle(Vector2(36, 39), 5, Game.C_GREEN)
	Game.dtext(self, on_txt, Vector2(48, 45), 16, Color.WHITE, Game.font_bold)

	var x := 36.0
	var y := size.y - 270.0
	Game.dtext(self, str(cfg.role), Vector2(x, y), 18, acc.lightened(0.35), Game.font_tag)
	Game.dtext(self, str(cfg.title), Vector2(x - 4, y + 80), 92, Color.WHITE, Game.font_wide)
	Game.dtext(self, str(cfg.desc), Vector2(x, y + 118), 22, Game.C_TEXT)
	var stats: Array = cfg.stats
	for i in stats.size():
		var sy := y + 156.0 + i * 30.0
		Game.dtext(self, str(stats[i][0]), Vector2(x, sy), 16, Game.C_DIM, Game.font_tag)
		for k in 5:
			var on := k < int(stats[i][1])
			draw_rect(Rect2(x + 170 + k * 46, sy - 11, 40, 8), acc if on else Color(1, 1, 1, 0.12))
	Game.dtext(self, "CLICK TO JOIN  ›", Vector2(size.x * 0.5, size.y - 24.0), 18, Color(acc.lightened(0.4), _h), Game.font_tag, HORIZONTAL_ALIGNMENT_CENTER)
	if _flash > 0.0:
		draw_rect(r, Color(1, 1, 1, 0.4 * _flash))
