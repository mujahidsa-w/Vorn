extends Control
## Lobby background: slow camera drift + mouse parallax, flashing police lights,
## neon flicker, lightning, and a dim overlay used by sub-screens.

var tex: Texture2D = preload("res://assets/img/lobby_bg.jpg")
var glow: GradientTexture2D
var lights: Control
var t := 0.0
var dim := 0.0
var dim_target := 0.0
var flash := 0.0
var img_pos := Vector2.ZERO
var img_scale := 1.0
var _m := Vector2.ZERO
var _next_flash := 9.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.4))
	glow = GradientTexture2D.new()
	glow.gradient = g
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(0.5, 0.0)
	glow.width = 128
	glow.height = 128
	lights = Control.new()
	lights.set_anchors_preset(Control.PRESET_FULL_RECT)
	lights.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	lights.material = mat
	lights.draw.connect(_draw_lights)
	add_child(lights)


func _process(delta: float) -> void:
	t += delta
	var m := Vector2.ZERO
	if size.x > 0.0:
		m = (get_local_mouse_position() / size) - Vector2(0.5, 0.5)
		m = m.clamp(Vector2(-0.6, -0.6), Vector2(0.6, 0.6))
	_m = _m.lerp(m, 1.0 - exp(-delta * 2.5))
	dim = lerpf(dim, dim_target, 1.0 - exp(-delta * 5.0))
	_next_flash -= delta
	if _next_flash <= 0.0:
		_next_flash = randf_range(12.0, 26.0)
		if Game.settings.rain:
			flash = 1.0
	flash = maxf(0.0, flash - delta * 2.6)
	queue_redraw()
	lights.queue_redraw()


func _draw() -> void:
	var ts := tex.get_size()
	img_scale = maxf(size.x / ts.x, size.y / ts.y) * (1.05 + 0.012 * sin(t * 0.2))
	var dsize := ts * img_scale
	img_pos = (size - dsize) * 0.5 - _m * Vector2(36, 20)
	draw_texture_rect(tex, Rect2(img_pos, dsize), false)
	var c0 := Color(0.01, 0.02, 0.04, 0.8)
	var c1 := Color(0.01, 0.02, 0.04, 0.0)
	var lw := 760.0
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(lw, 0), Vector2(lw, size.y), Vector2(0, size.y)]), PackedColorArray([c0, c1, c1, c0]))
	var bh := 260.0
	var cb := Color(0.01, 0.02, 0.04, 0.6)
	draw_polygon(PackedVector2Array([Vector2(0, size.y - bh), Vector2(size.x, size.y - bh), Vector2(size.x, size.y), Vector2(0, size.y)]), PackedColorArray([c1, c1, cb, cb]))
	if dim > 0.001:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.015, 0.035, dim))
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.75, 0.82, 1.0, flash * 0.13 * (0.6 + 0.4 * sin(t * 70.0))))


func _glow(p_img: Vector2, r_img: float, col: Color) -> void:
	var p := img_pos + p_img * img_scale
	var r := r_img * img_scale
	lights.draw_texture_rect(glow, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, col)


func _draw_lights() -> void:
	var k := 1.0 - dim
	if k <= 0.02:
		return
	var ph := fmod(t * 2.2, 1.0)
	var blue := 1.0 if (ph < 0.1 or (ph > 0.18 and ph < 0.28)) else 0.12
	var red := 1.0 if ((ph > 0.5 and ph < 0.6) or (ph > 0.68 and ph < 0.78)) else 0.12
	_glow(Vector2(760, 938), 150, Color(0.2, 0.35, 1.0, 0.7 * blue * k))
	_glow(Vector2(828, 940), 150, Color(1.0, 0.12, 0.18, 0.6 * red * k))
	_glow(Vector2(790, 960), 560, Color(0.2, 0.3, 1.0, 0.14 * blue * k))
	_glow(Vector2(790, 960), 560, Color(1.0, 0.1, 0.2, 0.12 * red * k))
	var f := 1.0
	var nt := fmod(t, 7.0)
	if nt > 5.6 and nt < 6.1:
		f = 0.15 if fmod(t * 18.0, 1.0) > 0.5 else 1.0
	_glow(Vector2(2180, 660), 260, Color(1.0, 0.15, 0.45, 0.2 * f * k))
	_glow(Vector2(1972, 343), 70, Color(1, 1, 1, (0.35 + 0.15 * sin(t * 3.0)) * k))
