extends Node3D
## Главное меню: трёхмерная сцена с бойцами на рынке, навигация слева, панели «Играть», «Кейсы», «Инвентарь», «Настройки».

var world: World
var cam: Camera3D
var t := 0.0
var ui: Control
var panels := {}
var cur_panel := ""
var credits_l: Label
var stats_l: Label
var roll: Control
var roll_items: Array = []
var roll_off := 0.0
var roll_target := 0.0
var roll_win := ""
var roll_active := false
var roll_last_i := -1
var result_box: PanelContainer
var result_l: Label
var result_card: Control
var inv_grid: GridContainer
var inv_view: SubViewport
var inv_pivot: Node3D
var inv_sel := ""
var open_btn: Button
var rng := RandomNumberGenerator.new()
const CARD := 168.0
var nav: VBoxContainer
var holder_box: CenterContainer
var bar_box: StyleBoxFlat
var built_inset := -1.0

func _ready() -> void:
	rng.randomize()
	G.set_mouse(Input.MOUSE_MODE_VISIBLE)
	world = World.new()
	add_child(world)
	world.load_map("kasbah")
	cam = Camera3D.new()
	cam.fov = 42.0
	add_child(cam)
	cam.current = true
	_fighters()
	_build_ui()
	Sfx.stop_all()
	Sfx.music("menu_theme", 1.5, -6.0)
	Sfx.ambient("amb_desert", -22.0)
	if G.args.has("panel"):
		_show(String(G.args["panel"]))
	if G.args.has("loop"):
		_loop_test()
	elif G.shots_dir != "":
		_auto_shots()

func _fighters() -> void:
	# строй справа от меню: двое спереди, двое чуть позади, все лицом к камере
	var spots := [["t_2", Vector2(70.91, 67.15), 230.0, "rifle_idle", "mac10"], ["ct_1", Vector2(70.16, 65.18), 222.0, "rifle_idle", "m4"],
		["t_1", Vector2(71.85, 64.96), 213.0, "rifle_idle_aiming", "ak"], ["ct_2", Vector2(71.89, 63.60), 204.0, "pistol_idle", "usp"]]
	for s in spots:
		var fb := FighterBody.new()
		add_child(fb)
		fb.setup(null, s[0])
		var p: Vector2 = s[1]
		fb.position = World.w(p.x, p.y, 0.0)
		fb.rotation.y = deg_to_rad(float(s[2]) - 90.0)
		fb.pose(s[3])
		fb.set_weapon(s[4])

func _process(dt: float) -> void:
	t += dt
	var base := World.w(64.9, 62.5, 1.42)
	var look := World.w(70.2, 66.6, 1.22)
	cam.position = base + Vector3(sin(t * 0.21) * 0.25, sin(t * 0.17) * 0.06, cos(t * 0.19) * 0.2)
	cam.look_at(look + Vector3(0, sin(t * 0.13) * 0.05, 0), Vector3.UP)
	if roll_active:
		roll.queue_redraw()
	if built_inset != G.inset:
		_apply_inset()
	if inv_pivot:
		inv_pivot.rotation.y += dt * 0.8

