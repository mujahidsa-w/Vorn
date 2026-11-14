extends Node3D
## Lobby: the player's fighter on a gold-rimmed stand in the Kasbah at sunset (drag to turn him, tap him
## to reload), profile card, balance, START with the mode card, side buttons, event banners and the bottom
## bar. Play options, playing with friends, cases, inventory, season stats and settings open as overlays.

var world: World
var cam: Camera3D
var t := 0.0
var ui: Control
var hud: Control
var overlay: Control
var holder: CenterContainer
var panels := {}
var cur_panel := ""
var stage: Node3D
var hero: Node3D
var hero_key := ""
var yaw := 0.0
var yaw_to := 0.0
var drag_px := 0.0
var name_tag: Control
var slots: Array[Control] = []
var start_btn: Button
var credits_l: Label
var built_for := Vector3(-1, -1, -1)
# cases
var roll: Control
var roll_items: Array = []
var roll_off := 0.0
var roll_target := 0.0
var roll_win := ""
var roll_active := false
var roll_last_i := -1
var result_box: PanelContainer
var result_l: Label
var open_btn: Button
# inventory
var inv_grid: GridContainer
var inv_view: SubViewport
var inv_pivot: Node3D
var inv_sel := ""
var stats_box: VBoxContainer
var rng := RandomNumberGenerator.new()
const CARD := 168.0
# the stand at the east end of the long lane: the camera looks west down the street into the low sun
const HERO_AT := Vector2(65.0, 8.1)
const CAM_AT := Vector3(69.7, 9.3, 1.05)

func _ready() -> void:
	rng.randomize()
	G.set_mouse(Input.MOUSE_MODE_VISIBLE)
	if not G.profile.has("uid"):
		G.profile["uid"] = rng.randi_range(51000000, 59999999)
		G.save_profile()
	world = World.new()
	add_child(world)
	world.load_map("kasbah")
	world.golden_hour(1.4)
	cam = Camera3D.new()
	cam.fov = 36.0
	var ca := CameraAttributesPractical.new()
	ca.dof_blur_far_enabled = true
	ca.dof_blur_far_distance = 6.5
	ca.dof_blur_far_transition = 5.0
	ca.dof_blur_amount = 0.06
	cam.attributes = ca
	add_child(cam)
	cam.current = true
	_stage()
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

# ------------------------------------------------------------------ 3D stand and hero
func _stage() -> void:
	stage = Node3D.new()
	stage.position = World.w(HERO_AT.x, HERO_AT.y, 0.0)
	add_child(stage)
	# round stand: dark metal disc with a glowing gold rim
	var disc := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.95
	cy.bottom_radius = 1.0
	cy.height = 0.06
	cy.radial_segments = 64
	disc.mesh = cy
	disc.position.y = 0.03
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.08, 0.08, 0.09)
	dm.metallic = 0.8
	dm.roughness = 0.35
	disc.material_override = dm
	stage.add_child(disc)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.93
	tm.outer_radius = 0.985
	tm.rings = 96
	tm.ring_segments = 8
	rim.mesh = tm
	rim.position.y = 0.062
	rim.scale = Vector3(1, 0.35, 1)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = UI.GOLD
	rm.metallic = 1.0
	rm.roughness = 0.25
	rm.emission_enabled = true
	rm.emission = Color(1.0, 0.72, 0.30)
	rm.emission_energy_multiplier = 1.6
	rim.material_override = rm
	stage.add_child(rim)
	# key light from the camera side and a cool rim light from behind: the hero reads against the busy street
	var key := SpotLight3D.new()
	key.light_color = Color(1.0, 0.86, 0.72)
	key.light_energy = 3.0
	key.spot_range = 9.0
	key.spot_angle = 26.0
	key.shadow_enabled = true
	add_child(key)
	key.look_at_from_position(World.w(CAM_AT.x + 0.6, CAM_AT.y - 0.4, 2.6), stage.position + Vector3(0, 1.0, 0), Vector3.UP)
	var back := OmniLight3D.new()
	back.light_color = Color(0.55, 0.70, 1.0)
	back.light_energy = 2.2
	back.omni_range = 3.5
	back.position = stage.position + (stage.position - World.w(CAM_AT.x, CAM_AT.y, 0)).normalized() * 1.3 + Vector3(0, 2.0, 0)
	add_child(back)
	_hero()

const OUTFITS := {"ct": ["ct_1", "ct_2"], "t": ["t_1", "t_2"]}
const OUTFIT_NAMES := {"ct": ["طقم المدافعين الأول", "طقم المدافعين الثاني"], "t": ["طقم المهاجمين الأول", "طقم المهاجمين الثاني"]}
var mate: Node3D

