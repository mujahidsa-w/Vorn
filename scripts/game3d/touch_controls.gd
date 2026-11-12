extends CanvasLayer
## Mobile controls for the match, laid out like mobile tactical shooters:
## - left half: floating joystick (push to the edge to run)
## - right half: drag to look (dragging the fire buttons also aims)
## - icon buttons: fire (right, plus optional left fire), aim, reload, jump, crouch,
##   weapon slots, scoreboard (hold) and settings
## Size, opacity, left fire and sensitivity come from the settings (MOBILE tab).
## Everything feeds the same inputs keyboard and mouse use, so gameplay code is shared.

const W = preload("res://scripts/game3d/weapons.gd")
const SIZES := [0.85, 1.0, 1.18]

var world
var pad: Control
var t := 0.0

var joy_id := -1
var joy_home := Vector2(330, 790)
var joy_base := Vector2(330, 790)
var joy_pos := Vector2(330, 790)
var joy_vec := Vector2.ZERO
const JOY_R := 135.0

var look_id := -1
var buttons := {}            # id -> {pos, r, icon, key, hold, down}
var btn_touch := {}          # touch index -> button id
var _held := {}
var _aim_on := false
var _scale := 1.0
var _alpha := 0.6


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	pad = Control.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.draw.connect(_draw_pad)
	add_child(pad)
	Input.emulate_mouse_from_touch = false
	_layout()
	Game.settings_changed.connect(_layout)


## button positions on the 1920x1080 canvas, scaled around their own centre
func _layout() -> void:
	_scale = SIZES[clampi(int(Game.settings.get("btn_scale", 1)), 0, 2)]
	_alpha = clampf(float(Game.settings.get("btn_alpha", 0.6)), 0.2, 1.0)
	var s := _scale
	buttons.clear()
	_btn("fire", Vector2(1640, 800), 96 * s, "fire", "lmb", true)
	if bool(Game.settings.get("left_fire", true)):
		_btn("fire_l", Vector2(250, 470), 70 * s, "fire", "lmb", true)
	_btn("aim", Vector2(1800, 600), 58 * s, "aim", "aim", false)
	_btn("reload", Vector2(1450, 620), 52 * s, "reload", KEY_R, false)
	_btn("jump", Vector2(1820, 860), 60 * s, "jump", KEY_SPACE, false)
	_btn("crouch", Vector2(1660, 1000), 54 * s, "crouch", KEY_C, false)
	_btn("slot1", Vector2(1160, 1010), 46 * s, "slot", KEY_1, false)
	_btn("slot2", Vector2(1290, 1010), 46 * s, "slot", KEY_2, false)
	_btn("score", Vector2(1720, 70), 38 * s, "score", KEY_TAB, true)
	_btn("pause", Vector2(1840, 70), 38 * s, "gear", KEY_ESCAPE, false)
	_btn("buy", Vector2(120, 210), 48 * s, "buy", "buy", false)


func _btn(id: String, p: Vector2, r: float, icon: String, key, hold: bool) -> void:
	buttons[id] = {"pos": p, "r": r, "icon": icon, "key": key, "hold": hold, "down": false}


func _comp():
	return world.get_meta("comp") if world and world.has_meta("comp") else null


func _btn_live(id: String) -> bool:
	if id == "buy":
		var cm = _comp()
		return cm != null and cm.can_buy()
	return true


func _blocked() -> bool:
	var cm = _comp()
	if cm and cm.buy and cm.buy.open:
		return true
	return get_tree().paused or (world and world.hud and world.hud.get("map_open"))


