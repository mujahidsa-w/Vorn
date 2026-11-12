extends Node
## Global game state, settings, audio and small UI helpers (autoload "Game").

signal player_changed
signal settings_changed

const C_PANEL := Color(0.03, 0.05, 0.09, 0.84)
const C_CYAN := Color(0.25, 0.85, 1.0)
const C_BLUE := Color(0.25, 0.5, 1.0)
const C_RED := Color(1.0, 0.25, 0.38)
const C_GOLD := Color(1.0, 0.78, 0.25)
const C_TEXT := Color(0.88, 0.92, 0.97)
const C_DIM := Color(0.56, 0.63, 0.73)
const C_GREEN := Color(0.3, 0.95, 0.5)
const RARITY := {
	"Common": Color(0.66, 0.7, 0.75),
	"Rare": Color(0.3, 0.6, 1.0),
	"Epic": Color(0.72, 0.38, 1.0),
	"Legendary": Color(1.0, 0.75, 0.2),
}

const SAVE_PATH := "user://save.cfg"

var font_bold: Font
var font_semi: Font
var font_med: Font
var font_wide: FontVariation
var font_tag: FontVariation

var player := {
	"name": "PLAYER",
	"level": 1,
	"xp": 0.62,
	"coins": 12480,
	"gems": 860,
	"owned": [],
	"equipped": {},
	"daily_claimed": "",
	"gps_dest": null,
}
var next_screen := ""
var settings := {
	"fullscreen": true,
	"vsync": true,
	"show_fps": false,
	"rain": true,
	"max_fps": 30,
	"fps_v2": true,
	"mobile_v1": true,
	"quality": 1,
	"master": 0.8,
	"music": 0.55,
	"sfx": 0.8,
	"cam_dist": 2.3,
	"fov": 62.0,
	"sens": 1.0,
	"invert_y": false,
	"gfx_api": 0,        # Windows: 0 = DirectX 11 (ANGLE), 1 = OpenGL
	"time_mode": 0,      # 0 dynamic day/night, 1 day, 2 sunset, 3 night
	"weather": 0,        # 0 dynamic, 1 clear, 2 rain, 3 fog
	"map_north": 0,      # minimap: 0 rotates with you, 1 north up
	"gps_beep": true,
}
const DEFAULT_SETTINGS := {
	"fullscreen": true, "vsync": true, "show_fps": false, "rain": true, "max_fps": 30, "quality": 1,
	"master": 0.8, "music": 0.55, "sfx": 0.8, "cam_dist": 2.3, "fov": 62.0, "sens": 1.0, "invert_y": false,
	"gfx_api": 0, "time_mode": 0, "weather": 0, "map_north": 0, "gps_beep": true,
}

var _music: AudioStreamPlayer
var _rain: AudioStreamPlayer
var _sfx := {}
var _pool: Array[AudioStreamPlayer] = []
var _quiet := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	font_bold = load("res://assets/fonts/Rajdhani-Bold.ttf")
	font_semi = load("res://assets/fonts/Rajdhani-SemiBold.ttf")
	font_med = load("res://assets/fonts/Rajdhani-Medium.ttf")
	font_wide = FontVariation.new()
	font_wide.base_font = font_bold
	font_wide.spacing_glyph = 3
	font_tag = FontVariation.new()
	font_tag.base_font = font_med
	font_tag.spacing_glyph = 7
	# Arabic glyphs: Rajdhani is Latin-only, so every UI font falls back to Cairo for Arabic text
	var ar_bold: Font = load("res://assets/fonts/Cairo-Bold.woff")
	var ar_semi: Font = load("res://assets/fonts/Cairo-SemiBold.woff")
	var ar_med: Font = load("res://assets/fonts/Cairo-Regular.woff")
	font_bold.fallbacks = [ar_bold]
	font_semi.fallbacks = [ar_semi]
	font_med.fallbacks = [ar_med]
	font_wide.base_font = font_bold
	font_wide.fallbacks = [ar_bold]
	font_tag.fallbacks = [ar_med]
	_setup_buses()
	_setup_audio()
	load_data()
	apply_settings()


# ---------------------------------------------------------------- audio
func _setup_buses() -> void:
	for n in ["Music", "SFX"]:
		if AudioServer.get_bus_index(n) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, n)
			AudioServer.set_bus_send(i, "Master")
	# loud gunshots without harsh clipping
	var si := AudioServer.get_bus_index("SFX")
	if si >= 0 and AudioServer.get_bus_effect_count(si) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.3
		lim.pre_gain_db = 0.0
		AudioServer.add_bus_effect(si, lim)


