class_name BRNet
extends Node
## Online battle royale over the ENet session of Network (LAN / direct IP), host-authoritative:
##   - the host runs everything: bots, loot, storm, supply drops, vehicles, bullets and damage;
##   - every peer builds the same desert from the host's seed (the loot scattered at the start and the parked vehicles
##     come out identical, so they share their ids);
##   - each player moves their own fighter and reports its pose; the host sends snapshots of all fighters and vehicles
##     15 times a second, plus events: items appearing / taken, shots, kills, supply drops, the end;
##   - picking up, swapping, healing and getting in or out of a vehicle are requests the host carries out.
## Node path /root/BRMatch/Net on every peer (the RPCs travel along it).

const SNAP_HZ := 15.0
const STATE_HZ := 20.0

var game: Node                        # br_match
var host := false
var peers := {}                       # host: peer_id -> {name, ready, actor}
var my_idx := -1                      # client: index of my fighter in game.actors
var _snap_acc := 0.0
var _state_acc := 0.0
var _storm_acc := 0.0
var lobby_label: Label
var start_btn: Button
var started := false

func _ready() -> void:
	host = Network.is_host
	if host:
		multiplayer.peer_disconnected.connect(_on_peer_left)

# ================================================================== lobby
func hello() -> void:
	## client: the scene is up — ask the host for the world
	rpc_id(1, "c_hello", String(G.settings.get("name", "لاعب")))

@rpc("any_peer", "call_remote", "reliable")
func c_hello(nick: String) -> void:
	if not host:
		return
	var id := multiplayer.get_remote_sender_id()
	if started:
		rpc_id(id, "h_refused", "المعركة بدأت بالفعل — انتظر الجولة القادمة")
		return
	peers[id] = {"name": nick.substr(0, 18), "ready": false}
	rpc_id(id, "h_world", int(game.world_seed))
	_lobby_text()

@rpc("authority", "call_remote", "reliable")
func h_refused(why: String) -> void:
	if lobby_label:
		lobby_label.text = why

@rpc("authority", "call_remote", "reliable")
func h_world(seed_v: int) -> void:
	await game.build_world(seed_v)
	if lobby_label:
		lobby_label.text = "جاهز — بانتظار أن يبدأ المضيف المعركة"
	rpc_id(1, "c_ready")

@rpc("any_peer", "call_remote", "reliable")
func c_ready() -> void:
	var id := multiplayer.get_remote_sender_id()
	if host and peers.has(id):
		peers[id]["ready"] = true
		_lobby_text()

func _on_peer_left(id: int) -> void:
	if not peers.has(id):
		return
	var a = peers[id].get("actor", null)
	peers.erase(id)
	if a and is_instance_valid(a) and a.alive:
		# a player who leaves falls where they stand
		a.take_damage(999.0, null, "fall", "chest", a.global_position)
	_lobby_text()

func lobby_ui(overlay: CanvasLayer) -> void:
	## text (and the host's start button) over the loading picture while the room fills up
	lobby_label = UI.label("", 26, UI.TEXT, true)
	lobby_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	lobby_label.offset_left = -500
	lobby_label.offset_right = 500
	lobby_label.offset_top = 40
	lobby_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay.add_child(lobby_label)
	if host:
		start_btn = UI.button("ابدأ المعركة", 26, UI.GOLD, Vector2(300, 70))
		start_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		start_btn.offset_left = -150
		start_btn.offset_right = 150
		start_btn.offset_top = 130
		start_btn.offset_bottom = 200
		start_btn.pressed.connect(host_start)
		overlay.add_child(start_btn)
		G.set_mouse(Input.MOUSE_MODE_VISIBLE)
		_lobby_text()
		if G.args.has("netstart"):
			# checks: start on our own after a few seconds
			get_tree().create_timer(float(G.args["netstart"])).timeout.connect(host_start)
	else:
		lobby_label.text = "متصل — جارٍ استلام خريطة المضيف..."

