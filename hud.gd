extends CanvasLayer
# Vorn interface: Arabic HUD, menus and multi-touch controls.
# Everything is drawn by code on one full-screen canvas, so it adapts to any
# screen shape (phones with a notch, tablets, desktop) and never depends on GUI focus.

const AMBER := Color(1.0, 0.78, 0.30)
const GREEN := Color(0.55, 0.95, 0.5)
const RED := Color(0.96, 0.33, 0.27)
const INK := Color(0.035, 0.045, 0.06)
const WHITE := Color(1, 1, 1)
const LTR := TextServer.DIRECTION_LTR
const RTL := TextServer.DIRECTION_RTL
const TOUCH_SENS := 0.0030
const JOY_R := 135.0
const JOY_TRAVEL := 105.0
const SB_H := 680.0

var main
var touch_mode := false
var pad: Control
var f_md: Font
var f_bd: Font
var f_bk: Font
var V := Vector2(1920, 1080)
var sx := 28.0   # side margin (grows with the notch)
var st := 0.0    # top inset
var sb := 0.0    # bottom inset (home indicator)
var inset_override := -1.0
var sens := 1.0
var paused := false
var show_score := false
var hot: Array = []     # tap zones of menus/panels, rebuilt on every draw: [Rect2, id]
var held := {}          # pointer index -> {"role": ..., "id": ...}
var down := {}          # ids currently pressed (for visual feedback)
var btn := {}           # in-game round buttons: id -> [centre, radius]
var joy_c := Vector2.ZERO
var joy_raw := Vector2.ZERO
var joy_v := Vector2.ZERO
var joy_on := false
var dmg := 0.0
var hit_from = null
var hit_t := 0.0
var clock := 0.0
var sbox := {}

func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	touch_mode = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	for a in OS.get_cmdline_user_args():
		if a == "--touch": touch_mode = true
		if a.begins_with("--inset="): inset_override = float(a.split("=")[1])
	f_md = mkfont(600)
	f_bd = mkfont(800)
	f_bk = mkfont(900)
	pad = Control.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.layout_direction = Control.LAYOUT_DIRECTION_LTR
	add_child(pad)
	pad.draw.connect(_draw_all)
	var cf := ConfigFile.new()
	if cf.load("user://vorn.cfg") == OK: sens = clamp(float(cf.get_value("input", "sens", 1.0)), 0.4, 2.5)

func mkfont(weight: int) -> Font:
	var fv := FontVariation.new()
	fv.base_font = load("res://fonts/Cairo.ttf")
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return fv

func _notification(what: int) -> void:
	# pause when the app goes to the background on a phone
	if main != null and main.mobile and (what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT):
		set_pause(true)

# ------------------------------------------------------------------ STATE
func modal() -> bool:
	return paused or main.phase == "menu" or main.phase == "match" or (main.player != null and main.player.buy_open)

func set_pause(b: bool) -> void:
	if main.player == null or main.phase == "menu" or main.phase == "match": b = false
	paused = b
	get_tree().paused = b
	if b: _release_game()

func set_sens(v: float) -> void:
	sens = clamp(snappedf(v, 0.1), 0.4, 2.5)
	var cf := ConfigFile.new()
	cf.set_value("input", "sens", sens)
	cf.save("user://vorn.cfg")

func on_hurt(attacker) -> void:
	dmg = 0.3
	hit_from = attacker
	hit_t = 1.2 if attacker != null else 0.0
	if touch_mode and main.mobile: Input.vibrate_handheld(40)

func _insets() -> void:
	sx = 28.0
	st = 0.0
	sb = 0.0
	if inset_override >= 0.0:
		sx = 28.0 + inset_override
		sb = 40.0 if inset_override > 0.0 else 0.0
		return
	if not main.mobile: return
	var win := Vector2(DisplayServer.window_get_size())
	if win.x < 1.0 or win.y < 1.0: return
	var safe := DisplayServer.get_display_safe_area()
	var k: float = V.x / win.x
	var l: float = safe.position.x * k
	var r: float = (win.x - safe.end.x) * k
	sx = 28.0 + clamp(max(l, r), 0.0, 200.0)
	st = clamp(safe.position.y * k, 0.0, 120.0)
	sb = clamp((win.y - safe.end.y) * k, 0.0, 120.0)

func _layout() -> void:
	var r: float = V.x - sx
	var h: float = V.y
	btn = {
		"fire": [Vector2(r - 300, h - 300), 104.0],
		"jump": [Vector2(r - 112, h - 430), 66.0],
		"crouch": [Vector2(r - 112, h - 240), 62.0],
		"reload": [Vector2(r - 505, h - 170), 60.0],
		"scope": [Vector2(r - 525, h - 345), 60.0],
		"he": [Vector2(r - 470, h - 520), 56.0],
		"use": [Vector2(r - 290, h - 560), 74.0],
		"buy": [Vector2(r - 112, h - 640), 60.0],
		"pause": [Vector2(r - 62, 66 + st), 44.0],
		"score": [Vector2(r - 168, 66 + st), 44.0],
	}
	if not joy_on: joy_c = Vector2(sx + 250, h - 270)

func slot_rect(k: int) -> Rect2:
	var w := 196.0
	var x0: float = V.x * 0.5 - (w * 3 + 24) * 0.5
	return Rect2(x0 + k * (w + 12), V.y - sb * 0.6 - 100, w, 80)

func _process(dt: float) -> void:
	clock += dt
	V = pad.size
	_insets()
	_layout()
	dmg = max(0.0, dmg - dt * 1.2)
	hit_t = max(0.0, hit_t - dt)
	var p = main.player
	if p != null:
		if p.buy_open and not p.can_buy(): p.buy_open = false
		if modal() or not p.alive: _release_game()
		p.t_move = joy_v if joy_on else Vector2.ZERO
	if not touch_mode and not main.mobile and main.test == "":
		var want: int = Input.MOUSE_MODE_VISIBLE if modal() else Input.MOUSE_MODE_CAPTURED
		if Input.mouse_mode != want: Input.mouse_mode = want
	pad.queue_redraw()