func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	if _blocked():
		if event is InputEventScreenTouch and not event.pressed:
			_release_all()
		return
	var p: Vector2 = event.position
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down(event.index, p)
		else:
			_touch_up(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_touch_drag(event.index, p, event.relative)
		get_viewport().set_input_as_handled()


func _touch_down(idx: int, p: Vector2) -> void:
	for id in buttons:
		var b: Dictionary = buttons[id]
		if _btn_live(id) and p.distance_to(b.pos) < b.r + 16:
			btn_touch[idx] = id
			_press(id)
			if id == "fire" or id == "fire_l":
				look_id = idx        # drag while firing to keep aiming
			return
	if p.x < 900 and p.y > 300:
		joy_id = idx
		joy_base = p
		joy_pos = p
		joy_vec = Vector2.ZERO
		return
	if p.x >= 900 and look_id == -1:
		look_id = idx


func _touch_drag(idx: int, p: Vector2, rel: Vector2) -> void:
	if idx == joy_id:
		var d := p - joy_base
		if d.length() > JOY_R:
			# the base follows the finger when pulled far, so direction changes stay quick
			joy_base = p - d.normalized() * JOY_R
			d = d.normalized() * JOY_R
		joy_pos = joy_base + d
		joy_vec = d / JOY_R
		_apply_joystick()
	if idx == look_id:
		_look(rel)


func _touch_up(idx: int) -> void:
	if btn_touch.has(idx):
		_release(btn_touch[idx])
		btn_touch.erase(idx)
	if idx == joy_id:
		joy_id = -1
		joy_vec = Vector2.ZERO
		_apply_joystick()
	if idx == look_id:
		look_id = -1


func _look(rel: Vector2) -> void:
	var pl = world.player
	if pl == null or pl.dead:
		return
	var sens := 0.0042 * float(Game.settings.get("sens", 1.0))
	if pl.aiming:
		sens *= float(Game.settings.get("aim_sens", 0.6))
	var inv := -1.0 if bool(Game.settings.get("invert_y", false)) else 1.0
	pl.yaw -= rel.x * sens
	pl.pitch = clampf(pl.pitch - rel.y * sens * inv, -1.25, 0.8)


func _apply_joystick() -> void:
	var v := joy_vec
	_hold(KEY_W, v.y < -0.3)
	_hold(KEY_S, v.y > 0.3)
	_hold(KEY_A, v.x < -0.3)
	_hold(KEY_D, v.x > 0.3)
	_hold(KEY_SHIFT, v.length() > 0.95 and v.y < -0.5)


func _hold(k: Key, on: bool) -> void:
	if bool(_held.get(k, false)) == on:
		return
	_held[k] = on
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = on
	Input.parse_input_event(e)


func _tap_key(k: Key) -> void:
	_hold(k, true)
	_hold(k, false)


func _mouse(btn: MouseButton, on: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = on
	e.position = get_viewport().get_visible_rect().size * 0.5
	Input.parse_input_event(e)


func _press(id: String) -> void:
	var b: Dictionary = buttons[id]
	b.down = true
	Game.play_sfx("click", 1.3, -14.0)
	match str(b.key):
		"lmb":
			_mouse(MOUSE_BUTTON_LEFT, true)
		"buy":
			var cm = _comp()
			if cm:
				cm.buy.toggle()
		"aim":
			_aim_on = not _aim_on
			_mouse(MOUSE_BUTTON_RIGHT, _aim_on)
		_:
			if b.hold:
				_hold(b.key, true)
			else:
				_tap_key(b.key)


func _release(id: String) -> void:
	if not buttons.has(id):
		return
	var b: Dictionary = buttons[id]
	b.down = false
	if str(b.key) == "lmb":
		# keep shooting while the other fire button is still held
		for other in btn_touch.values():
			if other != id and buttons.has(other) and str(buttons[other].key) == "lmb":
				return
		_mouse(MOUSE_BUTTON_LEFT, false)
	elif b.hold and not (b.key is String):
		_hold(b.key, false)


func _release_all() -> void:
	for idx in btn_touch.keys():
		_release(btn_touch[idx])
	btn_touch.clear()
	for k in _held.keys():
		_hold(k, false)
	_mouse(MOUSE_BUTTON_LEFT, false)
	joy_id = -1
	look_id = -1
	joy_vec = Vector2.ZERO


func _process(delta: float) -> void:
	t += delta
	if _aim_on and world and world.player and (world.player.current == "" or world.player.dead):
		_aim_on = false
		_mouse(MOUSE_BUTTON_RIGHT, false)
	pad.visible = not _blocked()
	pad.queue_redraw()


# ---------------------------------------------------------------- drawing
func _draw_pad() -> void:
	if world == null or world.player == null or world.player.dead:
		return
	var c := pad
	var a := _alpha
	# joystick
	var base := joy_base if joy_id != -1 else joy_home
	var knob := joy_pos if joy_id != -1 else base
	c.draw_circle(base, JOY_R, Color(0, 0, 0, 0.25 * a))
	c.draw_arc(base, JOY_R, 0, TAU, 64, Color(1, 1, 1, 0.35 * a), 3.0, true)
	for i in 4:
		var ang := i * PI * 0.5
		var tip := base + Vector2(cos(ang), sin(ang)) * (JOY_R - 18)
		_chevron(c, tip, ang, 10.0, Color(1, 1, 1, 0.3 * a))
	c.draw_circle(knob, 54, Color(1, 1, 1, (0.4 if joy_id != -1 else 0.22) * a))
	c.draw_arc(knob, 54, 0, TAU, 40, Color(1, 1, 1, 0.7 * a), 2.0, true)
	if joy_vec.length() > 0.95 and joy_vec.y < -0.5:
		Game.dtext(c, "SPRINT", base + Vector2(0, -JOY_R - 16), 18, Color(1, 1, 1, 0.85), Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	for id in buttons:
		if _btn_live(id):
			_draw_button(c, id, buttons[id], a)


func _draw_button(c: Control, id: String, b: Dictionary, a: float) -> void:
	var p: Vector2 = b.pos
	var r: float = b.r
	var fire: bool = b.icon == "fire"
	var on: bool = b.down or (id == "aim" and _aim_on)
	var accent := Color(1.0, 0.32, 0.28) if fire else (Color(1.0, 0.78, 0.25) if on else Color(1, 1, 1))
	c.draw_circle(p, r, Color(0.02, 0.03, 0.05, (0.62 if on else 0.42) * a))
	c.draw_arc(p, r, 0, TAU, 56, Color(accent, (0.95 if on else 0.6) * a), 3.0 if not fire else 4.0, true)
	if on:
		c.draw_circle(p, r * 0.92, Color(accent, 0.12 * a))
	var ic := Color(1, 1, 1, 0.92 * maxf(a, 0.5))
	var s := r / 60.0
	match str(b.icon):
		"fire":
			_icon_bullet(c, p, s, ic)
		"aim":
			_icon_scope(c, p, s, ic)
		"reload":
			_icon_reload(c, p, s, ic)
		"jump":
			_chevron(c, p + Vector2(0, 8) * s, -PI * 0.5, 22 * s, ic, 5.0 * s)
			_chevron(c, p + Vector2(0, -10) * s, -PI * 0.5, 22 * s, ic, 5.0 * s)
		"crouch":
			_icon_crouch(c, p, s, ic)
		"score":
			for i in 3:
				c.draw_line(p + Vector2(-14, -10 + i * 10) * s, p + Vector2(14, -10 + i * 10) * s, ic, 3.0 * s)
		"gear":
			_icon_gear(c, p, s, ic)
		"buy":
			Game.dtext(c, "$", p + Vector2(0, 14 * s), int(40 * s), Color(0.45, 1.0, 0.55), Game.font_wide, HORIZONTAL_ALIGNMENT_CENTER)
			Game.dtext(c, "BUY", p + Vector2(0, r + 22), 16, ic, Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
		"slot":
			_draw_slot(c, id, p, r, ic)


func _draw_slot(c: Control, id: String, p: Vector2, r: float, ic: Color) -> void:
	var pl = world.player
	var i := 0 if id == "slot1" else 1
	var wid := ""
	if pl and i < pl.inventory.size():
		wid = str(pl.inventory[i])
	if wid == "":
		Game.dtext(c, str(i + 1), p + Vector2(0, 8), 22, Color(ic, 0.5), Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var cur: bool = pl.current == wid
	if cur:
		c.draw_arc(p, r + 5, 0, TAU, 48, Color(1.0, 0.78, 0.25, 0.9), 3.0, true)
	var nm := str(W.DATA[wid].name).get_slice(" ", 0)
	Game.dtext(c, nm, p + Vector2(0, -2), 15, ic, Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	var ammo := "%d/%d" % [int(pl.ammo.get(wid, 0)), int(W.DATA[wid].mag)]
	Game.dtext(c, ammo, p + Vector2(0, 18), 13, Color(ic, 0.7), Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)


# ---------------------------------------------------------------- icons (vector, no image files)
func _chevron(c: Control, tip: Vector2, ang: float, size: float, col: Color, w := 3.0) -> void:
	var back := Vector2(cos(ang), sin(ang)) * -size
	var side := Vector2(-sin(ang), cos(ang)) * size * 0.75
	c.draw_line(tip, tip + back + side, col, w, true)
	c.draw_line(tip, tip + back - side, col, w, true)


func _icon_bullet(c: Control, p: Vector2, s: float, col: Color) -> void:
	# a cartridge: case, rim and pointed head, slightly tilted
	var rot := -0.5
	var pts := PackedVector2Array([
		Vector2(-7, 22), Vector2(7, 22), Vector2(7, -4), Vector2(5, -14), Vector2(0, -24), Vector2(-5, -14), Vector2(-7, -4)])
	var out := PackedVector2Array()
	for v in pts:
		out.append(p + (v * s * 1.3).rotated(rot))
	c.draw_colored_polygon(out, col)
	c.draw_line(p + (Vector2(-9, 16) * s * 1.3).rotated(rot), p + (Vector2(9, 16) * s * 1.3).rotated(rot), Color(0, 0, 0, 0.5), 2.0 * s)
	c.draw_line(p + (Vector2(-7, -4) * s * 1.3).rotated(rot), p + (Vector2(7, -4) * s * 1.3).rotated(rot), Color(0, 0, 0, 0.45), 2.0 * s)


func _icon_scope(c: Control, p: Vector2, s: float, col: Color) -> void:
	c.draw_arc(p, 20 * s, 0, TAU, 40, col, 3.0 * s, true)
	c.draw_circle(p, 3 * s, col)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		c.draw_line(p + d * 9 * s, p + d * 28 * s, col, 3.0 * s)


func _icon_reload(c: Control, p: Vector2, s: float, col: Color) -> void:
	var rr := 17 * s
	c.draw_arc(p, rr, -PI * 0.15, PI * 0.85, 24, col, 4.0 * s, true)
	c.draw_arc(p, rr, PI * 0.85 + 0.35, TAU - PI * 0.15 + 0.35 - 0.35, 24, col, 4.0 * s, true)
	var e1 := p + Vector2(cos(PI * 0.85), sin(PI * 0.85)) * rr
	var e2 := p + Vector2(cos(-PI * 0.15), sin(-PI * 0.15)) * rr
	_chevron(c, e1, PI * 0.85 + PI * 0.5, 8 * s, col, 4.0 * s)
	_chevron(c, e2, -PI * 0.15 + PI * 0.5, 8 * s, col, 4.0 * s)


func _icon_crouch(c: Control, p: Vector2, s: float, col: Color) -> void:
	# a crouching figure: head, bent back, folded legs
	c.draw_circle(p + Vector2(4, -18) * s, 6 * s, col)
	c.draw_polyline(PackedVector2Array([p + Vector2(2, -10) * s, p + Vector2(-8, 4) * s, p + Vector2(6, 8) * s, p + Vector2(0, 22) * s]), col, 5.0 * s, true)
	c.draw_line(p + Vector2(-8, 4) * s, p + Vector2(-14, 22) * s, col, 5.0 * s, true)
	c.draw_line(p + Vector2(-20, 24) * s, p + Vector2(20, 24) * s, Color(col, 0.6), 2.0 * s)


func _icon_gear(c: Control, p: Vector2, s: float, col: Color) -> void:
	for i in 8:
		var ang := i * TAU / 8.0
		var d := Vector2(cos(ang), sin(ang))
		c.draw_line(p + d * 11 * s, p + d * 19 * s, col, 6.0 * s)
	c.draw_arc(p, 12 * s, 0, TAU, 32, col, 5.0 * s, true)
	c.draw_circle(p, 4 * s, col)
