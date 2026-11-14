extends Node3D
## Матч: раунды, экономика, бомба, пули и урон, гранаты, звук, табло. Игрок + 4 бота против 5 ботов.

enum S { FREEZE, LIVE, PLANTED, END, HALF, OVER }

const T_NAMES := ["الذئب", "السموم", "العقرب", "الفنك", "الكثيب"]
const CT_NAMES := ["الغرانيت", "العقاب", "الصقر", "الفارس", "الأرز"]

var world: World
var fx: Fx
var hud
var actors: Array = []
var player: Player
var state := S.FREEZE
var t_left := 0.0
var round_no := 0
var score := {"t": 0, "ct": 0}
var win_target := 7
var half_at := 6
var swapped := false
var loss_streak := {"t": 0, "ct": 0}
var bomb := {"state": "none", "pos": Vector3.ZERO, "carrier": null, "site": "", "t": 0.0, "node": null, "planter": null, "beep": 0.0}
var t_plan := "a"
var rng := RandomNumberGenerator.new()
var round_time := 0.0
var last_winner := ""
var last_reason := ""
var reports := {"t": [], "ct": []}
var smokes: Array = []
var fires: Array = []
var nades: Array = []
var dropped_c4: Node3D
var auto := false
var over_t := 0.0
var stats_first_blood := false
var _test_t := 0.0
var _online_started := false
var bullet_range := 190.0          # m; the battle royale map is far bigger

func hostile(a: Actor, b: Actor) -> bool:
	## who may hurt whom: the other team here, everybody else in the battle royale
	return a.team != b.team

func _ready() -> void:
	rng.randomize()
	if G.args.has("seed"):
		rng.seed = int(G.args["seed"])
	auto = G.args.has("auto")
	if G.args.has("loop") and G.shots_dir != "":
		_loop_shot()
	win_target = int(G.settings["match_len"])
	half_at = win_target - 1
	world = World.new()
	world.name = "World"
	add_child(world)
	world.load_map("kasbah")
	fx = Fx.new()
	fx.name = "Fx"
	add_child(fx)
	_spawn_teams()
	hud = preload("res://game/hud.gd").new()
	hud.name = "HUD"
	hud.game = self
	add_child(hud)
	Touch.game = self
	Sfx.music("")
	Sfx.ambient("amb_desert", -16.0)
	G.set_mouse(Input.MOUSE_MODE_CAPTURED)
	if G.args.has("timescale"):
		Engine.time_scale = float(G.args["timescale"])
	if Network.online and actors.size() < 2:
		_online_started = false
		state = S.FREEZE
		t_left = 9999.0
		hud.announce("بانتظار لاعب آخر للانضمام", 9999.0)
	else:
		_online_started = true
		_start_round()
	if G.args.has("vmtest"):
		_vm_test()
	elif G.args.has("hudtest"):
		_hud_test()
	elif G.args.has("sndtest"):
		_snd_test()
	elif G.args.has("tptest"):
		_tp_test()
	elif G.args.has("walltest"):
		_wall_test()
	elif G.shots_dir != "":
		_auto_shots()

var test_wish := Vector2.ZERO

func _loop_shot() -> void:
	await get_tree().create_timer(12.0, true, false, true).timeout
	await G.shot("loop_3_match")

func _tp_test() -> void:
	## проверка оружия в руках бойцов от третьего лица: крупные планы спереди, сбоку и сзади
	t_left = 9999.0
	await get_tree().create_timer(1.0).timeout
	hud.visible = false
	player.layer.visible = false
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 38.0
	cam.current = true
	var list: Array = String(G.args.get("tptest", "1")).split(",") if String(G.args.get("tptest", "1")) != "1" else ["ak", "m4", "awp", "usp", "knife", "shotgun", "mp9", "deagle"]
	var i := 0
	for a in actors:
		if a == player or i >= list.size() or (G.args.has("tpteam") and a.team != String(G.args["tpteam"])):
			continue
		var wid: String = list[i]
		i += 1
		var d: Dictionary = DB.W[wid]
		if wid != "knife":
			a.inv[d["slot"]] = wid
			a._fill(wid)
		a.cur = ""
		a.switch_to(wid, true)
		await get_tree().create_timer(0.6).timeout
		var fwd: Vector3 = -Basis(Vector3.UP, a.view_yaw).z
		var right: Vector3 = Basis(Vector3.UP, a.view_yaw).x
		for v in [["f", fwd * 1.5 + right * 0.9], ["s", right * 1.7 + fwd * 0.25], ["l", -right * 1.7 + fwd * 0.25]]:
			cam.global_position = a.global_position + Vector3(0, 1.4, 0) + (v[1] as Vector3)
			cam.look_at(a.global_position + Vector3(0, 1.22, 0))
			await get_tree().process_frame
			await get_tree().process_frame
			await G.shot("tp_%s_%s_%s" % [a.team, wid, v[0]])
	get_tree().quit()

func _ev(n: String) -> void:
	print("EV %d %s" % [Time.get_ticks_msec(), n])

func _snd_test() -> void:
	## Проверка синхронизации звука в сборке: общая шина пишется в файл, события игры печатаются с метками времени.
	## Сверка начала звука в записи с моментом события — снаружи (tools/snd_check.py).
	t_left = 9999.0
	G.args["sndlog"] = "1"
	for a in actors:
		if a != player:
			a.set_physics_process(false)
	Sfx.ambient("")
	Sfx.music("", 0.1)
	var p := player
	p.money = 16000
	p.view_yaw = deg_to_rad(float(G.args.get("yaw", "-70")))
	await get_tree().create_timer(1.5).timeout
	var rec := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, rec)
	rec.set_recording_active(true)
	_ev("rec_start")
	state = S.LIVE
	var guns := ["m4" if p.team == "ct" else "ak", "usp" if p.team == "ct" else "glock"]
	for wid in guns:
		var d: Dictionary = DB.W[wid]
		p.inv[d["slot"]] = wid
		p._fill(wid)
		p.cur = ""
		p.switch_to(wid, true)
		await get_tree().create_timer(1.2).timeout
		for i in 3:
			_ev("shot_" + wid)
			p.try_fire()
			await get_tree().create_timer(0.6).timeout
		p.ammo[wid][0] = 3
		_ev("reload_" + wid)
		p.start_reload()
		await get_tree().create_timer(float(d["reload"]) + 0.6).timeout
	# бег: шаги игрока (качание камеры идёт по той же фазе)
	p.switch_to("knife", true)
	await get_tree().create_timer(0.8).timeout
	test_wish = Vector2(0, 1)
	await get_tree().create_timer(2.6).timeout
	test_wish = Vector2.ZERO
	await get_tree().create_timer(0.6).timeout
	rec.set_recording_active(false)
	_ev("rec_stop")
	var wav := rec.get_recording()
	if wav and G.shots_dir != "":
		wav.save_to_wav(G.shots_dir + "/sndtest.wav")
		print("WAV saved ", wav.get_length())
	get_tree().quit()

