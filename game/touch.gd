extends CanvasLayer
## Touch — on-screen controls for phones and tablets (autoload).
## In a match it draws the move stick, the action buttons and a bottom status cluster and feeds
## the game's input actions. While a menu or a panel is open, any finger acts as the mouse so
## every ordinary button, slider and list works by touch.

const AMBER := Color(1.0, 0.78, 0.30)
const INK := Color(0.035, 0.045, 0.06)
const WHITE := Color(1, 1, 1)
const LOOK := 0.0030          # radians per layout unit of finger travel at sensitivity 1.0
const JOY_R := 135.0
const JOY_TRAVEL := 105.0
const HOLD_MIN := 0.09        # a tap keeps its action pressed at least this long, so the game loop sees it

var game                      # the running match (set by match.gd); null in the menu
var pad: Control
var u := 1.0                  # canvas units per layout unit; the layout is designed for a 1080-unit-high screen
var W := 1920.0
var H := 1080.0
var sx := 28.0
var sb := 0.0
var held := {}                # finger index -> {"role": ..., "id": ..., "t": ...}
var down := {}
var btn := {}
var cells: Array = []         # weapon cells of this frame: [Rect2, weapon id]
var joy_c := Vector2.ZERO
var joy_raw := Vector2.ZERO
var joy_on := false
var crouch_on := false
var score_on := false
var mouse_idx := -1           # the finger currently acting as the mouse in menus
var clock := 0.0
var sbox := {}

func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS
	pad = Control.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.visible = false
	add_child(pad)
	pad.draw.connect(_draw_all)

# ------------------------------------------------------------------ state
func playing() -> bool:
	return game != null and is_instance_valid(game) and game.player != null and not game.auto

func panel_open() -> bool:
	return game.hud.buy.visible or game.hud.pause.visible or game.state == game.S.OVER

func _process(dt: float) -> void:
	if not G.touch:
		return
	clock += dt
	var v: Vector2 = pad.size
	if v.y < 1.0:
		return
	u = v.y / 1080.0 * (0.74 if v.x / v.y < 1.6 else 1.0)
	W = v.x / u
	H = v.y / u
	sx = 28.0 + G.inset / u
	sb = G.inset_b / u
	_layout()
	var play: bool = playing()
	pad.visible = play
	if not play:
		_release_game()
		crouch_on = false
		score_on = false
		_set_action("crouch", false)
		_set_action("score", false)
		return
	var p: Player = game.player
	if panel_open() or not p.alive:
		_release_game()
	if not p.alive and crouch_on:
		crouch_on = false
		_set_action("crouch", false)
	_feed_move()
	pad.queue_redraw()

func _layout() -> void:
	var r: float = W - sx
	btn = {
		"fire": [Vector2(r - 300, H - 300), 104.0],
		"jump": [Vector2(r - 112, H - 430), 66.0],
		"crouch": [Vector2(r - 112, H - 240), 62.0],
		"reload": [Vector2(r - 505, H - 170), 60.0],
		"alt": [Vector2(r - 525, H - 345), 60.0],
		"use": [Vector2(r - 290, H - 560), 76.0],
		"buy": [Vector2(r - 112, H - 640), 60.0],
		"pause": [Vector2(r - 62, 66), 44.0],
		"score": [Vector2(r - 168, 66), 44.0],
	}
	if not joy_on:
		joy_c = Vector2(sx + 250, H - 270)

func _set_action(n: String, on: bool, strength := 1.0) -> void:
	if on:
		Input.action_press(n, strength)
	elif Input.is_action_pressed(n):
		Input.action_release(n)

func _feed_move() -> void:
	var v := joy_raw if joy_on else Vector2.ZERO
	_set_action("right", v.x > 0.02, v.x)
	_set_action("left", v.x < -0.02, -v.x)
	_set_action("back", v.y > 0.02, v.y)
	_set_action("fwd", v.y < -0.02, -v.y)

# ------------------------------------------------------------------ input
func _input(ev: InputEvent) -> void:
	if not G.touch:
		return
	if ev is InputEventScreenTouch:
		if playing() and not panel_open():
			get_viewport().set_input_as_handled()
			if ev.pressed:
				_down(ev.index, ev.position / u)
			else:
				_up(ev.index)
		else:
			_gui_touch(ev.index, ev.position, ev.pressed)
	elif ev is InputEventScreenDrag:
		if held.has(ev.index):
			get_viewport().set_input_as_handled()
			_drag(ev.index, ev.position / u, ev.relative / u)
		elif ev.index == mouse_idx:
			_mouse_motion(ev.position, ev.relative, MOUSE_BUTTON_MASK_LEFT)

