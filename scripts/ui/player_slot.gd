extends Control
## One player row in the pre-match lobby.

const Icons = preload("res://scripts/ui/icons.gd")

var info := {}
var accent := Color.WHITE
var t := 0.0
var _join := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_info(d: Dictionary) -> void:
	if info.is_empty() and not d.is_empty():
		_join = 1.0
	info = d


func _process(delta: float) -> void:
	t += delta
	_join = maxf(0.0, _join - delta * 2.0)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var you: bool = info.get("you", false)
	var cy := size.y * 0.5
	draw_rect(r, Color(0.03, 0.05, 0.09, 0.84))
	if you:
		draw_rect(r, Color(accent, 0.1))
	draw_rect(r, Color(accent, 0.45 if you else 0.12), false, 1.0)
	draw_rect(Rect2(0, 0, 4, size.y), Color(accent, 0.25 if info.is_empty() else 0.95))
	if info.is_empty():
		var sc := Vector2(40, cy)
		draw_arc(sc, 13, t * 5.0, t * 5.0 + 4.0, 24, Color(accent, 0.7), 3.0, true)
		Game.dtext(self, "SEARCHING" + ".".repeat(int(t * 2.5) % 4), Vector2(74, cy + 7), 20, Game.C_DIM, Game.font_tag)
		return
	var ac := Vector2(40, cy)
	draw_circle(ac, 22, accent.darkened(0.6))
	draw_arc(ac, 22, 0, TAU, 32, accent, 2.0, true)
	var nm := str(info.name)
	Game.dtext(self, nm.substr(0, 1).to_upper(), ac + Vector2(0, 9), 26, Color.WHITE, Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	var nw := Game.dtext(self, nm, Vector2(76, cy - 2), 26, Color.WHITE, Game.font_bold)
	if you:
		var yr := Rect2(84 + nw, cy - 22, 46, 22)
		draw_rect(yr, Game.C_CYAN)
		Game.dtext(self, "YOU", Vector2(yr.get_center().x, cy - 5), 15, Color(0.02, 0.05, 0.1), Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	Game.dtext(self, "LVL %d     %d ms" % [int(info.level), int(info.ping)], Vector2(76, cy + 22), 17, Game.C_DIM)
	var rx := size.x - 20.0
	if info.ready:
		Game.dtext(self, "READY", Vector2(rx, cy + 8), 22, Game.C_GREEN, Game.font_wide, HORIZONTAL_ALIGNMENT_RIGHT)
		Icons.draw(self, "check", Vector2(rx - 96, cy), 22, Game.C_GREEN)
	else:
		Game.dtext(self, "NOT READY", Vector2(rx, cy + 8), 20, Color(1, 1, 1, 0.35), Game.font_wide, HORIZONTAL_ALIGNMENT_RIGHT)
	if _join > 0.0:
		draw_rect(r, Color(accent, 0.35 * _join))