func _fighter(parent: Node3D, model: String, gun: String, idle: String) -> Node3D:
	if FighterBody.available(model):
		var fb := FighterBody.new()
		parent.add_child(fb)
		fb.setup(null, model)
		fb.pose(idle)
		fb.set_weapon(gun)
		return fb
	var m := _mannequin()      # builds without the character archive (local tests) show a stand-in
	parent.add_child(m)
	return m

func _hero() -> void:
	## the team's two outfits: the chosen one on the stand, the other one beside him as the squad mate
	var team := String(G.settings["team"])
	var oi := int(G.settings.get("outfit", 0)) % 2
	var key := "%s:%d" % [team, oi]
	if hero_key == key:
		return
	hero_key = key
	var gun := "m4" if team == "ct" else "ak"
	var gun2 := "mp9" if team == "ct" else "mac10"
	if hero:
		hero.queue_free()
	if mate:
		mate.queue_free()
	hero = _fighter(stage, OUTFITS[team][oi], gun, "rifle_idle")
	var d := World.w(CAM_AT.x, CAM_AT.y, 0.0) - stage.position
	hero.rotation.y = atan2(-d.x, -d.z)          # faces the camera
	mate = _fighter(self, OUTFITS[team][1 - oi], gun2, "rifle_idle_aiming")
	var to_cam := Vector3(d.x, 0, d.z).normalized()
	var right := Vector3.UP.cross(to_cam).normalized()          # camera right
	mate.global_position = stage.global_position + right * 1.45 - to_cam * 0.9
	var d2 := World.w(CAM_AT.x, CAM_AT.y, 0.0) - mate.global_position
	mate.rotation.y = atan2(-d2.x, -d2.z) + 0.35

func _switch_outfit(step: int) -> void:
	G.settings["outfit"] = posmod(int(G.settings.get("outfit", 0)) + step, 2)
	G.save_settings()
	_hero()
	built_for = Vector3(-1, -1, -1)
	Sfx.ui("ui_click", -8.0)

func _mannequin() -> Node3D:
	var n := Node3D.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.32, 0.33, 0.36)
	m.roughness = 0.6
	for part in [[Vector3(0, 1.20, 0), Vector3(0.20, 0.34, 0)], [Vector3(0, 1.66, 0), Vector3(0.12, 0.0, 0)],
			[Vector3(-0.11, 0.48, 0), Vector3(0.085, 0.46, 0)], [Vector3(0.11, 0.48, 0), Vector3(0.085, 0.46, 0)]]:
		var mi := MeshInstance3D.new()
		if part[1].y > 0.0:
			var c := CapsuleMesh.new()
			c.radius = part[1].x
			c.height = part[1].y * 2.0
			mi.mesh = c
		else:
			var s := SphereMesh.new()
			s.radius = part[1].x
			s.height = part[1].x * 2.0
			mi.mesh = s
		mi.position = part[0]
		mi.material_override = m
		n.add_child(mi)
	return n

func _process(dt: float) -> void:
	t += dt
	var look := stage.position + Vector3(0, 0.98, 0)
	cam.position = World.w(CAM_AT.x, CAM_AT.y, CAM_AT.z) + Vector3(sin(t * 0.21) * 0.06, sin(t * 0.17) * 0.03, cos(t * 0.19) * 0.05)
	cam.look_at(look, Vector3.UP)
	yaw = lerp_angle(yaw, yaw_to, minf(1.0, dt * 8.0))
	stage.rotation.y = yaw
	if roll_active:
		roll.queue_redraw()
	var vs := get_viewport().get_visible_rect().size
	if built_for != Vector3(vs.x, vs.y, G.inset):
		_build_hud()
	_place_tags()
	if inv_pivot:
		inv_pivot.rotation.y += dt * 0.8
	if start_btn:
		start_btn.get_child(0).modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(t * 2.6))
	_idle_poses(dt)

var _pose_t := 8.0

func _idle_poses(dt: float) -> void:
	## extra clips named lobby_* (assets/anims_extra) play now and then, then the hero returns to his idle
	if not (hero is FighterBody):
		return
	var fb := hero as FighterBody
	_pose_t -= dt
	if fb.cur.begins_with("lobby_") and not fb.ap.is_playing():
		fb.pose("rifle_idle")
	if _pose_t > 0.0:
		return
	_pose_t = rng.randf_range(9.0, 14.0)
	var extra: Array[String] = []
	for n in fb.alib.get_animation_list():
		if String(n).begins_with("lobby_"):
			extra.append(String(n))
	if extra.size() > 0 and fb.cur == "rifle_idle":
		var pick := extra[rng.randi() % extra.size()]
		fb.alib.get_animation(pick).loop_mode = Animation.LOOP_NONE
		fb.pose(pick)