func _vm_test() -> void:
	## проверка рук и оружия от первого лица: кадр на каждый ствол, выстрел, перезарядка
	t_left = 9999.0
	player.money = 16000
	var p := player
	p.view_yaw = deg_to_rad(float(G.args.get("yaw", "-70")))
	var list: Array = String(G.args.get("vmtest", "1")).split(",") if String(G.args.get("vmtest", "1")) != "1" else ["ak", "m4", "awp", "shotgun", "mac10", "mp9", "glock", "usp", "deagle", "knife", "he", "c4"]
	await get_tree().create_timer(1.0).timeout
	for wid in list:
		var d: Dictionary = DB.W[wid]
		if d["cls"] == "nade":
			p.nades.append(wid)
		elif d["cls"] == "c4":
			p.inv[5] = "c4"
		elif wid != "knife":
			p.inv[d["slot"]] = wid
			p._fill(wid)
		p.cur = ""
		p.switch_to(wid, true)
		await get_tree().create_timer(0.9).timeout
		await G.shot("vm_%s" % wid)
		if G.args.has("vmads") and d.has("sight"):
			p.scoped = true
			await get_tree().create_timer(0.9).timeout
			await G.shot("vm_%s_ads" % wid)
			if p.vm.sight and p.vm.sight.magnified() and G.shots_dir != "":
				p.vm.scope_vp.get_texture().get_image().save_png("%s/vm_%s_scopeview.png" % [G.shots_dir, wid])
				print("SIGHT view %s fov %.2f live %s off %s" % [wid, p.vm.scope_cam.fov, p.vm.sight.lens_mat.get_shader_parameter("live"), p.vm.sight.lens_mat.get_shader_parameter("shadow_off")])
			p.scoped = false
			await get_tree().create_timer(0.4).timeout
		if G.args.has("vmdbg"):
			# отладочные ракурсы: оружие и руки крутятся перед камерой (слева, справа, сверху, снизу, три четверти)
			hud.visible = false
			var c: Vector3 = p.vm.grip_cam + Vector3(0, 0.05, -0.14)
			var views := [["L", Basis(Vector3.UP, PI / 2)], ["R", Basis(Vector3.UP, -PI / 2)], ["T", Basis(Vector3.RIGHT, PI / 2)],
				["U", Basis(Vector3.RIGHT, -PI / 2)], ["Q", Basis(Vector3.RIGHT, deg_to_rad(25.0)) * Basis(Vector3.UP, deg_to_rad(40.0))]]
			for v in views:
				var vb: Basis = v[1]
				p.vm.transform = Transform3D(vb, Vector3(0, 0, float(G.args.get("vmdist", "-0.62"))) - vb * c)
				await get_tree().process_frame
				await get_tree().process_frame
				await G.shot("vm_%s_%s" % [wid, v[0]])
			p.vm.transform = Transform3D.IDENTITY
			hud.visible = true
		if G.args.has("vmact"):
			# раскадровки действий: затвор/цевьё после выстрела, удары ножом, бросок, осмотр
			state = S.LIVE
			var cl: String = d["cls"]
			if cl in ["sniper", "shotgun"]:
				p._fill(wid)
				p.try_fire()
				for k in 4:
					await get_tree().create_timer(0.16).timeout
					await G.shot("vm_%s_c%d" % [wid, k])
				await get_tree().create_timer(0.8).timeout
			if cl == "knife":
				p.try_fire(false)
				for k in 3:
					await get_tree().create_timer(0.09).timeout
					await G.shot("vm_%s_a%d" % [wid, k])
				await get_tree().create_timer(0.6).timeout
				p.try_fire(true)
				for k in 4:
					await get_tree().create_timer(0.14).timeout
					await G.shot("vm_%s_b%d" % [wid, k])
				await get_tree().create_timer(0.8).timeout
			if cl == "nade":
				p.try_fire(false)
				for k in 4:
					await get_tree().create_timer(0.13).timeout
					await G.shot("vm_%s_t%d" % [wid, k])
				await get_tree().create_timer(0.6).timeout
			elif p.vm.hold in ["rifle", "smg", "pistol", "knife"]:
				p.vm.inspect()
				for k in 4:
					await get_tree().create_timer(0.72).timeout
					await G.shot("vm_%s_i%d" % [wid, k])
				await get_tree().create_timer(0.8).timeout
			state = S.FREEZE
		if d.has("mag") and d["mag"] > 0 and G.args.has("vmfull"):
			state = S.LIVE
			p.try_fire()
			await get_tree().process_frame
			await get_tree().process_frame
			await G.shot("vm_%s_fire" % wid)
			p.ammo[wid][0] = 3
			p.start_reload()
			if G.args.has("vmstrip"):
				# раскадровка перезарядки: 8 кадров через равные доли
				for k in 8:
					await get_tree().create_timer(d["reload"] * 0.118).timeout
					await G.shot("vm_%s_r%d" % [wid, k])
			else:
				for k in [0.3, 0.55, 0.85]:
					await get_tree().create_timer(d["reload"] * 0.27).timeout
					await G.shot("vm_%s_rel%d" % [wid, int(k * 100)])
			await get_tree().create_timer(1.2).timeout
			state = S.FREEZE
	get_tree().quit()

