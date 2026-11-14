class_name Glyph
extends Control
## Small vector icons drawn with primitives (no image files): the lobby and loading screen use them.

var kind := ""
var col := Color.WHITE
var thick := 0.08

static func make(k: String, sz: float, c := Color.WHITE) -> Glyph:
	var g := Glyph.new()
	g.kind = k
	g.col = c
	g.custom_minimum_size = Vector2(sz, sz)
	g.size = Vector2(sz, sz)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g

func set_kind(k: String) -> void:
	kind = k
	queue_redraw()

func _p(x: float, y: float) -> Vector2:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	return o + Vector2(x, y) * s

func _poly(pts: Array, c := col) -> void:
	var a := PackedVector2Array()
	for q in pts:
		a.append(_p(q[0], q[1]))
	draw_colored_polygon(a, c)

func _line(pts: Array, w := -1.0, c := col) -> void:
	var a := PackedVector2Array()
	for q in pts:
		a.append(_p(q[0], q[1]))
	var s := minf(size.x, size.y)
	draw_polyline(a, c, (thick if w < 0.0 else w) * s, true)

func _circle(x: float, y: float, r: float, c := col, filled := true, w := -1.0) -> void:
	var s := minf(size.x, size.y)
	if filled:
		draw_circle(_p(x, y), r * s, c)
	else:
		draw_arc(_p(x, y), r * s, 0.0, TAU, 40, c, (thick if w < 0.0 else w) * s, true)

func _arc(x: float, y: float, r: float, a0: float, a1: float, w := -1.0, c := col) -> void:
	var s := minf(size.x, size.y)
	draw_arc(_p(x, y), r * s, a0, a1, 24, c, (thick if w < 0.0 else w) * s, true)

func _draw() -> void:
	match kind:
		"sound", "mute":
			_poly([[0.12, 0.38], [0.30, 0.38], [0.52, 0.18], [0.52, 0.82], [0.30, 0.62], [0.12, 0.62]])
			if kind == "sound":
				_arc(0.52, 0.5, 0.16, -0.9, 0.9)
				_arc(0.52, 0.5, 0.30, -0.9, 0.9)
			else:
				_line([[0.64, 0.36], [0.90, 0.64]])
				_line([[0.90, 0.36], [0.64, 0.64]])
		"gear":
			for i in 8:
				var a := TAU * i / 8.0
				var d := Vector2(cos(a), sin(a))
				var n := Vector2(-d.y, d.x)
				var c := Vector2(0.5, 0.5)
				var p1 := c + d * 0.30 + n * 0.07
				var p2 := c + d * 0.44 + n * 0.055
				var p3 := c + d * 0.44 - n * 0.055
				var p4 := c + d * 0.30 - n * 0.07
				_poly([[p1.x, p1.y], [p2.x, p2.y], [p3.x, p3.y], [p4.x, p4.y]])
			_circle(0.5, 0.5, 0.25, col, false, 0.13)
		"friends":
			_circle(0.36, 0.34, 0.13)
			_poly([[0.12, 0.80], [0.16, 0.58], [0.36, 0.50], [0.56, 0.58], [0.60, 0.80]])
			_circle(0.68, 0.30, 0.11, Color(col, col.a * 0.75))
			_poly([[0.62, 0.50], [0.82, 0.52], [0.90, 0.72], [0.66, 0.72]], Color(col, col.a * 0.75))
		"crate":
			_line([[0.14, 0.30], [0.50, 0.14], [0.86, 0.30], [0.86, 0.72], [0.50, 0.88], [0.14, 0.72], [0.14, 0.30]])
			_line([[0.14, 0.30], [0.50, 0.46], [0.86, 0.30]])
			_line([[0.50, 0.46], [0.50, 0.88]])
		"bag":
			_line([[0.34, 0.30], [0.34, 0.20], [0.66, 0.20], [0.66, 0.30]])
			_poly([[0.16, 0.32], [0.84, 0.32], [0.80, 0.86], [0.20, 0.86]])
			_poly([[0.30, 0.52], [0.70, 0.52], [0.70, 0.62], [0.30, 0.62]], Color(0, 0, 0, 0.35))
		"trophy":
			_poly([[0.26, 0.16], [0.74, 0.16], [0.70, 0.46], [0.58, 0.58], [0.42, 0.58], [0.30, 0.46]])
			_arc(0.26, 0.30, 0.10, PI * 0.5, PI * 1.5)
			_arc(0.74, 0.30, 0.10, -PI * 0.5, PI * 0.5)
			_poly([[0.45, 0.58], [0.55, 0.58], [0.56, 0.72], [0.44, 0.72]])
			_poly([[0.30, 0.74], [0.70, 0.74], [0.70, 0.84], [0.30, 0.84]])
		"cart":
			_line([[0.08, 0.20], [0.22, 0.20], [0.32, 0.62], [0.80, 0.62], [0.88, 0.32], [0.26, 0.32]])
			_circle(0.36, 0.78, 0.07)
			_circle(0.74, 0.78, 0.07)
		"mail":
			_line([[0.12, 0.26], [0.88, 0.26], [0.88, 0.76], [0.12, 0.76], [0.12, 0.26]])
			_line([[0.12, 0.28], [0.50, 0.56], [0.88, 0.28]])
		"play":
			_poly([[0.30, 0.18], [0.82, 0.50], [0.30, 0.82]])
		"plus":
			_line([[0.5, 0.18], [0.5, 0.82]], 0.14)
			_line([[0.18, 0.5], [0.82, 0.5]], 0.14)
		"coin":
			_circle(0.5, 0.5, 0.42, UI.GOLD_DK)
			_circle(0.5, 0.5, 0.35, UI.GOLD)
			_circle(0.5, 0.5, 0.24, UI.GOLD_HI, false, 0.06)
		"gem":
			_poly([[0.22, 0.38], [0.36, 0.20], [0.64, 0.20], [0.78, 0.38], [0.50, 0.84]], Color(0.45, 0.85, 1.0))
			_poly([[0.22, 0.38], [0.78, 0.38], [0.50, 0.84]], Color(0.25, 0.62, 0.95))
		"target":
			_circle(0.5, 0.5, 0.32, col, false)
			_line([[0.5, 0.06], [0.5, 0.30]])
			_line([[0.5, 0.70], [0.5, 0.94]])
			_line([[0.06, 0.5], [0.30, 0.5]])
			_line([[0.70, 0.5], [0.94, 0.5]])
		"wifi":
			_arc(0.5, 0.80, 0.56, PI * 1.25, PI * 1.75, 0.09)
			_arc(0.5, 0.80, 0.36, PI * 1.25, PI * 1.75, 0.09)
			_circle(0.5, 0.78, 0.07)
		"star":
			var pts := []
			for i in 10:
				var a := -PI / 2.0 + TAU * i / 10.0
				var r := 0.44 if i % 2 == 0 else 0.19
				pts.append([0.5 + cos(a) * r, 0.54 + sin(a) * r])
			_poly(pts)
		"rotate":
			_arc(0.5, 0.5, 0.30, 0.3, PI * 1.6, 0.09)
			_poly([[0.84, 0.44], [0.62, 0.50], [0.80, 0.66]])
		"exit":
			_line([[0.56, 0.18], [0.20, 0.18], [0.20, 0.82], [0.56, 0.82]])
			_line([[0.44, 0.5], [0.88, 0.5]])
			_poly([[0.90, 0.5], [0.72, 0.36], [0.72, 0.64]])
