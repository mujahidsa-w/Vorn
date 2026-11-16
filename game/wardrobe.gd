class_name Wardrobe
extends Control
## The inventory on the whole screen: the fighter stays visible on the left (the lobby behind), the items on the
## right as picture cards, the sections as icons down the right edge. A tap on a card equips it.

const SECTIONS := [["outfit", "bag", "الملابس"], ["weapon", "target", "الأسلحة"], ["chute", "gem", "المظلات"]]
const OUTFIT_RAR := [1, 1, 2, 2, 3, 3, 4, 4]

signal closed

var menu: Node
var sec := "outfit"
var grid: GridContainer
var tabs := {}
var title_l: Label
var info_l: Label
var renders := {}           # outfit index -> ViewportTexture

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	var vs := get_viewport().get_visible_rect().size
	# right side: the items
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", UI.box(Color(0.03, 0.035, 0.045, 0.93), 0, 0))
	right.anchor_left = 0.44
	right.anchor_right = 1.0
	right.anchor_bottom = 1.0
	right.offset_right = -G.inset
	add_child(right)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 0)
	right.add_child(hb)
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 10)
	hb.add_child(main)
	var top := HBoxContainer.new()
	top.custom_minimum_size = Vector2(0, 76)
	top.add_theme_constant_override("separation", 12)
	var back := UI.button("‹  رجوع", 20, UI.GOLD, Vector2(150, 54))
	back.pressed.connect(func(): closed.emit())
	top.add_child(back)
	title_l = UI.label("", 28, UI.TEXT, true)
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(title_l)
	main.add_child(top)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(sc)
	var mc := MarginContainer.new()
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + k, 12)
	sc.add_child(mc)
	grid = GridContainer.new()
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	var room := vs.x * 0.56 - 120.0 - G.inset
	grid.columns = clampi(int(room / 162.0), 2, 6)
	mc.add_child(grid)
	info_l = UI.label("", 16, UI.DIM)
	info_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_l.custom_minimum_size = Vector2(0, 34)
	main.add_child(info_l)
	# the section icons down the right edge
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(104, 0)
	side.add_theme_constant_override("separation", 4)
	var bg := ColorRect.new()
	hb.add_child(side)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 80)
	side.add_child(spacer)
	for s in SECTIONS:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(100, 96)
		b.add_theme_stylebox_override("normal", UI.box(Color(1, 1, 1, 0.03), 0, 0))
		b.add_theme_stylebox_override("hover", UI.box(Color(1, 1, 1, 0.07), 0, 0))
		b.add_theme_stylebox_override("pressed", UI.box(Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.22), 0, 0))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var g := Glyph.make(s[1], 40, UI.GOLD)
		g.position = Vector2(30, 14)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(g)
		var l := UI.label(s[2], 14, UI.TEXT, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.position = Vector2(0, 62)
		l.size = Vector2(100, 24)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(l)
		b.pressed.connect(open.bind(s[0]))
		side.add_child(b)
		tabs[s[0]] = b
	bg.queue_free()
	open("outfit")

func open(s: String) -> void:
	sec = s
	for k in tabs:
		tabs[k].button_pressed = k == s
	for c in grid.get_children():
		c.queue_free()
	match s:
		"outfit":
			title_l.text = "الملابس"
			for i in DB.OUTFITS.size():
				grid.add_child(_outfit_card(i))
			info_l.text = "الطقم المجهّز: %s" % DB.OUTFIT_NAMES[posmod(int(G.settings.get("outfit", 0)), DB.OUTFITS.size())]
		"weapon":
			title_l.text = "الأسلحة"
			var inv: Array = G.profile["inv"]
			if inv.is_empty():
				grid.add_child(_empty_card())
			for id in inv:
				grid.add_child(_skin_card(String(id)))
			info_l.text = "اضغط على الطلاء لتجهيزه — يظهر على السلاح في اللوبي والمعركة."
		"chute":
			title_l.text = "المظلات"
			for i in DB.CHUTES.size():
				grid.add_child(_chute_card(i))
			info_l.text = "المظلة المجهّزة: %s" % DB.CHUTES[int(G.settings.get("chute", 0)) % DB.CHUTES.size()][0]

# ------------------------------------------------------------------ cards
func _card(rar: int, on: bool) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 186)
	var rc: Color = DB.RAR_COL[clampi(rar, 0, DB.RAR_COL.size() - 1)]
	var st := UI.box(Color(rc.r * 0.25, rc.g * 0.25, rc.b * 0.25, 0.95), 6, 3 if on else 1, UI.GOLD if on else Color(rc.r, rc.g, rc.b, 0.6))
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", st)
	b.add_theme_stylebox_override("pressed", st)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var stripe := ColorRect.new()
	stripe.color = rc
	stripe.anchor_top = 1.0
	stripe.anchor_right = 1.0
	stripe.anchor_bottom = 1.0
	stripe.offset_top = -6
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(stripe)
	if on:
		var tick := UI.label("✓", 22, UI.GOLD_HI, true)
		tick.position = Vector2(8, 2)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tick)
	return b