# ------------------------------------------------------------------ интерфейс
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ui)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type canvas_item; void fragment(){ float a = smoothstep(0.62, 0.0, UV.x) * 0.72 + smoothstep(0.82, 1.0, UV.y) * 0.5; COLOR = vec4(0.02, 0.025, 0.03, clamp(a, 0.0, 0.85)); }"
	gm.shader = sh
	shade.material = gm
	ui.add_child(shade)
	var left := VBoxContainer.new()
	nav = left
	left.position = Vector2(64, 60 if not G.touch else 34)
	left.add_theme_constant_override("separation", 12)
	ui.add_child(left)
	var title := UI.label("Vorn", 84 if not G.touch else 72, UI.AMBER, true)
	left.add_child(title)
	var sub := UI.label("خريطة «القصبة»  ·  5 ضد 5  ·  زرع القنبلة", 18, UI.AMBER)
	left.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 34 if not G.touch else 4)
	left.add_child(gap)
	for item in [["العب", "play", UI.AMBER], ["الصناديق", "cases", UI.TEAL], ["المخزون", "inv", UI.TEAL], ["الإعدادات", "settings", UI.AMBER]]:
		var b := UI.button(item[0], 26, item[2], Vector2(340, 64))
		b.pressed.connect(_show.bind(item[1]))
		left.add_child(b)
	var bq := UI.button("خروج", 26, UI.RED, Vector2(340, 64))
	bq.pressed.connect(func(): G.quit())
	if not G.mobile:
		left.add_child(bq)
	# нижняя полоса
	var bar := PanelContainer.new()
	bar_box = UI.box(Color(0.04, 0.05, 0.06, 0.9), 0)
	bar.add_theme_stylebox_override("panel", bar_box)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -58
	ui.add_child(bar)
	UI.rtl(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 40)
	bar.add_child(hb)
	credits_l = UI.label("", 20, UI.AMBER, true)
	hb.add_child(credits_l)
	stats_l = UI.label("", 17, UI.DIM)
	hb.add_child(stats_l)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)
	hb.add_child(UI.label("الإصدار %s" % G.VERSION, 15, UI.DIM))
	# панели справа
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder_box = holder
	holder.offset_bottom = -70
	_apply_inset()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(holder)
	panels["play"] = _panel_play()
	panels["cases"] = _panel_cases()
	panels["inv"] = _panel_inv()
	var st := SettingsPanel.new()
	st.closed.connect(_show.bind(""))
	panels["settings"] = st
	for k in panels:
		holder.add_child(panels[k])
		panels[k].visible = false
	_refresh()
	if not G.last_result.is_empty():
		var r: Dictionary = G.last_result
		var msg := {"win": "فوز", "lose": "هزيمة", "draw": "تعادل"}[r["res"]] as String
		var note := UI.label("المباراة السابقة: %s %d:%d  ·  +%d رصيد" % [msg, r["score"][0], r["score"][1], r["credits"]], 18, UI.GREEN if r["res"] == "win" else UI.TEXT)
		left.add_child(note)

func _apply_inset() -> void:
	## keeps the menu clear of the notch; called again if the safe area changes
	built_inset = G.inset
	nav.position.x = 64 + G.inset
	holder_box.offset_left = 440 + G.inset
	holder_box.offset_right = -G.inset
	bar_box.content_margin_left = 14 + G.inset
	bar_box.content_margin_right = 14 + G.inset

func _refresh() -> void:
	credits_l.text = "الرصيد: %d" % int(G.profile["credits"])
	stats_l.text = "المباريات: %d   ·   الانتصارات: %d   ·   القتلى: %d   ·   الطلاءات: %d" % [int(G.profile["matches"]), int(G.profile["wins"]), int(G.profile["kills"]), (G.profile["inv"] as Array).size()]
	if open_btn:
		open_btn.disabled = int(G.profile["credits"]) < int(DB.CASES["kasbah"]["price"]) or roll_active

func _show(n: String) -> void:
	if roll_active:
		return
	cur_panel = "" if n == cur_panel else n
	for k in panels:
		panels[k].visible = k == cur_panel
	if cur_panel == "inv":
		_fill_inv()
	_refresh()

func _choice(vb: VBoxContainer, title: String, key: String, opts: Array) -> void:
	vb.add_child(UI.label(title, 17, UI.DIM))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	vb.add_child(hb)
	var btns: Array = []
	for o in opts:
		var b := UI.button(o[0], 19, UI.AMBER, Vector2(190, 50))
		b.toggle_mode = true
		b.button_pressed = G.settings[key] == o[1]
		b.pressed.connect(func():
			G.settings[key] = o[1]
			for x in btns:
				x.button_pressed = x == b
			G.save_settings())
		hb.add_child(b)
		btns.append(b)

