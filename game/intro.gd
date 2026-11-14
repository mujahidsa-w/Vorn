class_name Intro
extends Control
## Start-up screens before the loading screen:
##   1) studio logo on black (continues the engine's boot splash, then a gold shine passes over it);
##   2) credits: studio, developer, engine and copyright, while heavy resources start loading.
## A tap shortens the current screen.

signal skipped

const SHINE := "shader_type canvas_item;
uniform float t = -1.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float d = (UV.x + UV.y * 0.32) - (t * 1.7 - 0.25);
	float band = exp(-d * d * 260.0);
	c.rgb += vec3(1.0, 0.93, 0.72) * band * 0.9 * c.a;
	COLOR = c;
}"

const GLOW := "shader_type canvas_item;
uniform vec4 inner : source_color = vec4(0.07, 0.09, 0.15, 1.0);
uniform vec4 outer : source_color = vec4(0.02, 0.025, 0.045, 1.0);
void fragment() {
	vec2 p = (UV - vec2(0.5, 0.42)) * vec2(1.6, 1.0);
	COLOR = mix(inner, outer, smoothstep(0.0, 0.9, length(p)));
}"

var _skip := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(e: InputEvent) -> void:
	if (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed):
		_skip = true
		skipped.emit()

func _canvas() -> Vector2:
	return get_viewport().get_visible_rect().size

func _wait(sec: float) -> void:
	## waits, but returns early once the player taps
	var left := sec
	while left > 0.0 and not _skip:
		await get_tree().process_frame
		left -= get_process_delta_time()

func _clear() -> void:
	for c in get_children():
		c.queue_free()
	_skip = false

func studio() -> void:
	## Screen 1: the same picture as the boot splash (logo centred on black), so there is no jump.
	_clear()
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var cs := _canvas()
	var k := minf(cs.x / 1920.0, cs.y / 1080.0)
	var logo := TextureRect.new()
	logo.texture = UI.tex("res://assets/brand/studio_logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size = Vector2(1400, 420) * 0.62 * k
	logo.position = (cs - logo.size) * 0.5
	logo.pivot_offset = logo.size * 0.5
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHINE
	mat.shader = sh
	logo.material = mat
	add_child(logo)
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_method(func(v: float): mat.set_shader_parameter("t", v), 0.0, 1.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(logo, "scale", Vector2(1.03, 1.03), 2.4).set_trans(Tween.TRANS_SINE)
	await _wait(2.3)
	tw.kill()
	var out := create_tween()
	out.tween_property(logo, "modulate:a", 0.0, 0.25 if _skip else 0.45)
	await out.finished

func credits() -> void:
	## Screen 2: studio and developer side by side, launch line, copyright and engine credit.
	_clear()
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gm := ShaderMaterial.new()
	var gs := Shader.new()
	gs.code = GLOW
	gm.shader = gs
	bg.material = gm
	add_child(bg)
	var cs := _canvas()
	var k := minf(cs.x / 1920.0, cs.y / 1080.0)
	var body := Control.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.modulate.a = 0.0
	add_child(body)
	# studio (left) — emblem and wordmark
	var logo := TextureRect.new()
	logo.texture = UI.tex("res://assets/brand/studio_logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size = Vector2(1400, 420) * 0.44 * k
	logo.position = Vector2(cs.x * 0.29 - logo.size.x * 0.5, cs.y * 0.33 - logo.size.y * 0.5)
	body.add_child(logo)
	# divider
	var line := ColorRect.new()
	line.color = Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.35)
	line.size = Vector2(2, 230 * k)
	line.position = Vector2(cs.x * 0.53, cs.y * 0.33 - line.size.y * 0.5)
	body.add_child(line)
	# developer (right)
	var dev := VBoxContainer.new()
	dev.alignment = BoxContainer.ALIGNMENT_CENTER
	dev.add_theme_constant_override("separation", int(6 * k))
	var by := UI.label("D E V E L O P E D   B Y", int(30 * k), Color(0.72, 0.75, 0.86))
	by.add_theme_font_override("font", UI.latin())
	by.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dev.add_child(by)
	var name_l := UI.label(UI.DEVELOPER, int(104 * k), UI.GOLD, true)
	name_l.add_theme_font_override("font", UI.latin())
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	name_l.add_theme_constant_override("shadow_offset_y", int(4 * k))
	dev.add_child(name_l)
	var ar := UI.label("تطوير وتصميم", int(26 * k), Color(0.72, 0.75, 0.86))
	ar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dev.add_child(ar)
	dev.size = Vector2(cs.x * 0.36, 260 * k)
	dev.position = Vector2(cs.x * 0.74 - dev.size.x * 0.5, cs.y * 0.33 - dev.size.y * 0.5)
	body.add_child(dev)
	# launch line, copyright, engine
	var rows := [
		["%s قيد التشغيل. جارٍ فكّ موارد اللعبة..." % UI.GAME_NAME, 34, Color(0.74, 0.77, 0.92), 0.62],
		["© 2026 %s. جميع الحقوق محفوظة." % UI.STUDIO, 26, Color(0.42, 0.45, 0.56), 0.77],
		["صُنعت بمحرّك Godot Engine — برخصة MIT", 22, Color(0.36, 0.39, 0.50), 0.83],
	]
	for r in rows:
		var l := UI.label(r[0], int(float(r[1]) * k), r[2])
		l.text_direction = Control.TEXT_DIRECTION_RTL
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(cs.x, 60 * k)
		l.position = Vector2(0, cs.y * float(r[3]) - 30 * k)
		body.add_child(l)
	var tw := create_tween()
	tw.tween_property(body, "modulate:a", 1.0, 0.5)
	await _wait(3.2)
	tw.kill()
	var out := create_tween()
	out.tween_property(body, "modulate:a", 0.0, 0.25 if _skip else 0.45)
	await out.finished
