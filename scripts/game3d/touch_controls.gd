extends CanvasLayer
## On-screen controls for phones. On foot: joystick, fire, aim and actions.
## In a car: driving controls and the map only. Button positions can be moved
## from Settings > Controls > Button layout (saved in Game.settings["btn_layout"]).

const W = preload("res://scripts/game3d/weapons.gd")
const JOY_R := 140.0
const LAYOUT_KEY := "btn_layout"
const EDIT_BAR_H := 150.0          # top strip reserved for the layout editor's own buttons

var world
var pad: Control
var t := 0.0
var editing := false               # layout editor mode (works without a world)

# joystick
var joy_home := Vector2(560, 820)
var joy_id := -1
var joy_base := Vector2(560, 820)
var joy_pos := Vector2(560, 820)
var joy_vec := Vector2.ZERO
# camera drag
var look_id := -1
var look_last := Vector2.ZERO
# buttons: id -> {pos, home, r, label, key, hold, mode, down}
var buttons := {}
var btn_touch := {}                # touch index -> button id
var _held := {}                    # key -> bool (keys we currently hold down)
var _aim_on := false
var _drag := {}                    # edit mode: touch index -> button id ("joy" for the stick)


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
	_btn("c4", Vector2(1310, 830), 46, "BOOM", KEY_G, false, "foot")
	# both: map and pause are always reachable
	_btn("map", Vector2(1845, 280), 46, "MAP", KEY_F11, false, "both")
	_btn("pause", Vector2(1845, 160), 46, "II", KEY_ESCAPE, false, "both")
	# in a car: driving controls only (plus map and pause)
	_btn("gas", Vector2(1480, 960), 100, "GAS", KEY_W, true, "car")
	_btn("brake", Vector2(1290, 960), 78, "BRAKE", KEY_S, true, "car")
	_btn("left", Vector2(470, 880), 88, "◀", KEY_A, true, "car")
	_btn("right", Vector2(660, 880), 88, "▶", KEY_D, true, "car")
	_btn("hand", Vector2(1760, 620), 58, "HAND", KEY_SPACE, true, "car")
	_btn("exit", Vector2(1560, 640), 58, "EXIT", KEY_E, false, "car")
	_btn("siren", Vector2(1210, 820), 52, "SIREN", KEY_Q, false, "car")
	_btn("horn", Vector2(1420, 760), 46, "HORN", KEY_H, false, "car")
	_apply_layout()


func _btn(id: String, p: Vector2, r: float, label: String, key, hold: bool, mode: String) -> void:
	buttons[id] = {"pos": p, "home": p, "r": r, "label": label, "key": key, "hold": hold, "mode": mode, "down": false}


## Positions the player saved from the layout editor.
func _apply_layout() -> void:
	var lay = Game.settings.get(LAYOUT_KEY, {})
	if not (lay is Dictionary):
		return
	for id in lay:
		var v = lay[id]
		if not (v is Array) or v.size() < 2:
			continue
		var p := Vector2(float(v[0]), float(v[1]))
		if id == "joy":
			joy_home = p
			joy_base = p
			joy_pos = p
		elif buttons.has(id):
			buttons[id].pos = p


func save_layout() -> void:
	var lay := {"joy": [joy_home.x, joy_home.y]}
	for id in buttons:
		var p: Vector2 = buttons[id].pos
		lay[id] = [p.x, p.y]
	Game.set_setting(LAYOUT_KEY, lay)


func reset_layout() -> void:
	joy_home = Vector2(560, 820)
	joy_base = joy_home
	joy_pos = joy_home
	for id in buttons:
		buttons[id].pos = buttons[id].home
	Game.set_setting(LAYOUT_KEY, {})


func start_edit() -> void:
	editing = true
	_release_all()


func stop_edit() -> void:
	editing = false
	_drag.clear()


func _in_car() -> bool:
	return world != null and world.active_car != null


func _visible_btn(b: Dictionary) -> bool:
	if editing:
		return true
	if b.mode == "both":
		return true
	var car := _in_car()
	if b.mode == "car" and not car:
		return false
	if b.mode == "foot" and car:
		return false
	return true


func _blocked() -> bool:
	return get_tree().paused or (world != null and world.hud != null and world.hud.map_open)


func _in_edit_bar(p: Vector2) -> bool:
	return editing and p.y < EDIT_BAR_H


