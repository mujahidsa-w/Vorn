extends "res://game/hud.gd"
## Battle royale HUD: minimap with the sandstorm and the next safe zone, compass, fighters alive, kills, storm timer,
## health/armour with meds, altitude in the jump, pickup prompts and notes, full map (Tab / score button),
## and the results card. Crosshair, hit markers, damage arcs, kill feed and announcements work as in the match.

var mini: Control
var big: Control
var notes: Array = []          # [text, time]
var res := {}
var res_btn: Button

func _ready() -> void:
	super._ready()
	mini = Control.new()
	mini.clip_contents = true
	mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini.draw.connect(_draw_mini.bind(mini, false))
	add_child(mini)
	big = Control.new()
	big.clip_contents = true
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big.visible = false
	big.draw.connect(_draw_mini.bind(big, true))
	add_child(big)

func _process(dt: float) -> void:
	ann_t -= dt
	hit_t -= dt
	hurt_a = maxf(0.0, hurt_a - dt * 1.6)
	if flash_hold > 0.0:
		flash_hold -= dt
	else:
		flash_a = maxf(0.0, flash_a - dt * 0.7)
	for f in feed.duplicate():
		f[1] -= dt
		if f[1] <= 0.0:
			feed.erase(f)
	for d in dmg_marks.duplicate():
		d[1] -= dt
		if d[1] <= 0.0:
			dmg_marks.erase(d)
	for n in notes.duplicate():
		n[1] -= dt
		if n[1] <= 0.0:
			notes.erase(n)
	var p: Player = game.player
	if not game.auto:
		if Input.is_action_just_pressed("pause") and res.is_empty():
			_set_pause(not pause.visible)
	p.ui_block = pause.visible
	var sz := root.size
	var ms := clampf(sz.y * 0.26, 170.0, 250.0)
	mini.position = Vector2(20 + G.inset, 20)
	mini.size = Vector2(ms, ms)
	var show_big := Input.is_action_pressed("score")
	big.visible = show_big and res.is_empty()
	var bs := minf(sz.x, sz.y) * 0.86
	big.size = Vector2(bs, bs)
	big.position = (sz - big.size) * 0.5
	root.queue_redraw()
	mini.queue_redraw()
	if big.visible:
		big.queue_redraw()

func touch_buy() -> void:
	game.use_heal(game.player)

func round_start() -> void:
	pass

func pickup_note(text: String, n: int) -> void:
	notes.append(["+ %s%s" % [text, (" ×%d" % n) if n > 1 else ""], 2.6])
	if notes.size() > 5:
		notes.pop_front()

func show_results(r: Dictionary) -> void:
	res = r
	pause.visible = false
	if res_btn:
		res_btn.queue_free()
	res_btn = UI.button("العودة إلى اللوبي", 24, UI.GOLD, Vector2(320, 56))
	res_btn.size = Vector2(320, 56)
	res_btn.pressed.connect(func(): game.leave())
	add_child(res_btn)
	_mouse()

func _mouse() -> void:
	if game.auto:
		return
	G.set_mouse(Input.MOUSE_MODE_VISIBLE if (pause.visible or not res.is_empty()) else Input.MOUSE_MODE_CAPTURED)

# ------------------------------------------------------------------ map helpers
func _to_map(w: Vector2, center: Vector2, span: float, box: Vector2) -> Vector2:
	return box * 0.5 + (w - center) / span * box.x * 0.5