func _panel_play() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color(0.05, 0.06, 0.075, 0.95), 16, 1))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	p.add_child(vb)
	UI.rtl(p)
	vb.add_child(UI.label("مباراة جديدة", 28, UI.TEXT, true))
	_choice(vb, "فريقك في الشوط الأول", "team", [["الدفاع", "ct"], ["الهجوم", "t"]])
	_choice(vb, "طول المباراة", "match_len", [["قصيرة · حتى 4", 4], ["عادية · حتى 7", 7], ["كاملة · حتى 13", 13]])
	_choice(vb, "مستوى البوتات", "difficulty", [["مبتدئون", 0], ["مقاتلون", 1], ["محترفون", 2]])
	var help := UI.label("حرّك العصا اليسرى للمشي  ·  اسحب على يمين الشاشة للتصويب  ·  زر الرصاصة للإطلاق" if G.touch else "الحركة: WASD  ·  مشي: Shift  ·  انحناء: Ctrl  ·  المتجر: B  ·  تفكيك: E  ·  تفحّص السلاح: F  ·  النتائج: Tab", 14, UI.DIM)
	help.text_direction = Control.TEXT_DIRECTION_RTL
	vb.add_child(help)
	var go := UI.button("مباراة أوفلاين ضد البوتات", 24, UI.TEAL, Vector2(340, 58))
	go.pressed.connect(func():
		Network.close_session()
		G.save_settings()
		G.start_match())
	vb.add_child(go)
	var online_title := UI.label("اللعب عبر الشبكة · تجربة أولية", 20, UI.AMBER, true)
	vb.add_child(online_title)
	var address := LineEdit.new()
	address.placeholder_text = "عنوان IP للمضيف"
	address.text = "127.0.0.1"
	address.custom_minimum_size = Vector2(340, 48)
	address.alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(address)
	var online_status := UI.label("المضيف واللاعبون يجب أن يستخدموا المنفذ 24567", 13, UI.DIM)
	vb.add_child(online_status)
	Network.connection_failed.connect(func(reason): online_status.text = reason)
	var host_btn := UI.button("إنشاء غرفة (Host)", 22, UI.AMBER, Vector2(340, 54))
	host_btn.pressed.connect(func():
		var err := Network.host()
		if err == OK:
			online_status.text = "الغرفة بدأت على المنفذ 24567. أعطِ عنوان IP للاعب الآخر."
			G.start_match())
	vb.add_child(host_btn)
	var join_btn := UI.button("انضمام إلى غرفة (Join)", 22, UI.TEAL, Vector2(340, 54))
	join_btn.pressed.connect(func():
		var err := Network.join(address.text)
		if err == OK:
			online_status.text = "جارٍ الاتصال..."
			var start_online := func():
				if is_inside_tree():
					online_status.text = "تم الاتصال، جارٍ تحميل المباراة."
					G.start_match()
			if not Network.session_ready.is_connected(start_online):
				Network.session_ready.connect(start_online, CONNECT_ONE_SHOT))
	vb.add_child(join_btn)
	return p