func _lobby_text() -> void:
	if lobby_label == null or not host:
		return
	var n_ready := 0
	for id in peers:
		if peers[id]["ready"]:
			n_ready += 1
	lobby_label.text = "غرفتك جاهزة على المنفذ %d\nاللاعبون المتصلون: %d (جاهز %d) — البقية بوتات حتى 30 مقاتلاً" % [Network.DEFAULT_PORT, peers.size() + 1, n_ready]

func host_start() -> void:
	if started or not host:
		return
	started = true
	if start_btn:
		start_btn.disabled = true
	var humans := [[1, String(G.settings.get("name", "المضيف"))]]
	for id in peers:
		if peers[id]["ready"]:
			humans.append([id, peers[id]["name"]])
	game.start_battle(humans)
	# tell everyone who is who and where the plane flies
	var roster := []
	for i in game.actors.size():
		var a: Actor = game.actors[i]
		var pid: int = 1 if a == game.player else (a.peer if a is NetPuppet else 0)
		roster.append([i, pid, a.nick, a.model_name])
		if a is NetPuppet and a.peer > 0 and peers.has(a.peer):
			peers[a.peer]["actor"] = a
	for id in peers:
		if peers[id]["ready"]:
			rpc_id(id, "h_start", roster, game.plane_from, game.plane_dir, int(game.world_seed))

@rpc("authority", "call_remote", "reliable")
func h_start(roster: Array, plane_from: Vector3, plane_dir: Vector3, _seed: int) -> void:
	started = true
	game.plane_from = plane_from
	game.plane_dir = plane_dir
	game.start_battle([], roster)

# ================================================================== running
var _log_t := 0.0

func tick(dt: float) -> void:
	if not started:
		return
	if G.args.has("netlog"):
		_log_t += dt
		if _log_t >= 5.0:
			_log_t = 0.0
			var p: Actor = game.player
			G.log_line("NET %s t=%d alive %d items %d me %s st %s hp %d inv %s storm r=%d veh_drivers %d" % ["host" if host else "client", int(game.match_t), game.alive_count(), game.items.size(),
				p.global_position.snapped(Vector3.ONE), game.fly[p]["st"], p.hp, [p.inv[1], p.inv[2]], int(game.storm["r"]), game.vehicles.filter(func(v): return v.driver != null).size()])
	if host:
		_snap_acc += dt
		if _snap_acc >= 1.0 / SNAP_HZ:
			_snap_acc = 0.0
			_send_snapshot()
		_storm_acc += dt
		if _storm_acc >= 1.0:
			_storm_acc = 0.0
			var st: Dictionary = game.storm
			rpc("h_storm", [st["c"], st["r"], st["c0"], st["r0"], st["c1"], st["r1"], st["k"], st["t"], st["closing"], st["dmg"]], game.match_t)
	else:
		_state_acc += dt
		if _state_acc >= 1.0 / STATE_HZ:
			_state_acc = 0.0
			_send_state()

func _send_snapshot() -> void:
	var fighters := []
	for i in game.actors.size():
		var a: Actor = game.actors[i]
		var st: String = game.fly[a]["st"] if game.fly.has(a) else "ground"
		var vi: int = game.vehicles.find(a.vehicle) if a.vehicle else -1
		fighters.append([a.global_position, a.view_yaw, a.view_pitch, a.crouch_t, a.prone_t, a.lean, a.hp, a.armor, a.alive, a.cur, st, a.helmet, vi])
	var cars := []
	for v in game.vehicles:
		var vh := v as Vehicle
		cars.append([vh.global_position, vh.global_basis.get_rotation_quaternion(), vh.hp, vh.wrecked, game.actors.find(vh.driver) if vh.driver else -1, vh.steering, vh.linear_velocity])
	rpc("h_snap", fighters, cars, game.plane_t)

