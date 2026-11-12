extends CanvasLayer
## In-game HUD: GTA-style GPS minimap with health/armor, full map (F11), speedometer,
## weapon/ammo, damage flash, WASTED screen with spectating, pause menu with settings.

const NeonButton = preload("res://scripts/ui/neon_button.gd")
const OptionRow = preload("res://scripts/ui/option_row.gd")
const Weapons = preload("res://scripts/game3d/weapons.gd")
const MapUI = preload("res://scripts/game3d/map_ui.gd")

const MM_SIZE := Vector2(340, 210)
const MM_RANGE := 0.55          # pixels per metre on the minimap

var world
var root: Control
var paint: Control
var minimap: Control
var bigmap: Control
var pause_root: Control
var pause_menu: Control
var settings_root: Control
var gray: ColorRect
var gray_mat: ShaderMaterial
var t := 0.0
var help_t := 14.0
## competitive match: city elements (GPS minimap, city badge, help) are hidden
var comp := false
var show_help := true
var map_open := false
var _note := ""
var _note_t := 0.0
var _dmg_t := 0.0
var _dmg_dir := Vector3.ZERO
var wasted := false
var wasted_t := 0.0
var suicide := false
var _route2d: PackedVector2Array
var _route_bounds := Rect2()
var phone


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font = Game.font_med
	root.theme = th
	add_child(root)
	# grayscale "wasted" filter (reads the screen)
	gray = ColorRect.new()
	Game.lay(gray, [0, 0, 1, 1], [0, 0, 0, 0])
	gray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount = 0.0;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 g = mix(c, vec3(l) * vec3(1.05, 0.95, 0.9), amount);
	vec2 d = SCREEN_UV - 0.5;
	float v = 1.0 - dot(d, d) * 1.6 * amount;
	COLOR = vec4(g * v, 1.0);
}"""
	gray_mat = ShaderMaterial.new()
	gray_mat.shader = sh
	gray.material = gray_mat
	gray.visible = false
	root.add_child(gray)
	paint = Control.new()
	Game.lay(paint, [0, 0, 1, 1], [0, 0, 0, 0])
	paint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paint.draw.connect(_draw_hud)
	root.add_child(paint)
	minimap = Control.new()
	minimap.clip_contents = true
	minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	Game.lay(minimap, [0, 1, 0, 1], [28, -28 - MM_SIZE.y - 22, 28 + MM_SIZE.x, -28 - 22])
	minimap.draw.connect(_draw_minimap)
	minimap.gui_input.connect(_on_minimap_input)
	root.add_child(minimap)
	bigmap = MapUI.new()
	bigmap.world = world
	bigmap.hud = self
	bigmap.close_requested.connect(_toggle_map)
	Game.lay(bigmap, [0, 0, 1, 1], [0, 0, 0, 0])
	bigmap.visible = false
	root.add_child(bigmap)
	_build_pause()


func _on_notification(text: String) -> void:
	_note = text
	_note_t = 3.0


func _prepare_route() -> void:
	if _route2d.size() > 0 or world == null or world.route.is_empty():
		return
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for i in range(0, world.route.size(), 2):
		var p: Vector3 = world.route[i]
		var v := Vector2(p.x, p.z)
		_route2d.append(v)
		mn = Vector2(minf(mn.x, v.x), minf(mn.y, v.y))
		mx = Vector2(maxf(mx.x, v.x), maxf(mx.y, v.y))
	_route_bounds = Rect2(mn, mx - mn).grow(80.0)


func _process(delta: float) -> void:
	t += delta
	if help_t > 0.0:
		help_t -= delta
		if help_t <= 0.0:
			show_help = false
	_dmg_t = maxf(0.0, _dmg_t - delta)
	if wasted:
		wasted_t += delta
		gray_mat.set_shader_parameter("amount", clampf(wasted_t / 1.2, 0.0, 1.0))
	_prepare_route()
	paint.queue_redraw()
	minimap.visible = not comp
	if comp:
		show_help = false
	else:
		minimap.queue_redraw()


func blocks_mouse() -> bool:
	return pause_root.visible or map_open


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			if map_open:
				_toggle_map()
			elif settings_root.visible:
				_close_settings()
			else:
				_toggle_pause()
			get_viewport().set_input_as_handled()
		elif (event.physical_keycode == KEY_F11 or (event.physical_keycode == KEY_M and not (map_open and bigmap.search.has_focus()))) and not pause_root.visible:
			_toggle_map()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_F1:
			show_help = not show_help
			help_t = 0.0
		elif wasted and event.physical_keycode in [KEY_LEFT, KEY_RIGHT, KEY_A, KEY_D]:
			world.spectate_next(1 if event.physical_keycode in [KEY_RIGHT, KEY_D] else -1)
	elif event is InputEventMouseButton and event.pressed and not get_tree().paused and not map_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _toggle_map() -> void:
	map_open = not map_open
	if map_open:
		bigmap.open()
	else:
		bigmap.visible = false
	# the world waits while you read the map (like GTA)
	get_tree().paused = map_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if map_open else Input.MOUSE_MODE_CAPTURED
	if Game.touch:
		Input.emulate_mouse_from_touch = map_open
	Game.play_sfx("click" if map_open else "back")


func _on_minimap_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not pause_root.visible and not wasted:
			_toggle_map()
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- pause + settings
func _toggle_pause() -> void:
	var p := not get_tree().paused
	get_tree().paused = p
	pause_root.visible = p
	pause_menu.visible = true
	settings_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if p else Input.MOUSE_MODE_CAPTURED
	if Game.touch:
		Input.emulate_mouse_from_touch = p or map_open     # menus are tapped like clicks
	Game.play_sfx("click" if p else "back")
	if p:
		Game.quiet_focus(pause_menu.get_child(1))


func _build_pause() -> void:
	pause_root = Control.new()
	Game.lay(pause_root, [0, 0, 1, 1], [0, 0, 0, 0])
	pause_root.visible = false
	root.add_child(pause_root)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.75)
	Game.lay(dim, [0, 0, 1, 1], [0, 0, 0, 0])
	pause_root.add_child(dim)
	pause_menu = Control.new()
	Game.lay(pause_menu, [0, 0, 1, 1], [0, 0, 0, 0])
	pause_root.add_child(pause_menu)
	var title := Game.label("PAUSED", 72, Game.font_wide, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	Game.lay(title, [0.5, 0.5, 0.5, 0.5], [-400, -300, 400, -210])
	pause_menu.add_child(title)
	var items := [["RESUME", "play", _toggle_pause], ["SETTINGS", "settings", _open_settings], ["RESET POSITION", "back", _reset_pos], ["RETURN TO LOBBY", "exit", _lobby]]
	for i in items.size():
		var b := NeonButton.new()
		b.setup(items[i][0], items[i][1], 34)
		b.primary = i == 0
		Game.lay(b, [0.5, 0.5, 0.5, 0.5], [-230, -160 + i * 92, 230, -84 + i * 92])
		b.pressed.connect(items[i][2])
		pause_menu.add_child(b)
	_build_settings()


func _row(parent: Control, i: int, lbl: String) -> OptionRow:
	var r := OptionRow.new()
	r.label_text = lbl
	Game.lay(r, [0.5, 0, 0.5, 0], [-560, 140 + i * 56, 560, 140 + i * 56 + 52])
	parent.add_child(r)
	return r


func _slider(parent: Control, i: int, lbl: String, key: String, lo: float, hi: float, fmt: String) -> void:
	var r := _row(parent, i, lbl)
	r.is_slider = true
	r.value = clampf((float(Game.settings.get(key, lo)) - lo) / (hi - lo), 0.0, 1.0)
	r.value_fmt = func(v: float) -> String: return fmt % (lo + (hi - lo) * v)
	r.changed.connect(func(v: float) -> void: Game.set_setting(key, lo + (hi - lo) * v))


func _cycle(parent: Control, i: int, lbl: String, opts: Array, idx: int, cb: Callable) -> void:
	var r := _row(parent, i, lbl)
	r.options = opts
	r.index = idx
	r.changed.connect(cb)


func _build_settings() -> void:
	settings_root = Control.new()
	Game.lay(settings_root, [0, 0, 1, 1], [0, 0, 0, 0])
	settings_root.visible = false
	pause_root.add_child(settings_root)
	var title := Game.label("SETTINGS", 60, Game.font_wide, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	Game.lay(title, [0.5, 0, 0.5, 0], [-400, 50, 400, 130])
	settings_root.add_child(title)
	var i := 0
	_slider(settings_root, i, "CAMERA DISTANCE", "cam_dist", 1.2, 5.5, "%.1f m"); i += 1
	_slider(settings_root, i, "FIELD OF VIEW", "fov", 50.0, 90.0, "%.0f°"); i += 1
	_slider(settings_root, i, "MOUSE SENSITIVITY", "sens", 0.2, 3.0, "%.1fx"); i += 1
	_cycle(settings_root, i, "INVERT MOUSE Y", ["OFF", "ON"], 1 if Game.settings.get("invert_y", false) else 0, func(v: int) -> void: Game.set_setting("invert_y", v == 1)); i += 1
	_cycle(settings_root, i, "GRAPHICS QUALITY", ["LOW", "MEDIUM", "HIGH"], int(Game.settings.quality), func(v: int) -> void: Game.set_setting("quality", v)); i += 1
	_cycle(settings_root, i, "RAIN", ["OFF", "ON"], 1 if Game.settings.rain else 0, _set_rain); i += 1
	_cycle(settings_root, i, "TIME OF DAY", ["DYNAMIC", "DAY", "SUNSET", "NIGHT"], int(Game.settings.get("time_mode", 0)), func(v: int) -> void: Game.set_setting("time_mode", v)); i += 1
	_cycle(settings_root, i, "MINIMAP", ["ROTATES WITH YOU", "NORTH UP"], int(Game.settings.get("map_north", 0)), func(v: int) -> void: Game.set_setting("map_north", v)); i += 1
	_cycle(settings_root, i, "GPS TURN BEEP", ["OFF", "ON"], 1 if Game.settings.get("gps_beep", true) else 0, func(v: int) -> void: Game.set_setting("gps_beep", v == 1)); i += 1
	_cycle(settings_root, i, "WEATHER", ["DYNAMIC", "CLEAR", "RAIN", "FOG"], int(Game.settings.get("weather", 0)), func(v: int) -> void: Game.set_setting("weather", v)); i += 1
	_cycle(settings_root, i, "SHOW FPS", ["OFF", "ON"], 1 if Game.settings.show_fps else 0, func(v: int) -> void: Game.set_setting("show_fps", v == 1)); i += 1
	_slider(settings_root, i, "MASTER VOLUME", "master", 0.0, 1.0, "%.0f"); i += 1
	_slider(settings_root, i, "EFFECTS VOLUME", "sfx", 0.0, 1.0, "%.0f"); i += 1
	for c in settings_root.get_children():
		if c is OptionRow and c.label_text.ends_with("VOLUME"):
			c.value_fmt = func(v: float) -> String: return "%d%%" % int(round(v * 100.0))
	var note := Game.label("Graphics quality fully applies after returning to the lobby.", 18, Game.font_med, Game.C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	Game.lay(note, [0.5, 0, 0.5, 0], [-560, 140 + i * 56 + 6, 560, 140 + i * 56 + 36])
	settings_root.add_child(note)
	var b := NeonButton.new()
	b.setup("BACK", "back", 30)
	Game.lay(b, [0.5, 1, 0.5, 1], [-180, -110, 180, -44])
	b.pressed.connect(_close_settings)
	settings_root.add_child(b)


func _set_rain(v: int) -> void:
	Game.set_setting("rain", v == 1)


func _open_settings() -> void:
	pause_menu.visible = false
	settings_root.visible = true
	Game.play_sfx("click")
	Game.quiet_focus(settings_root.get_child(1))


func _close_settings() -> void:
	settings_root.visible = false
	pause_menu.visible = true
	Game.play_sfx("back")
	Game.quiet_focus(pause_menu.get_child(2))


func _reset_pos() -> void:
	_toggle_pause()
	if world.active_car:
		world.reset_vehicle()
	elif not world.player.dead:
		world.respawn_player()


func _lobby() -> void:
	world.back_to_lobby()


# ---------------------------------------------------------------- events from world
func notify(msg: String) -> void:
	_note = msg
	_note_t = 2.5


func damage_flash(dir: Vector3) -> void:
	_dmg_t = 0.6
	_dmg_dir = dir


func show_wasted(by_self := false) -> void:
	wasted = true
	wasted_t = 0.0
	suicide = by_self
	gray.visible = true
	Game.play_sfx("beep", 0.45, 0.0)


func hide_wasted() -> void:
	wasted = false
	gray.visible = false
	gray_mat.set_shader_parameter("amount", 0.0)


# ---------------------------------------------------------------- drawing helpers
func _box(r: Rect2, acc := Color(0, 0, 0, 0)) -> void:
	paint.draw_rect(r, Color(0.03, 0.05, 0.09, 0.78))
	paint.draw_rect(r, Color(1, 1, 1, 0.1), false, 1.0)
	if acc.a > 0.0:
		paint.draw_rect(Rect2(r.position, Vector2(4, r.size.y)), acc)


func _focus_pos() -> Vector3:
	if world.active_car:
		return world.active_car.global_position
	return world.player.global_position


func _heading() -> float:
	var cam: Camera3D = world.current_camera()
	if cam == null:
		return 0.0
	var f: Vector3 = -cam.global_transform.basis.z
	return atan2(f.x, -f.z)     # 0 = north (-Z)


func _arrow(c: Control, p: Vector2, ang: float, s: float, col: Color) -> void:
	var pts := PackedVector2Array([Vector2(0, -1.2), Vector2(0.8, 0.8), Vector2(0, 0.35), Vector2(-0.8, 0.8)])
	for i in pts.size():
		pts[i] = p + pts[i].rotated(ang) * s
	c.draw_colored_polygon(pts, col)
	var outline := pts.duplicate()
	outline.append(pts[0])
	c.draw_polyline(outline, Color(0, 0, 0, 0.8), 1.5)


func _poi_icon(c: Control, p: Vector2, txt: String, col: Color, s := 11.0) -> void:
	c.draw_circle(p, s + 2.0, Color(0, 0, 0, 0.7))
	c.draw_circle(p, s, col)
	Game.dtext(c, txt, p + Vector2(0, 5), int(s * 1.2), Color(0.05, 0.05, 0.07), Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)


# ---------------------------------------------------------------- minimap (GPS)
func _draw_minimap() -> void:
	if world == null or world.player == null:
		return
	if world.gps:
		bigmap.draw_minimap(minimap)
		return
	var sz := minimap.size
	var c := sz * 0.5 + Vector2(0, 30)
	minimap.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.09, 0.12, 0.1, 0.88))
	var pp := _focus_pos()
	var h := _heading()
	var sc := MM_RANGE * (0.7 if world.active_car and absf(world.active_car.speed) > 15.0 else 1.0)
	var cs := cos(h)
	var sn := sin(h)
	var to_screen := func(wx: float, wz: float) -> Vector2:
		var dx := wx - pp.x
		var dz := wz - pp.z
		# forward f=(sn,-cs), right r=(cs,sn)
		return c + Vector2(dx * cs + dz * sn, dx * sn - dz * cs) * sc
	# grid blocks for a city feel
	var grid := 60.0
	var gx0 := floorf((pp.x - 400.0) / grid) * grid
	var gz0 := floorf((pp.z - 400.0) / grid) * grid
	for i in 14:
		var a: Vector2 = to_screen.call(gx0 + i * grid, pp.z - 400.0)
		var b: Vector2 = to_screen.call(gx0 + i * grid, pp.z + 400.0)
		minimap.draw_line(a, b, Color(1, 1, 1, 0.035), 6.0)
		var a2: Vector2 = to_screen.call(pp.x - 400.0, gz0 + i * grid)
		var b2: Vector2 = to_screen.call(pp.x + 400.0, gz0 + i * grid)
		minimap.draw_line(a2, b2, Color(1, 1, 1, 0.035), 6.0)
	# main road (route)
	var pts := PackedVector2Array()
	for v in _route2d:
		if absf(v.x - pp.x) < 600.0 and absf(v.y - pp.z) < 600.0:
			pts.append(to_screen.call(v.x, v.y))
		elif pts.size() > 1:
			minimap.draw_polyline(pts, Color(0.62, 0.64, 0.66, 0.95), 9.0, true)
			pts = PackedVector2Array()
		else:
			pts = PackedVector2Array()
	if pts.size() > 1:
		minimap.draw_polyline(pts, Color(0.62, 0.64, 0.66, 0.95), 9.0, true)
	# points of interest (clamped to the border)
	for poi in world.poi:
		var p: Vector2 = to_screen.call(poi.pos.x, poi.pos.z)
		var r := Rect2(Vector2(14, 14), sz - Vector2(28, 28))
		if not r.has_point(p):
			var d := p - c
			var k := minf(absf((r.size.x * 0.5) / maxf(absf(d.x), 0.01)), absf((sz.y * 0.5 - 14) / maxf(absf(d.y), 0.01)))
			p = (c + d * minf(k, 1.0)).clamp(r.position, r.end)
		_poi_icon(minimap, p, str(poi.name)[0], poi.color)
	# cars nearby
	for car in world.cars:
		if is_instance_valid(car) and car != world.active_car and car.global_position.distance_to(pp) < 200.0:
			var cp: Vector2 = to_screen.call(car.global_position.x, car.global_position.z)
			minimap.draw_rect(Rect2(cp - Vector2(3, 3), Vector2(6, 6)), Color(0.5, 0.5, 0.5) if car.wrecked else Color(0.9, 0.9, 0.9, 0.7))
	# teammates (real players)
	if world.net:
		for r in world.net.remotes.values():
			if is_instance_valid(r) and r.team == world.team:
				var rp: Vector2 = to_screen.call(r.global_position.x, r.global_position.z)
				var rcol := Game.C_BLUE if r.team == "cops" else Game.C_RED
				minimap.draw_circle(rp, 6.0, Color(0, 0, 0, 0.8))
				minimap.draw_circle(rp, 4.5, rcol.lightened(0.3) if not r.dead else Color(0.5, 0.5, 0.5))
	# npcs that are fighting (red dots)
	for n in world.npcs:
		if is_instance_valid(n) and n.role == "guard" and n.state == 4:
			var np: Vector2 = to_screen.call(n.global_position.x, n.global_position.z)
			minimap.draw_circle(np, 4.0, Color(1, 0.2, 0.2))
	# player arrow
	var fy: float = world.active_car.rotation.y if world.active_car else world.player.rotation.y
	var face_h := atan2(-sin(fy), -cos(fy))       # world heading of the character
	_arrow(minimap, c, face_h - h, 11.0, Color.WHITE)
	# north marker
	var np2: Vector2 = c + Vector2(-sn, -cs) * 1000.0
	var nr := Rect2(Vector2(14, 14), sz - Vector2(28, 28))
	var dn := np2 - c
	var kk := minf(absf((nr.size.x * 0.5) / maxf(absf(dn.x), 0.01)), absf((c.y - 14) / maxf(absf(dn.y), 0.01)))
	var npos := (c + dn * minf(kk, 1.0)).clamp(nr.position, nr.end)
	minimap.draw_circle(npos, 10.0, Color(0, 0, 0, 0.75))
	Game.dtext(minimap, "N", npos + Vector2(0, 6), 15, Color.WHITE, Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	minimap.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.9), false, 3.0)


# ---------------------------------------------------------------- full map (F11)
func _draw_bigmap() -> void:
	if _route_bounds.size == Vector2.ZERO:
		return
	var sz := bigmap.size
	bigmap.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.03, 0.05, 0.07, 0.94))
	var area := Rect2(Vector2(120, 110), sz - Vector2(240, 190))
	var s := minf(area.size.x / _route_bounds.size.x, area.size.y / _route_bounds.size.y)
	var off := area.position + (area.size - _route_bounds.size * s) * 0.5
	var to_map := func(x: float, z: float) -> Vector2:
		return off + (Vector2(x, z) - _route_bounds.position) * s
	bigmap.draw_rect(Rect2(off, _route_bounds.size * s), Color(0.08, 0.11, 0.1), true)
	var gstep := 100.0
	var gx := ceilf(_route_bounds.position.x / gstep) * gstep
	while gx < _route_bounds.end.x:
		bigmap.draw_line(to_map.call(gx, _route_bounds.position.y), to_map.call(gx, _route_bounds.end.y), Color(1, 1, 1, 0.04), 1.0)
		gx += gstep
	var gz := ceilf(_route_bounds.position.y / gstep) * gstep
	while gz < _route_bounds.end.y:
		bigmap.draw_line(to_map.call(_route_bounds.position.x, gz), to_map.call(_route_bounds.end.x, gz), Color(1, 1, 1, 0.04), 1.0)
		gz += gstep
	var pts := PackedVector2Array()
	for v in _route2d:
		pts.append(to_map.call(v.x, v.y))
	bigmap.draw_polyline(pts, Color(0.2, 0.22, 0.24), 12.0, true)
	bigmap.draw_polyline(pts, Color(0.66, 0.68, 0.7), 6.0, true)
	for poi in world.poi:
		var p: Vector2 = to_map.call(poi.pos.x, poi.pos.z)
		_poi_icon(bigmap, p, str(poi.name)[0], poi.color, 15.0)
		Game.dtext(bigmap, str(poi.name), p + Vector2(0, -24), 20, Color.WHITE, Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	var pp := _focus_pos()
	var fy: float = world.active_car.rotation.y if world.active_car else world.player.rotation.y
	_arrow(bigmap, to_map.call(pp.x, pp.z), atan2(-sin(fy), -cos(fy)), 14.0, Game.C_CYAN if fmod(t, 0.8) < 0.55 else Color.WHITE)
	Game.dtext(bigmap, "LOS ANGELES", Vector2(120, 80), 44, Color.WHITE, Game.font_wide)
	Game.dtext(bigmap, "[F11]  CLOSE MAP", Vector2(sz.x - 120, 80), 20, Game.C_DIM, Game.font_bold, HORIZONTAL_ALIGNMENT_RIGHT)
	var lx := 120.0
	for poi in world.poi:
		_poi_icon(bigmap, Vector2(lx + 12, sz.y - 50), str(poi.name)[0], poi.color)
		Game.dtext(bigmap, str(poi.name), Vector2(lx + 32, sz.y - 43), 18, Color.WHITE, Game.font_bold)
		lx += 190.0
	_arrow(bigmap, Vector2(lx + 12, sz.y - 50), 0.0, 10.0, Game.C_CYAN)
	Game.dtext(bigmap, "YOU", Vector2(lx + 32, sz.y - 43), 18, Color.WHITE, Game.font_bold)


# ---------------------------------------------------------------- GPS readout
func _draw_gps(mm: Rect2, bar_y: float) -> void:
	var gps = world.gps
	if gps == null:
		return
	# zone + street under the health bars, like GTA
	var line: String = gps.zone + ("   |   " + gps.street if gps.street != "" else "")
	Game.dtext(paint, line, Vector2(mm.position.x + 2, bar_y + 36), 18, Color(1, 1, 1, 0.92), Game.font_bold)
	# new area name, big and fading
	if gps.zone_flash > 0.0:
		var a := clampf(gps.zone_flash, 0.0, 1.0) * clampf((4.0 - gps.zone_flash) * 2.0, 0.0, 1.0)
		Game.dtext(paint, gps.zone, Vector2(paint.size.x - 60, paint.size.y - 300), 48, Color(1, 1, 1, a), Game.font_wide, HORIZONTAL_ALIGNMENT_RIGHT)
	if not gps.dest_set:
		return
	# destination box above the minimap: next turn and distance left
	var r := Rect2(mm.position.x, mm.position.y - 66, mm.size.x, 58)
	_box(r, Color(0.85, 0.25, 0.95))
	var txt := MapUI.fmt_dist(gps.remaining)
	if gps.turn_dir != 0 and gps.turn_dist < 400.0:
		var ac := r.position + Vector2(34, 29)
		_arrow(paint, ac, PI * 0.5 * gps.turn_dir, 14.0, Color(0.95, 0.6, 1.0))
		txt = "%s  %s   •   %s left" % ["TURN LEFT" if gps.turn_dir < 0 else "TURN RIGHT", MapUI.fmt_dist(gps.turn_dist), MapUI.fmt_dist(gps.remaining)]
	else:
		_arrow(paint, r.position + Vector2(34, 29), 0.0, 14.0, Color(0.95, 0.6, 1.0))
		txt = "%s  •  %s" % [gps.dest_name, MapUI.fmt_dist(gps.remaining)]
	Game.dtext(paint, txt, r.position + Vector2(62, 36), 18, Color.WHITE, Game.font_bold)


# ---------------------------------------------------------------- main HUD
func _draw_hud() -> void:
	var sz := paint.size
	var tc := Game.C_BLUE if world.team == "cops" else Game.C_RED
	var pl = world.player
	var car = world.active_car
	if pl == null:
		return
	# low-health vignette + damage flash
	var low := clampf((35.0 - pl.hp) / 35.0, 0.0, 1.0) if not pl.dead else 0.0
	var dmg := maxf(_dmg_t / 0.6, low * (0.45 + 0.25 * sin(t * 5.0)))
	if dmg > 0.01:
		for i in 8:
			var w := 18.0 + i * 16.0
			var a := dmg * 0.11 * (1.0 - i / 8.0)
			var col := Color(0.8, 0.0, 0.0, a)
			paint.draw_rect(Rect2(0, 0, w, sz.y), col)
			paint.draw_rect(Rect2(sz.x - w, 0, w, sz.y), col)
			paint.draw_rect(Rect2(0, 0, sz.x, w * 0.6), col)
			paint.draw_rect(Rect2(0, sz.y - w * 0.6, sz.x, w * 0.6), col)
	if _dmg_t > 0.0 and _dmg_dir.length() > 0.1 and world.current_camera():
		var cam: Camera3D = world.current_camera()
		var from := -_dmg_dir
		var l := Vector2(from.dot(cam.global_transform.basis.x), -from.dot(-cam.global_transform.basis.z))
		if l.length() > 0.05:
			var ang: float = atan2(l.x, -l.y)
			paint.draw_arc(sz * 0.5, 150, ang - PI / 2 - 0.35, ang - PI / 2 + 0.35, 24, Color(1, 0.1, 0.1, _dmg_t), 10.0, true)
	# sniper scope
	if car == null and pl.aiming and pl.current == "sniper" and pl.cam.fov < 25.0:
		var cc := sz * 0.5
		var rad := sz.y * 0.42
		var dark := Color(0, 0, 0, 0.92)
		paint.draw_rect(Rect2(0, 0, cc.x - rad, sz.y), dark)
		paint.draw_rect(Rect2(cc.x + rad, 0, sz.x - cc.x - rad, sz.y), dark)
		paint.draw_arc(cc, rad + 60, 0, TAU, 96, dark, 120.0)
		paint.draw_line(Vector2(cc.x - rad, cc.y), Vector2(cc.x + rad, cc.y), Color(0, 0, 0, 0.8), 1.5)
		paint.draw_line(Vector2(cc.x, cc.y - rad), Vector2(cc.x, cc.y + rad), Color(0, 0, 0, 0.8), 1.5)
		paint.draw_circle(cc, 2.5, Color(1, 0.1, 0.1))
	if comp:
		_draw_comp_vitals(sz, pl)
	else:
		_draw_city_vitals(pl)
	_draw_hint_and_rest(sz, pl, car, tc)


## competitive: health and armor numbers bottom-left, CS style
func _draw_comp_vitals(sz: Vector2, pl) -> void:
	var y := sz.y - 70.0
	var cm = world.get_meta("comp") if world.has_meta("comp") else null
	if cm:
		Game.dtext(paint, "$%d" % int(cm.money), Vector2(30, y - 22), 30, Color(0.45, 1.0, 0.55), Game.font_wide)
		if cm.can_buy() and not Game.touch:
			Game.dtext(paint, "B  BUY MENU", Vector2(170, y - 24), 16, Color(1, 1, 1, 0.75), Game.font_bold)
	_box(Rect2(24, y - 6, 330, 58), Game.C_CYAN)
	var hp := int(maxf(pl.hp, 0.0))
	var hp_col := Color.WHITE if hp > 30 else Color(1.0, 0.3, 0.25)
	Game.dtext(paint, "+", Vector2(44, y + 38), 34, hp_col, Game.font_wide)
	Game.dtext(paint, str(hp), Vector2(74, y + 40), 38, hp_col, Game.font_wide)
	Game.dtext(paint, "ARMOR", Vector2(176, y + 22), 13, Game.C_DIM, Game.font_tag)
	Game.dtext(paint, str(int(pl.armor)), Vector2(176, y + 46), 26, Color(0.55, 0.78, 1.0), Game.font_wide)


func _draw_city_vitals(pl) -> void:
	# health + armor bars under the minimap (GTA style)
	var mm := Rect2(minimap.position, minimap.size)
	var by := mm.end.y + 6.0
	var half := (mm.size.x - 6.0) * 0.5
	paint.draw_rect(Rect2(mm.position.x, by, mm.size.x, 12), Color(0, 0, 0, 0.75))
	paint.draw_rect(Rect2(mm.position.x + 2, by + 2, half - 2, 8), Color(0.15, 0.35, 0.18))
	paint.draw_rect(Rect2(mm.position.x + 2, by + 2, (half - 2) * clampf(pl.hp / 100.0, 0, 1), 8), Color(0.35, 0.85, 0.4) if pl.hp > 30.0 else Color(0.95, 0.25, 0.2))
	paint.draw_rect(Rect2(mm.position.x + half + 4, by + 2, half - 2, 8), Color(0.12, 0.22, 0.38))
	paint.draw_rect(Rect2(mm.position.x + half + 4, by + 2, (half - 2) * clampf(pl.armor / 50.0, 0, 1), 8), Color(0.3, 0.6, 1.0))
	_draw_gps(mm, by)
	# city identity badge
	_box(Rect2(24, 24, 390, 78), Game.C_CYAN)
	Game.dtext(paint, "VORN CITY", Vector2(46, 64), 34, Color.WHITE, Game.font_wide)
	var clock := ""
	if world.sky:
		var hh := int(world.sky.hour)
		clock = "%02d:%02d  •  %s  •  %s" % [hh, int(fmod(world.sky.hour, 1.0) * 60.0), world.sky.phase_name(), world.sky.weather_name]
		Game.dtext(paint, clock, Vector2(46, 90), 14, Game.C_DIM, Game.font_tag)


func _draw_hint_and_rest(sz: Vector2, pl, car, tc: Color) -> void:
	var hint := ""
	if pl.dead:
		hint = ""
	elif car == null:
		var pk = world.nearest_pickup(1.9)
		if pk:
			hint = "[E]  TAKE  " + ("BODY ARMOR" if pk.id == "armor" else str(Weapons.DATA[pk.id].name))
		else:
			var nc = world.nearest_car(4.5)
			if nc:
				hint = ("[E]  TAKE THIS CAR" if nc.traffic else "[E]  ENTER  " + str(nc.display_name))
	else:
		match car.engine_state:
			0:
				hint = "[W] / [I]  START ENGINE        [E]  EXIT"
			1:
				hint = "STARTING ENGINE" + ".".repeat(int(t * 3.0) % 4)
			_:
				hint = "[E]  EXIT        [I]  ENGINE OFF"
				if car.kind == "police":
					hint += "        [Q]  SIREN: " + ["OFF", "WAIL", "YELP"][car.siren_mode]
		if car.on_fire_t > 0.0:
			hint = "ENGINE ON FIRE!   [E]  GET OUT"
	if hint != "":
		var w := Game.font_bold.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 48
		_box(Rect2((sz.x - w) * 0.5, sz.y - 140, w, 50), Game.C_CYAN)
		Game.dtext(paint, hint, Vector2(sz.x * 0.5, sz.y - 107), 22, Color.WHITE, Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	if _note_t > 0.0:
		_note_t -= get_process_delta_time()
		var a := clampf(_note_t, 0.0, 1.0)
		Game.dtext(paint, _note, Vector2(sz.x * 0.5, sz.y * 0.3), 30, Color(1, 1, 1, a), Game.font_wide, HORIZONTAL_ALIGNMENT_CENTER)
	# speedometer
	if car:
		var c := Vector2(sz.x - 160, sz.y - 160)
		paint.draw_circle(c, 120, Color(0.03, 0.05, 0.09, 0.8))
		paint.draw_arc(c, 106, deg_to_rad(135), deg_to_rad(405), 64, Color(1, 1, 1, 0.12), 8.0, true)
		var f := clampf(car.kmh() / 220.0, 0.0, 1.0)
		paint.draw_arc(c, 106, deg_to_rad(135), deg_to_rad(135 + 270 * f), 64, tc.lightened(0.2), 8.0, true)
		var rp: float = car.rpm
		var rc := Game.C_CYAN if rp < 0.85 else Game.C_RED
		paint.draw_arc(c, 90, deg_to_rad(135), deg_to_rad(135 + 270 * rp), 48, rc, 4.0, true)
		Game.dtext(paint, str(car.kmh()), c + Vector2(0, 16), 56, Color.WHITE, Game.font_wide, HORIZONTAL_ALIGNMENT_CENTER)
		Game.dtext(paint, "KM/H", c + Vector2(0, 42), 15, Game.C_DIM, Game.font_tag, HORIZONTAL_ALIGNMENT_CENTER)
		var gtxt := "N" if car.engine_state != 2 else ("R" if car.speed < -0.3 else str(car.gear))
		Game.dtext(paint, gtxt, c + Vector2(0, 84), 26, Color.WHITE if car.engine_state == 2 else Game.C_DIM, Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
		Game.dtext(paint, str(car.display_name), c + Vector2(0, -52), 14, Game.C_DIM, Game.font_tag, HORIZONTAL_ALIGNMENT_CENTER)
		# vehicle health
		var vh := clampf(car.hp / 100.0, 0.0, 1.0)
		paint.draw_rect(Rect2(c.x - 70, c.y + 128, 140, 6), Color(0, 0, 0, 0.7))
		paint.draw_rect(Rect2(c.x - 70, c.y + 128, 140 * vh, 6), Color(1.0, 0.75, 0.2) if vh > 0.35 else Color(1, 0.25, 0.15))
	# weapon / crosshair
	if car == null and not pl.dead and Game.touch and pl.current != "" and not (pl.aiming and pl.current == "sniper"):
		var cct := sz * 0.5
		var gt := 6.0 if pl.aiming else 12.0
		paint.draw_circle(cct, 2.0, Color(1, 1, 1, 0.9))
		for v in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			paint.draw_line(cct + v * gt, cct + v * (gt + 8.0), Color(1, 1, 1, 0.9), 2.0)
	if car == null and not pl.dead and not Game.touch:
		if pl.current != "":
			var d: Dictionary = Weapons.DATA[pl.current]
			var r := Rect2(sz.x - 360, sz.y - 120, 336, 96)
			_box(r, tc)
			Game.dtext(paint, str(d.name), r.position + Vector2(22, 38), 24, Color.WHITE, Game.font_wide)
			var am := "RELOADING..." if pl.reload_t > 0.0 else "%d / %d" % [int(pl.ammo.get(pl.current, 0)), int(d.mag)]
			Game.dtext(paint, am, r.position + Vector2(22, 76), 28, Game.C_GOLD if pl.reload_t > 0.0 else Color.WHITE, Game.font_bold)
			var slots := ""
			for i in pl.inventory.size():
				slots += "[%d] " % (i + 1)
			Game.dtext(paint, slots, r.position + Vector2(r.size.x - 18, 76), 15, Game.C_DIM, Game.font_tag, HORIZONTAL_ALIGNMENT_RIGHT)
			if not (pl.aiming and pl.current == "sniper"):
				var cc2 := sz * 0.5
				var g := 6.0 if pl.aiming else 12.0
				var cl := Color(1, 1, 1, 0.9)
				paint.draw_circle(cc2, 2.0, cl)
				for v in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
					paint.draw_line(cc2 + v * g, cc2 + v * (g + 8.0), cl, 2.0)
			if pl.current == "c4" and pl.c4_list.size() > 0:
				Game.dtext(paint, "[G]  DETONATE (%d)" % pl.c4_list.size(), Vector2(sz.x - 192, sz.y - 136), 18, Game.C_RED, Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
		else:
			_box(Rect2(sz.x - 250, sz.y - 84, 226, 60), tc)
			Game.dtext(paint, "FISTS", Vector2(sz.x - 226, sz.y - 46), 24, Color.WHITE, Game.font_wide)
		var st: String = ["", "CROUCHING", "PRONE"][pl.stance]
		if st != "":
			Game.dtext(paint, st, Vector2(sz.x - 30, sz.y - 136 if pl.current != "" else sz.y - 100), 16, Game.C_DIM, Game.font_tag, HORIZONTAL_ALIGNMENT_RIGHT)
	# help
	if show_help and not pl.dead and not Game.touch:
		var lines := [["W A S D", "Walk"], ["SHIFT", "Run"], ["SPACE", "Jump"], ["MOUSE", "Look / Aim (RMB)"], ["LMB", "Shoot / Punch combo"],
			["C", "Crouch"], ["V", "First person"], ["1-4  X", "Switch / holster"],
			["R   G", "Reload"],
				["TAP GPS", "Open map + GPS"], ["F11 / M", "Map shortcut"], ["F5", "Reset position"], ["F1  ESC", "Help / Pause + Settings"]]
		var rr := Rect2(24, 120, 360, 40 + lines.size() * 27)
		_box(rr)
		Game.dtext(paint, "CONTROLS", Vector2(44, 148), 16, Game.C_DIM, Game.font_tag)
		for i in lines.size():
			var y := 178 + i * 27
			Game.dtext(paint, lines[i][0], Vector2(44, y), 17, Color.WHITE, Game.font_bold)
			Game.dtext(paint, lines[i][1], Vector2(140, y), 17, Game.C_TEXT, Game.font_med)
	elif not pl.dead and not Game.touch:
		Game.dtext(paint, "F1  CONTROLS", Vector2(28, 124), 14, Color(1, 1, 1, 0.4), Game.font_tag)
	if Game.settings.show_fps:
		Game.dtext(paint, "%d FPS" % Engine.get_frames_per_second(), Vector2(sz.x - 20, 30), 16, Game.C_GREEN, Game.font_bold, HORIZONTAL_ALIGNMENT_RIGHT)
	if wasted:
		_draw_wasted(sz, pl)


func _draw_wasted(sz: Vector2, pl) -> void:
	var k := clampf((wasted_t - 0.4) / 0.5, 0.0, 1.0)
	if k <= 0.0:
		return
	var band := Rect2(0, sz.y * 0.42, sz.x, 150)
	paint.draw_rect(band, Color(0, 0, 0, 0.55 * k))
	var scale_k := lerpf(1.6, 1.0, ease(k, 0.3))
	var fs := int(140 * scale_k)
	var pos := Vector2(sz.x * 0.5, band.position.y + 75 + fs * 0.33)
	for o in [Vector2(-4, 0), Vector2(4, 0), Vector2(0, -4), Vector2(0, 4), Vector2(5, 6)]:
		Game.dtext(paint, "WASTED", pos + o, fs, Color(0, 0, 0, 0.9 * k), Game.font_wide, HORIZONTAL_ALIGNMENT_CENTER)
	Game.dtext(paint, "WASTED", pos, fs, Color(0.85, 0.07, 0.07, k), Game.font_wide, HORIZONTAL_ALIGNMENT_CENTER)
	if wasted_t > 3.0:
		var k2 := clampf((wasted_t - 3.0) / 0.6, 0.0, 1.0)
		var left := maxf(pl.respawn_left, 0.0)
		var tm: Array = world.teammates()
		var spec := "NO TEAMMATES IN THIS MATCH  —  WATCHING YOUR POSITION" if tm.is_empty() else "SPECTATING TEAMMATE   ◀ A / D ▶"
		Game.dtext(paint, spec, Vector2(sz.x * 0.5, band.end.y + 50), 22, Color(1, 1, 1, 0.85 * k2), Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
		Game.dtext(paint, "RESPAWN AT BASE IN  %d:%02d" % [int(left) / 60, int(left) % 60], Vector2(sz.x * 0.5, band.end.y + 92), 30, Color(1, 0.85, 0.85, k2), Game.font_wide, HORIZONTAL_ALIGNMENT_CENTER)