# ---- menus and panels: one finger is the mouse
func _gui_touch(i: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		if mouse_idx != -1:
			return
		mouse_idx = i
		_mouse_motion(pos, Vector2.ZERO, 0)        # lets the control under the finger react as on hover
		_mouse_button(pos, true)
	elif i == mouse_idx:
		mouse_idx = -1
		_mouse_button(pos, false)
		_mouse_motion(Vector2(-20, -20), Vector2.ZERO, 0)

func _to_window(pos: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * pos

func _mouse_button(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	e.position = _to_window(pos)
	e.global_position = e.position
	Input.parse_input_event.call_deferred(e)

func _mouse_motion(pos: Vector2, rel: Vector2, mask: int) -> void:
	var e := InputEventMouseMotion.new()
	e.position = _to_window(pos)
	e.global_position = e.position
	e.relative = get_viewport().get_final_transform().basis_xform(rel)
	e.button_mask = mask
	Input.parse_input_event.call_deferred(e)

# ---- match: stick, look and buttons
func _hit(id: String, pos: Vector2) -> bool:
	var b: Array = btn[id]
	return pos.distance_to(b[0]) <= b[1] + 14.0

func _use_mode() -> String:
	## "plant" at a bomb site with the bomb, "defuse" next to a planted bomb, "" otherwise
	var p: Player = game.player
	if not p.alive:
		return ""
	if game.state == game.S.LIVE and p.inv[5] == "c4" and game.world.site_at(p.global_position) != "":
		return "plant"
	if game.state == game.S.PLANTED and p.team == "ct" and p.global_position.distance_to(game.bomb["pos"]) < 1.7:
		return "defuse"
	return ""

func _alt_label() -> String:
	var cls: String = game.player.wd()["cls"]
	if cls == "knife":
		return "طعنة"
	if cls == "nade":
		return "قريبة"
	return ""

func _vis(id: String) -> bool:
	var p: Player = game.player
	match id:
		"alt": return p.wd().get("scope", false) or p.wd()["cls"] in ["knife", "nade"]
		"use": return _use_mode() != ""
		"buy": return game.can_buy(p)
		"reload": return p.ammo.has(p.cur)
	return true

func _down(i: int, pos: Vector2) -> void:
	var p: Player = game.player
	if score_on:
		score_on = false
		_set_action("score", false)
		held[i] = {"role": "tap", "id": "score"}
		return
	for id in ["pause", "score"]:
		if _hit(id, pos):
			_tap(id, i)
			return
	if not p.alive:
		p._next_spect()
		held[i] = {"role": "look"}
		return
	for id in ["fire", "use", "jump", "crouch", "reload", "alt", "buy"]:
		if _vis(id) and _hit(id, pos):
			_tap(id, i)
			return
	for c in cells:
		if (c[0] as Rect2).grow(6).has_point(pos):
			p.switch_to(c[1])
			held[i] = {"role": "tap", "id": "w:" + String(c[1])}
			return
	if not joy_on and pos.x < W * 0.42 and pos.y > H * 0.40:
		joy_on = true
		joy_c = Vector2(clampf(pos.x, sx + JOY_R * 0.8, W * 0.42), clampf(pos.y, H * 0.40, H - JOY_R * 0.7))
		joy_raw = Vector2.ZERO
		held[i] = {"role": "joy"}
	else:
		held[i] = {"role": "look"}

func _tap(id: String, i: int) -> void:
	var p: Player = game.player
	down[id] = true
	held[i] = {"role": "tap", "id": id, "t": clock}
	match id:
		"fire":
			held[i]["role"] = "fire"
			_set_action("fire", true)
		"jump":
			held[i]["role"] = "jump"
			_set_action("jump", true)
		"use":
			held[i]["role"] = "use"
			if _use_mode() == "plant" and p.cur != "c4":
				p.switch_slot(5)
			_set_action("use", true)
		"crouch":
			crouch_on = not crouch_on
			_set_action("crouch", crouch_on)
		"reload": p.start_reload()
		"alt":
			if p.wd()["cls"] != "c4":
				p.try_fire(true)
		"buy": game.hud.touch_buy()
		"pause": game.hud._set_pause(true)
		"score":
			score_on = not score_on
			_set_action("score", score_on)

func _drag(i: int, pos: Vector2, rel: Vector2) -> void:
	var role: String = held[i]["role"]
	if role == "joy":
		var d: Vector2 = (pos - joy_c) / JOY_TRAVEL
		if d.length() > 1.0:
			d = d.normalized()
		joy_raw = d
	elif role in ["look", "fire", "jump", "use"]:
		var p: Player = game.player
		var k: float = LOOK * float(G.settings["sens"]) * (0.55 if p.aim_on_enemy() else 1.0)
		p.look(Vector2(rel.x, rel.y * 0.8), k)

func _up(i: int) -> void:
	if not held.has(i):
		return
	var h: Dictionary = held[i]
	held.erase(i)
	var role: String = h["role"]
	if role == "joy":
		joy_on = false
		joy_raw = Vector2.ZERO
	elif role in ["fire", "jump", "use"]:
		down.erase(role)
		# a very short tap still has to last through one game tick
		var wait: float = HOLD_MIN - (clock - float(h["t"]))
		if wait > 0.0:
			get_tree().create_timer(wait).timeout.connect(_late_release.bind(role))
		else:
			_set_action(role, false)
	elif role == "tap" and h.has("id"):
		down.erase(h["id"])

func _late_release(role: String) -> void:
	if not down.has(role):
		_set_action(role, false)

func _release_game() -> void:
	## drop every gameplay touch: a panel opened, the player died or the match ended
	if held.is_empty() and not joy_on:
		return
	held.clear()
	down.clear()
	joy_on = false
	joy_raw = Vector2.ZERO
	for n in ["fire", "jump", "use", "left", "right", "fwd", "back"]:
		_set_action(n, false)

# ------------------------------------------------------------------ drawing helpers (layout units)
func _rr(r: Rect2, col: Color, rad := 16.0, border := Color(0, 0, 0, 0), bw := 0.0) -> void:
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

func _txt(pos: Vector2, s: String, size: float, col := WHITE, align := 0, bold := true, outline := 0, dir := TextServer.DIRECTION_AUTO) -> void:
	# pos.y is the visual middle of the line; align: 0 starts at pos.x, 1 centred on it, 2 ends at it.
	# Text is drawn unscaled at its real pixel size so it stays sharp.
	var font: Font = UI.bold() if bold else UI.font()
	var px: int = maxi(8, int(round(size * u)))
	var q: Vector2 = pos * u
	if align != 0:
		var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, TextServer.JUSTIFICATION_NONE, dir).x
		q.x -= w * (0.5 if align == 1 else 1.0)
	q.y += px * 0.34
	pad.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if outline > 0:
		pad.draw_string_outline(font, q, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, maxi(1, int(outline * u)), Color(0, 0, 0, 0.8 * col.a), TextServer.JUSTIFICATION_NONE, dir)
	pad.draw_string(font, q, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col, TextServer.JUSTIFICATION_NONE, dir)
	pad.draw_set_transform(Vector2.ZERO, 0.0, Vector2(u, u))

func _cbtn(id: String, icon: String, label := "", active := false) -> void:
	var b: Array = btn[id]
	var c: Vector2 = b[0]
	var on: bool = down.has(id)
	var r: float = b[1] * (1.07 if on else 1.0)
	pad.draw_circle(c, r, Color(AMBER, 0.42) if on else (Color(AMBER, 0.20) if active else Color(INK, 0.42)))
	pad.draw_arc(c, r, 0, TAU, 72, Color(AMBER, 0.95) if (on or active) else Color(1, 1, 1, 0.55), 3.0, true)
	var col := Color(1, 1, 1, 0.95)
	if icon == "":
		_txt(c, label, b[1] * 0.42, col, 1)
	elif label == "":
		_icon(icon, c, b[1] * 0.5, col)
	else:
		_icon(icon, c - Vector2(0, b[1] * 0.20), b[1] * 0.40, col)
		_txt(c + Vector2(0, b[1] * 0.50), label, b[1] * 0.36, col, 1)

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
				for q in part:
					pts.append(c + d * (q[0] * k) + nv * (q[1] * k))
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
		"bomb":
			pad.draw_rect(Rect2(c + Vector2(-s * 0.80, -s * 0.30), Vector2(s * 1.60, s * 0.86)), col)
			pad.draw_rect(Rect2(c + Vector2(-s * 0.56, -s * 0.10), Vector2(s * 0.62, s * 0.36)), Color(INK, col.a))
			pad.draw_arc(c + Vector2(-s * 0.26, -s * 0.30), s * 0.26, PI, TAU, 12, col, 4.0, true)
			pad.draw_arc(c + Vector2(s * 0.34, -s * 0.30), s * 0.22, PI, TAU, 12, col, 4.0, true)
		"buy":
			_txt(c, "$", s * 2.1, col, 1, true, 0, TextServer.DIRECTION_LTR)
		"pause":
			pad.draw_rect(Rect2(c + Vector2(-s * 0.55, -s * 0.62), Vector2(s * 0.36, s * 1.24)), col)
			pad.draw_rect(Rect2(c + Vector2(s * 0.19, -s * 0.62), Vector2(s * 0.36, s * 1.24)), col)
		"score":
			for k in 3:
				var y: float = c.y + (k - 1) * s * 0.52
				pad.draw_circle(Vector2(c.x + s * 0.62, y), 4.0, col)
				pad.draw_line(Vector2(c.x - s * 0.72, y), Vector2(c.x + s * 0.32, y), col, 5.0, true)
		"heart":
			pad.draw_rect(Rect2(c + Vector2(-s * 0.22, -s * 0.62), Vector2(s * 0.44, s * 1.24)), col)
			pad.draw_rect(Rect2(c + Vector2(-s * 0.62, -s * 0.22), Vector2(s * 1.24, s * 0.44)), col)
		"shield":
			pad.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.56, -s * 0.60), c + Vector2(s * 0.56, -s * 0.60), c + Vector2(s * 0.56, s * 0.08), c + Vector2(0, s * 0.70), c + Vector2(-s * 0.56, s * 0.08)]), col)

