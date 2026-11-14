class_name LoadingScreen
extends Control
## Loading screen: key art with slow drift and dust, game logo, sound toggle, progress bar, stage line,
## percentage with UTC time, a gameplay tip, and the studio emblem turning in the corner.
## The progress is real: it follows the version check, the file check, the threaded loading of the heavy
## resources (in megabytes) and the weapon preparation.

const ARTS := ["res://assets/brand/keyart_1.jpg", "res://assets/brand/keyart_2.jpg", "res://assets/brand/keyart_3.jpg"]
const TIPS := [
	"الإصابة في الرأس تضاعف الضرر أربع مرات — اجعل علامة التصويب على مستوى الرأس.",
	"المشي البطيء والانحناء لا يُصدران صوت خطوات، فاقترب من خصمك بهدوء.",
	"الإطلاق أثناء الركض يوسّع انتشار الرصاص، توقّف لحظة قبل أن تطلق.",
	"عدّة التفكيك تختصر وقت تفكيك القنبلة كثيراً، اشترها مع الدفاع.",
	"استخدم القنبلة الدخانية لعبور الممرات المكشوفة.",
	"الرصيد يأتي من القتل والفوز وأفضل لاعب في الجولة، وتفتح به صناديق الطلاءات.",
]
const BAR_BG := Color(1, 1, 1, 0.18)

var art: TextureRect
var bar_fill: ColorRect
var bar_back: ColorRect
var status_l: Label
var pct_l: Label
var tip_l: Label
var emblem: TextureRect
var sound_btn: Button
var sound_g: Glyph
var progress := 0.0
var shown := 0.0
var t := 0.0
var _tip_i := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()