func _wall_test() -> void:
	## проверка карты: все открытые клетки свободны для бойца, все стены на границе зон непроходимы, выйти за карту нельзя
	t_left = 9999.0
	await get_tree().create_timer(0.5).timeout
	var space := get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = 1
	var open_n := 0
	var open_bad := 0
	var wall_n := 0
	var wall_bad := 0
	var bad_list := []
	var rows: Array = world.data["open"]
	var nav: Array = world.data["nav"]
	for y in world.size.y:
		for x in world.size.x:
			if rows[y][x] != "1":
				continue
			var c := Vector3(x + 0.5, 0.0, -(y + 0.5))
			if nav[y][x] == "1":
				open_n += 1
				q.transform = Transform3D(Basis.IDENTITY, c + Vector3(0, 0.95, 0))
				if not space.intersect_shape(q, 1).is_empty():
					open_bad += 1
					if bad_list.size() < 200:
						bad_list.append("occupied %d,%d" % [x, y])
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				var solid: bool = nx < 0 or ny < 0 or nx >= world.size.x or ny >= world.size.y or rows[ny][nx] != "1"
				if solid:
					wall_n += 1
					var to := Vector3(nx + 0.5, 0.0, -(ny + 0.5))
					for h in [0.3, 1.0, 1.7]:
						var rq := PhysicsRayQueryParameters3D.create(c + Vector3(0, h, 0), to + Vector3(0, h, 0), 1)
						if space.intersect_ray(rq).is_empty():
							wall_bad += 1
							if bad_list.size() < 200:
								bad_list.append("hole %d,%d -> %d,%d h=%.1f" % [x, y, nx, ny, h])
							break
	# достижимость: обе точки и обе базы связаны по сетке навигации
	var pa := world.path(world.spawn("t", 0).origin, world.rect_center(world.data["site_a"])).size()
	var pb := world.path(world.spawn("t", 0).origin, world.rect_center(world.data["site_b"])).size()
	var ca := world.path(world.spawn("ct", 0).origin, world.rect_center(world.data["site_a"])).size()
	var cb := world.path(world.spawn("ct", 0).origin, world.rect_center(world.data["site_b"])).size()
	G.log_line("WALLTEST open %d bad %d | walls %d holes %d | paths T->A %d T->B %d CT->A %d CT->B %d | %s" % [open_n, open_bad, wall_n, wall_bad, pa, pb, ca, cb, ", ".join(bad_list)])
	get_tree().quit()

func _hud_test() -> void:
	## проверка интерфейса матча: закупка, таблица, пауза, итог
	t_left = 30.0
	player.money = 9000
	await get_tree().create_timer(1.2).timeout
	hud._set_buy(true)
	hud.buy._show("m4" if player.team == "ct" else "ak")
	await get_tree().create_timer(0.4).timeout
	await G.shot("hud_buy")
	player.buy("m4" if player.team == "ct" else "ak")
	player.buy("helmet")
	player.buy("he")
	player.buy("smoke")
	hud.buy.refresh()
	await get_tree().create_timer(0.3).timeout
	await G.shot("hud_buy2")
	hud._set_buy(false)
	hud.show_score = true
	set_meta("force_score", true)
	await get_tree().create_timer(0.3).timeout
	await G.shot("hud_score")
	remove_meta("force_score")
	hud._set_pause(true)
	await get_tree().create_timer(0.3).timeout
	await G.shot("hud_pause")
	hud._set_pause(false)
	t_left = 0.5
	await get_tree().create_timer(2.5).timeout
	await G.shot("hud_live")
	get_tree().quit()

func _auto_shots() -> void:
	## проверка матча: кадры через равные промежутки
	var n := 0
	var every := float(G.args.get("every", "6"))
	while n < int(G.args.get("shots_n", "12")):
		await get_tree().create_timer(every, true, false, true).timeout
		await G.shot("match_%02d" % n)
		G.log_line("fps %d  objects %d  draws %d" % [Engine.get_frames_per_second(), int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)), int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))])
		n += 1

func _spawn_teams() -> void:
	if Network.online:
		Network.match_ref = self
		_spawn_online_players()
		Network.peer_joined.connect(_on_network_peer_joined)
		Network.peer_left.connect(_on_network_peer_left)
		Network.state_received.connect(_on_network_state)
		return
	var pteam: String = G.settings["team"]
	var models := {"t": ["t_1", "t_2"], "ct": ["ct_1", "ct_2"]}
	for team in ["t", "ct"]:
		var names: Array = T_NAMES if team == "t" else CT_NAMES
		for i in 5:
			var a: Actor
			var is_p: bool = team == pteam and i == 0
			if is_p:
				player = Player.new()
				a = player
			else:
				a = Bot.new()
			a.name = "%s_%d" % [team, i]
			add_child(a)
			var outfit: int = int(G.settings.get("outfit", 0)) if team == pteam else 0
			a.setup(self, team, (String(G.settings["name"]) if is_p else names[i]), not is_p, models[team][(i + outfit) % 2])
			a.full_reset()
			if is_p:
				player.init_player()
			if not is_p or auto:
				var br := Brain.new()
				br.name = "Brain"
				a.add_child(br)
				br.setup(a, self)
				a.set_meta("brain", br)
			if not is_p:
				var fb := FighterBody.new()
				fb.name = "Body"
				a.add_child(fb)
				fb.setup(a, a.model_name)
				a.body = fb
				a.shot.connect(fb.on_shot.unbind(1))
				a.reload_started.connect(func(_w, t): fb.on_reload(t))
			actors.append(a)


func _spawn_online_players() -> void:
	var ids: Array[int] = [1]
	for id in multiplayer.get_peers():
		ids.append(int(id))
	ids.sort()
	for id in ids:
		_add_network_actor(id)

func _add_network_actor(peer_id: int) -> void:
	if get_node_or_null(str("Peer_", peer_id)) != null:
		return
	var team := Network.peer_team(peer_id)
	var slot := Network.peer_slot(peer_id)
	var models := {"t": ["t_1", "t_2"], "ct": ["ct_1", "ct_2"]}
	var a: Actor
	if peer_id == multiplayer.get_unique_id():
		player = Player.new()
		a = player
	else:
		a = RemoteActor.new()
	a.name = "Peer_%d" % peer_id
	if peer_id != multiplayer.get_unique_id():
		a.set_meta("network_peer_id", peer_id)
	add_child(a)
	a.setup(self, team, (String(G.settings["name"]) if peer_id == multiplayer.get_unique_id() else "Player %d" % peer_id), false, models[team][slot % 2])
	a.full_reset()
	if a == player:
		player.init_player()
	else:
		var fb := FighterBody.new()
		fb.name = "Body"
		a.add_child(fb)
		fb.setup(a, a.model_name)
		a.body = fb
		a.shot.connect(fb.on_shot.unbind(1))
		a.reload_started.connect(func(_w, t): fb.on_reload(t))
	actors.append(a)
	var xf := world.spawn(team, slot)
	a.spawn_at(xf.origin, world.spawn_yaw(team, slot), false)
	if a == player:
		player.team = team