# ------------------------------------------------------------------ кейсы
func _panel_cases() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color(0.05, 0.06, 0.075, 0.95), 16, 1))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	p.add_child(vb)
	UI.rtl(p)
	var c: Dictionary = DB.CASES["kasbah"]
	vb.add_child(UI.label(String(c["name"]).to_upper(), 28, UI.TEXT, true))
	var room: float = get_viewport().get_visible_rect().size.x - 440.0 - 2.0 * G.inset - 70.0
	var note := UI.label("ثمانية طلاءات لتسعة أسلحة وللسكين. تكسب الرصيد من المباريات: القتل، أفضل لاعب في الجولة، والفوز.", 15, UI.DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(note)
	roll = Control.new()
	roll.layout_direction = Control.LAYOUT_DIRECTION_LTR
	roll.custom_minimum_size = Vector2(clampf(room, 620.0, 1000.0), 210)
	roll.clip_contents = true
	roll.draw.connect(_draw_roll)
	vb.add_child(roll)
	var odds := HBoxContainer.new()
	odds.add_theme_constant_override("separation", 18)
	vb.add_child(odds)
	for i in DB.RAR_NAME.size():
		odds.add_child(UI.label("■ %s %d%%" % [DB.RAR_NAME[i], int(round(DB.RAR_ODDS[i] * 100))], 14, DB.RAR_COL[i]))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	vb.add_child(hb)
	open_btn = UI.button("افتح مقابل %d" % int(c["price"]), 24, UI.TEAL, Vector2(320, 60))
	open_btn.pressed.connect(_open_case)
	hb.add_child(open_btn)
	result_box = PanelContainer.new()
	result_box.add_theme_stylebox_override("panel", UI.box(UI.PANEL2, 10))
	result_box.visible = false
	hb.add_child(result_box)
	var rb := HBoxContainer.new()
	rb.add_theme_constant_override("separation", 14)
	result_box.add_child(rb)
	result_l = UI.label("", 20, UI.TEXT, true)
	rb.add_child(result_l)
	var eq := UI.button("تجهيز", 18, UI.AMBER, Vector2(130, 44))
	eq.pressed.connect(func():
		if roll_win != "":
			var pr := roll_win.split(":")
			G.profile["equip"][pr[0]] = pr[1]
			G.save_profile()
			result_l.text = DB.skin_title(roll_win) + " — تم التجهيز")
	rb.add_child(eq)
	_fill_roll("")
	return p

func _fill_roll(win: String) -> void:
	roll_items.clear()
	var r := RandomNumberGenerator.new()
	r.randomize()
	for i in 52:
		roll_items.append(DB.roll_case("kasbah", r))
	if win != "":
		roll_items[44] = win

func _open_case() -> void:
	var price := int(DB.CASES["kasbah"]["price"])
	if roll_active or int(G.profile["credits"]) < price:
		Sfx.ui("ui_error", -8.0)
		return
	G.profile["credits"] = int(G.profile["credits"]) - price
	G.profile["cases"] = int(G.profile["cases"]) + 1
	roll_win = DB.roll_case("kasbah", rng)
	_fill_roll(roll_win)
	result_box.visible = false
	roll_active = true
	roll_off = 0.0
	roll_last_i = -1
	roll_target = 44.0 * CARD + rng.randf_range(-CARD * 0.36, CARD * 0.36)
	Sfx.ui("case_open", -4.0)
	_refresh()
	var tw := create_tween()
	tw.tween_property(self, "roll_off", roll_target, 6.2).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_case_done)

func _case_done() -> void:
	roll_active = false
	var inv: Array = G.profile["inv"]
	var rar: int = DB.SKINS[roll_win.split(":")[1]]["rar"]
	if inv.has(roll_win):
		var back := 150 + rar * 100
		G.profile["credits"] = int(G.profile["credits"]) + back
		result_l.text = "%s — موجود لديك، استرجعت %d" % [DB.skin_title(roll_win), back]
	else:
		inv.append(roll_win)
		result_l.text = "%s  ·  %s" % [DB.skin_title(roll_win), DB.RAR_NAME[rar]]
	result_l.add_theme_color_override("font_color", DB.RAR_COL[rar])
	result_box.visible = true
	G.save_profile()
	Sfx.ui("case_rare" if rar >= 2 else "case_win", -3.0)
	roll.queue_redraw()
	_refresh()
	G.log_line("case opened: %s" % roll_win)