func _looped(path: String) -> AudioStream:
	var s = load(path)
	if s is AudioStreamWAV:
		s = s.duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	return s


func _setup_audio() -> void:
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.stream = _looped("res://assets/audio/music.wav")
	add_child(_music)
	_rain = AudioStreamPlayer.new()
	_rain.bus = "SFX"
	_rain.volume_db = -10.0
	_rain.stream = _looped("res://assets/audio/rain.wav")
	add_child(_rain)
	for n in ["hover", "click", "back", "beep", "go", "whoosh", "ready", "door", "horn", "step", "shot_rifle", "shot_ak", "shot_pistol", "shot_sniper", "explosion", "rocket", "reload", "pickup", "empty", "c4beep",
			"skid", "thunder", "glass", "step_concrete_1", "step_concrete_2", "step_concrete_3", "step_tile_1", "step_tile_2", "step_tile_3",
			"step_grass_1", "step_grass_2", "step_grass_3", "step_wet_1", "step_wet_2", "step_wet_3"]:
		if ResourceLoader.exists("res://assets/audio/%s.wav" % n):
			_sfx[n] = load("res://assets/audio/%s.wav" % n)
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)


func start_ambience() -> void:
	_music.volume_db = -40.0
	_music.play()
	create_tween().tween_property(_music, "volume_db", 0.0, 2.5)
	if settings.rain:
		_rain.play()


func stop_music() -> void:
	if _music.playing:
		var tw := create_tween()
		tw.tween_property(_music, "volume_db", -40.0, 1.2)
		tw.tween_callback(_music.stop)


func play_sfx(n: String, pitch := 1.0, vol := 0.0) -> void:
	if _quiet or not _sfx.has(n):
		return
	var p: AudioStreamPlayer = _pool[0]
	for q in _pool:
		if not q.playing:
			p = q
			break
	p.stream = _sfx[n]
	p.pitch_scale = pitch
	p.volume_db = vol
	p.play()


func quiet_focus(c: Control) -> void:
	_quiet = true
	c.grab_focus()
	_quiet = false


func _bus_vol(bus: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001)


# ---------------------------------------------------------------- settings / save
func apply_settings() -> void:
	var want_fs: bool = settings.fullscreen
	var mode := DisplayServer.window_get_mode()
	var is_fs := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if want_fs and not is_fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not want_fs and is_fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var scr := DisplayServer.screen_get_usable_rect()
		var sz := Vector2i(mini(1600, int(scr.size.x * 0.9)), mini(900, int(scr.size.y * 0.9)))
		DisplayServer.window_set_size(sz)
		DisplayServer.window_set_position(scr.position + (scr.size - sz) / 2)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(settings.max_fps)
	var vp := get_tree().root if get_tree() else null
	if vp:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = [0.6, 0.8, 1.0][clampi(int(settings.quality), 0, 2)] * _dyn_scale
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096][clampi(int(settings.quality), 0, 2)], true)
	_bus_vol("Master", settings.master)
	_bus_vol("Music", settings.music)
	_bus_vol("SFX", settings.sfx)
	if _rain:
		if settings.rain and not _rain.playing and _music.playing:
			_rain.play()
		elif not settings.rain:
			_rain.stop()
	settings_changed.emit()


# ---------------------------------------------------------------- dynamic resolution
## Keeps the game at its FPS target: if a PC can't hold it, the 3D resolution drops a
## little (HUD stays sharp); when there's headroom again it slowly comes back.
var intro_shown := false
## Touch-screen build (Android) or desktop test with --touch
var touch: bool = OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--touch")
var _dyn_scale := 1.0
var _no_dyn: bool = OS.get_cmdline_args().has("--write-movie") or OS.get_cmdline_user_args().size() > 0
var _fps_acc := 0.0
var _fps_frames := 0
var _fps_win := 0.0
var _good_t := 0.0
var _cool_t := 0.0


func _notification(what: int) -> void:
	# Android back button acts like ESC (pause / go back) instead of closing the game
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		for down in [true, false]:
			var e := InputEventKey.new()
			e.keycode = KEY_ESCAPE
			e.physical_keycode = KEY_ESCAPE
			e.pressed = down
			Input.parse_input_event(e)