func _place_tags() -> void:
	## name over the hero's head and the two invite plates beside him follow the camera
	if name_tag == null:
		return
	var head := stage.global_position + Vector3(0, 2.08, 0)
	var p := cam.unproject_position(head)
	name_tag.position = p - Vector2(name_tag.size.x * 0.5, name_tag.size.y)
	var right := cam.global_transform.basis.x
	for i in slots.size():
		var side := -1.0 if i == 0 else 1.0
		var w := stage.global_position + right * side * 1.75 + Vector3(0, 0.55, 0)
		var q := cam.unproject_position(w)
		slots[i].position = q - slots[i].size * 0.5

# ------------------------------------------------------------------ interface
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_PASS
	ui.gui_input.connect(_drag_input)
	layer.add_child(ui)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type canvas_item; void fragment(){ float a = smoothstep(0.30, 0.0, UV.x) * 0.45 + smoothstep(0.72, 1.0, UV.x) * 0.45 + smoothstep(0.78, 1.0, UV.y) * 0.55 + smoothstep(0.14, 0.0, UV.y) * 0.45; COLOR = vec4(0.02, 0.018, 0.025, clamp(a, 0.0, 0.85)); }"
	gm.shader = sh
	shade.material = gm
	ui.add_child(shade)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud)
	# overlay for panels
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	ui.add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.012, 0.018, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			_show(""))
	overlay.add_child(dim)
	holder = CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(holder)
	var close := _round_btn("exit", 54)
	close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	close.offset_left = -84
	close.offset_top = 18
	close.pressed.connect(_show.bind(""))
	overlay.add_child(close)
	overlay.set_meta("close", close)
	panels["play"] = _panel_play()
	panels["online"] = _panel_online()
	panels["cases"] = _panel_cases()
	panels["inv"] = _panel_inv()
	panels["stats"] = _panel_stats()
	var st := SettingsPanel.new()
	st.closed.connect(_show.bind(""))
	panels["settings"] = st
	for k in panels:
		holder.add_child(panels[k])
		panels[k].visible = false
	_build_hud()

func _drag_input(e: InputEvent) -> void:
	## drag anywhere on the open stage turns the hero; a short tap on him plays a reload
	if e is InputEventScreenDrag or (e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT)):
		yaw_to += e.relative.x * 0.011
		drag_px += absf(e.relative.x)
	elif (e is InputEventScreenTouch or e is InputEventMouseButton) and e.pressed:
		drag_px = 0.0
	elif (e is InputEventScreenTouch or e is InputEventMouseButton) and not e.pressed and drag_px < 8.0:
		var p := cam.unproject_position(stage.global_position + Vector3(0, 1.0, 0))
		if absf(e.position.x - p.x) < 120.0 and hero is FighterBody:
			var fb := hero as FighterBody
			if fb.up.has_animation("reloading"):
				fb.up.play("reloading", 0.1, 1.2)
				Sfx.ui("reload" if Sfx.has("reload") else "ui_click", -10.0)

func _box(col := UI.INK, r := 8, border := 1, bcol := Color(1, 1, 1, 0.10)) -> StyleBoxFlat:
	var s := UI.box(col, r, border, bcol)
	return s

func _round_btn(glyph: String, sz: float, col := Color.WHITE) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(sz, sz)
	b.size = Vector2(sz, sz)
	var n := _box(Color(0.05, 0.055, 0.065, 0.78), int(sz / 2), 2, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.55))
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", _box(Color(0.10, 0.10, 0.11, 0.9), int(sz / 2), 2, UI.GOLD))
	b.add_theme_stylebox_override("pressed", _box(Color(0.18, 0.15, 0.08, 0.95), int(sz / 2), 2, UI.GOLD_HI))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var g := Glyph.make(glyph, sz * 0.52, col)
	g.position = Vector2(sz * 0.24, sz * 0.24)
	b.add_child(g)
	b.pressed.connect(func(): Sfx.ui("ui_click", -8.0))
	return b