func _draw_mini(c: Control, full: bool) -> void:
	var land: BRLand = game.land
	if land == null or land.map_tex == null:
		return
	var p: Player = game.player
	var me := Vector2(p.global_position.x, p.global_position.z)
	if p.cam_mode == "free" and is_instance_valid(game.plane):
		me = Vector2(game.plane.global_position.x, game.plane.global_position.z)
	var box := c.size
	var span := BRLand.HALF if full else (420.0 if game.fly[p]["st"] != "ground" else 170.0)
	var center := Vector2.ZERO if full else me
	c.draw_rect(Rect2(Vector2.ZERO, box), Color(0.05, 0.05, 0.06, 0.9))
	# terrain picture: map pixels cover -HALF..HALF
	var tex := land.map_tex
	var tw := float(tex.get_width())
	var src := Rect2((center - Vector2(span, span) + Vector2(BRLand.HALF, BRLand.HALF)) / (BRLand.HALF * 2.0) * tw, Vector2(span, span) * 2.0 / (BRLand.HALF * 2.0) * tw)
	c.draw_texture_rect_region(tex, Rect2(Vector2.ZERO, box), src, Color(1, 1, 1, 0.95))
	# sandstorm: everything outside the current circle tinted, the next safe zone in white
	var sc: Vector2 = game.storm["c"]
	var sr: float = game.storm["r"]
	var cpos := _to_map(sc, center, span, box)
	var crad := sr / span * box.x * 0.5
	var ring_w := maxf(box.x, box.y) * 1.5
	c.draw_arc(cpos, crad + ring_w * 0.5, 0, TAU, 96, Color(0.9, 0.45, 0.12, 0.35), ring_w, false)
	c.draw_arc(cpos, crad, 0, TAU, 96, Color(1.0, 0.55, 0.15, 0.95), 2.5, true)
	var nc: Vector2 = game.storm["c1"]
	var nr: float = game.storm["r1"]
	c.draw_arc(_to_map(nc, center, span, box), maxf(1.0, nr / span * box.x * 0.5), 0, TAU, 96, Color(1, 1, 1, 0.95), 2.0, true)
	# plane route while anyone is still aboard
	if is_instance_valid(game.plane) and game.phase == "plane":
		var a0: Vector3 = game.plane_from
		var a1: Vector3 = game.plane_from + game.plane_dir * game.plane_len
		c.draw_line(_to_map(Vector2(a0.x, a0.z), center, span, box), _to_map(Vector2(a1.x, a1.z), center, span, box), Color(1, 1, 1, 0.55), 2.0)
		var pp := _to_map(Vector2(game.plane.global_position.x, game.plane.global_position.z), center, span, box)
		c.draw_circle(pp, 5.0, UI.GOLD_HI)
	if full:
		for t in land.towns:
			var tp := _to_map(t["c"], center, span, box)
			var f := UI.bold()
			var s: String = t["name"]
			var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			c.draw_string_outline(f, tp - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.8))
			c.draw_string(f, tp - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.95, 0.85))
	# me: an arrow along the view
	var mp := _to_map(me, center, span, box)
	var fwd := Vector2(-sin(p.view_yaw), -cos(p.view_yaw))
	var rt := Vector2(-fwd.y, fwd.x)
	c.draw_colored_polygon(PackedVector2Array([mp + fwd * 10.0, mp - fwd * 6.0 + rt * 6.0, mp - fwd * 3.0, mp - fwd * 6.0 - rt * 6.0]), UI.GOLD_HI)
	c.draw_rect(Rect2(Vector2.ZERO, box), Color(1, 1, 1, 0.25), false, 2.0)

