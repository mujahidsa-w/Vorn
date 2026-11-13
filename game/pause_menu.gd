extends Control
## Пауза в матче: продолжить, настройки, выход в меню.

var game
var box: PanelContainer
var settings: SettingsPanel

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	box = PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.box(Color(0.05, 0.06, 0.075, 0.96), 16, 1))
	cc.add_child(box)
	UI.rtl(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	box.add_child(vb)
	vb.add_child(UI.label("إيقاف مؤقت", 30, UI.TEXT, true))
	vb.add_child(UI.label("المباراة مستمرة: البوتات لا تنتظر.", 15, UI.DIM))
	var b1 := UI.button("متابعة", 22, UI.TEAL, Vector2(360, 52))
	b1.pressed.connect(func(): get_parent()._set_pause(false))
	vb.add_child(b1)
	var b2 := UI.button("الإعدادات", 22, UI.AMBER, Vector2(360, 52))
	b2.pressed.connect(func():
		box.visible = false
		settings.visible = true)
	vb.add_child(b2)
	var b3 := UI.button("القائمة الرئيسية", 22, UI.AMBER, Vector2(360, 52))
	b3.pressed.connect(func(): G.to_menu())
	vb.add_child(b3)
	var b4 := UI.button("خروج من اللعبة", 22, UI.RED, Vector2(360, 52))
	b4.pressed.connect(func(): G.quit())
	if not G.mobile:
		vb.add_child(b4)
	settings = SettingsPanel.new()
	settings.visible = false
	cc.add_child(settings)
	settings.closed.connect(func():
		settings.visible = false
		box.visible = true)