# ------------------------------------------------------------------ INPUT
func _input(ev: InputEvent) -> void:
	# the event is marked as handled first: a tap may reload the scene and take this node out of the tree
	if ev is InputEventScreenTouch:
		get_viewport().set_input_as_handled()
		touch_mode = true
		if ev.pressed: _down(ev.index, ev.position)
		else: _up(ev.index, ev.position)
	elif ev is InputEventScreenDrag:
		get_viewport().set_input_as_handled()
		_drag(ev.index, ev.position, ev.relative)
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.device != InputEvent.DEVICE_ID_EMULATION:
		if modal() or held.has(-1):
			get_viewport().set_input_as_handled()
			if ev.pressed: _down(-1, ev.position)
			else: _up(-1, ev.position)
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		_key(ev)

func _key(ev: InputEventKey) -> void:
	var p = main.player
	if p == null or main.phase == "menu" or main.phase == "match": return
	var kc: int = ev.physical_keycode
	if kc == KEY_ESCAPE:
		if p.buy_open and not paused: p.buy_open = false
		else: set_pause(not paused)
		get_viewport().set_input_as_handled()
	elif paused:
		get_viewport().set_input_as_handled()
	elif p.buy_open:
		if kc == KEY_B: p.buy_open = false
		elif kc >= KEY_1 and kc <= KEY_5: p.buy(kc - KEY_1)
		get_viewport().set_input_as_handled()

func _hit(id: String, pos: Vector2) -> bool:
	var b: Array = btn[id]
	return pos.distance_to(b[0]) <= b[1] + 14.0

func _vis(id: String) -> bool:
	var p = main.player
	match id:
		"scope": return p.cur == "sniper"
		"he": return p.he > 0
		"use": return p.can_plant() or p.can_defuse()
		"buy": return p.can_buy()
	return true

func _down(i: int, pos: Vector2) -> void:
	# menus and panels first (the last drawn zone is on top)
	for k in range(hot.size() - 1, -1, -1):
		var z: Array = hot[k]
		if z[0].has_point(pos):
			held[i] = {"role": "ui", "id": z[1]}
			down[z[1]] = true
			return
	var p = main.player
	if modal() or p == null or i < 0: return
	for id in ["pause", "score"]:
		if _hit(id, pos):
			_tap(id, i)
			return
	if not p.alive: return
	for id in ["fire", "use", "jump", "crouch", "reload", "scope", "he", "buy"]:
		if _vis(id) and _hit(id, pos):
			_tap(id, i)
			return
	for k in 3:
		if slot_rect(k).grow(8).has_point(pos):
			_tap("w%d" % (k + 1), i)
			return
	if not joy_on and pos.x < V.x * 0.42 and pos.y > V.y * 0.26:
		joy_on = true
		joy_c = Vector2(clamp(pos.x, sx + JOY_R * 0.8, V.x * 0.42), clamp(pos.y, V.y * 0.26, V.y - JOY_R * 0.7))
		joy_raw = Vector2.ZERO
		joy_v = Vector2.ZERO
		held[i] = {"role": "joy"}
	else:
		held[i] = {"role": "look"}

func _tap(id: String, i: int) -> void:
	var p = main.player
	down[id] = true
	held[i] = {"role": "tap", "id": id}
	match id:
		"fire":
			held[i]["role"] = "fire"
			p.t_fire = true
			if not main.W[p.cur].auto: p.try_fire()
		"jump":
			held[i]["role"] = "jump"
			p.t_jump = true
		"use":
			held[i]["role"] = "use"
			p.t_use = true
		"crouch": p.t_crouch = not p.t_crouch
		"reload": p.reload()
		"scope": p.toggle_scope()
		"he": p.throw_he()
		"buy": p.buy_open = p.can_buy()
		"pause": set_pause(true)
		"score": show_score = not show_score
		"w1":
			if p.primary != "": p.equip(p.primary)
		"w2": p.equip("pistol")
		"w3": p.equip("knife")

func _drag(i: int, pos: Vector2, rel: Vector2) -> void:
	if not held.has(i): return
	var role: String = held[i]["role"]
	if role == "joy":
		var d: Vector2 = (pos - joy_c) / JOY_TRAVEL
		if d.length() > 1.0: d = d.normalized()
		joy_raw = d
		var m: float = d.length()
		joy_v = Vector2.ZERO if m < 0.14 else d / m * ((m - 0.14) / 0.86)
	elif role == "look" or role == "fire" or role == "jump" or role == "use":
		var p = main.player
		if p != null and p.alive and not modal():
			var k: float = TOUCH_SENS * sens * lerp(1.0, 0.55, float(p.aim_assist))
			p.look(Vector2(rel.x, rel.y * 0.8), k)

func _up(i: int, pos: Vector2) -> void:
	if not held.has(i): return
	var h: Dictionary = held[i]
	held.erase(i)
	var p = main.player
	match h["role"]:
		"ui":
			down.erase(h["id"])
			for z in hot:
				if z[1] == h["id"] and z[0].grow(14).has_point(pos):
					_ui(h["id"])
					break
		"joy":
			joy_on = false
			joy_raw = Vector2.ZERO
			joy_v = Vector2.ZERO
		"fire":
			down.erase("fire")
			if p != null: p.t_fire = false
		"jump":
			down.erase("jump")
			if p != null: p.t_jump = false
		"use":
			down.erase("use")
			if p != null: p.t_use = false
		"tap":
			down.erase(h["id"])

func _release_game() -> void:
	# drop every gameplay touch (a menu opened, the player died, the app lost focus)
	for i in held.keys():
		var role: String = held[i]["role"]
		if role != "ui" and role != "tap": held.erase(i)
	for id in ["fire", "jump", "use"]: down.erase(id)
	joy_on = false
	joy_raw = Vector2.ZERO
	joy_v = Vector2.ZERO
	var p = main.player
	if p != null:
		p.t_fire = false
		p.t_jump = false
		p.t_use = false
		p.trigger = false

