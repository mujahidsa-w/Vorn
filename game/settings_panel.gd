class_name SettingsPanel
extends PanelContainer
## Settings on the whole screen: the sections on the right, the chosen section's options in the middle.
## Every choice is a row of buttons (no drop-down pop-ups: those froze the paused game on phones).

signal closed

const SECTIONS := [["basic", "أساسي"], ["graphics", "الرسومات"], ["controls", "التحكم"], ["sound", "الصوت"]]
var body: VBoxContainer
var tabs := {}
var cur := "basic"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS          # works in the paused match too
	add_theme_stylebox_override("panel", UI.box(Color(0.03, 0.035, 0.045, 0.985), 0, 0))
	UI.rtl(self)
	_fit()
	get_viewport().size_changed.connect(_fit)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	# title bar
	var top := HBoxContainer.new()
	top.custom_minimum_size = Vector2(0, 84)
	top.add_theme_constant_override("separation", 16)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(28 + G.inset, 0)
	top.add_child(pad)
	top.add_child(Glyph.make("gear", 40, UI.GOLD))
	var t := UI.label("الإعدادات", 32, UI.TEXT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	var done := UI.button("رجوع", 22, UI.GOLD, Vector2(180, 56))
	done.pressed.connect(func():
		G.save_settings()
		closed.emit())
	top.add_child(done)
	var pad2 := Control.new()
	pad2.custom_minimum_size = Vector2(28 + G.inset, 0)
	top.add_child(pad2)
	root.add_child(top)
	var line := ColorRect.new()
	line.color = Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.35)
	line.custom_minimum_size = Vector2(0, 2)
	root.add_child(line)
	# sections (right, first in RTL) and options
	var hb := HBoxContainer.new()
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 0)
	root.add_child(hb)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(260 + G.inset, 0)
	side.add_theme_constant_override("separation", 6)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 14)
	side.add_child(sp)
	for s in SECTIONS:
		var b := Button.new()
		b.text = s[1]
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(240, 70)
		b.add_theme_font_override("font", UI.bold())
		b.add_theme_font_size_override("font_size", 23)
		b.add_theme_color_override("font_color", UI.DIM)
		b.add_theme_color_override("font_pressed_color", Color(0.1, 0.07, 0.02))
		b.add_theme_color_override("font_hover_color", UI.TEXT)
		b.add_theme_stylebox_override("normal", UI.box(Color(1, 1, 1, 0.04), 6, 0))
		b.add_theme_stylebox_override("hover", UI.box(Color(1, 1, 1, 0.08), 6, 0))
		b.add_theme_stylebox_override("pressed", UI.box(UI.GOLD, 6, 0))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.pressed.connect(_open.bind(s[0]))
		side.add_child(b)
		tabs[s[0]] = b
	hb.add_child(side)
	var div := ColorRect.new()
	div.color = Color(1, 1, 1, 0.08)
	div.custom_minimum_size = Vector2(2, 0)
	hb.add_child(div)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hb.add_child(scroll)
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in ["left", "right"]:
		m.add_theme_constant_override("margin_" + k, 36 + int(G.inset))
	m.add_theme_constant_override("margin_top", 20)
	m.add_theme_constant_override("margin_bottom", 30)
	scroll.add_child(m)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	m.add_child(body)
	_open("basic")

func _fit() -> void:
	custom_minimum_size = get_viewport().get_visible_rect().size

func _open(sec: String) -> void:
	cur = sec
	for k in tabs:
		tabs[k].button_pressed = k == sec
	for c in body.get_children():
		c.free()
	match sec:
		"basic":
			_choice("المنظور", "view", [["الشخص الثالث", "tpp"], ["الشخص الأول", "fpp"]])
			_choice("الخريطة", "br_map", [["جزيرة بوروفايا", "island"], ["وادي الذهب", "desert"]])
			_check("إظهار عدد الإطارات", "show_fps")
		"graphics":
			_choice("جودة الرسوم", "quality", [["منخفضة", 0], ["متوسطة", 1], ["عالية", 2], ["قصوى", 3]])
			_choice("عدد الإطارات", "fps_limit", [["30", 30], ["60", 60], ["90", 90], ["120", 120]])
			_choice("الظلال", "shadows", [["إيقاف", 0], ["تشغيل", 1]])
			if not G.mobile:
				_check("ملء الشاشة", "fullscreen")
				_check("المزامنة العمودية", "vsync")
			_note("الجودة الأقل تجعل اللعب أنعم وتوفّر البطارية.")
		"controls":
			_slider("حساسية التصويب", "sens", 0.2, 3.0, 0.05)
			_slider("حساسية المنظار", "ads_sens", 0.2, 2.0, 0.05)
			_slider("مجال الرؤية", "fov", 70.0, 110.0, 1.0)
			_choice("لون علامة التصويب", "cross_color", [["أخضر", 0], ["أبيض", 1], ["سماوي", 2], ["أصفر", 3]])
		"sound":
			_slider("الصوت العام", "vol_master", 0.0, 1.0, 0.02)
			_slider("الموسيقى", "vol_music", 0.0, 1.0, 0.02)
			_slider("المؤثرات", "vol_sfx", 0.0, 1.0, 0.02)

func _title(text: String) -> void:
	body.add_child(UI.label(text, 20, UI.TEXT, true))

func _note(text: String) -> void:
	var l := UI.label(text, 15, UI.DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(l)

func _apply() -> void:
	G.apply_settings()
	G.save_settings()

func _choice(title: String, key: String, opts: Array) -> void:
	_title(title)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	body.add_child(hb)
	var btns: Array = []
	for o in opts:
		var b := UI.button(String(o[0]), 19, UI.GOLD, Vector2(170, 54))
		b.toggle_mode = true
		b.button_pressed = G.settings.get(key, opts[0][1]) == o[1]
		b.pressed.connect(func():
			G.settings[key] = o[1]
			for x in btns:
				x.button_pressed = x == b
			_apply())
		hb.add_child(b)
		btns.append(b)

func _slider(title: String, key: String, lo: float, hi: float, step: float) -> void:
	_title(title)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	body.add_child(hb)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(G.settings.get(key, 1.0))
	s.custom_minimum_size = Vector2(420, 40)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	var v := UI.label("", 20, UI.GOLD_HI, true)
	v.custom_minimum_size = Vector2(80, 0)
	var fmt := func(x: float) -> String:
		return ("%d" % int(x)) if step >= 1.0 else (("%d%%" % int(round(x * 100))) if hi <= 1.0 else ("%.2f" % x))
	v.text = fmt.call(s.value)
	s.value_changed.connect(func(x: float):
		G.settings[key] = x
		v.text = fmt.call(x)
		G.apply_settings())
	s.drag_ended.connect(func(_c): G.save_settings())
	hb.add_child(s)
	hb.add_child(v)

func _check(title: String, key: String) -> void:
	_choice(title, key, [["إيقاف", false], ["تشغيل", true]])
