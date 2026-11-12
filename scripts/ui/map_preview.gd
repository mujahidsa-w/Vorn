extends Control
## Procedural top-down city map preview with animated routes.

var t := 0.0
var blocks: Array = []
var title := "CITY"
const LOCS := [
	["CITY CENTRE", Vector2(0.5, 0.42), Color(1.0, 0.78, 0.25)],
	["HARBOR", Vector2(0.86, 0.22), Color(0.3, 0.85, 1.0)],
	["GAS STATION", Vector2(0.4, 0.84), Color(0.4, 0.95, 0.5)],
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var cols := 9
	var rows := 6
	for gx in cols:
		for gy in rows:
			var cell := Rect2(float(gx) / cols, float(gy) / rows, 1.0 / cols, 1.0 / rows).grow(-0.012)
			if gx >= 7 and gy <= 2:
				continue
			var n := rng.randi_range(1, 3)
			for k in n:
				var w := cell.size.x / n
				var rr := Rect2(cell.position.x + w * k, cell.position.y, w, cell.size.y).grow(-0.004)
				rr.size.y *= rng.randf_range(0.55, 1.0)
				blocks.append(rr)


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _p(m: Rect2, v: Vector2) -> Vector2:
	return m.position + v * m.size


func _dashed(m: Rect2, pts: Array, col: Color) -> void:
	for i in pts.size() - 1:
		var a := _p(m, pts[i])
		var b := _p(m, pts[i + 1])
		var L := a.distance_to(b)
		var dir := (b - a) / L
		var s := fmod(t * 60.0, 24.0) - 24.0
		while s < L:
			var s0 := maxf(s, 0.0)
			var s1 := minf(s + 12.0, L)
			if s1 > s0:
				draw_line(a + dir * s0, a + dir * s1, col, 3.0)
			s += 24.0


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	Game.draw_panel(self, r, Color(Game.C_CYAN, 0.6))
	Game.dtext(self, "MAP PREVIEW", Vector2(18, 34), 18, Game.C_DIM, Game.font_tag)
	Game.dtext(self, title, Vector2(size.x - 18, 34), 20, Color.WHITE, Game.font_wide, HORIZONTAL_ALIGNMENT_RIGHT)
	var m := Rect2(16, 50, size.x - 32, size.y - 66)
	draw_rect(m, Color(0.05, 0.075, 0.11))
	# water
	draw_colored_polygon(PackedVector2Array([_p(m, Vector2(0.76, 0)), _p(m, Vector2(1, 0)), _p(m, Vector2(1, 0.5)), _p(m, Vector2(0.8, 0.42)), _p(m, Vector2(0.74, 0.2))]), Color(0.06, 0.16, 0.26))
	# park
	draw_rect(Rect2(_p(m, Vector2(0.02, 0.02)), m.size * Vector2(0.18, 0.28)), Color(0.07, 0.17, 0.11))
	for b in blocks:
		var br: Rect2 = b
		draw_rect(Rect2(_p(m, br.position), br.size * m.size), Color(0.1, 0.13, 0.19))
	# main avenues
	for v in [0.333, 0.667]:
		draw_line(_p(m, Vector2(0, v)), _p(m, Vector2(1, v)), Color(0.18, 0.22, 0.3), 4.0)
	for v in [0.222, 0.556]:
		draw_line(_p(m, Vector2(v, 0)), _p(m, Vector2(v, 1)), Color(0.18, 0.22, 0.3), 4.0)
	# routes
	_dashed(m, [Vector2(0.5, 0.42), Vector2(0.556, 0.42), Vector2(0.556, 0.64), Vector2(0.68, 0.64)], Color(1.0, 0.25, 0.38, 0.85))
	_dashed(m, [Vector2(0.17, 0.7), Vector2(0.222, 0.7), Vector2(0.222, 0.333), Vector2(0.5, 0.333), Vector2(0.5, 0.42)], Color(0.3, 0.55, 1.0, 0.85))
	# scan line
	var sx := m.position.x + fmod(t * 0.15, 1.0) * m.size.x
	draw_line(Vector2(sx, m.position.y), Vector2(sx, m.end.y), Color(Game.C_CYAN, 0.18), 2.0)
	for l in LOCS:
		var p := _p(m, l[1])
		var col: Color = l[2]
		var pulse := fmod(t * 0.8 + p.x * 0.01, 1.0)
		draw_arc(p, 8.0 + pulse * 18.0, 0, TAU, 24, Color(col, 0.6 * (1.0 - pulse)), 2.0, true)
		draw_circle(p, 7.0, col)
		draw_circle(p, 3.0, Color(0.03, 0.05, 0.09))
		var lw := Game.font_bold.get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var lp := p + Vector2(-lw * 0.5, -16)
		draw_rect(Rect2(lp + Vector2(-6, -15), Vector2(lw + 12, 20)), Color(0, 0, 0, 0.6))
		Game.dtext(self, l[0], lp, 15, Color.WHITE, Game.font_bold)
	draw_rect(m, Color(1, 1, 1, 0.1), false, 1.0)
