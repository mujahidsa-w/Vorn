extends Button
## Shop / locker item tile.

const Icons = preload("res://scripts/ui/icons.gd")

var item := {}
var state := ""   # "", "owned", "equipped"
var _h := 0.0
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
	focus_entered.connect(func(): Game.play_sfx("hover", 1.1, -6.0))


func flash() -> void:
	_flash = 1.0


func _process(delta: float) -> void:
	_h = lerpf(_h, 1.0 if (has_focus() or is_hovered()) else 0.0, 1.0 - exp(-delta * 14.0))
	_flash = maxf(0.0, _flash - delta * 2.5)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var rc: Color = Game.RARITY.get(str(item.get("rarity", "Common")), Color.WHITE)
	draw_rect(r, Color(0.035, 0.055, 0.09, 0.9))
	var gy := size.y * 0.25
	draw_polygon(PackedVector2Array([Vector2(0, gy), Vector2(size.x, gy), Vector2(size.x, size.y), Vector2(0, size.y)]),
		PackedColorArray([Color(rc, 0.0), Color(rc, 0.0), Color(rc, 0.22 + 0.12 * _h), Color(rc, 0.22 + 0.12 * _h)]))
	draw_rect(r, Color(rc, 0.25 + 0.6 * _h), false, 1.5 + _h)
	draw_rect(Rect2(0, size.y - 5, size.x, 5), rc)
	var icon_s := minf(size.x, size.y) * 0.34 * (1.0 + 0.06 * _h)
	Icons.draw(self, str(item.get("icon", "")), Vector2(size.x * 0.5, size.y * 0.4), icon_s, rc.lightened(0.25))
	var fs := 22 if size.x > 280 else 19
	Game.dtext(self, str(item.get("name", "")), Vector2(14, size.y - 40), fs, Color.WHITE, Game.font_bold)
	Game.dtext(self, str(item.get("rarity", "")).to_upper(), Vector2(14, size.y - 17), 14, rc, Game.font_tag)
	var tr := Vector2(size.x - 12, 28)
	if state == "equipped":
		Game.dtext(self, "EQUIPPED", tr, 15, Game.C_GREEN, Game.font_bold, HORIZONTAL_ALIGNMENT_RIGHT)
	elif state == "owned":
		Game.dtext(self, "OWNED", tr, 15, Game.C_DIM, Game.font_bold, HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		var price := int(item.get("price", 0))
		var cur := str(item.get("currency", "coins"))
		var label := "FREE" if price == 0 else Game.fmt(price)
		var w := Game.dtext(self, label, tr, 18, Color.WHITE, Game.font_bold, HORIZONTAL_ALIGNMENT_RIGHT)
		if price > 0:
			Icons.draw(self, "coin" if cur == "coins" else "gem", Vector2(tr.x - w - 14, tr.y - 6), 16, Color.WHITE)
	if _flash > 0.0:
		draw_rect(r, Color(1, 1, 1, 0.4 * _flash))