@rpc("authority", "call_remote", "unreliable_ordered")
func h_snap(fighters: Array, cars: Array, plane_t: float) -> void:
	if not started:
		return
	game.plane_t = maxf(game.plane_t, plane_t)
	for i in mini(fighters.size(), game.actors.size()):
		var a: Actor = game.actors[i]
		var f: Array = fighters[i]
		if a == game.player:
			# my own fighter: only what the host decides (health, armour, death)
			a.hp = int(f[6])
			a.armor = int(f[7])
			a.helmet = bool(f[11])
			if a.alive and not bool(f[8]):
				game.net_player_down()
			_my_vehicle(int(f[12]))
			continue
		var p := a as NetPuppet
		if p == null:
			continue
		p.apply_pose(f[0], f[1], f[2], f[3], f[4], f[5], f[9])
		p.target_hp = int(f[6])
		p.target_armor = int(f[7])
		p.target_helmet = bool(f[11])
		if p.alive and not bool(f[8]):
			p.net_die()
		game.net_flight(a, String(f[10]))
		p.vehicle = game.vehicles[int(f[12])] if int(f[12]) >= 0 and int(f[12]) < game.vehicles.size() else null
	for i in mini(cars.size(), game.vehicles.size()):
		var vh := game.vehicles[i] as Vehicle
		var c: Array = cars[i]
		vh.net_pose(c[0], c[1], c[6], float(c[5]))
		vh.hp = float(c[2])
		if bool(c[3]) and not vh.wrecked:
			vh.net_wreck()
		var di: int = int(c[4])
		vh.driver = game.actors[di] if di >= 0 and di < game.actors.size() else null

func _my_vehicle(vi: int) -> void:
	var p: Player = game.player
	var v: Vehicle = game.vehicles[vi] if vi >= 0 and vi < game.vehicles.size() else null
	if v == p.vehicle:
		return
	if v:
		p.vehicle = v
		p.cam_mode = "drive"
		p.collision_layer = 0
		p.collision_mask = 0
		p.crouch_t = 1.0
		p._apply_crouch()
		var fwd := v.global_basis.z
		p.view_yaw = atan2(-fwd.x, -fwd.z)
	else:
		var old := p.vehicle as Vehicle
		p.vehicle = null
		p.cam_mode = ""
		p.collision_layer = 2
		p.collision_mask = 1
		p.crouch_t = 0.0
		if old:
			p.global_position = old.global_transform * Vector3(-(old.spec["box"] as Vector3).x * 0.5 - 0.7, 0.4, 0)

@rpc("authority", "call_remote", "reliable")
func h_storm(st: Array, t: float) -> void:
	var s: Dictionary = game.storm
	s["c"] = st[0]
	s["r"] = st[1]
	s["c0"] = st[2]
	s["r0"] = st[3]
	s["c1"] = st[4]
	s["r1"] = st[5]
	s["k"] = st[6]
	s["t"] = st[7]
	s["closing"] = st[8]
	s["dmg"] = st[9]
	game.match_t = t

# ------------------------------------------------------------------ my fighter (client)
func _send_state() -> void:
	var p: Player = game.player
	if p == null:
		return
	var st: String = game.fly[p]["st"] if game.fly.has(p) else "ground"
	var mg := [0, 0]
	if p.ammo.has(p.cur):
		mg = p.ammo[p.cur]
	var ctl: Vector3 = p.vehicle.controls if p.vehicle else Vector3.ZERO
	rpc_id(1, "c_state", p.global_position, p.view_yaw, p.view_pitch, p.crouch_t, p.prone_t, p.lean, p.cur, st, int(mg[0]), int(mg[1]), ctl)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func c_state(pos: Vector3, yaw: float, pitch: float, crouch: float, prone_v: float, lean_v: float, weapon: String, st: String, mag: int, res: int, ctl: Vector3) -> void:
	if not host:
		return
	var a := _peer_actor(multiplayer.get_remote_sender_id())
	if a == null or not a.alive:
		return
	if a.vehicle == null:
		a.apply_pose(pos, yaw, pitch, crouch, prone_v, lean_v, weapon)
	else:
		a.target_yaw = yaw
		(a.vehicle as Vehicle).controls = Vector3(clampf(ctl.x, -1, 1), clampf(ctl.y, -1, 1), clampf(ctl.z, 0, 1))
	a.target_weapon = weapon
	game.net_flight(a, st)
	# the magazine as the player sees it, never more ammunition than the host gave
	if a.ammo.has(weapon):
		var have: int = int(a.ammo[weapon][0]) + int(a.ammo[weapon][1])
		if mag + res <= have:
			a.ammo[weapon] = [mag, res]

