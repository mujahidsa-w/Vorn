extends Control
## Settings: graphics, audio, controls. Saved automatically.

const UI = preload("res://scripts/ui/ui.gd")
const OptionRow = preload("res://scripts/ui/option_row.gd")

var main
var data := {}
var bg_dim := 0.7
var show_top := true

const FPS_OPTS := [0, 30, 60, 120, 144]
const KEYS := [
	["W A S D", "Walk"], ["SHIFT   SPACE", "Run / Jump"], ["MOUSE", "Look  •  RMB aim"], ["LMB", "Shoot / Punch"], ["C", "Crouch"],
	["V", "First person"], ["1-4  X", "Switch / Holster"], ["R   G", "Reload"],
	["F11  /  M", "Map + GPS (click to set a destination)"], ["ALT+ENTER", "Toggle fullscreen"], ["ESC", "Pause / Settings"],
]

var tab := 0
var tab_btns: Array = []
var content: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.back_button(self, on_back)
	UI.header(self, "SETTINGS", "CHANGES ARE SAVED AUTOMATICALLY")
	var names := ["GRAPHICS", "AUDIO", "CONTROLS", "MOBILE"]
	for i in 4:
		var b := UI.button(self, names[i], "", 24, Rect2(50 + i * 196, 236, 186, 58), _set_tab.bind(i))
		b.set("centered", true)
		tab_btns.append(b)
	UI.paint(self, func(c: Control): Game.draw_panel(c, Rect2(Vector2.ZERO, c.size)), Rect2(50, 310, 1100, 700))
	content = Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.rect(content, 70, 330, 1060, 660)
	add_child(content)
	var reset := UI.button(self, "RESET", "", 22, Rect2(850, 236, 300, 58), _reset, Game.C_RED)
	reset.set("centered", true)
	var who := "GOOGLE:  " + Online.email if not Online.guest else "GUEST ACCOUNT"
	var acc := Game.label("ACCOUNT\n" + Online.display_name + "\n" + who, 20, Game.font_semi, Game.C_TEXT)
	UI.rect(acc, 1200, 320, 600, 100)
	add_child(acc)
	var so := UI.button(self, "SIGN OUT", "exit", 22, Rect2(1200, 430, 300, 58), _sign_out, Game.C_RED)
	so.set("centered", true)
	_set_tab(0)


func _sign_out() -> void:
	main.confirm("SIGN OUT?", "You will return to the sign-in screen.", "SIGN OUT", _do_sign_out)


func _do_sign_out() -> void:
	Online.sign_out()
	main.go("login")