func _name_on(b: Control, text: String) -> void:
	var l := UI.label(text, 15, UI.TEXT, true)
	l.anchor_top = 1.0
	l.anchor_right = 1.0
	l.anchor_bottom = 1.0
	l.offset_top = -32
	l.offset_bottom = -8
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)

func _outfit_card(i: int) -> Button:
	var on := posmod(int(G.settings.get("outfit", 0)), DB.OUTFITS.size()) == i
	var b := _card(OUTFIT_RAR[i], on)
	var tr := TextureRect.new()
	tr.texture = _outfit_render(i)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.offset_top = 6
	tr.offset_bottom = -30
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(tr)
	_name_on(b, DB.OUTFIT_NAMES[i])
	b.pressed.connect(func():
		G.settings["outfit"] = i
		G.save_settings()
		if menu and menu.has_method("_switch_outfit"):
			menu._switch_outfit(0)
		open("outfit"))
	return b

func _outfit_render(i: int) -> Texture2D:
	## a still picture of the outfit: the fighter posed in a small 3D scene of its own, drawn once
	if renders.has(i):
		return renders[i]
	var vp := SubViewport.new()
	vp.size = Vector2i(220, 280)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 28.0
	cam.position = Vector3(0, 1.0, 4.4)
	vp.add_child(cam)
	cam.look_at(Vector3(0, 0.95, 0), Vector3.UP)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.82, 0.9)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	cam.environment = env
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-35, 30, 0)
	l.light_energy = 2.2
	vp.add_child(l)
	var model: String = DB.OUTFITS[i]
	if FighterBody.available(model):
		var fb := FighterBody.new()
		vp.add_child(fb)
		fb.setup(null, model)
		fb.pose("rifle_idle")
		fb.rotation.y = PI + 0.35
	else:
		var m := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.3
		cm.height = 1.8
		m.mesh = cm
		m.position.y = 0.9
		vp.add_child(m)
	# draw it a few frames later (the pose needs a frame to apply)
	get_tree().create_timer(0.2).timeout.connect(func(): vp.render_target_update_mode = SubViewport.UPDATE_ONCE)
	renders[i] = vp.get_texture()
	return renders[i]

func _skin_card(id: String) -> Button:
	var pr := id.split(":")
	var on: bool = G.profile["equip"].get(pr[0], "") == pr[1]
	var b := _card(int(DB.SKINS[pr[1]]["rar"]), on)
	var art := Control.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.draw.connect(func(): menu._draw_card(art, Rect2(Vector2.ZERO, art.size), id, on))
	b.add_child(art)
	b.pressed.connect(func():
		if G.profile["equip"].get(pr[0], "") == pr[1]:
			G.profile["equip"].erase(pr[0])
		else:
			G.profile["equip"][pr[0]] = pr[1]
		G.save_profile()
		if menu and menu.has_method("_preview"):
			menu._preview(pr[0], pr[1])
		open("weapon"))
	return b

func _empty_card() -> Button:
	var b := _card(0, false)
	b.custom_minimum_size = Vector2(312, 186)
	var g := Glyph.make("crate", 64, UI.GOLD)
	g.position = Vector2(124, 30)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(g)
	_name_on(b, "افتح صندوق الذهب لتحصل على طلاءات")
	b.pressed.connect(func():
		closed.emit()
		if menu:
			menu._show.call_deferred("cases"))
	return b

func _chute_card(i: int) -> Button:
	var on := int(G.settings.get("chute", 0)) % DB.CHUTES.size() == i
	var c: Array = DB.CHUTES[i]
	var b := _card(int(c[3]), on)
	var art := Control.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.draw.connect(func():
		# an arched canopy of cells, the centre in the main colour, lines down to a small figure
		var w := art.size.x
		var cells := 7
		for k in cells:
			var t := (k + 0.5) / cells * 2.0 - 1.0
			var x := w * 0.5 + t * w * 0.38
			var y := 40.0 + 14.0 * t * t
			var col: Color = c[1] if absf(t) < 0.45 else c[2]
			art.draw_rect(Rect2(x - w * 0.055, y - 12, w * 0.11, 26), col)
			art.draw_line(Vector2(x, y + 14), Vector2(w * 0.5, 118), Color(1, 1, 1, 0.55), 1.0, true)
		art.draw_circle(Vector2(w * 0.5, 122), 6, Color(0.9, 0.85, 0.75))
		art.draw_rect(Rect2(w * 0.5 - 5, 127, 10, 18), Color(0.3, 0.33, 0.28)))
	b.add_child(art)
	_name_on(b, String(c[0]))
	b.pressed.connect(func():
		G.settings["chute"] = i
		G.save_settings()
		open("chute"))
	return b