func _labeled(glyph: String, text: String, sz: float, cb: Callable) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	var b := _round_btn(glyph, sz)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(cb)
	vb.add_child(b)
	var l := UI.label(text, 16, UI.TEXT, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	vb.add_child(l)
	vb.set_meta("label", l)
	return vb

func _level() -> Array:
	## level from experience: matches, wins and kills all count
	var xp := int(G.profile["matches"]) * 60 + int(G.profile["wins"]) * 120 + int(G.profile["kills"]) * 15
	var lv := 1
	var need := 200
	while xp >= need:
		xp -= need
		lv += 1
		need = 200 + lv * 60
	return [lv, float(xp) / float(need)]

func _build_hud() -> void:
	var vs := get_viewport().get_visible_rect().size
	built_for = Vector3(vs.x, vs.y, G.inset)
	for c in hud.get_children():
		c.free()
	slots.clear()
	var m := 16.0 + G.inset
	var mb := 14.0 + G.inset_b
	var lv: Array = _level()
	# ---- profile card (top left)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(Color(0.03, 0.035, 0.045, 0.80), 8, 1, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.35)))
	card.position = Vector2(m, 12)
	hud.add_child(card)
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 12)
	card.add_child(ch)
	var av := Panel.new()
	av.custom_minimum_size = Vector2(66, 66)
	av.add_theme_stylebox_override("panel", _box(Color(0.10, 0.08, 0.04), 6, 2, UI.GOLD))
	ch.add_child(av)
	var avt := TextureRect.new()
	avt.texture = UI.tex("res://assets/brand/emblem.png")
	avt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avt.position = Vector2(5, 5)
	avt.size = Vector2(56, 56)
	av.add_child(avt)
	var lvb := PanelContainer.new()
	var lvs := _box(UI.GOLD, 4, 0)
	lvs.content_margin_left = 5
	lvs.content_margin_right = 5
	lvs.content_margin_top = 0
	lvs.content_margin_bottom = 0
	lvb.add_theme_stylebox_override("panel", lvs)
	var lvl := UI.label(str(lv[0]), 15, Color(0.1, 0.07, 0.02), true)
	lvl.add_theme_font_override("font", UI.latin())
	lvb.add_child(lvl)
	lvb.position = Vector2(42, 48)
	av.add_child(lvb)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	ch.add_child(info)
	info.add_child(UI.label(String(G.settings["name"]), 22, UI.TEXT, true))
	var idl := UI.label("ID %d" % int(G.profile["uid"]), 15, UI.DIM)
	idl.add_theme_font_override("font", UI.latin())
	info.add_child(idl)
	var xp := ProgressBar.new()
	xp.custom_minimum_size = Vector2(170, 6)
	xp.show_percentage = false
	xp.value = float(lv[1]) * 100.0
	var xbg := StyleBoxFlat.new()
	xbg.bg_color = Color(1, 1, 1, 0.12)
	var xfg := StyleBoxFlat.new()
	xfg.bg_color = UI.GOLD
	xp.add_theme_stylebox_override("background", xbg)
	xp.add_theme_stylebox_override("fill", xfg)
	info.add_child(xp)
	# ---- top right: balance, settings, exit
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 10)
	hud.add_child(tr)
	var chip := PanelContainer.new()
	var cst := _box(Color(0.03, 0.035, 0.045, 0.80), 22, 1, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.45))
	cst.content_margin_top = 4
	cst.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", cst)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var chb := HBoxContainer.new()
	chb.add_theme_constant_override("separation", 8)
	chip.add_child(chb)
	chb.add_child(Glyph.make("coin", 26))
	credits_l = UI.label(str(int(G.profile["credits"])), 21, UI.GOLD_HI, true)
	credits_l.add_theme_font_override("font", UI.latin())
	chb.add_child(credits_l)
	var plus := _round_btn("plus", 26, Color(0.1, 0.07, 0.02))
	plus.add_theme_stylebox_override("normal", _box(UI.GOLD, 13, 0))
	plus.add_theme_stylebox_override("hover", _box(UI.GOLD_HI, 13, 0))
	plus.pressed.connect(_show.bind("cases"))
	chb.add_child(plus)
	tr.add_child(chip)
	var gear := _round_btn("gear", 50)
	gear.pressed.connect(_show.bind("settings"))
	tr.add_child(gear)
	if not G.mobile:
		var ex := _round_btn("exit", 50)
		ex.pressed.connect(func(): G.quit())
		tr.add_child(ex)
	tr.reset_size()
	tr.position = Vector2(vs.x - m - tr.size.x, 14)
	# ---- left column
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	var team_name := "الدفاع" if G.settings["team"] == "ct" else "الهجوم"
	left.add_child(_labeled("target", "الفريق: " + team_name, 64, _toggle_team))
	left.add_child(_labeled("friends", "الأصدقاء", 64, _show.bind("online")))
	left.add_child(_labeled("trophy", "الإحصائيات", 64, _show.bind("stats")))
	hud.add_child(left)
	left.reset_size()
	left.position = Vector2(m + 4, 118)
	# ---- right banners
	var banners := VBoxContainer.new()
	banners.add_theme_constant_override("separation", 10)
	hud.add_child(banners)
	var price := int(DB.CASES["kasbah"]["price"])
	banners.add_child(_banner("crate", "صندوق القصبة", "طلاءات نادرة · %d" % price, UI.GOLD, _show.bind("cases")))
	banners.add_child(_banner("bag", "المخزون", "%d طلاء لديك" % (G.profile["inv"] as Array).size(), UI.TEAL, _show.bind("inv")))
	var last := "العب مباراتك الأولى"
	if not G.last_result.is_empty():
		var r: Dictionary = G.last_result
		last = "%s %d:%d  ·  +%d" % [{"win": "فوز", "lose": "هزيمة", "draw": "تعادل"}[r["res"]], r["score"][0], r["score"][1], r["credits"]]
	banners.add_child(_banner("star", "آخر مباراة", last, UI.GREEN if (not G.last_result.is_empty() and G.last_result["res"] == "win") else UI.DIM, _show.bind("stats")))
	banners.reset_size()
	banners.position = Vector2(vs.x - m - banners.size.x, 84)
	# ---- bottom left: mode card and START
	var bl := VBoxContainer.new()
	bl.add_theme_constant_override("separation", 6)
	hud.add_child(bl)
	var mode := Button.new()
	mode.focus_mode = Control.FOCUS_NONE
	mode.custom_minimum_size = Vector2(350, 62)
	mode.add_theme_stylebox_override("normal", _box(Color(0.03, 0.035, 0.045, 0.82), 6, 1, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.5)))
	mode.add_theme_stylebox_override("hover", _box(Color(0.07, 0.07, 0.08, 0.9), 6, 2, UI.GOLD))
	mode.add_theme_stylebox_override("pressed", _box(Color(0.12, 0.10, 0.06, 0.95), 6, 2, UI.GOLD_HI))
	mode.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	mode.pressed.connect(_show.bind("play"))
	mode.pressed.connect(func(): Sfx.ui("ui_click", -8.0))
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", -4)
	mv.position = Vector2(14, 5)
	mv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var diff_name: String = ["مبتدئون", "مقاتلون", "محترفون"][int(G.settings["difficulty"])]
	var br_mode := String(G.settings.get("mode", "br")) == "br"
	var ml := UI.label("باتل رويال — وادي الذهب" if br_mode else "كلاسيكي — القصبة", 20, UI.TEXT, true)
	ml.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mv.add_child(ml)
	var ms := UI.label(("30 مقاتلاً · العاصفة الرملية · كل واحد لنفسه") if br_mode else ("زرع القنبلة · 5 ضد 5 · بوتات %s" % diff_name), 15, UI.GOLD)
	ms.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mv.add_child(ms)
	mode.add_child(mv)
	bl.add_child(mode)
	start_btn = Button.new()
	start_btn.focus_mode = Control.FOCUS_NONE
	start_btn.custom_minimum_size = Vector2(310, 92)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0.98, 0.76, 0.22)
	sn.border_color = Color(1.0, 0.93, 0.62)
	sn.border_width_top = 3
	sn.border_width_bottom = 6
	sn.border_color = Color(0.70, 0.45, 0.06)
	sn.set_corner_radius_all(6)
	sn.skew = Vector2(-0.12, 0)
	sn.shadow_color = Color(1.0, 0.7, 0.2, 0.35)
	sn.shadow_size = 14
	var sh2 := sn.duplicate() as StyleBoxFlat
	sh2.bg_color = Color(1.0, 0.84, 0.36)
	var sp := sn.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.86, 0.62, 0.14)
	start_btn.add_theme_stylebox_override("normal", sn)
	start_btn.add_theme_stylebox_override("hover", sh2)
	start_btn.add_theme_stylebox_override("pressed", sp)
	start_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var glow := ColorRect.new()
	glow.color = Color(1, 1, 1, 0.10)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.offset_bottom = -52
	glow.offset_left = 10
	glow.offset_right = -10
	glow.offset_top = 6
	start_btn.add_child(glow)
	var stl := UI.label("ابدأ", 50, Color(0.12, 0.08, 0.02), true)
	stl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stl.offset_top = -6
	stl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	start_btn.add_child(stl)
	start_btn.pressed.connect(_start)
	bl.add_child(start_btn)
	var net := HBoxContainer.new()
	net.add_theme_constant_override("separation", 6)
	net.add_child(Glyph.make("wifi", 18, UI.GREEN))
	var nl := UI.label("متصل بالشبكة" if Network.online else "أوفلاين ضد البوتات", 14, UI.DIM)
	net.add_child(nl)
	bl.add_child(net)
	bl.reset_size()
	bl.position = Vector2(m, vs.y - mb - bl.size.y)
	# ---- bottom right navigation
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 18)
	hud.add_child(nav)
	nav.add_child(_labeled("trophy", "الموسم", 56, _show.bind("stats")))
	nav.add_child(_labeled("crate", "الصناديق", 56, _show.bind("cases")))
	nav.add_child(_labeled("bag", "المخزون", 56, _show.bind("inv")))
	nav.add_child(_labeled("gear", "الإعدادات", 56, _show.bind("settings")))
	nav.reset_size()
	nav.position = Vector2(vs.x - m - nav.size.x, vs.y - mb - nav.size.y)
	# ---- name over the hero, invite plates beside him
	name_tag = VBoxContainer.new()
	name_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nt := UI.label(String(G.settings["name"]), 20, UI.TEXT, true)
	nt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	nt.add_theme_constant_override("shadow_offset_y", 2)
	name_tag.add_child(nt)
	var lt := UI.label("المستوى %d" % int(lv[0]), 14, UI.GOLD)
	lt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	name_tag.add_child(lt)
	hud.add_child(name_tag)
	name_tag.reset_size()
	for i in 1:
		var s := Button.new()
		s.focus_mode = Control.FOCUS_NONE
		s.custom_minimum_size = Vector2(150, 46)
		s.text = "+  دعوة صديق"
		s.add_theme_font_override("font", UI.bold())
		s.add_theme_font_size_override("font_size", 17)
		s.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		s.add_theme_stylebox_override("normal", _box(Color(0.03, 0.035, 0.045, 0.55), 4, 1, Color(1, 1, 1, 0.35)))
		s.add_theme_stylebox_override("hover", _box(Color(0.08, 0.08, 0.09, 0.7), 4, 1, UI.GOLD))
		s.add_theme_stylebox_override("pressed", _box(Color(0.12, 0.10, 0.06, 0.8), 4, 1, UI.GOLD_HI))
		s.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		s.pressed.connect(_show.bind("online"))
		hud.add_child(s)
		s.reset_size()
		slots.append(s)
	# ---- outfit selector under the stand
	var team := String(G.settings["team"])
	var oi := int(G.settings.get("outfit", 0)) % 2
	var os := HBoxContainer.new()
	os.add_theme_constant_override("separation", 10)
	hud.add_child(os)
	var prev_b := _round_btn("play", 44)
	(prev_b.get_child(0) as Glyph).rotation = PI
	(prev_b.get_child(0) as Glyph).pivot_offset = (prev_b.get_child(0) as Glyph).size * 0.5
	prev_b.pressed.connect(_switch_outfit.bind(-1))
	os.add_child(prev_b)
	var opan := PanelContainer.new()
	opan.add_theme_stylebox_override("panel", _box(Color(0.03, 0.035, 0.045, 0.82), 22, 1, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.5)))
	opan.custom_minimum_size = Vector2(250, 44)
	var ol := UI.label(OUTFIT_NAMES[team][oi], 18, UI.TEXT, true)
	ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ol.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	opan.add_child(ol)
	os.add_child(opan)
	var next_b := _round_btn("play", 44)
	next_b.pressed.connect(_switch_outfit.bind(1))
	os.add_child(next_b)
	os.reset_size()
	os.position = Vector2((vs.x - os.size.x) * 0.5, vs.y - mb - os.size.y - 6)
	_place_tags()
	_refresh()

