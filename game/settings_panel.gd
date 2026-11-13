class_name SettingsPanel
extends PanelContainer
## Настройки: чувствительность, поле зрения, громкость, качество графики, полный экран, прицел.

signal closed

func _ready() -> void:
	add_theme_stylebox_override("panel", UI.box(Color(0.05, 0.06, 0.075, 0.96), 16, 1))
	custom_minimum_size = Vector2(640, 0)
	UI.rtl(self)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	add_child(vb)
	vb.add_child(UI.label("الإعدادات", 28, UI.TEXT, true))
	_slider(vb, "حساسية التصويب", "sens", 0.2, 3.0, 0.05)
	_slider(vb, "مجال الرؤية", "fov", 70.0, 110.0, 1.0)
	_slider(vb, "الصوت العام", "vol_master", 0.0, 1.0, 0.02)
	_slider(vb, "الموسيقى", "vol_music", 0.0, 1.0, 0.02)
	_slider(vb, "المؤثرات", "vol_sfx", 0.0, 1.0, 0.02)
	_option(vb, "جودة الرسوم", "quality", ["منخفضة", "متوسطة", "عالية", "قصوى"])
	_option(vb, "لون علامة التصويب", "cross_color", ["أخضر", "أبيض", "سماوي", "أصفر"])
	if not G.mobile:
		_check(vb, "ملء الشاشة", "fullscreen")
		_check(vb, "المزامنة العمودية", "vsync")
	_check(vb, "إظهار عدد الإطارات", "show_fps")
	var note := UI.label("تُطبَّق جودة الرسوم من المباراة التالية.", 14, UI.DIM)
	vb.add_child(note)
	var b := UI.button("تم", 20, UI.TEAL, Vector2(200, 46))
	b.pressed.connect(func():
		G.save_settings()
		closed.emit())
	vb.add_child(b)

func _row(vb: VBoxContainer, title: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	var l := UI.label(title, 18)
	l.custom_minimum_size = Vector2(290, 0)
	hb.add_child(l)
	vb.add_child(hb)
	return hb

func _slider(vb: VBoxContainer, title: String, key: String, lo: float, hi: float, step: float) -> void:
	var hb := _row(vb, title)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(G.settings[key])
	s.custom_minimum_size = Vector2(240, 28)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	var v := UI.label("", 17, UI.AMBER, true)
	v.custom_minimum_size = Vector2(60, 0)
	var fmt := func(x: float) -> String:
		return ("%d" % int(x)) if step >= 1.0 else (("%d%%" % int(round(x * 100))) if hi <= 1.0 else ("%.2f" % x))
	v.text = fmt.call(s.value)
	s.value_changed.connect(func(x: float):
		G.settings[key] = x
		v.text = fmt.call(x)
		G.apply_settings())
	hb.add_child(s)
	hb.add_child(v)

func _option(vb: VBoxContainer, title: String, key: String, names: Array) -> void:
	var hb := _row(vb, title)
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.add_theme_font_override("font", UI.font())
	o.add_theme_font_size_override("font_size", 17)
	for n in names:
		o.add_item(n)
	o.selected = clampi(int(G.settings[key]), 0, names.size() - 1)
	o.custom_minimum_size = Vector2(240, 36)
	o.item_selected.connect(func(i: int):
		G.settings[key] = i
		G.apply_settings())
	hb.add_child(o)

func _check(vb: VBoxContainer, title: String, key: String) -> void:
	var hb := _row(vb, title)
	var c := CheckButton.new()
	c.focus_mode = Control.FOCUS_NONE
	c.button_pressed = bool(G.settings[key])
	c.toggled.connect(func(on: bool):
		G.settings[key] = on
		G.apply_settings())
	hb.add_child(c)