# ------------------------------------------------------------------ drawing
func _draw_all() -> void:
	cells.clear()
	if sbox.size() > 300:
		sbox.clear()
	if not playing() or panel_open() or btn.is_empty():
		return
	var p: Player = game.player
	pad.draw_set_transform(Vector2.ZERO, 0.0, Vector2(u, u))
	_cbtn("pause", "pause")
	_cbtn("score", "score", "", score_on)
	if not p.alive or score_on:
		return
	_draw_status(p)
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
	_cbtn("fire", "fire")
	_cbtn("jump", "jump")
	_cbtn("crouch", "crouch", "", crouch_on)
	if _vis("reload"):
		_cbtn("reload", "reload", "", p.mag() == 0 and p.reload_t <= 0.0)
		if p.reload_t > 0.0 and p.reload_total > 0.0:
			var rb: Array = btn["reload"]
			pad.draw_arc(rb[0], rb[1] + 7, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - p.reload_t / p.reload_total), 48, AMBER, 6.0, true)
	if _vis("alt"):
		if p.wd().get("scope", false):
			_cbtn("alt", "aim", "", p.scoped)
		else:
			_cbtn("alt", "", _alt_label())
	var um := _use_mode()
	if um != "":
		_cbtn("use", "bomb", "ازرع" if um == "plant" else "فكّك", true)
		var prog := -1.0
		if p.plant_t >= 0.0:
			prog = p.plant_t / DB.T_PLANT
		elif p.defuse_t >= 0.0:
			prog = p.defuse_t / (DB.T_DEFUSE_KIT if p.kit else DB.T_DEFUSE)
		if prog > 0.0:
			var ub: Array = btn["use"]
			pad.draw_arc(ub[0], ub[1] + 9, -PI * 0.5, -PI * 0.5 + TAU * clampf(prog, 0.0, 1.0), 64, AMBER, 8.0, true)
	if _vis("buy"):
		_cbtn("buy", "buy", "المتجر", sin(clock * 5.0) > 0.0)

