extends CanvasLayer
## On-screen controls for phones: movement joystick, camera drag, action buttons,
## and driving controls. They feed the same inputs the keyboard and mouse use.

const W = preload("res://scripts/game3d/weapons.gd")

var world
var pad: Control
var t := 0.0

# joystick
var joy_id := -1
var joy_base := Vector2(560, 820)
var joy_pos := Vector2(560, 820)
var joy_vec := Vector2.ZERO
const JOY_R := 140.0
# camera drag
var look_id := -1
var look_last := Vector2.ZERO
# buttons: id -> {pos, r, label, key, hold, mode}
var buttons := {}
var btn_touch := {}           # touch index -> button id
var _held := {}               # key -> bool (keys we currently hold down)
var _aim_on := false


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	pad = Control.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.draw.connect(_draw_pad)
	add_child(pad)
	Input.emulate_mouse_from_touch = false
	# on foot
	_btn("fire", Vector2(1660, 790), 100, "FIRE", "lmb", true, "foot")
	_btn("aim", Vector2(1490, 945), 58, "AIM", "aim", false, "foot")
	_btn("jump", Vector2(1845, 620), 58, "JUMP", KEY_SPACE, false, "foot")
	_btn("crouch", Vector2(1845, 950), 58, "CROUCH", KEY_C, false, "foot")
	_btn("reload", Vector2(1490, 630), 50, "RELOAD", KEY_R, false, "foot")
	_btn("use", Vector2(1665, 545), 58, "USE", KEY_E, false, "foot")
	_btn("weapon", Vector2(1310, 985), 52, "WEAPON", "weapon", false, "foot")
	_btn("view", Vector2(1845, 400), 46, "VIEW", KEY_V, false, "both")
	_btn("map", Vector2(1845, 280), 46, "MAP", KEY_F11, false, "both")
	_btn("pause", Vector2(1845, 160), 46, "II", KEY_ESCAPE, false, "both")
	_btn("c4", Vector2(1310, 830), 46, "BOOM", KEY_G, false, "foot")
	# in a car
	_btn("gas", Vector2(1760, 860), 100, "GAS", KEY_W, true, "car")
	_btn("brake", Vector2(1530, 920), 78, "BRAKE", KEY_S, true, "car")
	_btn("left", Vector2(170, 880), 92, "◀", KEY_A, true, "car")
	_btn("right", Vector2(420, 880), 92, "▶", KEY_D, true, "car")
	_btn("hand", Vector2(1760, 620), 58, "HAND", KEY_SPACE, true, "car")
	_btn("exit", Vector2(1560, 640), 58, "EXIT", KEY_E, false, "car")
	_btn("siren", Vector2(1360, 980), 52, "SIREN", KEY_Q, false, "car")
	_btn("horn", Vector2(1360, 820), 46, "HORN", KEY_H, false, "car")


func _btn(id: String, p: Vector2, r: float, label: String, key, hold: bool, mode: String) -> void:
	buttons[id] = {"pos": p, "r": r, "label": label, "key": key, "hold": hold, "mode": mode, "down": false}


func _in_car() -> bool:
	return world != null and world.active_car != null


func _visible_btn(b: Dictionary) -> bool:
	if b.mode == "both":
		return true
	var car := _in_car()
	if b.mode == "car" and not car:
		return false
	if b.mode == "foot" and car:
		return false
	return true


func _canvas_pos(screen_pos: Vector2) -> Vector2:
	# touch positions are in window pixels; the UI is laid out on a 1920x1080 canvas
	# Godot already maps touch positions onto the 1920x1080 canvas before _input
	return screen_pos


func _blocked() -> bool:
	return get_tree().paused or (world and world.hud and world.hud.map_open)


func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	if _blocked():
		# let the pause menu / map receive the touches as clicks
		if event is InputEventScreenTouch and not event.pressed:
			_release_all()
		var map_btn: Dictionary = buttons["map"]
		if event is InputEventScreenTouch and event.pressed and world.hud.map_open and _canvas_pos(event.position).distance_to(map_btn.pos) < map_btn.r + 20:
			_tap_key(KEY_F11)
		return
	var p := _canvas_pos(event.position)
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
		if _visible_btn(b) and p.distance_to(b.pos) < b.r + 14:
			btn_touch[idx] = id
			_press(id)
			if id == "fire":
				look_id = idx       # dragging the fire button also aims (like mobile shooters)
				look_last = p
			return
	if p.x < 1000 and p.y > 380 and not _in_car():
		joy_id = idx
		joy_base = p
		joy_pos = p
		joy_vec = Vector2.ZERO
		return
	if p.x > 1000 and look_id == -1:
		look_id = idx
		look_last = p