func _banner(glyph: String, title: String, sub: String, accent: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(272, 76)
	b.add_theme_stylebox_override("normal", _box(Color(0.03, 0.035, 0.045, 0.80), 6, 1, Color(accent.r, accent.g, accent.b, 0.45)))
	b.add_theme_stylebox_override("hover", _box(Color(0.07, 0.07, 0.08, 0.9), 6, 2, accent))
	b.add_theme_stylebox_override("pressed", _box(Color(0.12, 0.10, 0.06, 0.95), 6, 2, accent))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	b.pressed.connect(func(): Sfx.ui("ui_click", -8.0))
	var stripe := ColorRect.new()
	stripe.color = accent
	stripe.position = Vector2(0, 8)
	stripe.size = Vector2(4, 60)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(stripe)
	var g := Glyph.make(glyph, 40, accent)
	g.position = Vector2(16, 18)
	b.add_child(g)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -4)
	vb.position = Vector2(68, 8)
	vb.size = Vector2(196, 60)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := UI.label(title, 19, UI.TEXT, true)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(tl)
	var sl := UI.label(sub, 15, accent)
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sl.clip_text = true
	sl.custom_minimum_size = Vector2(196, 0)
	vb.add_child(sl)
	b.add_child(vb)
	return b

func _toggle_team() -> void:
	G.settings["team"] = "t" if G.settings["team"] == "ct" else "ct"
	G.save_settings()
	_hero()
	built_for = Vector3(-1, -1, -1)