func _ui(id: String) -> void:
	var p = main.player
	if id.begins_with("buy_"):
		if p != null:
			if id == "buy_close": p.buy_open = false
			else: p.buy(int(id.substr(4)))
		return
	main.play("switch", -12)
	match id:
		"team_ct": main.choose_team("ct")
		"team_t": main.choose_team("t")
		"again", "tomenu": main.restart()
		"resume": set_pause(false)
		"sens-": set_sens(sens - 0.1)
		"sens+": set_sens(sens + 0.1)
		"quit": get_tree().quit()

# ------------------------------------------------------------------ DRAW HELPERS
func rr(r: Rect2, col: Color, rad := 16.0, border := Color(0, 0, 0, 0), bw := 0.0) -> void:
	var key := "%s|%d|%s|%d" % [col.to_html(), int(rad), border.to_html(), int(bw)]
	var s: StyleBoxFlat = sbox.get(key)
	if s == null:
		s = StyleBoxFlat.new()
		s.bg_color = col
		s.set_corner_radius_all(int(rad))
		s.corner_detail = 10
		s.anti_aliasing = true
		if bw > 0.0:
			s.set_border_width_all(int(bw))
			s.border_color = border
		sbox[key] = s
	pad.draw_style_box(s, r)

func tw(s: String, size: int, font: Font = null) -> float:
	if font == null: font = f_bd
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

func txt(pos: Vector2, s: String, size: int, col := WHITE, align := 0, font: Font = null, outline := 0, dir := TextServer.DIRECTION_AUTO) -> void:
	# pos.y is the visual middle of the line. align: 0 starts at pos.x, 1 centred on it, 2 ends at it
	if font == null: font = f_bd
	var x: float = pos.x
	if align != 0:
		var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, TextServer.JUSTIFICATION_NONE, dir).x
		x -= w * (0.5 if align == 1 else 1.0)
	var q := Vector2(x, pos.y + size * 0.34)
	if outline > 0: pad.draw_string_outline(font, q, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(0, 0, 0, 0.8 * col.a), TextServer.JUSTIFICATION_NONE, dir)
	pad.draw_string(font, q, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col, TextServer.JUSTIFICATION_NONE, dir)

func ibtn(r: Rect2, label: String, id: String, primary := false, size := 36) -> void:
	var on: bool = down.has(id)
	if primary: rr(r, AMBER.lightened(0.25) if on else AMBER, r.size.y * 0.5)
	else: rr(r, Color(1, 1, 1, 0.20 if on else 0.09), r.size.y * 0.5, Color(1, 1, 1, 0.22), 2)
	txt(r.get_center(), label, size, INK if primary else WHITE, 1, f_bk if primary else f_bd)
	hot.append([r, id])

func cbtn(id: String, icon: String, label := "", active := false) -> void:
	var b: Array = btn[id]
	var c: Vector2 = b[0]
	var on: bool = down.has(id)
	var r: float = b[1] * (1.07 if on else 1.0)
	pad.draw_circle(c, r, Color(AMBER, 0.42) if on else (Color(AMBER, 0.20) if active else Color(INK, 0.42)))
	pad.draw_arc(c, r, 0, TAU, 72, Color(AMBER, 0.95) if (on or active) else Color(1, 1, 1, 0.55), 3.0, true)
	var col := Color(1, 1, 1, 0.95)
	if label == "":
		_icon(icon, c, b[1] * 0.5, col)
	else:
		_icon(icon, c - Vector2(0, b[1] * 0.20), b[1] * 0.40, col)
		txt(c + Vector2(0, b[1] * 0.50), label, int(b[1] * 0.36), col, 1, f_bd)