func _input(event: InputEvent) -> void:
	if editing:
		_edit_input(event)
		return
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	if _blocked():
		# let the pause menu / map receive the touches as clicks
		if event is InputEventScreenTouch and not event.pressed:
			_release_all()
		var map_btn: Dictionary = buttons["map"]
		if event is InputEventScreenTouch and event.pressed and world.hud.map_open and event.position.distance_to(map_btn.pos) < map_btn.r + 20:
			_tap_key(KEY_F11)
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


# ---------------------------------------------------------------- layout editor input
func _edit_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if _in_edit_bar(event.position):
			return                           # the editor's own buttons get this touch
		if event.pressed:
			_edit_down(event.index, event.position)
		else:
			_drag.erase(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_edit_move(event.index, event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _in_edit_bar(event.position):
			return
		if event.pressed:
			_edit_down(99, event.position)
		else:
			_drag.erase(99)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_edit_move(99, event.position)


func _edit_down(idx: int, p: Vector2) -> void:
	var best := ""
	var best_d := INF
	if p.distance_to(joy_home) < JOY_R:
		best = "joy"
		best_d = p.distance_to(joy_home)
	for id in buttons:
		var d: float = p.distance_to(buttons[id].pos) - buttons[id].r
		if d < 30.0 and d < best_d:
			best = id
			best_d = d
	if best != "":
		_drag[idx] = best


func _edit_move(idx: int, p: Vector2) -> void:
	if not _drag.has(idx):
		return
	var id: String = _drag[idx]
	var q := Vector2(clampf(p.x, 40.0, 1880.0), clampf(p.y, EDIT_BAR_H + 20.0, 1040.0))
	if id == "joy":
		joy_home = q
		joy_base = q
		joy_pos = q
	else:
		buttons[id].pos = q


# ---------------------------------------------------------------- play input
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
	pad.visible = editing or not get_tree().paused
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


# ---------------------------------------------------------------- drawing
func _accent(id: String) -> Color:
	match id:
		"fire", "exit", "pause":
			return Game.C_RED
		"gas", "hand":
			return Game.C_GREEN
	return Game.C_CYAN


func _draw_btn(c: Control, p: Vector2, r: float, label: String, accent: Color, down: bool, fs: int) -> void:
	var rr := r * (0.95 if down else 1.0)
	c.draw_circle(p + Vector2(0, 5), rr + 3, Color(0, 0, 0, 0.35))                       # drop shadow
	c.draw_circle(p, rr, Color(0.05, 0.07, 0.11, 0.86 if down else 0.6))                 # glass body
	c.draw_arc(p, rr - 5, PI * 1.08, PI * 1.62, 24, Color(1, 1, 1, 0.16), 3.0, true)     # gloss
	c.draw_arc(p, rr, 0, TAU, 48, Color(accent, 0.95 if down else 0.6), 2.5, true)      # accent ring
	Game.dtext(c, label, p + Vector2(0, fs * 0.36), fs, Color(1, 1, 1, 0.95), Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_pad() -> void:
	var pl = world.player if world else null
	if not editing and (pl == null or pl.dead):
		return
	var c := pad
	var car := _in_car()
	# joystick (on foot only)
	if editing or not car:
		var base := joy_base if joy_id != -1 else joy_home
		var knob := joy_pos if joy_id != -1 else base
		c.draw_circle(base, JOY_R, Color(0.03, 0.05, 0.08, 0.3))
		c.draw_arc(base, JOY_R, 0, TAU, 48, Color(1, 1, 1, 0.22), 2.5, true)
		c.draw_circle(knob, 58, Color(0.6, 0.85, 1.0, 0.22 if joy_id != -1 else 0.14))
		c.draw_arc(knob, 58, 0, TAU, 32, Color(0.6, 0.85, 1.0, 0.5), 2.0, true)
		if joy_vec.length() > 0.92:
			Game.dtext(c, "RUN", base + Vector2(0, -JOY_R - 14), 18, Color(1, 1, 1, 0.7), Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
		if editing:
			c.draw_arc(base, JOY_R + 8, 0, TAU, 48, Color(1, 0.85, 0.2, 0.9), 2.0, true)
	for id in buttons:
		var b: Dictionary = buttons[id]
		if not _visible_btn(b):
			continue
		if not editing:
			if id == "siren" and not (car and world.active_car.kind == "police"):
				continue
			if id == "c4" and not (pl.current == "c4" and pl.c4_list.size() > 0):
				continue
		var fs := 26 if b.r >= 90 else (18 if b.r >= 55 else 15)
		_draw_btn(c, b.pos, b.r, _label_for(id, b), _accent(id), b.down, fs)
		if editing:
			c.draw_arc(b.pos, b.r + 8, 0, TAU, 48, Color(1, 0.85, 0.2, 0.9), 2.0, true)