func _build() -> void:
	var cs := get_viewport().get_visible_rect().size
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	art = TextureRect.new()
	art.texture = UI.tex(ARTS[randi() % ARTS.size()])
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.pivot_offset = cs * 0.5
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	_dust(cs)
	# shade: top for the buttons, bottom for the bar and text
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type canvas_item; void fragment(){ float a = smoothstep(0.55, 1.0, UV.y) * 0.92 + smoothstep(0.16, 0.0, UV.y) * 0.35; COLOR = vec4(0.015, 0.012, 0.02, a); }"
	sm.shader = sh
	shade.material = sm
	add_child(shade)
	var side := 112.0 + G.inset
	# game logo, upper left
	var logo := TextureRect.new()
	logo.texture = UI.tex("res://assets/brand/game_logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size = Vector2(1500, 560) * 0.40
	logo.position = Vector2(side - 60.0, 40)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	# sound toggle, upper right
	sound_btn = Button.new()
	sound_btn.focus_mode = Control.FOCUS_NONE
	sound_btn.custom_minimum_size = Vector2(64, 64)
	var sb := UI.box(Color(0.1, 0.11, 0.13, 0.55), 6, 2, Color(1, 1, 1, 0.55))
	sound_btn.add_theme_stylebox_override("normal", sb)
	sound_btn.add_theme_stylebox_override("hover", sb)
	sound_btn.add_theme_stylebox_override("pressed", UI.box(Color(0.2, 0.2, 0.22, 0.7), 6, 2, UI.GOLD))
	sound_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	sound_btn.position = Vector2(cs.x - side - 64.0 + 40.0, 26)
	sound_btn.pressed.connect(_toggle_sound)
	add_child(sound_btn)
	sound_g = Glyph.make("sound", 40)
	sound_g.position = Vector2(12, 12)
	sound_btn.add_child(sound_g)
	var sl := UI.label("الصوت", 18, UI.TEXT)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.size = Vector2(120, 30)
	sl.position = sound_btn.position + Vector2(-28, 66)
	add_child(sl)
	_sound_icon()
	# progress bar
	var bar_y := cs.y - 128.0 - G.inset_b
	var bar_w := cs.x - side * 2.0 - 140.0
	bar_back = ColorRect.new()
	bar_back.color = BAR_BG
	bar_back.position = Vector2(side, bar_y)
	bar_back.size = Vector2(bar_w, 4)
	bar_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar_back)
	bar_fill = ColorRect.new()
	bar_fill.color = Color(0.98, 0.93, 0.82)
	bar_fill.position = bar_back.position
	bar_fill.size = Vector2(0, 4)
	bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar_fill)
	# percentage + time (left, above the bar) and stage (right, under the bar: Arabic reads from the right)
	pct_l = UI.label("", 24, UI.TEXT, true)
	pct_l.add_theme_font_override("font", UI.latin())
	pct_l.position = Vector2(side, bar_y - 46)
	pct_l.size = Vector2(bar_w, 36)
	pct_l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	add_child(pct_l)
	status_l = UI.label("", 22, Color(0.92, 0.92, 0.94))
	status_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_l.text_direction = Control.TEXT_DIRECTION_RTL
	status_l.position = Vector2(side, bar_y + 14)
	status_l.size = Vector2(bar_w, 36)
	status_l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	add_child(status_l)
	tip_l = UI.label("", 21, Color(1.0, 0.84, 0.36))
	tip_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tip_l.text_direction = Control.TEXT_DIRECTION_RTL
	tip_l.position = Vector2(side, bar_y + 52)
	tip_l.size = Vector2(bar_w, 34)
	tip_l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	add_child(tip_l)
	_tip_i = randi() % TIPS.size()
	tip_l.text = "نصيحة: " + TIPS[_tip_i]
	# turning emblem, lower right
	var ring := Control.new()
	ring.size = Vector2(108, 108)
	ring.position = Vector2(cs.x - side - 108.0 + 40.0, bar_y - 54.0)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.draw.connect(func():
		ring.draw_circle(ring.size * 0.5, 52.0, Color(0, 0, 0, 0.45))
		ring.draw_arc(ring.size * 0.5, 50.0, 0.0, TAU, 64, Color(1, 1, 1, 0.25), 2.0, true)
		ring.draw_arc(ring.size * 0.5, 50.0, t * 2.4, t * 2.4 + 1.3, 24, UI.GOLD, 3.0, true))
	add_child(ring)
	emblem = TextureRect.new()
	emblem.texture = UI.tex("res://assets/brand/emblem.png")
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.size = Vector2(80, 80)
	emblem.position = ring.position + Vector2(14, 14)
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(emblem)
	set_meta("ring", ring)

func _dust(cs: Vector2) -> void:
	## warm motes drifting through the evening light
	var p := CPUParticles2D.new()
	p.amount = 70
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.position = Vector2(cs.x * 0.5, cs.y * 0.55)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = cs * 0.55
	p.direction = Vector2(-1, -0.25)
	p.spread = 25.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 26.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 3.2
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.6, 0.0))
	g.set_color(1, Color(1.0, 0.85, 0.6, 0.0))
	g.add_point(0.25, Color(1.0, 0.86, 0.62, 0.55))
	g.add_point(0.75, Color(1.0, 0.80, 0.55, 0.4))
	p.color_ramp = g
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			var d := Vector2(x - 3.5, y - 3.5).length() / 4.0
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0)))
	p.texture = ImageTexture.create_from_image(img)
	add_child(p)

func _sound_icon() -> void:
	var muted := bool(G.settings.get("muted", false))
	sound_g.col = Color(1, 1, 1, 0.6) if muted else Color.WHITE
	sound_g.set_kind("mute" if muted else "sound")

func _toggle_sound() -> void:
	G.settings["muted"] = not bool(G.settings.get("muted", false))
	G.save_settings()
	Sfx.apply_volumes()
	_sound_icon()