func _icon(n: String, c: Vector2, s: float, col: Color) -> void:
	match n:
		"fire":
			# a cartridge pointing up-right: rim, casing and bullet
			var d := Vector2(0.7071, -0.7071)
			var nv := Vector2(0.7071, 0.7071)
			var k: float = s * 1.12
			var parts := [
				[[-1.02, -0.37], [-0.90, -0.37], [-0.90, 0.37], [-1.02, 0.37]],
				[[-0.84, -0.31], [0.16, -0.31], [0.16, 0.31], [-0.84, 0.31]],
				[[0.25, -0.30], [0.50, -0.28], [0.74, -0.20], [0.94, -0.09], [1.04, 0.0], [0.94, 0.09], [0.74, 0.20], [0.50, 0.28], [0.25, 0.30]],
			]
			for part in parts:
				var pts := PackedVector2Array()
				for q in part: pts.append(c + d * (q[0] * k) + nv * (q[1] * k))
				pad.draw_colored_polygon(pts, col)
				pts.append(pts[0])
				pad.draw_polyline(pts, col, 1.5, true)
		"aim":
			pad.draw_arc(c, s * 0.62, 0, TAU, 40, col, 5.0, true)
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				pad.draw_line(c + d * s * 0.30, c + d * s * 1.02, col, 5.0, true)
			pad.draw_circle(c, 5.0, col)
		"jump", "crouch":
			var sg: float = 1.0 if n == "jump" else -1.0
			for k in 2:
				var o := Vector2(0, (-0.36 + k * 0.52) * s)
				pad.draw_polyline(PackedVector2Array([c + o + Vector2(-s * 0.62, s * 0.26 * sg), c + o + Vector2(0, -s * 0.26 * sg), c + o + Vector2(s * 0.62, s * 0.26 * sg)]), col, 6.0, true)
		"reload":
			var a0: float = deg_to_rad(-55.0)
			pad.draw_arc(c, s * 0.64, a0, deg_to_rad(215.0), 32, col, 5.5, true)
			var e: Vector2 = c + Vector2(cos(a0), sin(a0)) * s * 0.64
			var nrm := Vector2(cos(a0), sin(a0))
			var tng := Vector2(sin(a0), -cos(a0))
			pad.draw_colored_polygon(PackedVector2Array([e + tng * s * 0.42, e + nrm * s * 0.30 - tng * s * 0.06, e - nrm * s * 0.30 - tng * s * 0.06]), col)
		"he":
			pad.draw_circle(c + Vector2(0, s * 0.20), s * 0.58, col)
			pad.draw_rect(Rect2(c + Vector2(-s * 0.20, -s * 0.66), Vector2(s * 0.40, s * 0.34)), col)
			pad.draw_line(c + Vector2(s * 0.18, -s * 0.56), c + Vector2(s * 0.66, -s * 0.18), col, 5.0, true)
		"bomb":
			pad.draw_rect(Rect2(c + Vector2(-s * 0.80, -s * 0.30), Vector2(s * 1.60, s * 0.86)), col)
			pad.draw_rect(Rect2(c + Vector2(-s * 0.56, -s * 0.10), Vector2(s * 0.62, s * 0.36)), Color(INK, col.a))
			pad.draw_arc(c + Vector2(-s * 0.26, -s * 0.30), s * 0.26, PI, TAU, 12, col, 4.0, true)
			pad.draw_arc(c + Vector2(s * 0.34, -s * 0.30), s * 0.22, PI, TAU, 12, col, 4.0, true)
		"buy":
			txt(c, "$", int(s * 2.1), col, 1, f_bk, 0, LTR)
		"pause":
			pad.draw_rect(Rect2(c + Vector2(-s * 0.55, -s * 0.62), Vector2(s * 0.36, s * 1.24)), col)
			pad.draw_rect(Rect2(c + Vector2(s * 0.19, -s * 0.62), Vector2(s * 0.36, s * 1.24)), col)
		"score":
			for k in 3:
				var y: float = c.y + (k - 1) * s * 0.52
				pad.draw_circle(Vector2(c.x + s * 0.62, y), 4.0, col)
				pad.draw_line(Vector2(c.x - s * 0.72, y), Vector2(c.x + s * 0.32, y), col, 5.0, true)
		"x":
			pad.draw_line(c + Vector2(-s, -s), c + Vector2(s, s), col, 6.0, true)
			pad.draw_line(c + Vector2(-s, s), c + Vector2(s, -s), col, 6.0, true)
		"minus", "plus":
			pad.draw_line(c - Vector2(s, 0), c + Vector2(s, 0), col, 7.0, true)
			if n == "plus": pad.draw_line(c - Vector2(0, s), c + Vector2(0, s), col, 7.0, true)
		"heart":
			pad.draw_rect(Rect2(c + Vector2(-s * 0.22, -s * 0.62), Vector2(s * 0.44, s * 1.24)), col)
			pad.draw_rect(Rect2(c + Vector2(-s * 0.62, -s * 0.22), Vector2(s * 1.24, s * 0.44)), col)
		"shield":
			pad.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.56, -s * 0.60), c + Vector2(s * 0.56, -s * 0.60), c + Vector2(s * 0.56, s * 0.08), c + Vector2(0, s * 0.70), c + Vector2(-s * 0.56, s * 0.08)]), col)

# ------------------------------------------------------------------ DRAW
func _draw_all() -> void:
	hot.clear()
	if sbox.size() > 300: sbox.clear()
	if btn.is_empty():
		V = pad.size
		_layout()
	var p = main.player
	if main.phase == "menu" or p == null:
		_draw_menu()
		return
	if main.phase == "match":
		_draw_match()
		return
	_draw_cross(p)
	if dmg > 0.0: pad.draw_rect(Rect2(Vector2.ZERO, V), Color(0.7, 0, 0, dmg))
	_draw_hit(p)
	_draw_radar(p)
	_draw_top()
	_draw_feed()
	_draw_status(p)
	_draw_msgs(p)
	if touch_mode and not modal(): _draw_touch(p)
	if paused: _draw_pause()
	elif p.buy_open: _draw_buy(p)
	elif show_score or (not touch_mode and Input.is_physical_key_pressed(KEY_TAB)): _draw_scoreboard((V.y - SB_H) * 0.5)

func _draw_cross(p) -> void:
	if not p.alive: return
	var c: Vector2 = V * 0.5
	if p.scoped:
		pad.draw_rect(Rect2(0, c.y - 1, V.x, 2), Color.BLACK)
		pad.draw_rect(Rect2(c.x - 1, 0, 2, V.y), Color.BLACK)
		pad.draw_arc(c, 520, 0, TAU, 96, Color.BLACK, 6)
		pad.draw_arc(c, 1500, 0, TAU, 96, Color.BLACK, 1960)
		return
	var g: float = 5.0 + p.cur_spread * 900.0
	var col := Color(0.3, 1, 0.4)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		pad.draw_line(c + d * (g - 1), c + d * (g + 15), Color.BLACK, 6)
		pad.draw_line(c + d * g, c + d * (g + 14), col, 3)
	if p.hitmark > 0:
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			pad.draw_line(c + d * 8, c + d * 16, Color(1, 1, 1, p.hitmark * 4), 3)

func _draw_hit(p) -> void:
	# red arc pointing at whoever just hit the player
	if hit_t <= 0.0 or hit_from == null or not is_instance_valid(hit_from) or not p.alive: return
	var to: Vector3 = hit_from.global_position - p.global_position
	var bs: Basis = p.global_transform.basis
	var ang: float = atan2(to.dot(bs.x), to.dot(-bs.z)) - PI * 0.5
	pad.draw_arc(V * 0.5, 190, ang - 0.36, ang + 0.36, 24, Color(1, 0.15, 0.1, clamp(hit_t, 0.0, 1.0) * 0.85), 14.0, true)

