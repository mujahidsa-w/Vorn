extends CanvasLayer
## HUD: прицел, счёт и таймер, радар, здоровье и броня, патроны, деньги, лента убийств, объявления,
## метки попаданий, направление урона, ослепление, прогресс закладки/разминирования, таблица счёта, итог матча.

var game
var root: Control
var buy: Control
var pause: Control
var feed: Array = []            # [текст-части, время]
var ann_text := ""
var ann_sub := ""
var ann_t := 0.0
var ann_col := UI.TEXT
var hit_t := 0.0
var hit_head := false
var hit_kill := false
var dmg_marks: Array = []       # [мировая точка, время]
var flash_a := 0.0
var flash_hold := 0.0
var show_score := false
var over := {}
var radar: Texture2D
var hurt_a := 0.0

func _ready() -> void:
	layer = 5
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.draw.connect(_draw_hud)
	if ResourceLoader.exists("res://assets/ui/radar.png"):
		radar = load("res://assets/ui/radar.png")
	buy = preload("res://game/buy_menu.gd").new()
	buy.game = game
	buy.visible = false
	add_child(buy)
	pause = preload("res://game/pause_menu.gd").new()
	pause.game = game
	pause.visible = false
	add_child(pause)

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
	var p: Player = game.player
	if not game.auto:
		if Input.is_action_just_pressed("pause") and game.state != game.S.OVER:
			if buy.visible:
				_set_buy(false)
			else:
				_set_pause(not pause.visible)
		if Input.is_action_just_pressed("buy") and not pause.visible and p.alive:
			if buy.visible:
				_set_buy(false)
			elif game.can_buy(p):
				_set_buy(true)
			else:
				announce("الشراء غير متاح", 1.2)
		if buy.visible and not game.can_buy(p):
			_set_buy(false)
		show_score = Input.is_action_pressed("score") or game.state == game.S.OVER or game.has_meta("force_score")
	else:
		show_score = game.state == game.S.OVER or game.has_meta("force_score")
	p.ui_block = buy.visible or pause.visible
	root.queue_redraw()

func _set_buy(on: bool) -> void:
	buy.visible = on
	if on:
		buy.refresh()
	_mouse()

func _set_pause(on: bool) -> void:
	pause.visible = on
	_mouse()

func _mouse() -> void:
	if game.auto:
		return
	G.set_mouse(Input.MOUSE_MODE_VISIBLE if (buy.visible or pause.visible or game.state == game.S.OVER) else Input.MOUSE_MODE_CAPTURED)

# ------------------------------------------------------------------ события
func round_start() -> void:
	announce("الجولة %d" % game.round_no, 3.0, ("المتجر متاح الآن" if G.touch else "المتجر: B") if game.player.alive else "")
	feed.clear()

func round_end(winner: String, reason: String, mvp: Actor) -> void:
	var t := "فاز المهاجمون" if winner == "t" else "فاز المدافعون"
	var sub := reason
	if mvp:
		sub += "   ·   الأفضل: %s" % mvp.nick
	announce(t, DB.T_END - 0.5, sub, UI.team_col(winner))

func announce(t: String, dur := 2.5, sub := "", col := UI.TEXT) -> void:
	ann_text = t
	ann_sub = sub
	ann_t = dur
	ann_col = col

func kill(killer: Actor, v: Actor, wid: String, hs: bool) -> void:
	feed.append([{"k": killer.nick if killer else "", "kt": killer.team if killer else "", "v": v.nick, "vt": v.team, "w": wid, "hs": hs,
		"me": killer == game.player or v == game.player}, 6.0])
	if feed.size() > 6:
		feed.pop_front()

func hit_marker(head: bool, killed: bool) -> void:
	hit_t = 0.22 if not killed else 0.4
	hit_head = head
	hit_kill = killed
	Sfx.ui("hitmark", -9.0 if not killed else -5.0, 1.25 if head else 1.0)

func damage_from(pos: Vector3, n: int) -> void:
	dmg_marks.append([pos, 1.4])
	hurt_a = minf(1.0, hurt_a + 0.25 + n * 0.012)

func flash(t: float) -> void:
	flash_a = clampf(t / 1.5, 0.0, 1.0)
	flash_hold = maxf(0.0, t - 1.4)