func _on_network_peer_joined(peer_id: int) -> void:
	_add_network_actor(peer_id)

func _on_network_peer_left(peer_id: int) -> void:
	var node := get_node_or_null("Peer_%d" % peer_id)
	if node:
		actors.erase(node)
		node.queue_free()

func _on_network_state(peer_id: int, pos: Vector3, yaw: float, pitch: float, hp: int, alive: bool, crouch: float, weapon: String) -> void:
	var a := get_node_or_null("Peer_%d" % peer_id) as Actor
	if a is RemoteActor:
		a.apply_network_state(pos, yaw, pitch, hp, alive, crouch, weapon)

func team_of(t: String) -> Array:
	return actors.filter(func(x): return x.team == t)

func alive_of(t: String) -> Array:
	return actors.filter(func(x): return x.team == t and x.alive)

func nearest_alive(t: String, pos: Vector3) -> Actor:
	var best: Actor = null
	var bd := 1e9
	for a in alive_of(t):
		var d: float = a.global_position.distance_to(pos)
		if d < bd:
			bd = d
			best = a
	return best

func frozen() -> bool:
	return state == S.FREEZE or state == S.HALF or state == S.OVER

func round_over_no_damage() -> bool:
	return state == S.HALF or state == S.OVER

func time_left() -> float:
	return bomb["t"] if state == S.PLANTED else t_left

func can_buy(a: Actor) -> bool:
	if state == S.FREEZE:
		return true
	if state in [S.LIVE] and round_time < DB.T_BUY:
		return world.in_rect(a.global_position, world.data["buy_t" if a.team == "t" else "buy_ct"])
	return false

# ------------------------------------------------------------------ раунды
func _start_round() -> void:
	round_no += 1
	state = S.FREEZE
	t_left = DB.T_FREEZE
	round_time = 0.0
	stats_first_blood = false
	reports = {"t": [], "ct": []}
	for n in nades:
		if is_instance_valid(n):
			n.queue_free()
	nades.clear()
	for s in smokes:
		if is_instance_valid(s["node"]):
			s["node"].queue_free()
	smokes.clear()
	for f in fires:
		if is_instance_valid(f["node"]):
			f["node"].queue_free()
	fires.clear()
	fx.clear_round()
	if bomb["node"] and is_instance_valid(bomb["node"]):
		bomb["node"].queue_free()
	if dropped_c4 and is_instance_valid(dropped_c4):
		dropped_c4.queue_free()
	bomb = {"state": "carried", "pos": Vector3.ZERO, "carrier": null, "site": "", "t": 0.0, "node": null, "planter": null, "beep": 0.0}
	t_plan = "a" if rng.randf() < 0.5 else "b"
	var idx := {"t": 0, "ct": 0}
	var order := actors.duplicate()
	for a in order:
		var keep: bool = a.alive and round_no > 1 and not _fresh_half
		var i: int = idx[a.team]
		idx[a.team] += 1
		var xf := world.spawn(a.team, i)
		a.spawn_at(xf.origin, world.spawn_yaw(a.team, i), keep)
		if a.has_meta("brain"):
			(a.get_meta("brain") as Brain).new_round()
	_fresh_half = false
	# бомба — случайному атакующему (чаще боту)
	var ts := team_of("t")
	var carrier: Actor = ts[rng.randi() % ts.size()]
	carrier.inv[5] = "c4"
	bomb["carrier"] = carrier
	# роли защиты: двое на A, двое на B, один в центре
	var roles := ["a", "b", "a", "b", "mid"]
	roles.shuffle()
	var k := 0
	for a in team_of("ct"):
		if a.has_meta("brain"):
			(a.get_meta("brain") as Brain).role = roles[k % roles.size()]
		k += 1
	for a in actors:
		if a.is_bot or auto:
			_bot_buy(a)
	hud.round_start()
	Sfx.play("round_start", -6.0)
	G.log_line("round %d start  T %d : %d CT  plan=%s" % [round_no, score["t"], score["ct"], t_plan])

var _fresh_half := true

func _bot_buy(a: Actor) -> void:
	var m := a.money
	var t := a.team
	if a.inv[1] == "":
		if m >= 4750 + 1000 and rng.randf() < 0.12:
			a.buy("awp")
		elif m >= (2700 if t == "t" else 2900) + 650:
			a.buy("ak" if t == "t" else "m4")
		elif m >= 1050 + 650 + 300 and (loss_streak[t] >= 2 or m < 2400) and rng.randf() < 0.7:
			a.buy(("mac10" if t == "t" else "mp9") if rng.randf() < 0.75 else "shotgun")
		elif m >= 700 and m < 1500 and rng.randf() < 0.35:
			a.buy("deagle")
	if a.armor < 100 and a.money >= 1000 and a.inv[1] != "":
		a.buy("helmet")
	elif a.armor < 100 and a.money >= 650 and (a.inv[1] != "" or a.money >= 1400):
		a.buy("kevlar")
	if t == "ct" and not a.kit and a.money >= 400 + 300 and a.inv[1] != "":
		a.buy("kit")
	if a.money >= 600 and a.inv[1] != "" and rng.randf() < 0.5:
		a.buy(["he", "flash", "smoke"][rng.randi() % 3])