# ------------------------------------------------------------------ main draw
func _draw_hud() -> void:
	var p: Player = game.player
	var sz := root.size
	var cx := sz.x / 2.0
	var cy := sz.y / 2.0
	var st: String = game.fly[p]["st"] if game.fly.has(p) else "ground"
	if flash_a > 0.01:
		root.draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, flash_a))
	if hurt_a > 0.01:
		var hc := Color(0.7, 0.02, 0.0, 0.32 * hurt_a)
		root.draw_rect(Rect2(0, 0, sz.x, 70), hc)
		root.draw_rect(Rect2(0, sz.y - 70, sz.x, 70), hc)
		root.draw_rect(Rect2(0, 0, 70, sz.y), hc)
		root.draw_rect(Rect2(sz.x - 70, 0, 70, sz.y), hc)
	var caught: bool = p.alive and st == "ground" and not game.in_safe(p.global_position)
	if caught:
		root.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.75, 0.38, 0.10, 0.22 + 0.06 * sin(Time.get_ticks_msec() * 0.004)))
	# crosshair and hit markers
	if p.alive and st == "ground" and not pause.visible and res.is_empty():
		if not (p.scoped and p.wd().has("sight")) and p.wd()["cls"] != "sniper":
			var spread := p.spread_deg()
			var gap := 5.0 + spread * 5.5
			var cc: Color = [Color(0.35, 1.0, 0.45), Color(1, 1, 1), Color(0.3, 0.95, 1.0), Color(1.0, 0.85, 0.2)][int(G.settings["cross_color"]) % 4]
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				root.draw_line(Vector2(cx, cy) + d * gap, Vector2(cx, cy) + d * (gap + 9.0), Color(0, 0, 0, 0.6), 4.0)
				root.draw_line(Vector2(cx, cy) + d * gap, Vector2(cx, cy) + d * (gap + 9.0), cc, 2.0)
			root.draw_rect(Rect2(cx - 1, cy - 1, 2, 2), cc)
		if hit_t > 0.0:
			var hcol := UI.RED if hit_kill else (Color(1.0, 0.85, 0.3) if hit_head else Color(1, 1, 1))
			hcol.a = clampf(hit_t / 0.2, 0.0, 1.0)
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				root.draw_line(Vector2(cx, cy) + d * 7.0, Vector2(cx, cy) + d * 15.0, hcol, 2.5)
	for d in dmg_marks:
		var to: Vector3 = (d[0] as Vector3) - p.global_position
		var ang := atan2(-to.x, -to.z) - p.view_yaw
		var a := -ang - PI / 2.0
		root.draw_arc(Vector2(cx, cy), 120.0, a - 0.28, a + 0.28, 16, Color(0.95, 0.15, 0.1, clampf(d[1], 0.0, 1.0) * 0.8), 9.0, true)
	_compass(sz)
	# alive and kills, top right
	var tx := sz.x - 20 - G.inset
	_panel(Rect2(tx - 250, 20, 120, 54), UI.PANEL, 10)
	_text(Vector2(tx - 250, 44), str(game.alive_count()), 26, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 120)
	_text(Vector2(tx - 250, 66), "الأحياء", 13, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER, 120, false)
	_panel(Rect2(tx - 122, 20, 122, 54), UI.PANEL, 10)
	_text(Vector2(tx - 122, 44), str(p.kills), 26, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER, 122)
	_text(Vector2(tx - 122, 66), "القتلى", 13, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER, 122, false)
	# storm status under the minimap
	var my := mini.position.y + mini.size.y + 8.0
	var mx := mini.position.x
	var stxt := ""
	var scol := UI.TEXT
	if int(game.storm["k"]) < int(game.storm["n"]):
		if game.storm["closing"]:
			stxt = "العاصفة تتقلّص  %s" % UI.time_str(game.storm["t"])
			scol = Color(1.0, 0.6, 0.25)
		else:
			stxt = "العاصفة تتحرك بعد  %s" % UI.time_str(game.storm["t"])
	else:
		stxt = "المنطقة الأخيرة"
	_panel(Rect2(mx, my, mini.size.x, 30), UI.PANEL, 8)
	_text(Vector2(mx, my + 21), stxt, 15, scol, HORIZONTAL_ALIGNMENT_CENTER, mini.size.x)
	var me2 := Vector2(p.global_position.x, p.global_position.z)
	var to_safe := me2.distance_to(game.storm["c1"]) - float(game.storm["r1"])
	if p.alive and st == "ground" and to_safe > 0.0:
		_text(Vector2(mx, my + 50), "المنطقة الآمنة: %d م" % int(to_safe), 15, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, mini.size.x)
	# kill feed (right, under the counters)
	var fy := 86.0 if not G.touch else 130.0
	for f in feed:
		var e: Dictionary = f[0]
		var a2 := clampf(f[1] / 0.6, 0.0, 1.0)
		var wname: String = DB.W.get(e["w"], {}).get("name", {"he": "قنبلة", "fire": "نار", "zone": "العاصفة", "fall": "سقوط"}.get(e["w"], "")) as String
		var line: String = ("%s  [%s]  %s" % [e["k"], wname, e["v"]]) if e["k"] != "" else ("%s  [%s]" % [e["v"], wname])
		var w1 := UI.bold().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 24.0
		_panel(Rect2(tx - w1, fy, w1, 28), Color(0.5, 0.08, 0.06, 0.78 * a2) if e["me"] else Color(0.05, 0.06, 0.08, 0.7 * a2), 7)
		_text(Vector2(tx - w1 + 12, fy + 20), line, 16, Color(1, 1, 1, a2))
		fy += 32
	# pickup notes
	var ny := cy + 40.0
	for n in notes:
		_text(Vector2(cx + 160, ny), n[0], 17, Color(0.85, 1.0, 0.75, clampf(n[1], 0.0, 1.0)))
		ny += 24
	# jump phases
	if p.alive and st != "ground":
		var ground: float = game.land.height_at(p.global_position.x, p.global_position.z)
		var alt := int(p.global_position.y - ground)
		if st == "plane":
			_text(Vector2(cx - 300, sz.y - 150), ("اضغط «اقفز» عندما تكون فوق مكان هبوطك" if G.touch else "اضغط E أو المسافة للقفز") , 22, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 600)
			_text(Vector2(cx - 300, sz.y - 120), "حرّك الشاشة للنظر حول الطائرة · الخريطة: Tab" if not G.touch else "زر النتائج يفتح الخريطة", 15, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER, 600, false)
		else:
			_panel(Rect2(sz.x - 120 - G.inset, cy - 80, 86, 160), UI.PANEL, 10)
			_text(Vector2(sz.x - 120 - G.inset, cy - 50), "الارتفاع", 13, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER, 86, false)
			_text(Vector2(sz.x - 120 - G.inset, cy - 10), "%d" % alt, 30, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 86)
			_text(Vector2(sz.x - 120 - G.inset, cy + 14), "م", 14, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER, 86, false)
			var spd := int(absf(p.velocity.y) * 3.6)
			_text(Vector2(sz.x - 120 - G.inset, cy + 52), "%d كم/س" % spd, 14, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER, 86, false)
			if st == "fall":
				_text(Vector2(cx - 300, sz.y - 150), "انظر للأسفل لتنقضّ أسرع · " + ("«المظلة» تفتحها الآن" if G.touch else "E تفتح المظلة"), 18, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 600)
	# health, armour, meds (the touch layout draws its own health and ammo)
	if p.alive and st == "ground" and not G.touch:
		var bw := 440.0
		var bx := cx - bw * 0.5
		var by := sz.y - 64.0 - G.inset_b
		_panel(Rect2(bx, by, bw, 44), UI.PANEL, 10)
		root.draw_rect(Rect2(bx + 12, by + 10, bw - 24, 14), Color(1, 1, 1, 0.12))
		root.draw_rect(Rect2(bx + 12, by + 10, (bw - 24) * p.hp / 100.0, 14), UI.RED if p.hp <= 25 else Color(0.94, 0.94, 0.95))
		root.draw_rect(Rect2(bx + 12, by + 28, (bw - 24) * p.armor / 100.0, 6), UI.TEAL)
		_text(Vector2(bx - 64, by + 30), "◆" if p.helmet else "", 22, UI.TEAL)
		_ammo(p, sz)
	if p.alive and st == "ground":
		var m: Dictionary = game.meds[p]
		var mt := "ضمادات %d   ·   إسعاف %d" % [int(m["bandage"]), int(m["medkit"])]
		_text(Vector2(cx - 200, sz.y - 76.0 - G.inset_b - (0.0 if not G.touch else 70.0)), mt, 15, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER, 400, false)
		if game.heal.has(p):
			var h: Dictionary = game.heal[p]
			var k := 1.0 - float(h["t"]) / float(h["total"])
			_panel(Rect2(cx - 160, cy + 90, 320, 44), UI.PANEL, 10)
			_text(Vector2(cx - 160, cy + 110), "علاج: " + Loot.title(h["id"]), 15, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 320, false)
			root.draw_rect(Rect2(cx - 146, cy + 118, 292 * k, 8), UI.GREEN)
		elif not G.touch and game.can_buy(p):
			_text(Vector2(cx - 200, sz.y - 98.0 - G.inset_b), "B للعلاج", 14, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER, 400, false)
		var w: Loot = game.nearest_item(p, 1.9, true)
		if w and res.is_empty():
			var cur: String = p.inv[int(DB.W[w.id]["slot"])]
			var msg := ("التقط %s" % Loot.title(w.id)) + (("  (بدل %s)" % Loot.title(cur)) if cur != "" else "")
			_panel(Rect2(cx - 220, cy + 150, 440, 40), Color(0.05, 0.06, 0.08, 0.8), 10)
			_text(Vector2(cx - 220, cy + 177), ("E: " if not G.touch else "") + msg, 18, UI.GOLD_HI, HORIZONTAL_ALIGNMENT_CENTER, 440)
	elif not p.alive and res.is_empty():
		_text(Vector2(cx - 300, sz.y - 150), "لقد خرجت من المعركة", 26, UI.RED, HORIZONTAL_ALIGNMENT_CENTER, 600)
	# announcement
	if ann_t > 0.0 and ann_text != "":
		var a3 := clampf(ann_t / 0.4, 0.0, 1.0)
		var wdt := 620.0
		_panel(Rect2(cx - wdt / 2, 118, wdt, 86 if ann_sub != "" else 60), Color(0.05, 0.06, 0.08, 0.86 * a3), 12)
		root.draw_rect(Rect2(cx - wdt / 2, 118, 6, 86 if ann_sub != "" else 60), Color(ann_col.r, ann_col.g, ann_col.b, a3))
		var ac := ann_col
		ac.a = a3
		_text(Vector2(cx - wdt / 2, 160), ann_text, 32, ac, HORIZONTAL_ALIGNMENT_CENTER, wdt)
		if ann_sub != "":
			_text(Vector2(cx - wdt / 2, 190), ann_sub, 17, Color(1, 1, 1, 0.8 * a3), HORIZONTAL_ALIGNMENT_CENTER, wdt, false)
	if G.settings["show_fps"]:
		_text(Vector2(sz.x - 110, sz.y - 30), "%d إطار/ث" % Engine.get_frames_per_second(), 14, UI.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, false)
	if not res.is_empty():
		_results(sz)