func match_over(res: String, credits: int) -> void:
	over = {"res": res, "credits": credits}
	buy.visible = false
	pause.visible = false
	var b := UI.button("القائمة الرئيسية", 22, UI.TEAL, Vector2(300, 48))
	b.size = Vector2(300, 48)
	b.position = Vector2(root.size.x / 2.0 - 150.0, minf(root.size.y / 2.0 + 296.0, root.size.y - 52.0 - G.inset_b))
	b.pressed.connect(func(): game.leave())
	add_child(b)

func touch_buy() -> void:
	## the on-screen shop button: same rules as the B key
	var p: Player = game.player
	if pause.visible or not p.alive:
		return
	if buy.visible:
		_set_buy(false)
	elif game.can_buy(p):
		_set_buy(true)
	else:
		announce("الشراء غير متاح", 1.2)

# ------------------------------------------------------------------ отрисовка
func _text(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0, bold := true) -> void:
	var f := UI.bold() if bold else UI.font()
	root.draw_string_outline(f, pos, s, align, w, size, 3, Color(0, 0, 0, 0.55 * col.a))
	root.draw_string(f, pos, s, align, w, size, col)

func _panel(r: Rect2, col := UI.PANEL, rad := 10) -> void:
	var sb := UI.box(col, rad)
	root.draw_style_box(sb, r)

func _bar(r: Rect2, k: float, col: Color, segs := 10) -> void:
	var gap := 3.0
	var w := (r.size.x - gap * (segs - 1)) / segs
	for i in segs:
		var filled := float(i) < k * segs - 0.001
		var c := col if filled else Color(1, 1, 1, 0.12)
		root.draw_rect(Rect2(r.position.x + i * (w + gap), r.position.y, w, r.size.y), c)