func _touch_drag(idx: int, p: Vector2, rel: Vector2) -> void:
	if idx == joy_id:
		var d := p - joy_base
		if d.length() > JOY_R:
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
	var sens := 0.0042 * float(Game.settings.get("sens", 1.0))
	if _in_car():
		world.active_car.cam_yaw_off = clampf(world.active_car.cam_yaw_off - rel.x * sens * 0.8, -2.6, 2.6)
		return
	var pl = world.player
	if pl == null or pl.dead:
		return
	if pl.aiming:
		sens *= 0.5
	var inv := -1.0 if bool(Game.settings.get("invert_y", false)) else 1.0
	pl.yaw -= rel.x * sens
	pl.pitch = clampf(pl.pitch - rel.y * sens * inv, -1.25, 0.8)


func _apply_joystick() -> void:
	var v := joy_vec
	_hold(KEY_W, v.y < -0.3)
	_hold(KEY_S, v.y > 0.3)
	_hold(KEY_A, v.x < -0.3)
	_hold(KEY_D, v.x > 0.3)
	_hold(KEY_SHIFT, v.length() > 0.92)


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
	match str(b.key):
		"lmb":
			_mouse(MOUSE_BUTTON_LEFT, true)
		"aim":
			_aim_on = not _aim_on
			_mouse(MOUSE_BUTTON_RIGHT, _aim_on)
		"weapon":
			var pl = world.player
			if pl and pl.inventory.size() > 0:
				var i: int = pl.inventory.find(pl.current)
				var nxt := i + 1
				if nxt >= pl.inventory.size():
					pl.equip("")
				else:
					pl.equip(pl.inventory[nxt])
				Game.play_sfx("click", 1.2, -6.0)
		_:
			if b.hold:
				_hold(b.key, true)
			else:
				_tap_key(b.key)


func _release(id: String) -> void:
	var b: Dictionary = buttons[id]
	b.down = false
	if str(b.key) == "lmb":
		_mouse(MOUSE_BUTTON_LEFT, false)
	elif b.hold and not (b.key is String):
		_hold(b.key, false)


func _release_all() -> void:
	for idx in btn_touch.keys():
		_release(btn_touch[idx])
	btn_touch.clear()
	for k in _held.keys():
		_hold(k, false)
	joy_id = -1
	look_id = -1
	joy_vec = Vector2.ZERO


func _process(delta: float) -> void:
	t += delta
	# aim toggle follows the weapon (no aiming with fists)
	if _aim_on and world and world.player and world.player.current == "":
		_aim_on = false
		_mouse(MOUSE_BUTTON_RIGHT, false)
	if _in_car() and joy_id != -1:
		joy_id = -1
		joy_vec = Vector2.ZERO
		_apply_joystick()
	pad.visible = not get_tree().paused
	pad.queue_redraw()


func _label_for(id: String, b: Dictionary) -> String:
	var pl = world.player if world else null
	match id:
		"use":
			if pl and not _in_car():
				var pk = world.nearest_pickup(1.9)
				if pk:
					return "TAKE"
				if world.nearest_car(4.5):
					return "ENTER"
			return "USE"
		"weapon":
			if pl and pl.current != "":
				var nm := str(W.DATA[pl.current].name).get_slice(" ", 0)
				if pl.reload_t > 0.0:
					return nm + " ..."
				return nm + " %d/%d" % [int(pl.ammo.get(pl.current, 0)), int(W.DATA[pl.current].mag)]
			return "FISTS"
		"aim":
			return "AIM" if not _aim_on else "AIM ✓"
	return str(b.label)


func _draw_pad() -> void:
	if world == null or world.player == null or world.player.dead:
		return
	var c := pad
	# joystick
	if not _in_car():
		var base := joy_base if joy_id != -1 else Vector2(560, 820)
		var knob := joy_pos if joy_id != -1 else base
		c.draw_circle(base, JOY_R, Color(0, 0, 0, 0.22))
		c.draw_arc(base, JOY_R, 0, TAU, 48, Color(1, 1, 1, 0.25), 3.0, true)
		c.draw_circle(knob, 58, Color(1, 1, 1, 0.28 if joy_id != -1 else 0.16))
		c.draw_arc(knob, 58, 0, TAU, 32, Color(1, 1, 1, 0.5), 2.0, true)
		if joy_vec.length() > 0.92:
			Game.dtext(c, "RUN", base + Vector2(0, -JOY_R - 14), 18, Color(1, 1, 1, 0.7), Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	for id in buttons:
		var b: Dictionary = buttons[id]
		if not _visible_btn(b):
			continue
		if id == "siren" and not (_in_car() and world.active_car.kind == "police"):
			continue
		if id == "c4" and not (world.player.current == "c4" and world.player.c4_list.size() > 0):
			continue
		var accent := Game.C_RED if id == "fire" else (Game.C_GREEN if id == "gas" else Game.C_CYAN)
		var a := 0.55 if b.down else 0.3
		c.draw_circle(b.pos, b.r, Color(0.02, 0.04, 0.08, a))
		c.draw_arc(b.pos, b.r, 0, TAU, 40, Color(accent, 0.85 if b.down else 0.55), 3.0, true)
		var fs := 26 if b.r >= 90 else (18 if b.r >= 55 else 15)
		Game.dtext(c, _label_for(id, b), b.pos + Vector2(0, fs * 0.36), fs, Color(1, 1, 1, 0.9), Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
