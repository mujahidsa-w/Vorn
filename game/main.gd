extends Node
## G — общий узел игры: настройки, профиль (кредиты, скины), клавиши, смена сцен, ключи запуска.

const CFG := "user://settings.json"
const SAVE := "user://profile.json"
const VERSION := "1.0"

var settings := {
	"sens": 1.0, "fov": 90.0, "vol_master": 0.8, "vol_music": 0.45, "vol_sfx": 0.9,
	"quality": 2, "fullscreen": true, "vsync": true, "crosshair": 0, "cross_color": 0,
	"name": "اللاعب", "team": "ct", "match_len": 7, "difficulty": 1, "viewmodel_fov": 54.0, "show_fps": false,
}
var profile := {"credits": 1500, "inv": [], "equip": {}, "cases": 0, "matches": 0, "wins": 0, "kills": 0}
var args := {}
var shots_dir := ""
var last_result := {}
var loop_stage := 0
var mobile := false          # phone / tablet build
var touch := false           # on-screen controls are in use
var inset := 0.0             # side safe-area margin (notch), in canvas units
var inset_b := 0.0           # bottom safe-area margin (home indicator)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_args()
	mobile = OS.has_feature("mobile") or args.has("mobile")
	touch = mobile or DisplayServer.is_touchscreen_available() or args.has("touch")
	if mobile and not FileAccess.file_exists(CFG):
		settings["quality"] = 1
	_load()
	_input_map()
	apply_settings()
	fit_screen()
	get_tree().root.size_changed.connect(fit_screen)
	if args.has("mute"):
		AudioServer.set_bus_mute(0, true)
	_prep_weapons()
	if args.has("dev"):
		# development driver (screenshots, simulated touches); only ever passed on the command line
		add_child((load(args["dev"]) as GDScript).new())

var _wkeep := {}

func _prep_weapons() -> void:
	## Материалы оружия: в запечённой карте канал затенения почти чёрный и гасил весь рассеянный свет —
	## стволы выходили чёрными силуэтами. Затенение отключается, тёмная сталь чуть высветляется.
	var dir := DirAccess.open("res://assets/models/weapons")
	if dir == null:
		return
	var lifts := {"deagle": 1.0, "c4": 1.0, "knife": 1.25, "defuser": 1.2, "he": 1.15, "flash": 1.15, "smoke": 1.15, "molotov": 1.15, "decoy": 1.15}
	for f in dir.get_files():
		var fname := String(f).trim_suffix(".import").trim_suffix(".remap")
		if not fname.ends_with(".scn") or _wkeep.has(fname):
			continue
		var ps := load("res://assets/models/weapons/" + fname) as PackedScene
		if ps == null:
			continue
		_wkeep[fname] = ps
		var lift: float = lifts.get(fname.trim_suffix(".scn"), 1.3)
		var inst := ps.instantiate()
		for c in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			if mi.mesh == null:
				continue
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i) as StandardMaterial3D
				if m and m.ao_enabled:
					m.ao_enabled = false
					m.albedo_color = Color(lift, lift, lift)
		inst.free()

var _fit_t := 0.0

func _process(dt: float) -> void:
	# the safe area is only known once the first frames are on screen, and it follows device rotation
	if mobile:
		_fit_t -= dt
		if _fit_t <= 0.0:
			_fit_t = 0.5
			fit_screen()

func fit_screen() -> void:
	## Interface scale and safe-area margins for the current screen shape.
	var win := Vector2(DisplayServer.window_get_size())
	if win.x < 1.0 or win.y < 1.0:
		return
	var aspect := win.x / win.y
	var s := 1.2
	if touch:
		s = 1.5 if aspect >= 1.95 else (1.4 if aspect >= 1.7 else 1.3)
	if args.has("uiscale"):
		s = float(args["uiscale"])
	if not is_equal_approx(get_tree().root.content_scale_factor, s):
		get_tree().root.content_scale_factor = s
	var canvas_h := maxf(1080.0, 1920.0 / aspect) / s
	var k := canvas_h / win.y
	inset = 0.0
	inset_b = 0.0
	if args.has("inset"):
		inset = float(args["inset"])
		inset_b = 14.0
	elif mobile:
		var safe := DisplayServer.get_display_safe_area()
		inset = clampf(maxf(float(safe.position.x), win.x - float(safe.end.x)) * k, 0.0, 160.0)
		inset_b = clampf((win.y - float(safe.end.y)) * k, 0.0, 60.0)