func _start() -> void:
	Sfx.ui("ui_click", -4.0)
	Network.close_session()
	G.save_settings()
	G.start_match()

func _refresh() -> void:
	if credits_l:
		credits_l.text = str(int(G.profile["credits"]))
	if open_btn:
		open_btn.disabled = int(G.profile["credits"]) < int(DB.CASES["kasbah"]["price"]) or roll_active
	if stats_box and cur_panel == "stats":
		_fill_stats()

func _show(n: String) -> void:
	if roll_active:
		return
	cur_panel = "" if n == cur_panel else n
	for k in panels:
		panels[k].visible = k == cur_panel
	overlay.visible = cur_panel != ""
	(overlay.get_meta("close") as Control).offset_left = -84 - G.inset
	(overlay.get_meta("close") as Control).offset_right = -30 - G.inset
	if cur_panel == "inv":
		_fill_inv()
	if cur_panel != "":
		overlay.modulate.a = 0.0
		create_tween().tween_property(overlay, "modulate:a", 1.0, 0.15)
	_refresh()
	if cur_panel == "" and built_for.x > 0:
		built_for = Vector3(-1, -1, -1)       # balance and banners may have changed

func _room() -> float:
	return get_viewport().get_visible_rect().size.x - 2.0 * G.inset - 160.0