func _peer_actor(id: int) -> NetPuppet:
	if not peers.has(id):
		return null
	var a = peers[id].get("actor", null)
	return a as NetPuppet if a and is_instance_valid(a) else null

# ------------------------------------------------------------------ requests (client -> host)
func req_take(item: Loot, swap: bool) -> void:
	rpc_id(1, "c_take", int(item.get_meta("nid", -1)), swap)

@rpc("any_peer", "call_remote", "reliable")
func c_take(nid: int, swap: bool) -> void:
	var a := _peer_actor(multiplayer.get_remote_sender_id())
	if a == null or not a.alive or not game.items_by_nid.has(nid):
		return
	var l: Loot = game.items_by_nid[nid]
	if is_instance_valid(l) and not l.taken and l.global_position.distance_to(a.global_position) < 3.0:
		game.take(a, l, swap)

func req_heal() -> void:
	rpc_id(1, "c_heal")

@rpc("any_peer", "call_remote", "reliable")
func c_heal() -> void:
	var a := _peer_actor(multiplayer.get_remote_sender_id())
	if a and a.alive:
		game.use_heal(a)

func req_enter(v: Vehicle) -> void:
	rpc_id(1, "c_enter", game.vehicles.find(v))

@rpc("any_peer", "call_remote", "reliable")
func c_enter(vi: int) -> void:
	var a := _peer_actor(multiplayer.get_remote_sender_id())
	if a == null or vi < 0 or vi >= game.vehicles.size():
		return
	var v := game.vehicles[vi] as Vehicle
	if v.can_enter(a):
		v.enter(a)

func req_leave() -> void:
	rpc_id(1, "c_leave")

@rpc("any_peer", "call_remote", "reliable")
func c_leave() -> void:
	var a := _peer_actor(multiplayer.get_remote_sender_id())
	if a and a.vehicle:
		(a.vehicle as Vehicle).leave(a)
		a.target_position = a.global_position

# ------------------------------------------------------------------ events (host -> clients)
func send_inventory(a: Actor) -> void:
	## after a pickup, a swap or healing: the player's own kit, as the host has it
	if not (a is NetPuppet) or (a as NetPuppet).peer <= 0:
		return
	var m: Dictionary = game.meds.get(a, {"bandage": 0, "medkit": 0})
	rpc_id((a as NetPuppet).peer, "h_inv", a.inv, a.ammo, a.nades, a.armor, a.helmet, int(m["bandage"]), int(m["medkit"]))

@rpc("authority", "call_remote", "reliable")
func h_inv(inv: Dictionary, ammo: Dictionary, nades: Array, armor: int, helmet: bool, bandage: int, medkit: int) -> void:
	var p: Player = game.player
	var before: String = p.cur
	p.inv = inv
	p.ammo = ammo
	p.nades.assign(nades)
	p.armor = armor
	p.helmet = helmet
	game.meds[p] = {"bandage": bandage, "medkit": medkit}
	if not p.owned().has(before):
		p.cur = ""
		p.switch_to(inv[1] if inv[1] != "" else (inv[2] if inv[2] != "" else "knife"), true)
	elif inv[1] != "" and before in ["knife", ""]:
		p.switch_to(inv[1])

func item_spawned(l: Loot) -> void:
	rpc("h_item", int(l.get_meta("nid", -1)), l.id, l.count, l.global_position, l.has_meta("drop"))

@rpc("authority", "call_remote", "reliable")
func h_item(nid: int, id: String, count: int, pos: Vector3, drop: bool) -> void:
	var l := Loot.make(id, count)
	game.add_child(l)
	l.global_position = pos
	l.set_meta("nid", nid)
	if drop:
		l.set_meta("drop", true)
	game.items.append(l)
	game.items_by_nid[nid] = l