func _draw_radar(p) -> void:
	var o := Vector2(sx + 24, 24 + st)
	rr(Rect2(o, Vector2(260, 200)), Color(INK, 0.50), 12, Color(1, 1, 1, 0.16), 2)
	var f := func(q: Vector3) -> Vector2: return o + Vector2((q.x + 37.0) / 74.0 * 260.0, (q.z + 27.0) / 54.0 * 200.0)
	for bd in main.BUILDINGS:
		var a: Vector2 = f.call(Vector3(bd[0], 0, bd[2]))
		var b: Vector2 = f.call(Vector3(bd[1], 0, bd[3]))
		pad.draw_rect(Rect2(a, b - a), Color(0.8, 0.7, 0.5, 0.5))
	for sn in main.SITES:
		var sc: Vector2 = f.call(main.NODES[main.SITES[sn]])
		pad.draw_circle(sc, 13, Color(0.9, 0.2, 0.1, 0.55))
		txt(sc - Vector2(0, 3), main.SITE_AR[sn], 19, WHITE, 1, f_bk)
	for a in main.actors:
		if not a.alive or a.team != p.team: continue
		var q: Vector2 = f.call(a.global_position)
		if a.is_player:
			var fw: Vector3 = -a.global_transform.basis.z
			var d := Vector2(fw.x * 260.0 / 74.0, fw.z * 200.0 / 54.0).normalized()
			var n := Vector2(-d.y, d.x)
			pad.draw_colored_polygon(PackedVector2Array([q + d * 11, q - d * 7 + n * 7, q - d * 7 - n * 7]), WHITE)
		else:
			pad.draw_circle(q, 4.5, main.team_col(a.team))
	if main.bomb != null:
		var bq: Vector2 = f.call(main.bomb.global_position)
		pad.draw_circle(bq, 6.0 + 2.0 * sin(clock * 8.0), Color(1, 0.1, 0.1))

func _draw_top() -> void:
	var cx: float = V.x * 0.5
	var y: float = 14.0 + st
	var planted: bool = main.phase == "planted"
	var tt: float = main.bomb_t if planted else main.round_time
	rr(Rect2(cx - 96, y, 192, 68), Color(INK, 0.62), 16, Color(RED, 0.9) if planted else Color(1, 1, 1, 0.16), 2)
	if planted:
		_icon("bomb", Vector2(cx - 50, y + 36), 20, Color(1, 0.4, 0.35, 0.65 + 0.35 * sin(clock * 10.0)))
		txt(Vector2(cx + 30, y + 34), "%d" % int(ceil(tt)), 44, Color(1, 0.5, 0.45), 1, f_bk, 0, LTR)
	else:
		var sec: int = int(max(tt, 0.0))
		txt(Vector2(cx, y + 34), "%d:%02d" % [sec / 60, sec % 60], 44, WHITE, 1, f_bk, 0, LTR)
	for k in 2:
		var tm: String = ["ct", "t"][k]
		var sg: float = -1.0 if k == 0 else 1.0
		var col: Color = main.team_col(tm)
		var bx: float = cx + sg * 149.0
		rr(Rect2(bx - 43, y, 86, 68), Color(col, 0.30), 16, Color(col, 0.75), 2)
		txt(Vector2(bx, y + 34), str(main.score[tm]), 46, WHITE, 1, f_bk, 0, LTR)
		var ex: float = bx + sg * 59.0
		txt(Vector2(ex, y + 19), main.TEAM_NAME[tm], 25, col, 2 if k == 0 else 0, f_bd, 6)
		var alive: int = main.alive_n(tm)
		for i in 5:
			pad.draw_circle(Vector2(ex + sg * (8 + i * 22), y + 53), 7.0, col if i < alive else Color(1, 1, 1, 0.2))

func _draw_feed() -> void:
	var x: float = V.x - sx - 24.0
	var y: float = (150.0 if touch_mode else 60.0) + st
	for f in main.feed:
		var a: float = clamp(f["t"] * 2.0, 0.0, 1.0)
		var total := -18.0
		for s in f["seg"]: total += tw(s[0], 27) + 18.0
		if a > 0.5: rr(Rect2(x - total - 14, y - 22, total + 28, 44), Color(INK, 0.5), 10)
		var q: float = x
		for s in f["seg"]:
			var c: Color = s[1]
			txt(Vector2(q, y), s[0], 27, Color(c, c.a * a), 2, f_bd, 5)
			q -= tw(s[0], 27) + 18.0
		y += 50.0

func _draw_status(p) -> void:
	var mx: float = sx + 24.0
	var my: float = 24.0 + st + 200.0 + 36.0
	txt(Vector2(mx, my), "$ %d" % p.money, 40, GREEN, 0, f_bk, 8, LTR)
	if main.bomb_carrier == p and main.bomb == null and p.alive:
		_icon("bomb", Vector2(mx + 22, my + 54), 20, AMBER)
		txt(Vector2(mx + 54, my + 54), "القنبلة معك", 28, AMBER, 0, f_bd, 6)
	if not p.alive: return
	var r0: Rect2 = slot_rect(0)
	var x0: float = r0.position.x
	var y: float = r0.position.y - 64.0
	var half: float = (slot_rect(2).end.x - x0 - 12.0) * 0.5
	var hp: int = max(p.hp, 0)
	var hc: Color = WHITE if hp > 35 else RED
	rr(Rect2(x0, y, half, 54), Color(INK, 0.55), 14)
	_icon("heart", Vector2(x0 + 32, y + 27), 20, Color(0.95, 0.3, 0.3))
	txt(Vector2(x0 + 60, y + 27), str(hp), 38, hc, 0, f_bk, 0, LTR)
	rr(Rect2(x0 + 142, y + 21, half - 160, 12), Color(1, 1, 1, 0.16), 6)
	if hp > 0: rr(Rect2(x0 + 142, y + 21, (half - 160) * hp / 100.0, 12), Color(0.95, 0.3, 0.3), 6)
	var ax: float = x0 + half + 12.0
	rr(Rect2(ax, y, half, 54), Color(INK, 0.55), 14)
	_icon("shield", Vector2(ax + 32, y + 27), 21, main.C_CT)
	txt(Vector2(ax + 60, y + 27), str(p.armor), 38, WHITE, 0, f_bk, 0, LTR)
	rr(Rect2(ax + 142, y + 21, half - 160, 12), Color(1, 1, 1, 0.16), 6)
	if p.armor > 0: rr(Rect2(ax + 142, y + 21, (half - 160) * p.armor / 100.0, 12), main.C_CT, 6)
	var keys := [p.primary, "pistol", "knife"]
	for k in 3:
		var r: Rect2 = slot_rect(k)
		var wk: String = keys[k]
		var act: bool = wk != "" and wk == p.cur
		var on: bool = down.has("w%d" % (k + 1))
		rr(r, Color(AMBER, 0.34 if on else 0.20) if act else Color(INK, 0.52), 14, Color(AMBER, 0.95) if act else Color(1, 1, 1, 0.18), 2)
		if not touch_mode: txt(Vector2(r.position.x + 12, r.position.y + 18), str(k + 1), 20, Color(1, 1, 1, 0.45), 0, f_md, 0, LTR)
		if wk == "":
			txt(r.get_center(), "—", 30, Color(1, 1, 1, 0.3), 1, f_bd, 0, LTR)
			continue
		var w: Dictionary = main.W[wk]
		var tc: Color = WHITE if act else Color(1, 1, 1, 0.66)
		if w.mag > 0:
			txt(Vector2(r.get_center().x, r.position.y + 23), w.name, 24, tc, 1, f_bd)
			var am: int = p.ammo[wk]
			txt(Vector2(r.get_center().x, r.position.y + 56), "%d / %d" % [am, p.reserve[wk]], 30, RED if am == 0 else tc, 1, f_bk, 0, LTR)
		else:
			txt(r.get_center(), w.name, 28, tc, 1, f_bd)
	if not touch_mode and p.he > 0:
		var gr := Rect2(slot_rect(2).end.x + 12, r0.position.y, 110, 80)
		rr(gr, Color(INK, 0.52), 14, Color(1, 1, 1, 0.18), 2)
		_icon("he", gr.get_center() - Vector2(22, 0), 22, WHITE)
		txt(gr.get_center() + Vector2(26, 0), "×%d" % p.he, 30, WHITE, 1, f_bk, 0, LTR)