func _panel_box() -> PanelContainer:
	var p := PanelContainer.new()
	var st := UI.box(Color(0.045, 0.05, 0.06, 0.97), 12, 1, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.35))
	st.content_margin_left = 22
	st.content_margin_right = 22
	st.content_margin_top = 14
	st.content_margin_bottom = 16
	p.add_theme_stylebox_override("panel", st)
	UI.rtl(p)
	return p

func _choice(vb: VBoxContainer, title: String, key: String, opts: Array) -> void:
	vb.add_child(UI.label(title, 17, UI.DIM))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	vb.add_child(hb)
	var btns: Array = []
	for o in opts:
		var b := UI.button(o[0], 19, UI.GOLD, Vector2(190, 50))
		b.toggle_mode = true
		b.button_pressed = G.settings[key] == o[1]
		b.pressed.connect(func():
			G.settings[key] = o[1]
			for x in btns:
				x.button_pressed = x == b
			G.save_settings()
			if key == "team":
				_hero()
			built_for = Vector3(-1, -1, -1))
		hb.add_child(b)
		btns.append(b)

func _panel_play() -> Control:
	var p := _panel_box()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	p.add_child(vb)
	vb.add_child(UI.label("اختر الطور", 28, UI.TEXT, true))
	_choice(vb, "الطور", "mode", [["باتل رويال · وادي الذهب", "br"], ["كلاسيكي 5 ضد 5 · القصبة", "classic"]])
	vb.add_child(UI.label("باتل رويال: اقفز من الطائرة، اجمع السلاح والعتاد، ابقَ داخل المنطقة الآمنة من العاصفة الرملية، وكن آخر من يبقى.", 15, UI.DIM))
	vb.add_child(UI.label("كلاسيكي: الهجوم يزرع القنبلة في «أ» أو «ب»، والدفاع يمنعه أو يفكّكها.", 15, UI.DIM))
	_choice(vb, "فريقك في الشوط الأول", "team", [["الدفاع", "ct"], ["الهجوم", "t"]])
	_choice(vb, "طول المباراة", "match_len", [["قصيرة · حتى 4", 4], ["عادية · حتى 7", 7], ["كاملة · حتى 13", 13]])
	_choice(vb, "مستوى البوتات", "difficulty", [["مبتدئون", 0], ["مقاتلون", 1], ["محترفون", 2]])
	var help := UI.label("العصا اليسرى للمشي · اسحب على يمين الشاشة للتصويب · زر الرصاصة للإطلاق" if G.touch else "الحركة: WASD · مشي: Shift · انحناء: Ctrl · المتجر: B · تفكيك: E · النتائج: Tab", 14, UI.DIM)
	help.text_direction = Control.TEXT_DIRECTION_RTL
	vb.add_child(help)
	var go := UI.button("ابدأ المباراة", 24, UI.GOLD, Vector2(340, 58))
	go.pressed.connect(_start)
	vb.add_child(go)
	return p

func _panel_online() -> Control:
	var p := _panel_box()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	p.add_child(vb)
	vb.add_child(UI.label("اللعب مع الأصدقاء", 28, UI.TEXT, true))
	vb.add_child(UI.label("تجربة أولية عبر الشبكة المحلية: أحدكم ينشئ غرفة والباقون ينضمون بعنوانه.", 15, UI.DIM))
	var address := LineEdit.new()
	address.placeholder_text = "عنوان IP للمضيف"
	address.text = "127.0.0.1"
	address.custom_minimum_size = Vector2(380, 50)
	address.alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(address)
	var online_status := UI.label("المضيف واللاعبون يجب أن يستخدموا المنفذ 24567", 14, UI.DIM)
	vb.add_child(online_status)
	Network.connection_failed.connect(func(reason): online_status.text = reason)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	vb.add_child(hb)
	var host_btn := UI.button("إنشاء غرفة", 22, UI.GOLD, Vector2(230, 56))
	host_btn.pressed.connect(func():
		var err := Network.host()
		if err == OK:
			online_status.text = "الغرفة بدأت على المنفذ 24567. أعطِ عنوان IP للاعب الآخر."
			G.start_match())
	hb.add_child(host_btn)
	var join_btn := UI.button("انضمام", 22, UI.TEAL, Vector2(230, 56))
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
	hb.add_child(join_btn)
	return p