func _physics_process(dt: float) -> void:
	if Network.online and player:
		Network.send_player_state(player, dt)
	if Network.online and not _online_started:
		if actors.size() >= 2:
			_online_started = true
			_start_round()
		return
	match state:
		S.FREEZE:
			t_left -= dt
			if t_left <= 0.0:
				state = S.LIVE
				t_left = DB.T_ROUND
				hud.announce("", 0.1)
				Sfx.play("go", -8.0)
		S.LIVE:
			t_left -= dt
			round_time += dt
			_bomb_tick(dt)
			_check_win()
			if state == S.LIVE and t_left <= 0.0:
				_end_round("ct", "انتهى الوقت")
		S.PLANTED:
			round_time += dt
			_bomb_tick(dt)
			_check_win()
		S.END:
			t_left -= dt
			if t_left <= 0.0:
				_after_round()
		S.HALF:
			t_left -= dt
			if t_left <= 0.0:
				_start_round()
		S.OVER:
			over_t += dt
			if over_t > (4.0 if auto else 14.0) or (over_t > 2.0 and Input.is_action_just_pressed("jump")):
				_finish()
	_areas_tick(dt)
	if auto and G.args.has("maxtime"):
		_test_t += dt
		if _test_t > float(G.args["maxtime"]):
			G.log_line("maxtime reached, score T %d : %d CT" % [score["t"], score["ct"]])
			_finish()

func _check_win() -> void:
	var ta := alive_of("t").size()
	var ca := alive_of("ct").size()
	if state == S.LIVE:
		if ta == 0 and ca == 0:
			_end_round("ct", "قُتل الجميع")
		elif ta == 0:
			_end_round("ct", "تم القضاء على المهاجمين")
		elif ca == 0:
			_end_round("t", "تم القضاء على المدافعين")
	elif state == S.PLANTED:
		if ca == 0:
			_end_round("t", "تم القضاء على المدافعين")

func _end_round(winner: String, reason: String) -> void:
	if state == S.END or state == S.OVER or state == S.HALF:
		return
	state = S.END
	t_left = DB.T_END
	last_winner = winner
	last_reason = reason
	score[winner] += 1
	var loser := "ct" if winner == "t" else "t"
	var win_money := DB.WIN_BOMB if reason in ["انفجرت القنبلة", "تم تفكيك القنبلة"] else DB.WIN_ELIM
	for a in team_of(winner):
		a.money = mini(DB.MAX_MONEY, a.money + win_money)
	var lb: int = DB.LOSS[mini(loss_streak[loser], DB.LOSS.size() - 1)]
	if loser == "t" and bomb["state"] in ["planted", "defused"]:
		lb += DB.PLANT_LOSS_BONUS
	for a in team_of(loser):
		if loser == "t" and a.alive and reason == "انتهى الوقت":
			continue          # выжившие атакующие при проигрыше по времени денег не получают
		a.money = mini(DB.MAX_MONEY, a.money + lb)
	loss_streak[loser] = mini(loss_streak[loser] + 1, 4)
	loss_streak[winner] = maxi(loss_streak[winner] - 1, 0)
	# лучший игрок раунда
	var best: Actor = null
	for a in team_of(winner):
		if best == null or a.round_kills > best.round_kills:
			best = a
	if bomb["planter"] and winner == "t" and reason == "انفجرت القنبلة":
		best = bomb["planter"]
	if best:
		best.mvps += 1
	hud.round_end(winner, reason, best)
	Sfx.music("", 1.2)
	Sfx.play("win" if winner == player.team else "lose", -5.0)
	G.log_line("round %d end: %s (%s)  T %d : %d CT" % [round_no, winner, reason, score["t"], score["ct"]])

func _after_round() -> void:
	var total: int = score["t"] + score["ct"]
	if score["t"] >= win_target or score["ct"] >= win_target or total >= 2 * half_at:
		_match_over()
		return
	if total == half_at and not swapped:
		_halftime()
		return
	_start_round()

func _halftime() -> void:
	swapped = true
	state = S.HALF
	t_left = 6.0
	for a in actors:
		a.team = "ct" if a.team == "t" else "t"
		a.alive = false
		a.money = DB.START_MONEY
	var s: int = score["t"]
	score["t"] = score["ct"]
	score["ct"] = s
	loss_streak = {"t": 0, "ct": 0}
	_fresh_half = true
	# модели бойцов остаются своими, меняется только сторона
	hud.announce("تبديل الجهتين", 5.0)
	Sfx.play("round_start", -6.0)

func _match_over() -> void:
	state = S.OVER
	over_t = 0.0
	var pt := player.team
	var ot := "ct" if pt == "t" else "t"
	var res := "draw"
	if score[pt] > score[ot]:
		res = "win"
	elif score[pt] < score[ot]:
		res = "lose"
	var credits := 150 + player.kills * 25 + player.mvps * 40 + (300 if res == "win" else (120 if res == "draw" else 0))
	G.profile["matches"] = int(G.profile["matches"]) + 1
	G.profile["kills"] = int(G.profile["kills"]) + player.kills
	if res == "win":
		G.profile["wins"] = int(G.profile["wins"]) + 1
	G.add_credits(credits)
	G.last_result = {"res": res, "score": [score[pt], score[ot]], "credits": credits, "kills": player.kills, "deaths": player.deaths}
	hud.match_over(res, credits)
	Sfx.music("win_theme" if res == "win" else "menu_theme", 2.0, -8.0)
	G.set_mouse(Input.MOUSE_MODE_VISIBLE)
	G.log_line("MATCH OVER %s  %d : %d  credits +%d" % [res, score[pt], score[ot], credits])
	for a in actors:
		G.log_line("  %s %s  K %d  D %d  A %d  dmg %d" % [a.team, a.nick, a.kills, a.deaths, a.assists, a.dmg_given])

func leave() -> void:
	## "main menu" button on the final scoreboard
	if state == S.OVER and over_t > 1.0 and is_physics_processing():
		_finish()

func _finish() -> void:
	set_physics_process(false)
	if G.args.has("quit_after"):
		G.log_line("quit after match")
		get_tree().quit()
		return
	G.to_menu()

# ------------------------------------------------------------------ сообщения ботам
func report(team: String, pos: Vector3) -> void:
	var arr: Array = reports[team]
	arr.append([Time.get_ticks_msec(), pos])
	if arr.size() > 24:
		arr.pop_front()

func hot_site(team: String) -> String:
	var now := Time.get_ticks_msec()
	var na := 0
	var nb := 0
	for r in reports[team]:
		if now - int(r[0]) > 9000:
			continue
		var p: Vector3 = r[1]
		if p.distance_to(world.rect_center(world.data["site_a"])) < 24.0:
			na += 1
		if p.distance_to(world.rect_center(world.data["site_b"])) < 24.0:
			nb += 1
	if na == 0 and nb == 0:
		return ""
	return "a" if na >= nb else "b"