func _draw_msgs(p) -> void:
	var cx: float = V.x * 0.5
	if main.msg_t > 0.0 and main.phase != "match":
		var lines: PackedStringArray = main.msg.split("\n")
		var a: float = clamp(main.msg_t * 3.0, 0.0, 1.0)
		txt(Vector2(cx, V.y * 0.27), lines[0], 76, Color(1, 0.92, 0.7, a), 1, f_bk, 12)
		if lines.size() > 1: txt(Vector2(cx, V.y * 0.27 + 86), lines[1], 40, Color(1, 1, 1, a), 1, f_bd, 9)
	var h := ""
	if main.phase == "freeze": h = main.hint
	elif not p.alive and (main.phase == "live" or main.phase == "planted"): h = "لقد قُتلت — أنت تشاهد زميلك الآن"
	if h != "" and not modal():
		var wmax: float = min(V.x - 2.0 * (sx + 340.0), 1250.0)
		var sz: Vector2 = f_md.get_multiline_string_size(h, HORIZONTAL_ALIGNMENT_CENTER, wmax, 30, -1, 3, TextServer.JUSTIFICATION_NONE, RTL)
		var top: float = 100.0 + st
		rr(Rect2(cx - sz.x * 0.5 - 26, top, sz.x + 52, sz.y + 16), Color(INK, 0.55), 14)
		pad.draw_multiline_string(f_md, Vector2(cx - wmax * 0.5, top + 8 + f_md.get_ascent(30)), h, HORIZONTAL_ALIGNMENT_CENTER, wmax, 30, -1, Color(1, 1, 1, 0.94), 3, TextServer.JUSTIFICATION_NONE, RTL)
	var prog: float = max(main.plant_prog / 3.2, main.defuse_prog / 5.0)
	if prog > 0.0:
		var by: float = V.y * 0.64
		txt(Vector2(cx, by - 34), "جارٍ زرع القنبلة" if main.plant_prog > 0.0 else "جارٍ تفكيك القنبلة", 30, WHITE, 1, f_bd, 7)
		rr(Rect2(cx - 250, by, 500, 22), Color(INK, 0.65), 11)
		rr(Rect2(cx - 247, by + 3, max(494.0 * clamp(prog, 0.0, 1.0), 16.0), 16), AMBER, 8)

func _draw_touch(p) -> void:
	cbtn("pause", "pause")
	cbtn("score", "score", "", show_score)
	if not p.alive: return
	# movement stick
	var ja: float = 1.0 if joy_on else 0.62
	pad.draw_circle(joy_c, JOY_R, Color(INK, 0.32 * ja))
	pad.draw_arc(joy_c, JOY_R, 0, TAU, 72, Color(1, 1, 1, 0.48 * ja), 3.0, true)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var q: Vector2 = joy_c + d * (JOY_R - 22.0)
		var n := Vector2(-d.y, d.x)
		pad.draw_polyline(PackedVector2Array([q - d * 10 + n * 12, q, q - d * 10 - n * 12]), Color(1, 1, 1, 0.38 * ja), 3.0, true)
	var kp: Vector2 = joy_c + joy_raw * JOY_TRAVEL
	pad.draw_circle(kp, 58, Color(AMBER, 0.55) if joy_on else Color(1, 1, 1, 0.26))
	pad.draw_arc(kp, 58, 0, TAU, 48, Color(1, 1, 1, 0.85 * ja), 3.0, true)
	# action buttons
	var w: Dictionary = main.W[p.cur]
	cbtn("fire", "fire")
	cbtn("jump", "jump")
	cbtn("crouch", "crouch", "", p.t_crouch)
	cbtn("reload", "reload", "", w.mag > 0 and p.ammo[p.cur] == 0 and p.reload_t <= 0.0)
	if p.reload_t > 0.0 and w.reload > 0.0:
		var rb: Array = btn["reload"]
		pad.draw_arc(rb[0], rb[1] + 7, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - p.reload_t / w.reload), 48, AMBER, 6.0, true)
	if _vis("scope"): cbtn("scope", "aim", "", p.scoped)
	if _vis("he"): cbtn("he", "he")
	if _vis("use"):
		cbtn("use", "bomb", "ازرع" if p.team == "t" else "فكّك", true)
		var prog: float = max(main.plant_prog / 3.2, main.defuse_prog / 5.0)
		if prog > 0.0:
			var ub: Array = btn["use"]
			pad.draw_arc(ub[0], ub[1] + 9, -PI * 0.5, -PI * 0.5 + TAU * clamp(prog, 0.0, 1.0), 64, AMBER, 8.0, true)
	if _vis("buy"): cbtn("buy", "buy", "المتجر", sin(clock * 5.0) > 0.0)

