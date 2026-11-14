class_name UI
extends RefCounted
## Общий стиль интерфейса: тёмные панели, янтарь (атака) и бирюза (защита), шрифты, кнопки, значки оружия.

const AMBER := Color(0.97, 0.66, 0.15)
const TEAL := Color(0.26, 0.80, 0.74)
const PANEL := Color(0.055, 0.065, 0.08, 0.88)
const PANEL2 := Color(0.11, 0.125, 0.15, 0.92)
const LINE := Color(1, 1, 1, 0.10)
const TEXT := Color(0.93, 0.94, 0.95)
const DIM := Color(0.62, 0.66, 0.70)
const RED := Color(0.93, 0.27, 0.22)
const GREEN := Color(0.45, 0.86, 0.42)
# AURUM STRIKE: золото бренда, тёмный графит лобби
const GOLD := Color(0.95, 0.76, 0.33)
const GOLD_HI := Color(1.0, 0.90, 0.60)
const GOLD_DK := Color(0.55, 0.38, 0.10)
const INK := Color(0.035, 0.04, 0.05, 0.86)

const GAME_NAME := "AURUM STRIKE"
const GAME_NAME_AR := "أوروم سترايك"
const STUDIO := "SAQR STUDIOS"
const STUDIO_AR := "استوديوهات صقر"
const DEVELOPER := "Mujahid"

static var _font: Font
static var _bold: Font
static var _latin: Font
static var _icons := {}

static func team_col(t: String) -> Color:
	return AMBER if t == "t" else TEAL

static func _mk(weight: int) -> Font:
	# Cairo covers Arabic and Latin; the symbols font supplies the few pictograms the HUD uses
	var fv := FontVariation.new()
	fv.base_font = load("res://assets/fonts/Cairo.ttf")
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	var fb: Array[Font] = [load("res://assets/fonts/NotoSansSymbols2.ttf")]
	fv.fallbacks = fb
	return fv

static func font() -> Font:
	if _font == null:
		_font = _mk(600)
	return _font

static func bold() -> Font:
	if _bold == null:
		_bold = _mk(800)
	return _bold

static func latin() -> Font:
	## Oxanium for numbers, levels and Latin labels; Cairo stays as the fallback for Arabic glyphs
	if _latin == null:
		var fv := FontVariation.new()
		fv.base_font = load("res://assets/fonts/Oxanium.ttf")
		var fb: Array[Font] = [bold()]
		fv.fallbacks = fb
		_latin = fv
	return _latin

static func tex(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

static func rtl(c: Control) -> Control:
	## Arabic panels read right to left: rows, sliders and labels are mirrored inside the control.
	c.layout_direction = Control.LAYOUT_DIRECTION_RTL
	return c

static func box(col := PANEL, radius := 10, border := 0, bcol := LINE) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = bcol
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.anti_aliasing = true
	return s

static func label(text: String, size := 20, col := TEXT, is_bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", bold() if is_bold else font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

static func button(text: String, size := 22, accent := AMBER, min_size := Vector2(0, 48)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", bold())
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", accent)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.3))
	b.add_theme_stylebox_override("normal", box(PANEL2, 8, 1, LINE))
	b.add_theme_stylebox_override("hover", box(Color(0.16, 0.18, 0.21, 0.96), 8, 2, accent))
	b.add_theme_stylebox_override("pressed", box(Color(0.20, 0.22, 0.25, 1.0), 8, 2, accent))
	b.add_theme_stylebox_override("disabled", box(Color(0.08, 0.09, 0.10, 0.7), 8, 1, LINE))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.mouse_entered.connect(func(): Sfx.ui("ui_hover", -16.0))
	b.pressed.connect(func(): Sfx.ui("ui_click", -8.0))
	return b

static func icon(wid: String) -> Texture2D:
	if _icons.has(wid):
		return _icons[wid]
	var p := "res://assets/ui/icons/%s.png" % wid
	var t: Texture2D = load(p) if ResourceLoader.exists(p) else null
	_icons[wid] = t
	return t

static func money(n: int) -> String:
	return "$%d" % n

static func time_str(t: float) -> String:
	var s := int(ceil(maxf(t, 0.0)))
	return "%d:%02d" % [s / 60, s % 60]