func _compass(sz: Vector2) -> void:
	var p: Player = game.player
	var cx := sz.x * 0.5
	var w := 420.0
	_panel(Rect2(cx - w * 0.5, 14, w, 36), Color(0.03, 0.035, 0.045, 0.55), 8)
	var bearing := fposmod(rad_to_deg(-p.view_yaw), 360.0)
	var names := {0: "ش", 45: "شش", 90: "شر", 135: "جش", 180: "ج", 225: "جغ", 270: "غ", 315: "شغ"}
	for k in range(-75, 76, 15):
		var deg := int(fposmod(round((bearing + k) / 15.0) * 15.0, 360.0))
		var off := fposmod(deg - bearing + 540.0, 360.0) - 180.0
		var x := cx + off / 75.0 * (w * 0.5 - 20.0)
		if absf(off) > 76.0:
			continue
		var big_tick := deg % 45 == 0
		root.draw_line(Vector2(x, 16), Vector2(x, 16 + (10 if big_tick else 5)), Color(1, 1, 1, 0.7), 2.0)
		var lab: String = names.get(deg, str(deg)) if big_tick else ""
		if lab != "":
			_text(Vector2(x - 30, 44), lab, 15 if deg % 90 == 0 else 13, UI.GOLD_HI if deg == 0 else UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 60)
	root.draw_colored_polygon(PackedVector2Array([Vector2(cx - 6, 52), Vector2(cx + 6, 52), Vector2(cx, 45)]), UI.GOLD)