func _draw_menu() -> void:
	var cx: float = V.x * 0.5
	var cy: float = V.y * 0.5
	pad.draw_rect(Rect2(Vector2.ZERO, V), Color(0.02, 0.03, 0.05, 0.62))
	txt(Vector2(cx, cy - 350), "Vorn", 190, AMBER, 1, f_bk, 14, LTR)
	txt(Vector2(cx, cy - 218), "قتال تكتيكي 5 ضد 5", 42, Color(1, 1, 1, 0.92), 1, f_bd, 8)
	txt(Vector2(cx, cy - 140), "اختر فريقك", 34, Color(1, 1, 1, 0.72), 1, f_md, 6)
	var cw := 620.0
	var ch := 340.0
	var cards := [
		["team_ct", "ct", "دافع عن النقطتين أ و ب", "وفكّك القنبلة قبل أن تنفجر", "1"],
		["team_t", "t", "ازرع القنبلة في إحدى النقطتين", "وامنع الخصم من تفكيكها", "2"],
	]
	for k in 2:
		var cd: Array = cards[k]
		# the first card sits on the right, the way Arabic is read
		var x: float = cx + 25.0 if k == 0 else cx - 25.0 - cw
		var r := Rect2(x, cy - 95, cw, ch)
		var col: Color = main.team_col(cd[1])
		var on: bool = down.has(cd[0])
		rr(r, Color(col.darkened(0.72), 0.96) if on else Color(INK, 0.88), 26, Color(col, 1.0 if on else 0.6), 3)
		rr(Rect2(r.position.x + 60, r.position.y, cw - 120, 8), col, 4)
		txt(Vector2(r.get_center().x, r.position.y + 76), main.TEAM_NAME[cd[1]], 60, col, 1, f_bk)
		txt(Vector2(r.get_center().x, r.position.y + 150), cd[2], 30, Color(1, 1, 1, 0.88), 1, f_md)
		txt(Vector2(r.get_center().x, r.position.y + 196), cd[3], 30, Color(1, 1, 1, 0.88), 1, f_md)
		var pr := Rect2(r.get_center().x - 130, r.end.y - 92, 260, 62)
		rr(pr, col, 31)
		txt(pr.get_center(), "العب", 34, INK, 1, f_bk)
		if not touch_mode: txt(Vector2(r.position.x + 30, r.position.y + 40), "[%s]" % cd[4], 26, Color(1, 1, 1, 0.5), 0, f_md, 0, LTR)
		hot.append([r, cd[0]])
	var hy: float = V.y - 84.0 - sb
	if touch_mode:
		txt(Vector2(cx, hy), "حرّك العصا اليسرى للمشي  ·  اسحب على يمين الشاشة للتصويب  ·  اضغط زر الإطلاق للرمي", 28, Color(1, 1, 1, 0.74), 1, f_md, 6, RTL)
	else:
		txt(Vector2(cx, hy - 44), "الحركة: WASD  ·  التصويب والإطلاق: الفأرة  ·  مشي هادئ: Shift  ·  انحناء: Ctrl  ·  قفز: Space", 26, Color(1, 1, 1, 0.74), 1, f_md, 6, RTL)
		txt(Vector2(cx, hy), "المتجر: B  ·  الأسلحة: 1 / 2 / 3  ·  تلقيم: R  ·  قنبلة يدوية: G  ·  القنبلة: E  ·  النتائج: Tab  ·  إيقاف مؤقت: Esc", 26, Color(1, 1, 1, 0.74), 1, f_md, 6, RTL)

func _draw_buy(p) -> void:
	var cx: float = V.x * 0.5
	var cy: float = V.y * 0.5
	pad.draw_rect(Rect2(Vector2.ZERO, V), Color(0, 0, 0, 0.45))
	var pw := 1100.0
	var ph := 690.0
	var r := Rect2(cx - pw * 0.5, cy - ph * 0.5, pw, ph)
	rr(r, Color(INK, 0.94), 28, Color(1, 1, 1, 0.16), 2)
	txt(Vector2(r.end.x - 44, r.position.y + 60), "المتجر", 52, AMBER, 2, f_bk)
	txt(Vector2(cx, r.position.y + 60), "$ %d" % p.money, 44, GREEN, 1, f_bk, 0, LTR)
	var cr := Rect2(r.position + Vector2(26, 22), Vector2(76, 76))
	rr(cr, Color(1, 1, 1, 0.22 if down.has("buy_close") else 0.10), 20)
	_icon("x", cr.get_center(), 16, WHITE)
	hot.append([cr.grow(10), "buy_close"])
	var y: float = r.position.y + 120.0
	for i in main.BUY.size():
		var it: Array = main.BUY[i]
		var k: String = it[0]
		var pr: int = main.PRICE[k] if main.PRICE.has(k) else main.W[k].price
		var own: bool = p.owned(k)
		var can: bool = p.money >= pr and not own
		var id := "buy_%d" % i
		var row := Rect2(r.position.x + 28, y, pw - 56, 98)
		if down.has(id): rr(row, Color(AMBER, 0.24), 18, Color(AMBER, 0.8), 2)
		elif own: rr(row, Color(GREEN, 0.10), 18, Color(GREEN, 0.5), 2)
		else: rr(row, Color(1, 1, 1, 0.06), 18, Color(1, 1, 1, 0.12), 2)
		var a: float = 1.0 if (can or own) else 0.42
		var tx: float = row.end.x - (30.0 if touch_mode else 84.0)
		if not touch_mode: txt(Vector2(row.end.x - 46, row.get_center().y), str(i + 1), 30, Color(1, 1, 1, 0.5), 1, f_bd, 0, LTR)
		txt(Vector2(tx, row.position.y + 34), it[1], 38, Color(1, 1, 1, a), 2, f_bk)
		txt(Vector2(tx, row.position.y + 73), it[2], 25, Color(1, 1, 1, 0.62 * a), 2, f_md)
		if own: txt(Vector2(row.position.x + 34, row.get_center().y), "تم الشراء", 30, GREEN, 0, f_bd)
		else: txt(Vector2(row.position.x + 34, row.get_center().y), "$ %d" % pr, 38, GREEN if can else Color(RED, 0.8), 0, f_bk, 0, LTR)
		hot.append([row, id])
		y += 108.0

