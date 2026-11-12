extends Control
## First-time name choice after signing in: the player picks the name shown in the lobby and online.

const GOLD := Color(1.0, 0.76, 0.12)
const CYAN := Color(0.25, 0.85, 1.0)

var main
var data := {}
var bg_dim := 0.0
var show_top := false
var field: LineEdit


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.08, 0.94)
	sb.border_color = Color(GOLD, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	card.add_theme_stylebox_override("panel", sb)
	Game.lay(card, [0.5, 0.5, 0.5, 0.5], [-260, -170, 260, 170])
	add_child(card)

	var title := Game.label("اختر اسمك", 34, Game.font_wide, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	Game.lay(title, [0.5, 0.5, 0.5, 0.5], [-240, -140, 240, -90])
	add_child(title)

	field = LineEdit.new()
	field.placeholder_text = "الاسم (3 إلى 16 حرف)"
	field.max_length = 16
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.add_theme_font_override("font", Game.font_bold)
	field.add_theme_font_size_override("font_size", 26)
	field.text_submitted.connect(func(_t: String): _confirm())
	Game.lay(field, [0.5, 0.5, 0.5, 0.5], [-220, -70, 220, -18])
	add_child(field)

	var ok := Button.new()
	ok.text = "تأكيد"
	ok.focus_mode = Control.FOCUS_NONE
	ok.add_theme_font_override("font", Game.font_wide)
	ok.add_theme_font_size_override("font_size", 26)
	ok.add_theme_color_override("font_color", Color(0.06, 0.05, 0.02))
	var ok_sb := StyleBoxFlat.new()
	ok_sb.bg_color = GOLD
	ok_sb.set_corner_radius_all(8)
	ok.add_theme_stylebox_override("normal", ok_sb)
	ok.add_theme_stylebox_override("hover", ok_sb)
	ok.add_theme_stylebox_override("pressed", ok_sb)
	Game.lay(ok, [0.5, 0.5, 0.5, 0.5], [-220, 10, 220, 80])
	ok.pressed.connect(_confirm)
	add_child(ok)
	field.call_deferred("grab_focus")


func _confirm() -> void:
	var nm := field.text.strip_edges()
	if nm.length() < 3:
		main.toast("الاسم لازم يكون 3 أحرف على الأقل", CYAN)
		return
	Online._set_profile_name(nm)
	Game.player.name_set = true
	Game.save_data()
	Online._save()
	if Online.is_signed_in():
		Online._start_presence()
	main.go("menu")


func on_back() -> void:
	pass