func smoke_blocks(a: Vector3, b: Vector3) -> bool:
	for s in smokes:
		var c: Vector3 = s["pos"] + Vector3(0, 1.4, 0)
		var r: float = s["r"]
		var ab := b - a
		var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if (a + ab * t).distance_to(c) < r:
			return true
	return false

func noise(pos: Vector3, from: Actor) -> void:
	for a in actors:
		if a != from and a.alive and hostile(a, from) and a.has_meta("brain"):
			a.get_meta("brain").hear(pos)

# ------------------------------------------------------------------ звук
func sound_at(n: String, pos: Vector3, vol := 0.0, who: Actor = null) -> void:
	if who and who == player and player.alive:
		Sfx.play(n, vol - 3.0)
	else:
		Sfx.at(n, pos, vol)

func gun_sound(a: Actor, wid: String) -> void:
	var snd: String = DB.W[wid].get("snd", "pistol")
	var n := {"ak": "ak_shot", "m4": "m4_shot", "pistol": "pistol_shot", "usp": "usp_shot", "deagle": "deagle_shot", "smg": "smg_shot", "shotgun": "shotgun_shot", "sniper": "sniper_shot"}.get(snd, "pistol_shot") as String
	if not Sfx.has(n):
		n = "pistol_shot"
	var pitch := randf_range(0.97, 1.03)
	if a == player and player.alive:
		Sfx.play(n, -2.0, pitch)
	else:
		# real recordings: the close take nearby, the mid-distance take (more room, less crack) further away
		var d := a.global_position.distance_to(player.global_position if player else Vector3.ZERO)
		var far := n + "_far"
		if d > 22.0 and Sfx.has(far):
			Sfx.at(far, a.eye(), 4.0, pitch, 14.0, 220.0)
		else:
			Sfx.at(n, a.eye(), 3.0, pitch, 9.0, 140.0)
			if d > 35.0 and Sfx.has("shot_far"):
				Sfx.at("shot_far", a.eye(), -4.0, pitch, 16.0, 200.0)
	if snd != "usp":
		noise(a.global_position, a)
	fx.flash(a.eye() - Basis(Vector3.UP, a.view_yaw).z * 0.9, 2.2, 6.0, 0.05)

func reload_sound(a: Actor, wid: String) -> void:
	var cls: String = DB.W[wid]["cls"]
	if a == player and player.alive:
		return            # у игрока перезарядка озвучена по событиям анимации рук
	var n := "reload_pistol" if cls == "pistol" and Sfx.has("reload_pistol") else "reload"
	sound_at(n, a.eye(), -6.0, a)

func footstep(a: Actor) -> void:
	var surf := world.surface_at(a.global_position)
	var n := "step_sand" if surf == "sand" else ("step_tile" if surf == "tile" and Sfx.has("step_tile") else "step")
	if a == player and player.alive:
		if G.args.has("sndlog"):
			_ev("step bob=%.2f" % absf(sin(player.step_ph)))
		Sfx.play(n, -13.0, randf_range(0.93, 1.07))
	else:
		Sfx.at(n, a.global_position, -3.0, randf_range(0.93, 1.07), 5.0, 38.0)
		for o in actors:
			if o != a and o.alive and hostile(o, a) and o.has_meta("brain") and o.global_position.distance_to(a.global_position) < 16.0:
				o.get_meta("brain").hear(a.global_position)

# ------------------------------------------------------------------ пули
func bullet(shooter: Actor, from: Vector3, dir: Vector3, wid: String, first: bool) -> void:
	var d: Dictionary = DB.W[wid]
	var dmg: float = d["dmg"]
	var pen_left: float = d.get("wall", 0.5)
	var pos := from
	var space := get_world_3d().direct_space_state
	var remaining := bullet_range
	var start_vis := from
	if shooter == player and player.vm:
		start_vis = player.vm.muzzle_world()
	elif shooter.body:
		start_vis = shooter.body.muzzle_pos()
	var end := from + dir * remaining
	for iter in 4:
		var q := PhysicsRayQueryParameters3D.create(pos, pos + dir * remaining, 5)
		q.exclude = shooter.hit_rids
		q.hit_from_inside = false
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var hp: Vector3 = hit["position"]
		end = hp
		var col: Object = hit["collider"]
		var travelled := from.distance_to(hp)
		if col.has_meta("actor"):
			var v: Actor = col.get_meta("actor")
			var zone: String = col.get_meta("zone")
			if hostile(v, shooter) and v.alive:
				var dm := dmg * pow(float(d["rmod"]), travelled / 12.7) * float(DB.ZONE[zone])
				fx.blood(hp, -dir)
				v.take_damage(dm, shooter, wid, zone, from)
				if shooter == player:
					hud.hit_marker(zone == "head", not v.alive)
			break
		# стена или предмет
		var n: Vector3 = hit["normal"]
		fx.impact(hp, n, "stone")
		if first or iter == 0:
			Sfx.at("impact", hp, -10.0, randf_range(0.9, 1.15), 3.0, 30.0)
			if randf() < 0.1:
				Sfx.at("ricochet", hp, -12.0, randf_range(0.9, 1.1), 4.0, 40.0)
		var lim := pen_left * (1.0 if col.has_meta("wood") else 0.2)
		if lim < 0.12:
			break
		# поиск выхода: шагаем сквозь преграду
		var exit_at := -1.0
		var pq := PhysicsPointQueryParameters3D.new()
		pq.collision_mask = 1
		var s := 0.12
		while s <= lim:
			pq.position = hp + dir * s
			if space.intersect_point(pq, 1).is_empty():
				exit_at = s
				break
			s += 0.12
		if exit_at < 0.0:
			break
		dmg *= 0.75 * (1.0 - 0.4 * exit_at / lim)
		pen_left -= exit_at * (1.0 if col.has_meta("wood") else 5.0)
		pos = hp + dir * (exit_at + 0.01)
		remaining -= travelled
		fx.impact(pos, dir, "stone")
		if remaining < 1.0 or dmg < 3.0:
			break
	if first:
		fx.tracer(start_vis, end)
		# свист пули рядом с головой игрока
		if shooter != player and player and player.alive and hostile(shooter, player):
			var pe := player.eye()
			var ab := end - from
			var tt := clampf((pe - from).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
			if tt > 0.05 and (from + ab * tt).distance_to(pe) < 1.7:
				Sfx.play("whiz", -7.0, randf_range(0.9, 1.1))

func knife_hit(a: Actor, alt: bool) -> void:
	var space := get_world_3d().direct_space_state
	var from := a.eye()
	var dir := -a.aim_basis(false).z
	var reach := 1.55 if not alt else 1.3
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach, 5)
	q.exclude = a.hit_rids
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var col: Object = hit["collider"]
	if col.has_meta("actor"):
		var v: Actor = col.get_meta("actor")
		if hostile(v, a) and v.alive:
			var back := (-Basis(Vector3.UP, v.view_yaw).z).dot(dir) > 0.45
			var dm := 65.0 if alt else 40.0
			if back:
				dm = 180.0 if alt else 90.0
			fx.blood(hit["position"], -dir)
			sound_at("knife_hit", hit["position"], -2.0, a)
			v.take_damage(dm, a, "knife", "chest", from)
			if a == player:
				hud.hit_marker(false, not v.alive)
	else:
		fx.impact(hit["position"], hit["normal"])
		sound_at("knife_wall", hit["position"], -6.0, a)