func _draw_scoreboard(top: float) -> void:
	var cx: float = V.x * 0.5
	var pw := 1000.0
	var rh := 42.0
	var r := Rect2(cx - pw * 0.5, top, pw, SB_H)
	rr(r, Color(INK, 0.90), 24, Color(1, 1, 1, 0.16), 2)
	var cols := [r.end.x - 48, r.position.x + 480, r.position.x + 310, r.position.x + 130]
	var dim := Color(1, 1, 1, 0.5)
	var y: float = top + 22.0
	for tm in ["ct", "t"]:
		var col: Color = main.team_col(tm)
		rr(Rect2(r.position.x + 24, y, pw - 48, 54), Color(col, 0.20), 12)
		txt(Vector2(cols[0], y + 27), main.TEAM_NAME[tm], 34, col, 2, f_bk)
		txt(Vector2(r.position.x + 56, y + 27), str(main.score[tm]), 38, col, 0, f_bk, 0, LTR)
		y += 64.0
		txt(Vector2(cols[0], y + 14), "اللاعب", 22, dim, 2, f_md)
		txt(Vector2(cols[1], y + 14), "قتل", 22, dim, 1, f_md)
		txt(Vector2(cols[2], y + 14), "موت", 22, dim, 1, f_md)
		txt(Vector2(cols[3], y + 14), "المال", 22, dim, 1, f_md)
		y += 36.0
		var lst: Array = main.actors.filter(func(a): return a.team == tm)
		lst.sort_custom(func(a, b): return a.kills > b.kills)
		for a in lst:
			var c: Color = (AMBER if a.is_player else WHITE) if a.alive else Color(1, 1, 1, 0.4)
			if a.is_player: rr(Rect2(r.position.x + 24, y + 1, pw - 48, rh - 2), Color(1, 1, 1, 0.07), 8)
			var cyy: float = y + rh * 0.5
			txt(Vector2(cols[0], cyy), a.nick + ("" if a.alive else "  (قتيل)"), 27, c, 2, f_bd, 0, RTL)
			txt(Vector2(cols[1], cyy), str(a.kills), 27, c, 1, f_bd, 0, LTR)
			txt(Vector2(cols[2], cyy), str(a.deaths), 27, c, 1, f_bd, 0, LTR)
			txt(Vector2(cols[3], cyy), "$%d" % a.money, 27, c, 1, f_bd, 0, LTR)
			y += rh
		y += 10.0

func _draw_match() -> void:
	var cx: float = V.x * 0.5
	pad.draw_rect(Rect2(Vector2.ZERO, V), Color(0.02, 0.03, 0.05, 0.74))
	var top: float = max(14.0, (V.y - 1040.0) * 0.5)
	var won: bool = main.match_won
	txt(Vector2(cx, top + 66), "انتصار!" if won else "هزيمة", 96, AMBER if won else RED, 1, f_bk, 12)
	txt(Vector2(cx - 70, top + 158), str(main.score["ct"]), 60, main.C_CT, 1, f_bk, 8, LTR)
	txt(Vector2(cx, top + 154), ":", 60, WHITE, 1, f_bk, 8, LTR)
	txt(Vector2(cx + 70, top + 158), str(main.score["t"]), 60, main.C_T, 1, f_bk, 8, LTR)
	_draw_scoreboard(top + 208.0)
	ibtn(Rect2(cx - 220, top + 208.0 + SB_H + 22.0, 440, 92), "العب مجدداً", "again", true, 40)

func _draw_pause() -> void:
	var cx: float = V.x * 0.5
	var cy: float = V.y * 0.5
	pad.draw_rect(Rect2(Vector2.ZERO, V), Color(0, 0, 0, 0.58))
	var pw := 760.0
	var ph: float = 560.0 if main.mobile else 664.0
	var r := Rect2(cx - pw * 0.5, cy - ph * 0.5, pw, ph)
	rr(r, Color(INK, 0.95), 28, Color(1, 1, 1, 0.16), 2)
	txt(Vector2(cx, r.position.y + 70), "إيقاف مؤقت", 56, AMBER, 1, f_bk)
	var y: float = r.position.y + 136.0
	ibtn(Rect2(cx - 280, y, 560, 88), "متابعة اللعب", "resume", true, 38)
	y += 118.0
	txt(Vector2(cx, y + 20), "حساسية التصويب", 30, Color(1, 1, 1, 0.8), 1, f_md)
	y += 52.0
	var mr := Rect2(cx - 280, y, 110, 88)
	var plr := Rect2(cx + 170, y, 110, 88)
	rr(mr, Color(1, 1, 1, 0.20 if down.has("sens-") else 0.09), 22, Color(1, 1, 1, 0.22), 2)
	_icon("minus", mr.get_center(), 18, WHITE)
	hot.append([mr, "sens-"])
	rr(plr, Color(1, 1, 1, 0.20 if down.has("sens+") else 0.09), 22, Color(1, 1, 1, 0.22), 2)
	_icon("plus", plr.get_center(), 18, WHITE)
	hot.append([plr, "sens+"])
	txt(Vector2(cx, y + 44), "%d%%" % int(round(sens * 100.0)), 46, WHITE, 1, f_bk, 0, LTR)
	y += 118.0
	ibtn(Rect2(cx - 280, y, 560, 84), "القائمة الرئيسية", "tomenu")
	if not main.mobile:
		y += 104.0
		ibtn(Rect2(cx - 280, y, 560, 84), "خروج من اللعبة", "quit")