func _process(delta: float) -> void:
	if _no_dyn:
		return
	var target := float(settings.max_fps) if int(settings.max_fps) > 0 else 30.0
	var cs := get_tree().current_scene
	if cs == null or not (cs is Node3D):
		return
	_fps_win += delta
	_fps_frames += 1
	_cool_t = maxf(0.0, _cool_t - delta)
	if _fps_win < 1.5:
		return
	var fps := _fps_frames / _fps_win
	_fps_win = 0.0
	_fps_frames = 0
	var vp := get_tree().root
	var base: float = [0.6, 0.8, 1.0][clampi(int(settings.quality), 0, 2)]
	if fps < target * 0.9 and _dyn_scale > 0.55:
		_dyn_scale = maxf(0.55, _dyn_scale - 0.1)
		_good_t = 0.0
		_cool_t = 20.0
		vp.scaling_3d_scale = base * _dyn_scale
	elif fps >= target * 0.97:
		_good_t += 1.5
		if _good_t > 8.0 and _cool_t <= 0.0 and _dyn_scale < 1.0:
			_dyn_scale = minf(1.0, _dyn_scale + 0.05)
			_good_t = 0.0
			vp.scaling_3d_scale = base * _dyn_scale
	else:
		_good_t = 0.0


func set_setting(k: String, v) -> void:
	settings[k] = v
	apply_settings()
	save_data()
	if k == "gfx_api":
		write_render_override()


## The graphics API is chosen before the game starts, so it lives in user://override.cfg
## (read by the engine at boot). DirectX 11 runs through ANGLE; OpenGL is the native driver.
func write_render_override() -> void:
	var f := FileAccess.open("user://override.cfg", FileAccess.WRITE)
	if f == null:
		return
	f.store_string('[rendering]\n\ngl_compatibility/driver.windows="%s"\n' % ("opengl3" if int(settings.get("gfx_api", 0)) == 1 else "opengl3_angle"))
	f.close()


func render_api_name() -> String:
	var v := RenderingServer.get_video_adapter_api_version() + " " + RenderingServer.get_video_adapter_name()
	if v.contains("ANGLE") or v.contains("Direct3D"):
		return "DirectX 11"
	return "OpenGL ES" if OS.get_name() == "Android" else "OpenGL"


func save_data() -> void:
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("settings", k, settings[k])
	for k in player:
		cf.set_value("player", k, player[k])
	cf.save(SAVE_PATH)


func load_data() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		if OS.has_feature("mobile"):
			settings.quality = 0
			settings.rain = false
		return
	for k in settings:
		settings[k] = cf.get_value("settings", k, settings[k])
	if not cf.has_section_key("settings", "fps_v2"):
		settings.max_fps = 30      # new default: steady 30 FPS on every PC
	if OS.has_feature("mobile") and not cf.has_section_key("settings", "mobile_v1"):
		settings.quality = 0
		settings.rain = false
	for k in player:
		if cf.has_section_key("player", k):
			player[k] = cf.get_value("player", k)


func spend(currency: String, amount: int) -> bool:
	if int(player[currency]) < amount:
		return false
	player[currency] = int(player[currency]) - amount
	player_changed.emit()
	save_data()
	return true


func earn(currency: String, amount: int) -> void:
	player[currency] = int(player[currency]) + amount
	player_changed.emit()
	save_data()


# ---------------------------------------------------------------- helpers
func fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func label(text: String, size := 22, font: Font = null, color := C_TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font if font else font_med)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func panel_style(bg := C_PANEL, border := Color(1, 1, 1, 0.09), radius := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s


func lay(c: Control, a: Array, o: Array) -> Control:
	c.anchor_left = a[0]
	c.anchor_top = a[1]
	c.anchor_right = a[2]
	c.anchor_bottom = a[3]
	c.offset_left = o[0]
	c.offset_top = o[1]
	c.offset_right = o[2]
	c.offset_bottom = o[3]
	return c


## Draw text at a baseline position. align: LEFT / CENTER / RIGHT relative to pos.x
func dtext(ci: CanvasItem, txt: String, pos: Vector2, fs: int, col: Color, font: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT) -> float:
	var f: Font = font if font else font_med
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	ci.draw_string(f, Vector2(x, pos.y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	return w


func draw_panel(ci: CanvasItem, r: Rect2, accent := Color(0, 0, 0, 0)) -> void:
	ci.draw_rect(r, C_PANEL)
	ci.draw_rect(r, Color(1, 1, 1, 0.08), false, 1.0)
	if accent.a > 0.0:
		ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), accent)
