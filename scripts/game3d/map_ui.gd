extends Control
## Full-screen world map (F11) and the GPS minimap drawing.
## Map: drag to move, wheel / +- to zoom, click anywhere to set a destination (the GPS routes
## along the roads), right click to clear, search places by name.

const MM_PX_PER_M := 0.55

signal close_requested

var world
var hud
var tex: Texture2D
var center := Vector2.ZERO
var zoom := 0.3
var _drag := false
var _moved := 0.0
var _press_pos := Vector2.ZERO
var search: LineEdit
var results: VBoxContainer
var t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists("res://assets/world/map.png"):
		tex = load("res://assets/world/map.png")
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.09, 0.92)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", sb)
	Game.lay(panel, [0, 0, 0, 0], [30, 120, 410, 700])
	add_child(panel)
	var close := Button.new()
	close.text = "×"
	close.tooltip_text = "Close map"
	close.add_theme_font_override("font", Game.font_wide)
	close.add_theme_font_size_override("font_size", 42)
	close.add_theme_color_override("font_color", Color.WHITE)
	close.add_theme_color_override("font_hover_color", Game.C_GOLD)
	close.focus_mode = Control.FOCUS_NONE
	Game.lay(close, [1, 0, 1, 0], [-112, 24, -32, 100])
	close.pressed.connect(func(): close_requested.emit())
	add_child(close)
	var lbl := Game.label("SEARCH PLACES", 18, Game.font_bold, Game.C_DIM)
	Game.lay(lbl, [0, 0, 0, 0], [48, 132, 400, 160])
	add_child(lbl)
	search = LineEdit.new()
	search.placeholder_text = "type a name…"
	search.add_theme_font_override("font", Game.font_semi)
	search.add_theme_font_size_override("font_size", 22)
	Game.lay(search, [0, 0, 0, 0], [46, 164, 394, 208])
	search.text_changed.connect(func(_s): _refresh())
	add_child(search)
	results = VBoxContainer.new()
	Game.lay(results, [0, 0, 0, 0], [46, 220, 394, 690])
	add_child(results)
	for spec in [["+", Vector2(-90, -250), func(): _zoom_at(size * 0.5, 1.4)], ["−", Vector2(-90, -190), func(): _zoom_at(size * 0.5, 1.0 / 1.4)],
			["YOU", Vector2(-90, -130), func(): _center_on_player()]]:
		var b := Button.new()
		b.text = spec[0]
		b.add_theme_font_override("font", Game.font_bold)
		b.add_theme_font_size_override("font_size", 22)
		Game.lay(b, [1, 1, 1, 1], [spec[1].x - 20, spec[1].y, spec[1].x + 60, spec[1].y + 50])
		b.pressed.connect(spec[2])
		add_child(b)


func open() -> void:
	visible = true
	_center_on_player()
	zoom = 0.32
	search.text = ""
	_refresh()


func _center_on_player() -> void:
	var p: Vector3 = hud._focus_pos()
	center = Vector2(p.x, p.z)


func _refresh() -> void:
	for c in results.get_children():
		c.queue_free()
	if world.gps == null:
		return
	var list: Array = world.gps.search(search.text)
	for k in mini(list.size(), 11):
		var pl: Dictionary = list[k]
		var b := Button.new()
		b.text = "  " + str(pl.name)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_override("font", Game.font_semi)
		b.add_theme_font_size_override("font_size", 19)
		b.add_theme_color_override("font_color", (pl.color as Color).lightened(0.3))
		b.flat = true
		b.pressed.connect(func():
			world.gps.set_destination(pl.pos, pl.name)
			center = Vector2(pl.pos.x, pl.pos.z)
			Game.play_sfx("click"))
		results.add_child(b)


func w2s(p: Vector2) -> Vector2:
	return size * 0.5 + (p - center) * zoom


func s2w(s: Vector2) -> Vector2:
	return center + (s - size * 0.5) / zoom