func item_gone(l: Loot) -> void:
	rpc("h_item_gone", int(l.get_meta("nid", -1)))

@rpc("authority", "call_remote", "reliable")
func h_item_gone(nid: int) -> void:
	var l = game.items_by_nid.get(nid, null)
	if l and is_instance_valid(l):
		game.items.erase(l)
		game.items_by_nid.erase(nid)
		l.queue_free()

func shot_fx(shooter: Actor, wid: String, from: Vector3, to: Vector3) -> void:
	var idx: int = game.actors.find(shooter)
	var skip: int = (shooter as NetPuppet).peer if shooter is NetPuppet else 0
	for id in peers:
		if id != skip and peers[id]["ready"]:
			rpc_id(id, "h_shot", idx, wid, from, to)

@rpc("authority", "call_remote", "unreliable")
func h_shot(idx: int, wid: String, from: Vector3, to: Vector3) -> void:
	if idx < 0 or idx >= game.actors.size():
		return
	var a: Actor = game.actors[idx]
	game.gun_sound(a, wid)
	game.fx.tracer(from, to)
	game.fx.impact(to, (from - to).normalized(), "stone")
	if a.body:
		a.body.on_shot()

func local_shot(p: Actor, dir: Vector3) -> void:
	## client: my own tracer right away (the host decides what it hits)
	var from := p.eye()
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 400.0, 5)
	q.exclude = p.hit_rids
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
	var to: Vector3 = hit["position"] if not hit.is_empty() else from + dir * 400.0
	var start: Vector3 = (p as Player).vm.muzzle_world() if p is Player and (p as Player).vm else from
	game.fx.tracer(start, to)
	if not hit.is_empty():
		game.fx.impact(to, hit["normal"], "stone")

func hurt(v: Actor, n: int, from_pos: Vector3) -> void:
	if v is NetPuppet and (v as NetPuppet).peer > 0:
		rpc_id((v as NetPuppet).peer, "h_hurt", n, from_pos)

@rpc("authority", "call_remote", "reliable")
func h_hurt(n: int, from_pos: Vector3) -> void:
	game.player.hurt.emit(n, from_pos)

func feed(v: Actor, killer: Actor, wid: String, headshot: bool) -> void:
	rpc("h_feed", game.actors.find(v), game.actors.find(killer) if killer else -1, wid, headshot)

@rpc("authority", "call_remote", "reliable")
func h_feed(vi: int, ki: int, wid: String, headshot: bool) -> void:
	if vi < 0 or vi >= game.actors.size():
		return
	var v: Actor = game.actors[vi]
	var k: Actor = game.actors[ki] if ki >= 0 and ki < game.actors.size() else null
	if k and k != v:
		k.kills += 1
	game.hud.kill(k, v, wid, headshot)
	if v != game.player and v is NetPuppet:
		(v as NetPuppet).net_die()
	if v == game.player:
		game.net_player_down(k)
	elif k == game.player:
		Sfx.play("kill", -8.0)
		game.hud.announce("قضيت على %s" % v.nick, 1.6, "%d متبقٍ" % game.alive_count(), UI.GOLD)

func drop(at: Vector3) -> void:
	rpc("h_drop", at)

@rpc("authority", "call_remote", "reliable")
func h_drop(at: Vector3) -> void:
	game.hud.announce("طائرة إمداد في الطريق", 4.0, "صندوق نادر يسقط داخل المنطقة الآمنة — ابحث عن الدخان الأحمر", Color(1.0, 0.35, 0.25))
	game.drops._drop(at)

func over(winner: Actor) -> void:
	rpc("h_over", game.actors.find(winner) if winner else -1)

@rpc("authority", "call_remote", "reliable")
func h_over(wi: int) -> void:
	var w: Actor = game.actors[wi] if wi >= 0 and wi < game.actors.size() else null
	game.net_over(w)