# ------------------------------------------------------------------ урон, смерти
func on_hurt(v: Actor, attacker: Actor, n: int, zone: String, armored: bool, from_pos: Vector3) -> void:
	if v == player:
		hud.damage_from(from_pos, n)
		Sfx.play("hurt", -6.0, randf_range(0.95, 1.05))
	if zone == "head":
		Sfx.at("headshot", v.eye(), 0.0 if attacker == player else -6.0, 1.0, 6.0, 60.0)
	elif armored:
		Sfx.at("hit_armor", v.eye(), -8.0, 1.0, 4.0, 40.0)
	else:
		Sfx.at("hit_body", v.eye(), -8.0, 1.0, 4.0, 40.0)
	if v.has_meta("brain") and attacker and attacker.alive:
		v.get_meta("brain").hear(attacker.global_position)

func on_death(v: Actor, killer: Actor, wid: String, headshot: bool) -> void:
	if killer and killer != v:
		killer.kills += 1
		killer.round_kills += 1
		killer.score += 2
		killer.money = mini(DB.MAX_MONEY, killer.money + int(DB.W.get(wid, {}).get("reward", 300)))
	for o in v.dmg_from:
		if o != killer and is_instance_valid(o) and int(v.dmg_from[o]) >= 40:
			o.assists += 1
			o.score += 1
	hud.kill(killer, v, wid, headshot)
	Sfx.at("death", v.global_position + Vector3(0, 1, 0), -4.0, randf_range(0.9, 1.1), 5.0, 45.0)
	if v.inv[5] == "c4":
		v.inv[5] = ""
		_drop_bomb(v.global_position)
	if v == player:
		player.on_player_death(killer)
	if killer == player and player.alive:
		Sfx.play("kill", -8.0)

func _c4_node() -> Node3D:
	var n: Node3D
	if ResourceLoader.exists("res://assets/models/weapons/c4.scn"):
		n = (load("res://assets/models/weapons/c4.scn") as PackedScene).instantiate()
	else:
		n = Node3D.new()
	var l := OmniLight3D.new()
	l.name = "Blink"
	l.light_color = Color(1.0, 0.1, 0.05)
	l.omni_range = 2.5
	l.light_energy = 0.0
	l.position = Vector3(0, 0.15, 0)
	n.add_child(l)
	add_child(n)
	return n

func _drop_bomb(pos: Vector3) -> void:
	bomb["state"] = "dropped"
	bomb["carrier"] = null
	bomb["pos"] = Vector3(pos.x, 0.02, pos.z)
	dropped_c4 = _c4_node()
	dropped_c4.global_position = bomb["pos"]
	dropped_c4.rotation = Vector3(-PI / 2.0, randf() * TAU, 0)
	hud.announce("سقطت القنبلة", 2.0)

func plant_spot(site: String, a: Actor) -> Vector3:
	var r: Array = world.data["site_" + site]
	var c := world.rect_center(r)
	var h := hash(a.nick + str(round_no))
	var p := c + Vector3(float(h % 7) - 3.0, 0, float((h / 7) % 7) - 3.0)
	var cell := world.free_cell(world.cell(p))
	return world.cell_center(cell)

func try_plant(a: Actor, holding: bool) -> void:
	if not holding or state != S.LIVE or a.inv[5] != "c4" or a.cur != "c4" or not a.is_on_floor() or world.site_at(a.global_position) == "":
		if a.plant_t >= 0.0:
			a.plant_t = -1.0
		return
	if a.plant_t < 0.0:
		a.plant_t = 0.0
		sound_at("bomb_plant", a.global_position, -4.0, a)
		noise(a.global_position, a)
	a.plant_t += get_physics_process_delta_time()
	if a.plant_t >= DB.T_PLANT:
		a.plant_t = -1.0
		a.inv[5] = ""
		a.cur = ""
		a.switch_to(a.inv[1] if a.inv[1] != "" else a.inv[2])
		a.money = mini(DB.MAX_MONEY, a.money + DB.PLANT_BONUS)
		a.score += 2
		bomb["state"] = "planted"
		bomb["site"] = world.site_at(a.global_position)
		bomb["pos"] = Vector3(a.global_position.x, a.global_position.y + 0.02, a.global_position.z) - Basis(Vector3.UP, a.view_yaw).z * 0.5
		bomb["t"] = DB.T_BOMB
		bomb["planter"] = a
		bomb["carrier"] = null
		var n := _c4_node()
		n.global_position = bomb["pos"]
		n.rotation = Vector3(-PI / 2.0, a.view_yaw, 0)
		bomb["node"] = n
		state = S.PLANTED
		hud.announce("زُرعت القنبلة", 3.0)
		Sfx.play("bomb_planted", -3.0)
		Sfx.music("action_theme", 0.6, -13.0)
		G.log_line("bomb planted at %s by %s" % [bomb["site"], a.nick])