func _zoom_at(screen_pos: Vector2, f: float) -> void:
	var before := s2w(screen_pos)
	zoom = clampf(zoom * f, 0.05, 3.0)
	var after := s2w(screen_pos)
	center += before - after


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, 1.15)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = true
				_moved = 0.0
				_press_pos = mb.position
				search.release_focus()
			else:
				_drag = false
				if _moved < 8.0:
					_click(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if world.gps.dest_set:
				world.gps.clear_destination()
				Game.play_sfx("back")
		accept_event()
	elif event is InputEventMouseMotion and _drag:
		center -= event.relative / zoom
		_moved += event.relative.length()
		accept_event()


func _click(sp: Vector2) -> void:
	var gps = world.gps
	# a place icon under the cursor wins
	for pl in gps.places:
		if w2s(Vector2(pl.pos.x, pl.pos.z)).distance_to(sp) < 16.0:
			gps.set_destination(pl.pos, pl.name)
			Game.play_sfx("click")
			return
	var w := s2w(sp)
	var n: int = gps.nearest_node(Vector3(w.x, 0, w.y))
	var np: Vector3 = gps.nodes[n]
	var y := np.y
	if world.country and world.country.in_world(w.x, w.y) and world.country.biome_at(w.x, w.y) != 0:
		y = world.country.height_at(w.x, w.y)
	var target := Vector3(w.x, y, w.y) if Vector2(np.x - w.x, np.z - w.y).length() < 60.0 else np
	gps.set_destination(target, "WAYPOINT")
	Game.play_sfx("click")


func _process(delta: float) -> void:
	if not visible:
		return
	t += delta
	if not search.has_focus():
		var mv := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
			float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
		center += mv * 700.0 * delta / zoom * 0.3
		if Input.is_physical_key_pressed(KEY_EQUAL) or Input.is_physical_key_pressed(KEY_KP_ADD):
			_zoom_at(size * 0.5, 1.0 + delta * 1.5)
		if Input.is_physical_key_pressed(KEY_MINUS) or Input.is_physical_key_pressed(KEY_KP_SUBTRACT):
			_zoom_at(size * 0.5, 1.0 / (1.0 + delta * 1.5))
	queue_redraw()


# ---------------------------------------------------------------- drawing helpers
static func glyph(c: CanvasItem, p: Vector2, kind: String, col: Color, s := 11.0) -> void:
	c.draw_circle(p, s + 2.5, Color(0, 0, 0, 0.75))
	c.draw_circle(p, s, col)
	var ch: String = {"police": "P", "hideout": "H", "bank": "$", "armory": "A", "garage": "G", "gas": "F", "tower": "T",
		"ranch": "R", "lake": "~", "lookout": "V", "zone": "•", "car": "C", "dest": "!"}.get(kind, "?")
	Game.dtext(c, ch, p + Vector2(0, s * 0.45), int(s * 1.25), Color(0.04, 0.04, 0.06), Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)


static func road_color(kind: String) -> Color:
	return {"highway": Color(0.98, 0.78, 0.25), "road": Color(0.92, 0.92, 0.92), "dirt": Color(0.78, 0.6, 0.42)}.get(kind, Color.WHITE)


func _draw() -> void:
	var sz := size
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.03, 0.06, 0.1, 0.97))
	var C = world.country
	var gps = world.gps
	if tex and C:
		var a := w2s(Vector2(C.x0, C.z0))
		var b := w2s(Vector2(C.x0 + C.nx * C.cell, C.z0 + C.nz * C.cell))
		draw_texture_rect(tex, Rect2(a, b - a), false)
	var lw := clampf(zoom * 14.0, 2.0, 9.0)
	# city road
	var pts := PackedVector2Array()
	for i in range(0, world.route.size(), 2):
		pts.append(w2s(Vector2(world.route[i].x, world.route[i].z)))
	draw_polyline(pts, Color(0.1, 0.1, 0.12), lw + 3.0, true)
	draw_polyline(pts, Color(0.85, 0.86, 0.88), lw, true)
	if C:
		for rd in C.roads:
			var rp := PackedVector2Array()
			var src: PackedVector3Array = rd.pts
			for k in range(0, src.size(), 2):
				rp.append(w2s(Vector2(src[k].x, src[k].z)))
			rp.append(w2s(Vector2(src[-1].x, src[-1].z)))
			draw_polyline(rp, Color(0.1, 0.1, 0.12), lw + 2.0, true)
			draw_polyline(rp, road_color(rd.kind), lw * (1.2 if rd.kind == "highway" else 0.85), true)
	# GPS route
	if gps and gps.dest_set and gps.path_pts.size() > 1:
		var gp := PackedVector2Array()
		for p in gps.path_pts:
			gp.append(w2s(Vector2(p.x, p.z)))
		draw_polyline(gp, Color(0.85, 0.25, 0.95), lw + 2.0, true)
	# zone names
	if C and zoom < 1.2:
		for p in C.places:
			if p.kind == "zone":
				Game.dtext(self, p.name, w2s(Vector2(p.x, p.z)) + Vector2(0, -30), 20 if zoom > 0.15 else 15, Color(1, 1, 1, 0.75), Game.font_wide, HORIZONTAL_ALIGNMENT_CENTER)
		for cz in C.info.city_zones:
			var mid: Vector3 = world.route[clampi((int(cz[0]) + int(cz[1])) / 2, 0, world.route.size() - 1)]
			Game.dtext(self, cz[2], w2s(Vector2(mid.x, mid.z)) + Vector2(0, -22), 17 if zoom > 0.15 else 13, Color(1, 1, 1, 0.6), Game.font_wide, HORIZONTAL_ALIGNMENT_CENTER)
	# places
	if gps:
		var mouse := get_local_mouse_position()
		for pl in gps.places:
			if pl.kind == "zone":
				continue
			var sp := w2s(Vector2(pl.pos.x, pl.pos.z))
			glyph(self, sp, pl.kind, pl.color, 12.0)
			if zoom > 0.45 or sp.distance_to(mouse) < 18.0:
				Game.dtext(self, pl.name, sp + Vector2(0, -20), 17, Color.WHITE, Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
		if world.last_car and is_instance_valid(world.last_car) and world.last_car != world.active_car:
			var cp := w2s(Vector2(world.last_car.global_position.x, world.last_car.global_position.z))
			glyph(self, cp, "car", Color(0.95, 0.95, 0.95), 10.0)
			if cp.distance_to(mouse) < 18.0:
				Game.dtext(self, "YOUR CAR", cp + Vector2(0, -18), 17, Color.WHITE, Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
		if gps.dest_set:
			var dp := w2s(Vector2(gps.dest.x, gps.dest.z))
			draw_line(dp, dp + Vector2(0, -30), Color(0, 0, 0, 0.8), 4.0)
			draw_line(dp, dp + Vector2(0, -30), Color(0.95, 0.3, 1.0), 2.0)
			glyph(self, dp + Vector2(0, -36), "dest", Color(0.95, 0.3, 1.0), 11.0)
	# other players
	if world.net:
		for r in world.net.remotes.values():
			if is_instance_valid(r):
				var rp2 := w2s(Vector2(r.global_position.x, r.global_position.z))
				var rc := Game.C_BLUE if r.team == "cops" else Game.C_RED
				draw_circle(rp2, 7.0, Color(0, 0, 0, 0.8))
				draw_circle(rp2, 5.0, rc.lightened(0.3))
	# you
	var pp: Vector3 = hud._focus_pos()
	var fy: float = world.active_car.rotation.y if world.active_car else world.player.rotation.y
	hud._arrow(self, w2s(Vector2(pp.x, pp.z)), atan2(-sin(fy), -cos(fy)), 13.0, Game.C_CYAN if fmod(t, 0.8) < 0.55 else Color.WHITE)
	# frame, title, help, scale bar, destination info
	draw_rect(Rect2(0, 0, sz.x, 100), Color(0, 0, 0, 0.55))
	Game.dtext(self, "LOS ANGELES COUNTY", Vector2(40, 66), 40, Color.WHITE, Game.font_wide)
	Game.dtext(self, "CLICK  SET DESTINATION    RIGHT CLICK  CLEAR    WHEEL / + -  ZOOM    DRAG / WASD  MOVE    F11  CLOSE", Vector2(sz.x - 40, 62), 17, Game.C_DIM, Game.font_bold, HORIZONTAL_ALIGNMENT_RIGHT)
	var bar_m := 500.0 if zoom < 0.6 else 100.0
	var bar_px := bar_m * zoom
	var bp := Vector2(sz.x - 60 - bar_px, sz.y - 40)
	draw_line(bp, bp + Vector2(bar_px, 0), Color.WHITE, 3.0)
	draw_line(bp, bp + Vector2(0, -8), Color.WHITE, 2.0)
	draw_line(bp + Vector2(bar_px, 0), bp + Vector2(bar_px, -8), Color.WHITE, 2.0)
	Game.dtext(self, "%d m" % int(bar_m), bp + Vector2(bar_px * 0.5, -12), 16, Color.WHITE, Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	if gps and gps.dest_set:
		var r := Rect2(30, sz.y - 150, 560, 120)
		draw_rect(r, Color(0.03, 0.05, 0.09, 0.92))
		draw_rect(Rect2(r.position, Vector2(5, r.size.y)), Color(0.85, 0.25, 0.95))
		Game.dtext(self, "DESTINATION:  " + gps.dest_name, r.position + Vector2(22, 36), 22, Color.WHITE, Game.font_bold)
		Game.dtext(self, "%s by road" % fmt_dist(gps.remaining), r.position + Vector2(22, 70), 20, Color(0.9, 0.8, 1.0), Game.font_semi)
		Game.dtext(self, "about %s by car  •  %s on foot" % [fmt_time(gps.eta(true)), fmt_time(gps.eta(false))], r.position + Vector2(22, 100), 18, Game.C_DIM, Game.font_semi)


static func fmt_dist(m: float) -> String:
	return ("%.1f km" % (m / 1000.0)) if m >= 1000.0 else ("%d m" % int(m))


static func fmt_time(s: float) -> String:
	if s < 60.0:
		return "%d s" % int(s)
	if s < 3600.0:
		return "%d min" % int(round(s / 60.0))
	return "%d h %d min" % [int(s / 3600.0), int(fmod(s, 3600.0) / 60.0)]


# ---------------------------------------------------------------- minimap
func draw_minimap(c: Control) -> void:
	var sz := c.size
	var mc := sz * 0.5 + Vector2(0, 30)
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.05, 0.08, 0.1, 0.92))
	var pp: Vector3 = hud._focus_pos()
	var north_up := int(Game.settings.get("map_north", 0)) == 1
	var h: float = 0.0 if north_up else hud._heading()
	var sc := MM_PX_PER_M * (0.62 if world.active_car and absf(world.active_car.speed) > 15.0 else 1.0)
	var C = world.country
	var gps = world.gps
	c.draw_set_transform(mc, -h, Vector2(sc, sc))
	if tex and C:
		c.draw_texture_rect(tex, Rect2(C.x0 - pp.x, C.z0 - pp.z, C.nx * C.cell, C.nz * C.cell), false)
	var reach := 700.0
	var rpts := PackedVector2Array()
	for i in world.route.size():
		var p: Vector3 = world.route[i]
		if absf(p.x - pp.x) < reach and absf(p.z - pp.z) < reach:
			rpts.append(Vector2(p.x - pp.x, p.z - pp.z))
		else:
			if rpts.size() > 1:
				c.draw_polyline(rpts, Color(0.82, 0.83, 0.86), 9.0 / sc, true)
			rpts = PackedVector2Array()
	if rpts.size() > 1:
		c.draw_polyline(rpts, Color(0.82, 0.83, 0.86), 9.0 / sc, true)
	if C:
		for rd in C.roads:
			var src: PackedVector3Array = rd.pts
			var seg := PackedVector2Array()
			for k in src.size():
				var p: Vector3 = src[k]
				if absf(p.x - pp.x) < reach and absf(p.z - pp.z) < reach:
					seg.append(Vector2(p.x - pp.x, p.z - pp.z))
				else:
					if seg.size() > 1:
						c.draw_polyline(seg, road_color(rd.kind), 7.0 / sc, true)
					seg = PackedVector2Array()
			if seg.size() > 1:
				c.draw_polyline(seg, road_color(rd.kind), 7.0 / sc, true)
	if gps and gps.dest_set and gps.path_pts.size() > 1:
		var gp := PackedVector2Array()
		for p in gps.path_pts:
			if absf(p.x - pp.x) < reach * 1.5 and absf(p.z - pp.z) < reach * 1.5:
				gp.append(Vector2(p.x - pp.x, p.z - pp.z))
		if gp.size() > 1:
			c.draw_polyline(gp, Color(0.85, 0.25, 0.95), 7.0 / sc, true)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var to_screen := func(wx: float, wz: float) -> Vector2:
		return mc + Vector2(wx - pp.x, wz - pp.z).rotated(-h) * sc
	var border := Rect2(Vector2(14, 14), sz - Vector2(28, 28))
	var clampb := func(p: Vector2) -> Vector2:
		if border.has_point(p):
			return p
		var d := p - mc
		var k := minf(absf((border.size.x * 0.5) / maxf(absf(d.x), 0.01)), absf((mc.y - 14.0) / maxf(absf(d.y), 0.01)))
		return (mc + d * minf(k, 1.0)).clamp(border.position, border.end)
	if gps:
		for pl in gps.places:
			if pl.kind == "zone":
				continue
			var important: bool = pl.kind in ["police", "hideout", "bank"]
			var sp: Vector2 = to_screen.call(pl.pos.x, pl.pos.z)
			if important:
				sp = clampb.call(sp)
			elif not border.has_point(sp):
				continue
			glyph(c, sp, pl.kind, pl.color, 9.0)
		if gps.dest_set:
			glyph(c, clampb.call(to_screen.call(gps.dest.x, gps.dest.z)), "dest", Color(0.95, 0.3, 1.0), 10.0)
	# cars nearby
	for car in world.cars:
		if is_instance_valid(car) and car != world.active_car and car.global_position.distance_to(pp) < 200.0:
			var cp: Vector2 = to_screen.call(car.global_position.x, car.global_position.z)
			c.draw_rect(Rect2(cp - Vector2(3, 3), Vector2(6, 6)), Color(0.5, 0.5, 0.5) if car.wrecked else Color(0.95, 0.95, 0.95, 0.8))
	if world.net:
		for r in world.net.remotes.values():
			if is_instance_valid(r) and r.team == world.team:
				var rp: Vector2 = clampb.call(to_screen.call(r.global_position.x, r.global_position.z))
				var rcol := Game.C_BLUE if r.team == "cops" else Game.C_RED
				c.draw_circle(rp, 6.0, Color(0, 0, 0, 0.8))
				c.draw_circle(rp, 4.5, rcol.lightened(0.3) if not r.dead else Color(0.5, 0.5, 0.5))
	for n in world.npcs:
		if is_instance_valid(n) and n.role == "guard" and n.state == 4:
			c.draw_circle(to_screen.call(n.global_position.x, n.global_position.z), 4.0, Color(1, 0.2, 0.2))
	var fy: float = world.active_car.rotation.y if world.active_car else world.player.rotation.y
	var face_h := atan2(-sin(fy), -cos(fy))
	hud._arrow(c, mc, face_h - h, 11.0, Color.WHITE)
	var npos: Vector2 = clampb.call(mc + Vector2(0, -1000).rotated(-h))
	c.draw_circle(npos, 10.0, Color(0, 0, 0, 0.75))
	Game.dtext(c, "N", npos + Vector2(0, 6), 15, Color.WHITE, Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.9), false, 3.0)