func _draw_card(c: Control, r: Rect2, id: String, glow := false) -> void:
	var pr := id.split(":")
	var sk: Dictionary = DB.SKINS[pr[1]]
	var rc: Color = DB.RAR_COL[sk["rar"]]
	c.draw_style_box(UI.box(Color(0.10, 0.11, 0.13, 1.0), 8, 2 if glow else 1, rc if glow else UI.LINE), r)
	var inner := r.grow(-8)
	c.draw_rect(Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.62)), Color(sk["a"].r, sk["a"].g, sk["a"].b, 0.55))
	c.draw_rect(Rect2(inner.position + Vector2(0, inner.size.y * 0.42), Vector2(inner.size.x, inner.size.y * 0.20)), Color(sk["b"].r, sk["b"].g, sk["b"].b, 0.75))
	var ic := UI.icon(pr[0])
	if ic:
		var iw := inner.size.x - 16
		var ih := iw * ic.get_height() / ic.get_width()
		if ih > inner.size.y * 0.5:
			ih = inner.size.y * 0.5
			iw = ih * ic.get_width() / ic.get_height()
		c.draw_texture_rect(ic, Rect2(inner.position + Vector2((inner.size.x - iw) / 2, inner.size.y * 0.31 - ih / 2), Vector2(iw, ih)), false, Color(1, 1, 1, 0.96))
	c.draw_string(UI.bold(), Vector2(inner.position.x, inner.end.y - 30), DB.W[pr[0]]["name"], HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 15, UI.TEXT)
	c.draw_string(UI.font(), Vector2(inner.position.x, inner.end.y - 12), sk["name"], HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 14, rc)
	c.draw_rect(Rect2(r.position.x + 8, r.end.y - 7, r.size.x - 16, 4), rc)

func _draw_roll() -> void:
	var w := roll.size.x
	var h := roll.size.y
	roll.draw_rect(Rect2(0, 0, w, h), Color(0.03, 0.035, 0.045, 0.9))
	var center := w / 2.0
	for i in roll_items.size():
		var x := center + i * CARD - roll_off - CARD / 2.0
		if x > w or x + CARD < 0:
			continue
		var win_here := not roll_active and roll_win != "" and i == 44
		_draw_card(roll, Rect2(x + 5, 14, CARD - 10, h - 28), roll_items[i], win_here)
	roll.draw_rect(Rect2(center - 2, 0, 4, h), UI.AMBER)
	roll.draw_colored_polygon(PackedVector2Array([Vector2(center - 12, 0), Vector2(center + 12, 0), Vector2(center, 16)]), UI.AMBER)
	roll.draw_colored_polygon(PackedVector2Array([Vector2(center - 12, h), Vector2(center + 12, h), Vector2(center, h - 16)]), UI.AMBER)
	if roll_active:
		var idx := int(floor((roll_off + CARD / 2.0) / CARD))
		if idx != roll_last_i:
			roll_last_i = idx
			Sfx.ui("case_tick", -9.0, randf_range(0.96, 1.04))

# ------------------------------------------------------------------ инвентарь
func _panel_inv() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color(0.05, 0.06, 0.075, 0.95), 16, 1))
	UI.rtl(p)
	var room: float = get_viewport().get_visible_rect().size.x - 440.0 - 2.0 * G.inset - 70.0
	var small: bool = room < 1060.0
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	p.add_child(hb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	hb.add_child(vb)
	vb.add_child(UI.label("المخزون", 28, UI.TEXT, true))
	vb.add_child(UI.label("اضغط على الطلاء لتجهيزه أو نزعه.", 15, UI.DIM))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(560, 430) if not small else Vector2(clampf(room - 330.0, 380.0, 560.0), 370)
	vb.add_child(sc)
	inv_grid = GridContainer.new()
	inv_grid.columns = 3 if sc.custom_minimum_size.x >= 550.0 else 2
	inv_grid.add_theme_constant_override("h_separation", 8)
	inv_grid.add_theme_constant_override("v_separation", 8)
	sc.add_child(inv_grid)
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = Vector2(460, 460) if not small else Vector2(300, 370)
	svc.stretch = true
	hb.add_child(svc)
	inv_view = SubViewport.new()
	inv_view.own_world_3d = true
	inv_view.transparent_bg = true
	inv_view.msaa_3d = Viewport.MSAA_4X
	svc.add_child(inv_view)
	var c := Camera3D.new()
	c.position = Vector3(0, 0.05, 1.25)
	c.fov = 30.0
	inv_view.add_child(c)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.82, 0.9)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	c.environment = env
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-40, 35, 0)
	l.light_energy = 2.4
	inv_view.add_child(l)
	var l2 := DirectionalLight3D.new()
	l2.rotation_degrees = Vector3(-10, -140, 0)
	l2.light_energy = 1.0
	l2.light_color = Color(0.6, 0.8, 1.0)
	inv_view.add_child(l2)
	inv_pivot = Node3D.new()
	inv_view.add_child(inv_pivot)
	return p