func try_defuse(a: Actor, holding: bool) -> void:
	if not holding or state != S.PLANTED or a.team != "ct" or not a.alive or a.global_position.distance_to(bomb["pos"]) > 1.7:
		if a.defuse_t >= 0.0:
			a.defuse_t = -1.0
		return
	if a.defuse_t < 0.0:
		a.defuse_t = 0.0
		sound_at("defuse_start", a.global_position, -4.0, a)
	a.defuse_t += get_physics_process_delta_time()
	var need := DB.T_DEFUSE_KIT if a.kit else DB.T_DEFUSE
	if a.defuse_t >= need:
		a.defuse_t = -1.0
		a.score += 2
		bomb["state"] = "defused"
		if bomb["node"]:
			(bomb["node"].get_node("Blink") as OmniLight3D).light_energy = 0.0
		Sfx.play("bomb_defused", -3.0)
		_end_round("ct", "تم تفكيك القنبلة")

func _bomb_tick(dt: float) -> void:
	var st: String = bomb["state"]
	if st == "dropped":
		for a in alive_of("t"):
			if a.global_position.distance_to(bomb["pos"]) < 1.1:
				a.inv[5] = "c4"
				bomb["state"] = "carried"
				bomb["carrier"] = a
				if dropped_c4 and is_instance_valid(dropped_c4):
					dropped_c4.queue_free()
				if a == player:
					hud.announce("التقطتَ القنبلة", 2.0)
				break
	elif st == "planted" and state == S.PLANTED:
		bomb["t"] -= dt
		bomb["beep"] -= dt
		if bomb["beep"] <= 0.0:
			var tl: float = bomb["t"]
			bomb["beep"] = clampf(0.1 + 0.9 * tl / DB.T_BOMB, 0.12, 1.0)
			Sfx.at("bomb_beep", bomb["pos"], 2.0, 1.0, 7.0, 80.0)
			var l := bomb["node"].get_node("Blink") as OmniLight3D
			l.light_energy = 3.0
			create_tween().tween_property(l, "light_energy", 0.0, 0.12)
		if bomb["t"] <= 0.0:
			_explode_bomb()

func _explode_bomb() -> void:
	bomb["state"] = "exploded"
	var p: Vector3 = bomb["pos"]
	fx.explosion(p, 11.0)
	Sfx.at("explosion_big", p, 8.0, 1.0, 30.0, 300.0)
	Sfx.play("explosion_big", -6.0, 1.0)
	if bomb["node"]:
		bomb["node"].visible = false
	for a in actors:
		if a.alive:
			var d: float = a.global_position.distance_to(p)
			if d < 17.0:
				a.take_damage(500.0 * pow(1.0 - d / 17.0, 1.4), bomb["planter"], "c4", "chest", p)
	if player:
		player.shake(1.0)
	_end_round("t", "انفجرت القنبلة")

# ------------------------------------------------------------------ гранаты
func throw_nade(owner: Actor, id: String, pos: Vector3, vel: Vector3) -> void:
	var n := Nade.new()
	add_child(n)
	n.launch(self, owner, id, pos, vel)
	nades.append(n)
	sound_at("nade_throw", pos, -6.0, owner)

func nade_burst(n: Nade) -> void:
	var p := n.global_position
	var id := n.id
	if id == "he":
		fx.explosion(p, 4.5)
		Sfx.at("explosion", p, 6.0, 1.15, 16.0, 160.0)
		for a in actors:
			if a.alive:
				var d: float = (a.global_position + Vector3(0, 0.9, 0)).distance_to(p)
				if d < 8.5 and world.los(p + Vector3(0, 0.2, 0), a.eye(), []):
					a.take_damage(98.0 * pow(1.0 - d / 8.5, 1.2), n.thrower, "he", "chest", p)
		if player and player.global_position.distance_to(p) < 14.0:
			player.shake(0.5)
	elif id == "flash":
		fx.flash(p, 60.0, 40.0, 0.25, Color(1, 1, 1))
		Sfx.at("flash_bang", p, 6.0, 1.0, 14.0, 140.0)
		for a in actors:
			if not a.alive:
				continue
			var d2: float = a.eye().distance_to(p)
			if d2 > 38.0 or not world.los(p, a.eye(), []):
				continue
			var facing: float = (-a.aim_basis(false).z).dot((p - a.eye()).normalized())
			var t: float = clampf(4.2 * (0.35 + 0.65 * clampf(facing * 0.5 + 0.5, 0.0, 1.0)) * (1.0 - d2 / 45.0), 0.0, 4.5)
			if facing < -0.2:
				t *= 0.3
			a.flash_t = maxf(a.flash_t, t)
			if a == player:
				hud.flash(t)
	elif id == "smoke":
		var node := fx.smoke_cloud(p, 4.6, 18.0)
		smokes.append({"pos": p, "r": 4.3, "t": 18.0, "node": node})
		Sfx.at("smoke_hiss", p, 0.0, 1.0, 7.0, 60.0)
	elif id == "molotov":
		var gp := Vector3(p.x, maxf(0.05, p.y - 0.1), p.z)
		var node2 := fx.fire_area(gp, 3.2, 7.0)
		fires.append({"pos": gp, "r": 3.2, "t": 7.0, "node": node2, "owner": n.thrower, "tick": 0.0})
		Sfx.at("molotov", p, 2.0, 1.0, 8.0, 70.0)
	elif id == "decoy":
		fx.flash(p, 3.0, 5.0, 0.2)
		Sfx.at("pistol_shot", p, 0.0, 1.0, 9.0, 120.0)

func _areas_tick(dt: float) -> void:
	for s in smokes.duplicate():
		s["t"] -= dt
		if s["t"] <= 0.0:
			smokes.erase(s)
	for f in fires.duplicate():
		f["t"] -= dt
		f["tick"] -= dt
		if f["tick"] <= 0.0:
			f["tick"] = 0.25
			for a in actors:
				if a.alive and Vector2(a.global_position.x - f["pos"].x, a.global_position.z - f["pos"].z).length() < f["r"] and absf(a.global_position.y - f["pos"].y) < 1.5:
					a.take_damage(9.0, f["owner"], "fire", "legs", f["pos"])
		if f["t"] <= 0.0:
			fires.erase(f)