func _draw_status(p: Player) -> void:
	## bottom-centre cluster: health, armour, ammo and the weapon cells (tap a cell to switch)
	var cx: float = W * 0.5
	var own: Array[String] = p.owned()
	var room: float = (W - sx - 590.0) - (sx + 410.0)
	var cw: float = clampf(room / maxf(1.0, own.size()) - 8.0, 92.0, 136.0)
	var total: float = cw * own.size() + 8.0 * (own.size() - 1)
	var y0: float = H - sb * 0.6 - 108.0
	var x0: float = cx - total * 0.5
	for k in own.size():
		var wid: String = own[k]
		var r := Rect2(x0 + k * (cw + 8.0), y0, cw, 92)
		var act: bool = wid == p.cur
		_rr(r, Color(AMBER, 0.22) if act else Color(INK, 0.52), 14, Color(AMBER, 0.95) if act else Color(1, 1, 1, 0.18), 2)
		var ic := UI.icon(wid)
		if ic:
			var ih := 44.0
			var iw: float = minf(ih * ic.get_width() / ic.get_height(), cw - 16.0)
			ih = iw * ic.get_height() / ic.get_width()
			pad.draw_texture_rect(ic, Rect2(r.get_center().x - iw * 0.5, r.position.y + 32 - ih * 0.5, iw, ih), false, Color(1, 1, 1, 1.0 if act else 0.6))
		var sub := ""
		if p.ammo.has(wid):
			sub = "%d / %d" % [p.ammo[wid][0], p.ammo[wid][1]]
		elif DB.W[wid]["cls"] == "nade":
			var cnt: int = p.nades.count(wid)
			sub = String(DB.W[wid]["name"]) + (" ×%d" % cnt if cnt > 1 else "")
		else:
			sub = DB.W[wid]["name"]
		_txt(Vector2(r.get_center().x, r.end.y - 20), sub, 23, WHITE if act else Color(1, 1, 1, 0.7), 1, act)
		cells.append([r, wid])
	# health / armour / ammo row
	var y: float = y0 - 62.0
	var hp: int = maxi(p.hp, 0)
	var hc: Color = WHITE if hp > 25 else UI.RED
	var bw := 236.0
	var hx: float = cx - bw - 6.0 - 120.0
	_rr(Rect2(hx, y, bw, 54), Color(INK, 0.55), 14)
	_icon("heart", Vector2(hx + 30, y + 27), 19, Color(0.95, 0.3, 0.3))
	_txt(Vector2(hx + 56, y + 27), str(hp), 36, hc, 0, true, 0, TextServer.DIRECTION_LTR)
	_rr(Rect2(hx + 130, y + 21, bw - 146, 12), Color(1, 1, 1, 0.16), 6)
	if hp > 0:
		_rr(Rect2(hx + 130, y + 21, maxf((bw - 146) * hp / 100.0, 12.0), 12), Color(0.95, 0.3, 0.3), 6)
	var ax: float = hx + bw + 12.0
	_rr(Rect2(ax, y, bw, 54), Color(INK, 0.55), 14)
	_icon("shield", Vector2(ax + 30, y + 27), 20, UI.TEAL)
	_txt(Vector2(ax + 56, y + 27), str(p.armor), 36, WHITE, 0, true, 0, TextServer.DIRECTION_LTR)
	_rr(Rect2(ax + 130, y + 21, bw - 146, 12), Color(1, 1, 1, 0.16), 6)
	if p.armor > 0:
		_rr(Rect2(ax + 130, y + 21, maxf((bw - 146) * p.armor / 100.0, 12.0), 12), UI.TEAL, 6)
	if p.helmet:
		pad.draw_arc(Vector2(ax + 30, y + 22), 17, PI, TAU, 16, UI.TEAL, 4.0, true)
	var mx: float = ax + bw + 12.0
	_rr(Rect2(mx, y, 228, 54), Color(INK, 0.55), 14)
	if p.ammo.has(p.cur):
		var m: int = p.mag()
		var low: bool = m <= int(p.wd()["mag"]) / 5
		_txt(Vector2(mx + 104, y + 27), str(m), 40, UI.RED if low else WHITE, 2, true, 0, TextServer.DIRECTION_LTR)
		_txt(Vector2(mx + 114, y + 29), "/ %d" % p.reserve(), 26, Color(1, 1, 1, 0.62), 0, true, 0, TextServer.DIRECTION_LTR)
	else:
		_txt(Vector2(mx + 114, y + 27), p.wd()["name"], 28, WHITE, 1)
	if p.kit:
		_txt(Vector2(cx, y - 22), "عدّة التفكيك معك", 22, UI.TEAL, 1, false, 5)