func _fill_inv() -> void:
	for c in inv_grid.get_children():
		c.queue_free()
	var inv: Array = G.profile["inv"]
	if inv.is_empty():
		inv_grid.add_child(UI.label("فارغ حالياً. افتح صندوقاً.", 18, UI.DIM))
		_preview("ak", "")
		return
	for id in inv:
		var pr := String(id).split(":")
		var on: bool = G.profile["equip"].get(pr[0], "") == pr[1]
		var b := UI.button(("✔ " if on else "") + DB.skin_title(id), 15, DB.RAR_COL[DB.SKINS[pr[1]]["rar"]], Vector2(178, 62))
		b.add_theme_color_override("font_color", DB.RAR_COL[DB.SKINS[pr[1]]["rar"]])
		b.pressed.connect(func():
			if G.profile["equip"].get(pr[0], "") == pr[1]:
				G.profile["equip"].erase(pr[0])
			else:
				G.profile["equip"][pr[0]] = pr[1]
			G.save_profile()
			_fill_inv.call_deferred()
			_preview(pr[0], pr[1]))
		b.mouse_entered.connect(_preview.bind(pr[0], pr[1]))
		inv_grid.add_child(b)
	if inv_sel == "":
		var p0 := String(inv[0]).split(":")
		_preview(p0[0], p0[1])

func _preview(wid: String, skin: String) -> void:
	inv_sel = wid + ":" + skin
	for c in inv_pivot.get_children():
		c.queue_free()
	var path := "res://assets/models/weapons/%s.scn" % wid
	if not ResourceLoader.exists(path):
		return
	var w := (load(path) as PackedScene).instantiate() as Node3D
	inv_pivot.add_child(w)
	Skins.apply(w, wid, skin)
	# центр и масштаб по габаритам
	var aabb := AABB()
	var first := true
	for mi in w.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var a: AABB = m.transform * m.get_aabb()
		aabb = a if first else aabb.merge(a)
		first = false
	var s := 0.62 / maxf(0.05, aabb.get_longest_axis_size())
	var rb := Basis(Vector3.UP, PI / 2.0)
	w.transform = Transform3D(rb.scaled(Vector3.ONE * s), -(rb * aabb.get_center()) * s)

func _loop_test() -> void:
	## проверка полного цикла: меню -> «В бой» -> матч до конца -> снова меню
	await get_tree().create_timer(2.0).timeout
	if G.loop_stage == 0:
		await G.shot("loop_1_menu")
		_show("play")
		await get_tree().create_timer(0.6).timeout
		await G.shot("loop_2_play")
		G.loop_stage = 1
		G.log_line("loop: menu -> match")
		G.start_match()
	else:
		await G.shot("loop_4_menu_again")
		G.log_line("loop: match -> menu, credits %d, matches %d, wins %d" % [int(G.profile["credits"]), int(G.profile["matches"]), int(G.profile["wins"])])
		G.log_line("LOOP OK")
		get_tree().quit()

func _auto_shots() -> void:
	await get_tree().create_timer(1.5).timeout
	await G.shot("menu_main")
	_show("play")
	await get_tree().create_timer(0.4).timeout
	await G.shot("menu_play")
	_show("settings")
	await get_tree().create_timer(0.4).timeout
	await G.shot("menu_settings")
	_show("cases")
	await get_tree().create_timer(0.4).timeout
	G.profile["credits"] = maxi(int(G.profile["credits"]), 2000)
	_open_case()
	await get_tree().create_timer(2.0).timeout
	await G.shot("menu_case_roll")
	await get_tree().create_timer(5.0).timeout
	await G.shot("menu_case_done")
	_show("inv")
	await get_tree().create_timer(0.8).timeout
	await G.shot("menu_inv")
	if G.args.has("quit_after") or G.args.has("quit_menu"):
		get_tree().quit()
