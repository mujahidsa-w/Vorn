extends RefCounted
## Vector icons drawn with canvas primitives. Call from inside a _draw().


static func _pts(c: Vector2, s: float, arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in arr:
		out.append(c + p * s)
	return out


static func _half_disc(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	var p := PackedVector2Array()
	for i in 17:
		var a := PI + PI * i / 16.0
		p.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_colored_polygon(p, col)


static func draw(ci: CanvasItem, kind: String, c: Vector2, s: float, col: Color) -> void:
	var w := maxf(2.0, s * 0.09)
	match kind:
		"play":
			ci.draw_colored_polygon(_pts(c, s, [Vector2(-0.38, -0.5), Vector2(0.5, 0), Vector2(-0.38, 0.5)]), col)
		"customize":
			ci.draw_colored_polygon(_pts(c, s, [Vector2(-0.2, -0.48), Vector2(0.2, -0.48), Vector2(0.56, -0.24), Vector2(0.42, 0.02), Vector2(0.28, -0.06), Vector2(0.28, 0.5), Vector2(-0.28, 0.5), Vector2(-0.28, -0.06), Vector2(-0.42, 0.02), Vector2(-0.56, -0.24)]), col)
		"shop":
			ci.draw_polyline(_pts(c, s, [Vector2(-0.56, -0.4), Vector2(-0.38, -0.4), Vector2(-0.22, 0.2), Vector2(0.42, 0.2), Vector2(0.54, -0.22), Vector2(-0.3, -0.22)]), col, w, true)
			ci.draw_circle(c + Vector2(-0.14, 0.42) * s, s * 0.09, col)
			ci.draw_circle(c + Vector2(0.34, 0.42) * s, s * 0.09, col)
		"friends":
			var col2 := Color(col, col.a * 0.7)
			ci.draw_circle(c + Vector2(0.26, -0.16) * s, s * 0.14, col2)
			_half_disc(ci, c + Vector2(0.3, 0.42) * s, s * 0.26, s * 0.3, col2)
			ci.draw_circle(c + Vector2(-0.16, -0.2) * s, s * 0.17, col)
			_half_disc(ci, c + Vector2(-0.16, 0.44) * s, s * 0.34, s * 0.36, col)
		"user":
			ci.draw_circle(c + Vector2(0, -0.2) * s, s * 0.19, col)
			_half_disc(ci, c + Vector2(0, 0.46) * s, s * 0.38, s * 0.38, col)
		"settings":
			var p := PackedVector2Array()
			var n := 32
			for i in n:
				var a := TAU * (i + 0.5) / n
				var r := s * (0.5 if (i % 4) < 2 else 0.37)
				p.append(c + Vector2(cos(a), sin(a)) * r)
			ci.draw_colored_polygon(p, col)
			ci.draw_circle(c, s * 0.15, Color(0.04, 0.07, 0.12))
		"exit":
			ci.draw_polyline(_pts(c, s, [Vector2(0.05, -0.28), Vector2(0.05, -0.5), Vector2(-0.45, -0.5), Vector2(-0.45, 0.5), Vector2(0.05, 0.5), Vector2(0.05, 0.28)]), col, w)
			ci.draw_line(c + Vector2(-0.18, 0) * s, c + Vector2(0.42, 0) * s, col, w)
			ci.draw_colored_polygon(_pts(c, s, [Vector2(0.56, 0), Vector2(0.34, -0.2), Vector2(0.34, 0.2)]), col)
		"back":
			ci.draw_polyline(_pts(c, s, [Vector2(0.2, -0.42), Vector2(-0.22, 0), Vector2(0.2, 0.42)]), col, w * 1.3)
		"check":
			ci.draw_polyline(_pts(c, s, [Vector2(-0.4, 0.0), Vector2(-0.1, 0.3), Vector2(0.45, -0.32)]), col, w * 1.3)
		"coin":
			ci.draw_circle(c, s * 0.5, Color(1.0, 0.72, 0.15))
			ci.draw_circle(c, s * 0.38, Color(1.0, 0.85, 0.35))
			ci.draw_arc(c, s * 0.2, 0.7, TAU - 0.7, 16, Color(0.6, 0.38, 0.0), maxf(1.5, s * 0.1))
		"gem":
			ci.draw_colored_polygon(_pts(c, s, [Vector2(-0.5, -0.15), Vector2(-0.25, -0.45), Vector2(0.25, -0.45), Vector2(0.5, -0.15), Vector2(0, 0.5)]), Color(0.3, 0.8, 1.0))
			ci.draw_colored_polygon(_pts(c, s, [Vector2(-0.5, -0.15), Vector2(0.5, -0.15), Vector2(0, 0.5)]), Color(0.15, 0.55, 0.95))
		"mask":
			ci.draw_colored_polygon(_pts(c, s, [Vector2(-0.5, -0.2), Vector2(-0.3, -0.4), Vector2(0.3, -0.4), Vector2(0.5, -0.2), Vector2(0.4, 0.25), Vector2(0, 0.45), Vector2(-0.4, 0.25)]), col)
			ci.draw_circle(c + Vector2(-0.2, -0.08) * s, s * 0.1, Color(0.04, 0.07, 0.12))
			ci.draw_circle(c + Vector2(0.2, -0.08) * s, s * 0.1, Color(0.04, 0.07, 0.12))
		"cap":
			_half_disc(ci, c + Vector2(0, 0.1) * s, s * 0.4, s * 0.45, col)
			ci.draw_colored_polygon(_pts(c, s, [Vector2(-0.4, 0.1), Vector2(0.62, 0.1), Vector2(0.55, 0.24), Vector2(-0.4, 0.22)]), col)
		"pants":
			ci.draw_colored_polygon(_pts(c, s, [Vector2(-0.32, -0.5), Vector2(0.32, -0.5), Vector2(0.38, 0.5), Vector2(0.08, 0.5), Vector2(0, -0.1), Vector2(-0.08, 0.5), Vector2(-0.38, 0.5)]), col)
		"shoe":
			ci.draw_colored_polygon(_pts(c, s, [Vector2(-0.5, -0.3), Vector2(-0.15, -0.3), Vector2(-0.05, -0.05), Vector2(0.4, 0.05), Vector2(0.55, 0.2), Vector2(0.55, 0.32), Vector2(-0.5, 0.32)]), col)
		"glove":
			ci.draw_colored_polygon(_pts(c, s, [Vector2(-0.3, 0.5), Vector2(-0.32, -0.2), Vector2(-0.28, -0.45), Vector2(0.28, -0.45), Vector2(0.32, -0.1), Vector2(0.52, -0.2), Vector2(0.45, 0.1), Vector2(0.3, 0.5)]), col)
		"badge":
			var p2 := PackedVector2Array()
			for i in 10:
				var a := -PI / 2 + TAU * i / 10.0
				var r2 := s * (0.5 if i % 2 == 0 else 0.25)
				p2.append(c + Vector2(cos(a), sin(a)) * r2)
			ci.draw_colored_polygon(p2, col)
		"car":
			ci.draw_colored_polygon(_pts(c, s, [Vector2(-0.56, 0.2), Vector2(-0.52, -0.02), Vector2(-0.25, -0.08), Vector2(-0.1, -0.3), Vector2(0.25, -0.3), Vector2(0.42, -0.06), Vector2(0.56, 0.0), Vector2(0.56, 0.2)]), col)
			ci.draw_circle(c + Vector2(-0.3, 0.22) * s, s * 0.13, Color(0.04, 0.07, 0.12))
			ci.draw_circle(c + Vector2(0.32, 0.22) * s, s * 0.13, Color(0.04, 0.07, 0.12))
		"bag":
			ci.draw_circle(c + Vector2(0, 0.12) * s, s * 0.38, col)
			ci.draw_colored_polygon(_pts(c, s, [Vector2(-0.16, -0.22), Vector2(-0.24, -0.46), Vector2(0.24, -0.46), Vector2(0.16, -0.22)]), col)
			ci.draw_string(ThemeDB.fallback_font, c + Vector2(-0.13, 0.3) * s, "$", HORIZONTAL_ALIGNMENT_LEFT, -1, int(s * 0.55), Color(0.04, 0.07, 0.12))
		"bolt":
			ci.draw_colored_polygon(_pts(c, s, [Vector2(0.1, -0.5), Vector2(-0.35, 0.08), Vector2(-0.02, 0.08), Vector2(-0.12, 0.5), Vector2(0.35, -0.1), Vector2(0.02, -0.1)]), col)
		"gift":
			ci.draw_rect(Rect2(c + Vector2(-0.42, -0.1) * s, Vector2(0.84, 0.6) * s), col)
			ci.draw_rect(Rect2(c + Vector2(-0.5, -0.3) * s, Vector2(1.0, 0.2) * s), col)
			ci.draw_rect(Rect2(c + Vector2(-0.07, -0.3) * s, Vector2(0.14, 0.8) * s), col.darkened(0.45))
			ci.draw_circle(c + Vector2(-0.15, -0.38) * s, s * 0.12, col)
			ci.draw_circle(c + Vector2(0.15, -0.38) * s, s * 0.12, col)
		"lock":
			ci.draw_arc(c + Vector2(0, -0.12) * s, s * 0.22, PI, TAU, 12, col, w)
			ci.draw_rect(Rect2(c + Vector2(-0.32, -0.1) * s, Vector2(0.64, 0.55) * s), col)
		"chat":
			ci.draw_rect(Rect2(c + Vector2(-0.5, -0.4) * s, Vector2(1.0, 0.65) * s), col)
			ci.draw_colored_polygon(_pts(c, s, [Vector2(-0.3, 0.25), Vector2(-0.05, 0.25), Vector2(-0.35, 0.5)]), col)
		_:
			ci.draw_circle(c, s * 0.3, col)