func _ammo(p: Player, sz: Vector2) -> void:
	var d: Dictionary = p.wd()
	var x0 := sz.x - 352 - G.inset
	_panel(Rect2(x0, sz.y - 96, 330, 74), UI.PANEL, 12)
	_text(Vector2(x0 + 14, sz.y - 70), d["name"], 17, UI.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, false)
	if p.ammo.has(p.cur):
		var m := p.mag()
		_text(Vector2(x0 + 162, sz.y - 40), str(m), 44, UI.RED if m <= int(d["mag"]) / 5 else UI.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 80)
		_text(Vector2(x0 + 250, sz.y - 40), "/ %d" % p.reserve(), 22, UI.DIM)
		if p.reload_t > 0.0:
			var rk := 1.0 - p.reload_t / maxf(0.01, p.reload_total)
			root.draw_rect(Rect2(x0 + 14, sz.y - 24, 300 * rk, 3), UI.AMBER)
	else:
		_text(Vector2(x0 + 14, sz.y - 38), "—", 32, UI.DIM)
	var iy := sz.y - 120.0
	var own: Array = p.owned()
	own.reverse()
	for wid in own:
		var cur: bool = wid == p.cur
		var nm: String = DB.W[wid]["name"]
		var ww := 190.0 if cur else 160.0
		_panel(Rect2(sz.x - 22 - G.inset - ww, iy - 30, ww, 30), Color(0.12, 0.14, 0.17, 0.92) if cur else Color(0.05, 0.06, 0.08, 0.6), 7)
		_text(Vector2(sz.x - 14 - G.inset - ww, iy - 9), "%d  %s" % [DB.W[wid]["slot"], nm], 15, UI.GOLD if cur else UI.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, cur)
		iy -= 34