func _panel_stats() -> Control:
	var p := _panel_box()
	p.custom_minimum_size = Vector2(560, 0)
	stats_box = VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 10)
	p.add_child(stats_box)
	_fill_stats()
	return p

func _fill_stats() -> void:
	for c in stats_box.get_children():
		c.free()
	var lv: Array = _level()
	stats_box.add_child(UI.label("الموسم الأول — إحصائياتك", 28, UI.TEXT, true))
	var m := int(G.profile["matches"])
	var w := int(G.profile["wins"])
	var k := int(G.profile["kills"])
	var rows := [
		["المستوى", "%d  (%d%%)" % [int(lv[0]), int(float(lv[1]) * 100.0)]],
		["المباريات", str(m)],
		["الانتصارات", str(w)],
		["نسبة الفوز", "%d%%" % (int(round(100.0 * w / m)) if m > 0 else 0)],
		["القتلى", str(k)],
		["معدّل القتل لكل مباراة", "%.1f" % (float(k) / m if m > 0 else 0.0)],
		["الصناديق المفتوحة", str(int(G.profile["cases"]))],
		["الطلاءات", str((G.profile["inv"] as Array).size())],
	]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 60)
	grid.add_theme_constant_override("v_separation", 8)
	stats_box.add_child(grid)
	for r in rows:
		grid.add_child(UI.label(r[0], 19, UI.DIM))
		var v := UI.label(r[1], 21, UI.GOLD_HI, true)
		v.add_theme_font_override("font", UI.latin())
		grid.add_child(v)
	stats_box.add_child(UI.label("ترتفع في المستوى بالمباريات والانتصارات وعدد القتلى.", 14, UI.DIM))

# ------------------------------------------------------------------ cases
func _panel_cases() -> Control:
	var p := _panel_box()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	p.add_child(vb)
	var c: Dictionary = DB.CASES["kasbah"]
	vb.add_child(UI.label(String(c["name"]).to_upper(), 28, UI.TEXT, true))
	var note := UI.label("ثمانية طلاءات لتسعة أسلحة وللسكين. تكسب الرصيد من المباريات: القتل، أفضل لاعب في الجولة، والفوز.", 15, UI.DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(note)
	roll = Control.new()
	roll.layout_direction = Control.LAYOUT_DIRECTION_LTR
	roll.custom_minimum_size = Vector2(clampf(_room(), 620.0, 1000.0), 210)
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
	open_btn = UI.button("افتح مقابل %d" % int(c["price"]), 24, UI.GOLD, Vector2(320, 60))
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
	var eq := UI.button("تجهيز", 18, UI.GOLD, Vector2(130, 44))
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
	roll.draw_rect(Rect2(center - 2, 0, 4, h), UI.GOLD)
	roll.draw_colored_polygon(PackedVector2Array([Vector2(center - 12, 0), Vector2(center + 12, 0), Vector2(center, 16)]), UI.GOLD)
	roll.draw_colored_polygon(PackedVector2Array([Vector2(center - 12, h), Vector2(center + 12, h), Vector2(center, h - 16)]), UI.GOLD)
	if roll_active:
		var idx := int(floor((roll_off + CARD / 2.0) / CARD))
		if idx != roll_last_i:
			roll_last_i = idx
			Sfx.ui("case_tick", -9.0, randf_range(0.96, 1.04))

# ------------------------------------------------------------------ inventory
func _panel_inv() -> Control:
	var p := _panel_box()
	var room := _room()
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
	# the hero holds the newest skin too
	if hero is FighterBody and (hero as FighterBody).weapon_id == wid:
		var fb := hero as FighterBody
		fb.weapon_id = ""
		fb.set_weapon(wid)

# ------------------------------------------------------------------ checks
func _loop_test() -> void:
	## full cycle check: lobby -> START -> match to the end -> lobby again
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
	await G.shot("lobby_main")
	for p in ["play", "online", "stats", "settings"]:
		_show(p)
		await get_tree().create_timer(0.4).timeout
		await G.shot("lobby_" + p)
	_show("cases")
	await get_tree().create_timer(0.4).timeout
	G.profile["credits"] = maxi(int(G.profile["credits"]), 2000)
	_open_case()
	await get_tree().create_timer(2.0).timeout
	await G.shot("lobby_case_roll")
	await get_tree().create_timer(5.0).timeout
	await G.shot("lobby_case_done")
	_show("inv")
	await get_tree().create_timer(0.8).timeout
	await G.shot("lobby_inv")
	_show("")
	_toggle_team()
	await get_tree().create_timer(0.6).timeout
	await G.shot("lobby_team_t")
	if G.args.has("quit_after") or G.args.has("quit_menu"):
		get_tree().quit()