func _set_tab(i: int) -> void:
	tab = i
	for k in tab_btns.size():
		tab_btns[k].set("primary", k == i)
	for c in content.get_children():
		c.queue_free()
	match i:
		0:
			_opt("Graphics Quality", ["LOW  (FAST)", "MEDIUM", "HIGH"], int(Game.settings.quality), func(v): Game.set_setting("quality", v))
			_opt("Display Mode", ["WINDOWED", "FULLSCREEN"], 1 if Game.settings.fullscreen else 0, func(v): Game.set_setting("fullscreen", v == 1))
			_opt("V-Sync", ["OFF", "ON"], 1 if Game.settings.vsync else 0, func(v): Game.set_setting("vsync", v == 1))
			var fps_labels := ["UNLIMITED", "30", "60", "120", "144"]
			_opt("Max FPS", fps_labels, maxi(0, FPS_OPTS.find(int(Game.settings.max_fps))), func(v): Game.set_setting("max_fps", FPS_OPTS[v]))
			_opt("Shadows", ["OFF  (FAST)", "ON"], 1 if Game.settings.shadows else 0, func(v): Game.set_setting("shadows", v == 1))
			_opt("Fire & Smoke Effects", ["LOW", "HIGH"], int(Game.settings.fx_level), func(v): Game.set_setting("fx_level", v))
			if OS.get_name() == "Windows":
				_opt("Graphics API  (now: %s)" % Game.render_api_name(), ["DIRECTX 11", "OPENGL"], int(Game.settings.gfx_api), func(v):
					Game.set_setting("gfx_api", v)
					main.toast("RESTART THE GAME TO SWITCH THE GRAPHICS API"))
			_opt("Show FPS", ["OFF", "ON"], 1 if Game.settings.show_fps else 0, func(v): Game.set_setting("show_fps", v == 1))
		1:
			_slider("Master Volume", Game.settings.master, func(v): Game.set_setting("master", v))
			_slider("Music", Game.settings.music, func(v): Game.set_setting("music", v))
			_slider("Effects & Ambience", Game.settings.sfx, func(v): Game.set_setting("sfx", v))
		2:
			var p := UI.paint(content, _draw_keys, Rect2(0, 0, 1060, 660))
			p.name = "keys"
		3:
			_slider("Look Sensitivity", clampf(float(Game.settings.sens) / 3.0, 0.0, 1.0), func(v): Game.set_setting("sens", maxf(0.15, v * 3.0)))
			_slider("Aim Sensitivity", clampf(float(Game.settings.aim_sens), 0.0, 1.0), func(v): Game.set_setting("aim_sens", maxf(0.15, v)))
			_opt("Invert Look (Y)", ["OFF", "ON"], 1 if Game.settings.invert_y else 0, func(v): Game.set_setting("invert_y", v == 1))
			_opt("Button Size", ["SMALL", "MEDIUM", "LARGE"], int(Game.settings.btn_scale), func(v): Game.set_setting("btn_scale", v))
			_slider("Button Opacity", clampf(float(Game.settings.btn_alpha), 0.0, 1.0), func(v): Game.set_setting("btn_alpha", maxf(0.2, v)))
			_opt("Left Fire Button", ["OFF", "ON"], 1 if Game.settings.left_fire else 0, func(v): Game.set_setting("left_fire", v == 1))
	await get_tree().process_frame
	for c in content.get_children():
		if c is Button and not c.is_queued_for_deletion():
			Game.quiet_focus(c)
			return
	Game.quiet_focus(tab_btns[i])


func _row_y() -> float:
	var n := 0
	for c in content.get_children():
		if not c.is_queued_for_deletion():
			n += 1
	return n * 73.0


func _opt(lbl: String, opts: Array, idx: int, cb: Callable) -> void:
	var r := OptionRow.new()
	r.label_text = lbl
	r.options = opts
	r.index = idx
	UI.rect(r, 0, _row_y(), 1060, 70)
	r.changed.connect(cb)
	content.add_child(r)


func _slider(lbl: String, v: float, cb: Callable) -> void:
	var r := OptionRow.new()
	r.label_text = lbl
	r.is_slider = true
	r.value = v
	UI.rect(r, 0, _row_y(), 1060, 70)
	r.changed.connect(cb)
	content.add_child(r)


func _draw_keys(c: Control) -> void:
	for i in KEYS.size():
		var col := i % 2
		var row := i / 2
		var x := col * 530.0
		var y := row * 72.0 + 10.0
		var k: String = KEYS[i][0]
		var kw := maxf(56.0, Game.font_bold.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 24.0)
		c.draw_rect(Rect2(x, y, kw, 44), Color(1, 1, 1, 0.08))
		c.draw_rect(Rect2(x, y, kw, 44), Color(1, 1, 1, 0.35), false, 1.0)
		Game.dtext(c, k, Vector2(x + kw * 0.5, y + 30), 20, Color.WHITE, Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
		Game.dtext(c, KEYS[i][1], Vector2(x + kw + 18, y + 30), 22, Game.C_TEXT, Game.font_med)
	Game.dtext(c, "Gameplay controls become active in the next build. Key rebinding coming soon.", Vector2(0, 640), 18, Game.C_DIM, Game.font_med)


func _reset() -> void:
	Game.settings = Game.DEFAULT_SETTINGS.duplicate()
	Game.settings["fps_v2"] = true
	Game.settings["mobile_v1"] = true
	Game.write_render_override()
	Game.apply_settings()
	Game.save_data()
	main.toast("Settings reset to default")
	_set_tab(tab)


func on_back() -> void:
	Game.play_sfx("back")
	main.go("menu")