func _results(sz: Vector2) -> void:
	root.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.02, 0.03, 0.72))
	var cx := sz.x * 0.5
	var won: bool = res["won"]
	var w := 640.0
	var top := sz.y * 0.5 - 210.0
	_panel(Rect2(cx - w * 0.5, top, w, 400), Color(0.05, 0.055, 0.07, 0.95), 16)
	root.draw_rect(Rect2(cx - w * 0.5, top, w, 6), UI.GOLD if won else UI.RED)
	_text(Vector2(cx - w * 0.5, top + 64), "أنت البطل الأخير!" if won else "انتهت معركتك", 40, UI.GOLD_HI if won else UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, w)
	_text(Vector2(cx - w * 0.5, top + 130), "#%d" % int(res["place"]), 64, UI.GOLD if won else UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, w)
	_text(Vector2(cx - w * 0.5, top + 160), "من %d مقاتلاً" % int(res["of"]), 18, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER, w, false)
	var rows := [["القتلى", str(res["kills"])], ["الضرر", str(res["dmg"])], ["مدة البقاء", UI.time_str(res["time"])], ["الرصيد المكتسب", "+%d" % int(res["credits"])]]
	for i in rows.size():
		var x := cx - w * 0.5 + 20 + i * (w - 40) / 4.0
		_text(Vector2(x, top + 230), rows[i][1], 30, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, (w - 40) / 4.0)
		_text(Vector2(x, top + 258), rows[i][0], 14, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER, (w - 40) / 4.0, false)
	if res_btn:
		res_btn.position = Vector2(cx - 160, top + 310)