func set_mouse(mode: int) -> void:
	## Mouse capture only exists on desktop; phones have no pointer to capture.
	if not touch:
		Input.mouse_mode = mode

func _parse_args() -> void:
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		var k := String(a[i]).trim_prefix("--")
		if i + 1 < a.size() and not String(a[i + 1]).begins_with("--"):
			args[k] = String(a[i + 1])
			i += 2
		else:
			args[k] = "1"
			i += 1
	shots_dir = args.get("shots", "")
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir)

func _load() -> void:
	for pair in [[CFG, settings], [SAVE, profile]]:
		if FileAccess.file_exists(pair[0]):
			var d = JSON.parse_string(FileAccess.get_file_as_string(pair[0]))
			if d is Dictionary:
				for k in d:
					pair[1][k] = d[k]
	if args.has("windowed"):
		settings["fullscreen"] = false
	if args.has("team"):
		settings["team"] = args["team"]
	if args.has("len"):
		settings["match_len"] = int(args["len"])
	if args.has("quality"):
		settings["quality"] = clampi(int(args["quality"]), 0, 3)

func save_settings() -> void:
	if args.has("nosave"):
		return
	var f := FileAccess.open(CFG, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings, "\t"))

func save_profile() -> void:
	if args.has("nosave"):
		return
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(profile, "\t"))

func apply_settings() -> void:
	if DisplayServer.get_name() != "headless" and not mobile:
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if settings["fullscreen"] else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings["vsync"] else DisplayServer.VSYNC_DISABLED)
	var q := int(settings["quality"])
	var vp := get_viewport()
	if mobile:
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_2X, Viewport.MSAA_4X][q]
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q == 0 else Viewport.SCREEN_SPACE_AA_DISABLED
		vp.scaling_3d_scale = [0.67, 0.8, 1.0, 1.0][q]
	else:
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_4X][q]
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		vp.scaling_3d_scale = [0.77, 1.0, 1.0, 1.0][q]
	if has_node("/root/Sfx"):
		Sfx.apply_volumes()

func _input_map() -> void:
	var keys := {
		"fwd": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D, "jump": KEY_SPACE, "crouch": KEY_CTRL, "walk": KEY_SHIFT,
		"reload": KEY_R, "use": KEY_E, "buy": KEY_B, "quick": KEY_Q, "inspect": KEY_F, "score": KEY_TAB, "pause": KEY_ESCAPE,
		"slot1": KEY_1, "slot2": KEY_2, "slot3": KEY_3, "slot4": KEY_4, "slot5": KEY_5,
	}
	for n in keys:
		if not InputMap.has_action(n):
			InputMap.add_action(n)
			var e := InputEventKey.new()
			e.physical_keycode = keys[n]
			InputMap.action_add_event(n, e)
	var mouse := {"fire": MOUSE_BUTTON_LEFT, "alt": MOUSE_BUTTON_RIGHT, "next": MOUSE_BUTTON_WHEEL_DOWN, "prev": MOUSE_BUTTON_WHEEL_UP}
	for n in mouse:
		if not InputMap.has_action(n):
			InputMap.add_action(n)
			if touch:
				continue      # on touch screens these actions are driven by the on-screen buttons only
			var e := InputEventMouseButton.new()
			e.button_index = mouse[n]
			InputMap.action_add_event(n, e)

# ------------------------------------------------------------------ сцены
func to_menu() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	set_mouse(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://game/menu.tscn")

func start_match() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://game/match.tscn")

func quit() -> void:
	save_settings()
	save_profile()
	get_tree().quit()

# ------------------------------------------------------------------ проверка: кадры
func shot(name: String) -> void:
	if shots_dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [shots_dir, name])
	print("SHOT ", name)

func log_line(s: String) -> void:
	print("[FS2] ", s)

# ------------------------------------------------------------------ скины
func equipped_skin(weapon: String) -> String:
	return String(profile["equip"].get(weapon, ""))

func add_credits(n: int) -> void:
	profile["credits"] = int(profile["credits"]) + n
	save_profile()