func _draw_hud() -> void:
	var p: Player = game.player
	var sz := root.size
	var cx := sz.x / 2.0
	var cy := sz.y / 2.0
	var watch: Actor = p if p.alive else p.spect
	# ---- эффекты на весь экран
	if flash_a > 0.01:
		root.draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, flash_a))
	if hurt_a > 0.01:
		var c := Color(0.7, 0.02, 0.0, 0.32 * hurt_a)
		root.draw_rect(Rect2(0, 0, sz.x, 70), c)
		root.draw_rect(Rect2(0, sz.y - 70, sz.x, 70), c)
		root.draw_rect(Rect2(0, 0, 70, sz.y), c)
		root.draw_rect(Rect2(sz.x - 70, 0, 70, sz.y), c)
	# ---- прицел
	if p.alive and not buy.visible and not pause.visible:
		if p.scoped and p.wd().has("sight"):
			pass                # aiming through the optic on the weapon: no crosshair, no overlay
		elif p.wd()["cls"] != "sniper":
			var spread := p.spread_deg()
			var gap := 5.0 + spread * 5.5
			var ln := 9.0
			var cc: Color = [Color(0.35, 1.0, 0.45), Color(1, 1, 1), Color(0.3, 0.95, 1.0), Color(1.0, 0.85, 0.2)][int(G.settings["cross_color"]) % 4]
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				root.draw_line(Vector2(cx, cy) + d * gap, Vector2(cx, cy) + d * (gap + ln), Color(0, 0, 0, 0.6), 4.0)
				root.draw_line(Vector2(cx, cy) + d * gap, Vector2(cx, cy) + d * (gap + ln), cc, 2.0)
			root.draw_rect(Rect2(cx - 1, cy - 1, 2, 2), cc)
		if hit_t > 0.0:
			var hc := UI.RED if hit_kill else (Color(1.0, 0.85, 0.3) if hit_head else Color(1, 1, 1))
			hc.a = clampf(hit_t / 0.2, 0.0, 1.0)
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				root.draw_line(Vector2(cx, cy) + d * 7.0, Vector2(cx, cy) + d * 15.0, hc, 2.5)
	# ---- направление урона
	for d in dmg_marks:
		var to: Vector3 = (d[0] as Vector3) - p.global_position
		var ang := atan2(-to.x, -to.z) - p.view_yaw
		var a := -ang - PI / 2.0
		var col2 := Color(0.95, 0.15, 0.1, clampf(d[1], 0.0, 1.0) * 0.8)
		root.draw_arc(Vector2(cx, cy), 120.0, a - 0.28, a + 0.28, 16, col2, 9.0, true)
	# ---- верх: счёт, таймер, живые
	var tw := 440.0
	_panel(Rect2(cx - tw / 2, 14, tw, 58), UI.PANEL, 12)
	var st: int = game.state
	var tl: float = game.time_left()
	var tcol := UI.TEXT
	var ts := UI.time_str(tl)
	if st == game.S.PLANTED:
		ts = "القنبلة"
		tcol = UI.RED if fmod(Time.get_ticks_msec() * 0.001, 0.8) < 0.4 else Color(1, 0.6, 0.5)
	elif st == game.S.FREEZE:
		tcol = UI.DIM
	elif tl < 10.0:
		tcol = UI.RED
	_text(Vector2(cx - 60, 54), ts, 30, tcol, HORIZONTAL_ALIGNMENT_CENTER, 120)
	_text(Vector2(cx - 122, 56), str(game.score["t"]), 36, UI.AMBER, HORIZONTAL_ALIGNMENT_CENTER, 50)
	_text(Vector2(cx + 72, 56), str(game.score["ct"]), 36, UI.TEAL, HORIZONTAL_ALIGNMENT_CENTER, 50)
	var ta: int = game.alive_of("t").size()
	var ca: int = game.alive_of("ct").size()
	for i in 5:
		root.draw_circle(Vector2(cx - 150 - i * 15, 43), 5.5, UI.AMBER if i < ta else Color(1, 1, 1, 0.14))
		root.draw_circle(Vector2(cx + 150 + i * 15, 43), 5.5, UI.TEAL if i < ca else Color(1, 1, 1, 0.14))
	_text(Vector2(cx - 220, 92), "الجولة %d  ·  حتى %d انتصارات" % [game.round_no, game.win_target], 15, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER, 440, false)
	# ---- радар
	root.draw_set_transform(Vector2(G.inset, 0))          # keep the left block clear of the notch
	_radar(Vector2(22, 22), 210.0, watch)
	if watch:
		_text(Vector2(26, 262), game.world.name_at(watch.global_position), 18, UI.TEXT)
	# ---- деньги и подсказки
	if p.alive:
		_text(Vector2(26, 296), UI.money(p.money), 28, UI.GREEN)
		if game.can_buy(p) and not buy.visible and not G.touch:
			_text(Vector2(26, 322), "المتجر: B", 16, UI.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, false)
	# ---- лента убийств
	root.draw_set_transform(Vector2(-G.inset, 0))
	var fy := 86.0 if G.touch else 24.0
	for f in feed:
		var e: Dictionary = f[0]
		var a2 := clampf(f[1] / 0.6, 0.0, 1.0)
		var wname: String = DB.W.get(e["w"], {}).get("name", {"he": "قنبلة", "fire": "نار", "c4": "القنبلة"}.get(e["w"], "")) as String
		var mid := "  [%s%s]  " % [wname, " ✚" if e["hs"] else ""]
		var f1 := UI.bold()
		var w1 := f1.get_string_size(e["k"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var w2 := f1.get_string_size(mid, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var w3 := f1.get_string_size(e["v"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var tot := w1 + w2 + w3 + 28
		var x0 := sz.x - 22 - tot
		_panel(Rect2(x0, fy, tot, 32), Color(0.5, 0.08, 0.06, 0.78 * a2) if e["me"] else Color(0.05, 0.06, 0.08, 0.72 * a2), 7)
		var kc := UI.team_col(e["kt"]); kc.a = a2
		var vc := UI.team_col(e["vt"]); vc.a = a2
		_text(Vector2(x0 + 14 + w3 + w2, fy + 23), e["k"], 18, kc)
		_text(Vector2(x0 + 14 + w3, fy + 22), mid, 16, Color(1, 1, 1, 0.85 * a2), HORIZONTAL_ALIGNMENT_LEFT, -1, false)
		_text(Vector2(x0 + 14, fy + 23), e["v"], 18, vc)
		fy += 38
	# ---- здоровье, броня, патроны
	if watch and watch.alive and not (G.touch and p.alive):
		root.draw_set_transform(Vector2(G.inset, 0))
		_panel(Rect2(22, sz.y - 96, 330, 74), UI.PANEL, 12)
		var hpk := watch.hp / 100.0
		_text(Vector2(36, sz.y - 62), "✚", 22, UI.TEXT)
		_text(Vector2(64, sz.y - 60), str(watch.hp), 28, UI.RED if watch.hp <= 25 else UI.TEXT)
		_bar(Rect2(124, sz.y - 80, 212, 16), hpk, UI.RED if watch.hp <= 25 else Color(0.92, 0.93, 0.95))
		_text(Vector2(36, sz.y - 32), "◆" if watch.helmet else "◈", 20, UI.TEAL)
		_text(Vector2(64, sz.y - 32), str(watch.armor), 22, UI.TEAL)
		_bar(Rect2(124, sz.y - 48, 212, 12), watch.armor / 100.0, UI.TEAL)
		var d: Dictionary = watch.wd()
		root.draw_set_transform(Vector2(-G.inset, 0))
		_panel(Rect2(sz.x - 352, sz.y - 96, 330, 74), UI.PANEL, 12)
		_text(Vector2(sz.x - 338, sz.y - 70), d["name"], 17, UI.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, false)
		if watch.ammo.has(watch.cur):
			var m := watch.mag()
			_text(Vector2(sz.x - 190, sz.y - 40), str(m), 44, UI.RED if m <= int(d["mag"]) / 5 else UI.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 80)
			_text(Vector2(sz.x - 102, sz.y - 40), "/ %d" % watch.reserve(), 22, UI.DIM)
			var n: int = mini(int(d["mag"]), 30)
			var bw := 300.0 / 30.0
			for i in n:
				var on: bool = float(i) < float(m) / float(d["mag"]) * n
				root.draw_rect(Rect2(sz.x - 338 + i * bw, sz.y - 34, bw - 3, 6), Color(1, 0.9, 0.6, 0.95) if on else Color(1, 1, 1, 0.12))
			if watch.reload_t > 0.0:
				var rk := 1.0 - watch.reload_t / maxf(0.01, watch.reload_total)
				root.draw_rect(Rect2(sz.x - 338, sz.y - 24, 300 * rk, 3), UI.AMBER)
		else:
			_text(Vector2(sz.x - 338, sz.y - 38), "—", 32, UI.DIM)
		# инвентарь справа
		var iy := sz.y - 120.0
		var own: Array = watch.owned()
		own.reverse()
		for wid in own:
			var cur: bool = wid == watch.cur
			var nm: String = DB.W[wid]["name"]
			var cnt: int = watch.nades.count(wid)
			if cnt > 1:
				nm += " ×%d" % cnt
			var ww := 190.0 if cur else 160.0
			_panel(Rect2(sz.x - 22 - ww, iy - 30, ww, 30), Color(0.12, 0.14, 0.17, 0.92) if cur else Color(0.05, 0.06, 0.08, 0.6), 7)
			var ic := UI.icon(wid)
			if ic:
				var ih := 22.0
				var iw := ih * ic.get_width() / ic.get_height()
				root.draw_texture_rect(ic, Rect2(sz.x - 30 - iw, iy - 26, iw, ih), false, Color(1, 1, 1, 1.0 if cur else 0.55))
			_text(Vector2(sz.x - 14 - ww, iy - 9), "%d  %s" % [DB.W[wid]["slot"], nm], 15, UI.team_col(watch.team) if cur else UI.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, cur)
			iy -= 34
		root.draw_set_transform(Vector2(G.inset, 0))
		if watch.kit:
			_text(Vector2(360, sz.y - 34), "عدّة التفكيك", 15, UI.TEAL, HORIZONTAL_ALIGNMENT_LEFT, -1, false)
		if watch.inv[5] == "c4":
			_text(Vector2(360, sz.y - 56), "القنبلة معك · 5", 15, UI.AMBER, HORIZONTAL_ALIGNMENT_LEFT, -1, false)
	# ---- прогресс закладки / разминирования, подсказки
	root.draw_set_transform(Vector2.ZERO)
	if p.alive:
		var prog := -1.0
		var ptxt := ""
		if p.plant_t >= 0.0:
			prog = p.plant_t / DB.T_PLANT
			ptxt = "زرع القنبلة"
		elif p.defuse_t >= 0.0:
			prog = p.defuse_t / (DB.T_DEFUSE_KIT if p.kit else DB.T_DEFUSE)
			ptxt = "تفكيك القنبلة"
		if prog >= 0.0:
			_panel(Rect2(cx - 180, cy + 110, 360, 46), UI.PANEL, 10)
			_text(Vector2(cx - 170, cy + 130), ptxt, 15, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 340, false)
			root.draw_rect(Rect2(cx - 166, cy + 138, 332, 8), Color(1, 1, 1, 0.12))
			root.draw_rect(Rect2(cx - 166, cy + 138, 332 * clampf(prog, 0, 1), 8), UI.team_col(p.team))
		elif st == game.S.PLANTED and p.team == "ct" and p.global_position.distance_to(game.bomb["pos"]) < 1.7:
			_text(Vector2(cx - 200, cy + 136), "اضغط مطولاً على زر التفكيك" if G.touch else "اضغط E مطولاً للتفكيك", 18, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 400)
		elif st == game.S.LIVE and p.inv[5] == "c4" and game.world.site_at(p.global_position) != "":
			_text(Vector2(cx - 240, cy + 136), "اضغط مطولاً على زر الزرع" if G.touch else "اختر القنبلة (5) واضغط زر الفأرة الأيسر مطولاً للزرع", 18, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 480)
	elif st != game.S.OVER:
		_text(Vector2(cx - 300, sz.y - 150), "لقد قُتلت", 26, UI.RED, HORIZONTAL_ALIGNMENT_CENTER, 600)
		if p.spect:
			_text(Vector2(cx - 300, sz.y - 120), ("تشاهد: %s   ·   المس الشاشة للتالي" if G.touch else "تشاهد: %s   ·   الزر الأيسر للتالي") % p.spect.nick, 17, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 600, false)
	# ---- объявление
	if ann_t > 0.0 and ann_text != "":
		var a3 := clampf(ann_t / 0.4, 0.0, 1.0)
		var wdt := 620.0
		_panel(Rect2(cx - wdt / 2, 118, wdt, 86 if ann_sub != "" else 60), Color(0.05, 0.06, 0.08, 0.86 * a3), 12)
		root.draw_rect(Rect2(cx - wdt / 2, 118, 6, 86 if ann_sub != "" else 60), Color(ann_col.r, ann_col.g, ann_col.b, a3))
		var ac := ann_col; ac.a = a3
		_text(Vector2(cx - wdt / 2, 160), ann_text, 34, ac, HORIZONTAL_ALIGNMENT_CENTER, wdt)
		if ann_sub != "":
			_text(Vector2(cx - wdt / 2, 190), ann_sub, 17, Color(1, 1, 1, 0.8 * a3), HORIZONTAL_ALIGNMENT_CENTER, wdt, false)
	if st == game.S.FREEZE:
		_text(Vector2(cx - 200, 232), "البداية بعد %d" % int(ceil(game.t_left)), 20, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER, 400, false)
	if G.settings["show_fps"]:
		_text(Vector2(sz.x - 110, sz.y - 108), "%d إطار/ث" % Engine.get_frames_per_second(), 14, UI.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, false)
	if show_score:
		_scoreboard(sz)

func _radar(pos: Vector2, s: float, watch: Actor) -> void:
	var ws: Vector2i = game.world.size
	var h := s * ws.y / ws.x
	_panel(Rect2(pos - Vector2(6, 6), Vector2(s + 12, h + 12)), UI.PANEL, 10)
	if radar:
		root.draw_texture_rect(radar, Rect2(pos, Vector2(s, h)), false, Color(1, 1, 1, 0.9))
	var k := s / ws.x
	var me: Player = game.player
	var b: Dictionary = game.bomb
	if b["state"] in ["planted", "dropped"] and (me.team == "t" or b["state"] == "planted"):
		var bp: Vector3 = b["pos"]
		root.draw_circle(pos + Vector2(bp.x, ws.y + bp.z) * k, 5.0, UI.RED)
	for a in game.actors:
		var o := a as Actor
		if not o.alive:
			continue
		var q := pos + Vector2(o.global_position.x, ws.y + o.global_position.z) * k
		if o.team == me.team:
			var col := UI.team_col(o.team)
			if o == watch:
				var fwd := Vector2(-sin(o.view_yaw), -cos(o.view_yaw))
				var side := Vector2(-fwd.y, fwd.x)
				root.draw_colored_polygon(PackedVector2Array([q + fwd * 9, q - fwd * 5 + side * 6, q - fwd * 5 - side * 6]), Color.WHITE)
			else:
				root.draw_circle(q, 4.5, col)
			if o.inv[5] == "c4":
				root.draw_arc(q, 7.5, 0, TAU, 12, UI.RED, 1.5)
		elif o.has_meta("seen_ms") and Time.get_ticks_msec() - int(o.get_meta("seen_ms")) < 2500:
			root.draw_circle(q, 4.5, UI.RED)

func _scoreboard(sz: Vector2) -> void:
	var w := 880.0
	var hh := 560.0
	var x := sz.x / 2 - w / 2
	var y := sz.y / 2 - hh / 2 + 10
	_panel(Rect2(x, y, w, hh), Color(0.045, 0.055, 0.07, 0.94), 14)
	var title := "القصبة  ·  AURUM STRIKE"
	if not over.is_empty():
		title = {"win": "انتصار", "lose": "هزيمة", "draw": "تعادل"}[over["res"]]
	_text(Vector2(x, y + 44), title, 30, UI.TEXT if over.is_empty() else ({"win": UI.GREEN, "lose": UI.RED, "draw": UI.TEXT}[over["res"]] as Color), HORIZONTAL_ALIGNMENT_CENTER, w)
	var yy := y + 66
	for team in ["ct", "t"]:
		var col := UI.team_col(team)
		root.draw_rect(Rect2(x + 20, yy, w - 40, 34), Color(col.r, col.g, col.b, 0.16))
		_text(Vector2(x + w - 332, yy + 24), ("الدفاع" if team == "ct" else "الهجوم") + "   %d" % game.score[team], 19, col, HORIZONTAL_ALIGNMENT_RIGHT, 300)
		for i in 5:
			var hd: String = ["قتل", "مساعدة", "موت", "الأفضل", "النقاط", "المال"][i] if i < 5 else ""
			_text(Vector2(x + w - 490 - i * 90, yy + 23), hd, 13, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER, 90, false)
		yy += 40
		var list: Array = game.team_of(team)
		list.sort_custom(func(a, b): return a.score > b.score)
		for a in list:
			var o := a as Actor
			var me: bool = o == game.player
			if me:
				root.draw_rect(Rect2(x + 20, yy - 2, w - 40, 32), Color(1, 1, 1, 0.07))
			var nc := UI.TEXT if o.alive else Color(1, 1, 1, 0.38)
			_text(Vector2(x + w - 34 - 220, yy + 21), ("● " if o.alive else "✖ ") + o.nick, 18, nc, HORIZONTAL_ALIGNMENT_RIGHT, 220, me)
			var vals := [str(o.kills), str(o.assists), str(o.deaths), "★%d" % o.mvps if o.mvps > 0 else "—", str(o.score)]
			for i in vals.size():
				_text(Vector2(x + w - 490 - i * 90, yy + 21), vals[i], 18, nc, HORIZONTAL_ALIGNMENT_CENTER, 90, me)
			if o.team == game.player.team:
				_text(Vector2(x + w - 250 - 130, yy + 21), UI.money(o.money), 15, UI.GREEN, HORIZONTAL_ALIGNMENT_RIGHT, 130, false)
			yy += 34
		yy += 14
	if not over.is_empty():
		_text(Vector2(x, y + hh - 46), "المكافأة: +%d رصيد للصناديق" % over["credits"], 20, UI.AMBER, HORIZONTAL_ALIGNMENT_CENTER, w)
		if not G.touch:
			_text(Vector2(x, y + hh - 18), "مسافة: العودة إلى القائمة الرئيسية", 16, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER, w, false)