func _process(dt: float) -> void:
	t += dt
	art.scale = Vector2.ONE * (1.0 + minf(t, 30.0) * 0.0022)
	shown = move_toward(shown, progress, dt * 0.9)
	shown = maxf(shown, progress - 0.25)
	bar_fill.size.x = bar_back.size.x * clampf(shown, 0.0, 1.0)
	var now := Time.get_datetime_dict_from_system(true)
	pct_l.text = "%d%%   %04d/%02d/%02d %02d:%02d (UTC+0)   v%s" % [int(round(shown * 100.0)), now["year"], now["month"], now["day"], now["hour"], now["minute"], G.VERSION]
	(get_meta("ring") as Control).queue_redraw()
	if fmod(t, 7.0) < dt:
		_tip_i = (_tip_i + 1) % TIPS.size()
		tip_l.text = "نصيحة: " + TIPS[_tip_i]

func _frame() -> void:
	await get_tree().process_frame

func _bytes(path: String) -> int:
	## size on disk of a resource, following the import remap for imported files (a .glb becomes a .scn)
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			return f.get_length()
	if FileAccess.file_exists(path + ".import"):
		var cf := ConfigFile.new()
		if cf.load(path + ".import") == OK:
			var rp := String(cf.get_value("remap", "path", ""))
			if rp != "" and FileAccess.file_exists(rp):
				var f2 := FileAccess.open(rp, FileAccess.READ)
				if f2:
					return f2.get_length()
	return 1 << 20

func run(paths: Array) -> void:
	## Runs every stage; returns when the lobby can open.
	var t0 := Time.get_ticks_msec()
	# 1 — version
	status_l.text = "جارٍ التحقق من التحديثات..."
	progress = 0.03
	await get_tree().create_timer(0.6).timeout
	var last := String(G.settings.get("last_version", ""))
	if last != G.VERSION:
		G.settings["last_version"] = G.VERSION
		G.save_settings()
		if last != "":
			status_l.text = "تم التحديث إلى الإصدار %s" % G.VERSION
			await get_tree().create_timer(0.8).timeout
	progress = 0.06
	# 2 — files
	status_l.text = "جارٍ التحقق من الموارد..."
	var want: Array[String] = []
	var missing := 0
	for i in paths.size():
		var p := String(paths[i])
		if ResourceLoader.exists(p):
			want.append(p)
		else:
			missing += 1
		progress = 0.06 + 0.06 * float(i + 1) / maxf(1.0, paths.size())
		await _frame()
	if missing > 0:
		G.log_line("loading: %d resources are not in this build" % missing)
	await get_tree().create_timer(0.3).timeout
	# 3 — threaded loading, shown in megabytes
	var sizes := {}
	var total := 0
	for p in want:
		sizes[p] = _bytes(p)
		total += int(sizes[p])
	var asked: Array[String] = []
	for p in want:
		if ResourceLoader.load_threaded_request(p) == OK:
			asked.append(p)
	var done := false
	while not done:
		done = true
		var got := 0.0
		for p in asked:
			var arr := []
			var st := ResourceLoader.load_threaded_get_status(p, arr)
			var f := 1.0 if st == ResourceLoader.THREAD_LOAD_LOADED or st == ResourceLoader.THREAD_LOAD_FAILED else float(arr[0] if arr.size() > 0 else 0.0)
			if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				done = false
			got += f * float(sizes[p])
		var mb := got / 1048576.0
		status_l.text = "جارٍ تحميل موارد اللعبة (%.1fMB/%.1fMB)" % [mb, float(total) / 1048576.0]
		progress = 0.12 + 0.70 * (got / maxf(1.0, float(total)))
		await _frame()
	for p in asked:
		var r = ResourceLoader.load_threaded_get(p)
		if r:
			G.warm.append(r)
	# 4 — weapons
	status_l.text = "جارٍ تجهيز الأسلحة..."
	progress = 0.86
	await _frame()
	await _frame()
	G.prepare_weapons()
	progress = 0.95
	# 5 — lobby
	status_l.text = "جارٍ الدخول إلى اللوبي..."
	var left := 3.8 - float(Time.get_ticks_msec() - t0) / 1000.0
	if left > 0.0:
		await get_tree().create_timer(left).timeout
	progress = 1.0
	while shown < 0.999:
		await _frame()
	await get_tree().create_timer(0.25).timeout
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(0, 0, 0, 1), 0.35)
	await tw.finished
