class_name BRNet
extends Node
## Online battle royale, host-authoritative. The host is a battle server of the AURUM MOBILE network (Online, --battle)
## or a player's phone hosting a private room (Network, LAN / direct IP):
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

var dedicated := false                # a battle server of the online network (no player of its own)

func _ready() -> void:
	host = game.net_role == "host"
	dedicated = Online.role == "battle"
	if host:
		multiplayer.peer_disconnected.connect(_on_peer_left)

## to every player of this battle (not to anyone else on the connection)
func _all(m: StringName, args: Array = []) -> void:
	for id in peers:
		if peers[id]["ready"]:
			callv("rpc_id", [id, m] + args)

func ready_count() -> int:
	var n := 0
	for id in peers:
		if peers[id]["ready"]:
			n += 1
	return n

# ================================================================== lobby
func hello() -> void:
	## client: the scene is up — ask the host for the world (online: with the room's ticket)
	rpc_id(1, "c_hello", String(G.settings.get("name", "لاعب")), String(Online.battle.get("ticket", "")), int(G.settings.get("outfit", 0)))

@rpc("any_peer", "call_remote", "reliable")
func c_hello(nick: String, ticket: String, outfit: int) -> void:
	if not host:
		return
	var id := multiplayer.get_remote_sender_id()
	if started:
		rpc_id(id, "h_refused", "المعركة بدأت بالفعل — انتظر الجولة القادمة")
		return
	if dedicated:
		var t := Online.use_ticket(ticket)
		if t.is_empty():
			rpc_id(id, "h_refused", "هذه المعركة ليست لك — ارجع إلى اللوبي")
			return
		nick = String(t["name"])
		outfit = int(t["outfit"])
	peers[id] = {"name": nick.substr(0, 18), "ready": false, "model": DB.OUTFITS[clampi(outfit, 0, DB.OUTFITS.size() - 1)]}
	rpc_id(id, "h_world", int(game.world_seed), game.world_map)
	_lobby_text()

@rpc("authority", "call_remote", "reliable")
func h_refused(why: String) -> void:
	if lobby_label:
		lobby_label.text = why
	if Online.playing and not started:
		await get_tree().create_timer(3.0).timeout
		Online.leave_battle()
		G.to_menu()

@rpc("authority", "call_remote", "reliable")
func h_world(seed_v: int, map_name: String) -> void:
	await game.build_world(seed_v, map_name)
	if lobby_label:
		lobby_label.text = "جاهز — بانتظار أن يبدأ المضيف المعركة"
	rpc_id(1, "c_ready")

@rpc("any_peer", "call_remote", "reliable")
func c_ready() -> void:
	var id := multiplayer.get_remote_sender_id()
	if host and peers.has(id):
		peers[id]["ready"] = true
		_lobby_text()
		if dedicated and not started and Online.all_in() and ready_count() == peers.size():
			host_start()          # the whole room is in: no need to wait for the timer

func _on_peer_left(id: int) -> void:
	if not peers.has(id):
		return
	var a = peers[id].get("actor", null)
	peers.erase(id)
	if a and is_instance_valid(a) and a.alive:
		# a player who leaves falls where they stand
		a.take_damage(999.0, null, "fall", "chest", a.global_position)
	_lobby_text()

func bye() -> void:
	## client: leaving for the lobby
	if not host and multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		rpc_id(1, "c_bye")

@rpc("any_peer", "call_remote", "reliable")
func c_bye() -> void:
	if host:
		_on_peer_left(multiplayer.get_remote_sender_id())

func humans_alive() -> int:
	var n := 0
	for id in peers:
		var a = peers[id].get("actor", null)
		if a and is_instance_valid(a) and a.alive:
			n += 1
	return n

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
	if host and not dedicated:
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
	elif not host:
		lobby_label.text = "متصل بالمعركة — جارٍ تجهيز الجزيرة..." if Online.playing else "متصل — جارٍ استلام خريطة المضيف..."

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
	# a battle server's own seat is one more bot
	var humans := [[1, String(game.NICKS[randi() % game.NICKS.size()]) if dedicated else String(G.settings.get("name", "المضيف"))]]
	for id in peers:
		if peers[id]["ready"]:
			humans.append([id, peers[id]["name"], peers[id].get("model", "")])
		else:
			rpc_id(id, "h_refused", "تأخّر التحميل — بدأت المعركة بدونك")
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
			_all("h_storm", [[st["c"], st["r"], st["c0"], st["r0"], st["c1"], st["r1"], st["k"], st["t"], st["closing"], st["dmg"]], game.match_t])
			if dedicated and humans_alive() == 0:
				Online.battle_done(4.0)          # no real player left alive: nobody to play for
	else:
		_state_acc += dt
		if _state_acc >= 1.0 / STATE_HZ:
			_state_acc = 0.0
			_send_state()

## snapshots are packed into bytes (positions to 2 cm, angles, health, flags, weapon index) so 30 fighters and
## 20 vehicles fit in one packet (~1 KB) instead of ~5 KB of variants that would be split and lost unreliably
const STATES := ["plane", "fall", "chute", "ground"]
static var _wids: Array = []

static func wid_index(w: String) -> int:
	if _wids.is_empty():
		_wids = DB.W.keys()
	return maxi(0, _wids.find(w))

static func wid_at(i: int) -> String:
	if _wids.is_empty():
		_wids = DB.W.keys()
	return String(_wids[i]) if i >= 0 and i < _wids.size() else "knife"

static func _put_pos(b: StreamPeerBuffer, p: Vector3) -> void:
	b.put_16(clampi(int(round(p.x * 50.0)), -32767, 32767))
	b.put_16(clampi(int(round(p.y * 50.0)), -32767, 32767))
	b.put_16(clampi(int(round(p.z * 50.0)), -32767, 32767))

static func _get_pos(b: StreamPeerBuffer) -> Vector3:
	var x := b.get_16() / 50.0
	var y := b.get_16() / 50.0
	var z := b.get_16() / 50.0
	return Vector3(x, y, z)

static func _put_angle(b: StreamPeerBuffer, a: float) -> void:
	b.put_16(int(round(wrapf(a, -PI, PI) / PI * 32767.0)))

static func _get_angle(b: StreamPeerBuffer) -> float:
	return b.get_16() / 32767.0 * PI

func _send_snapshot() -> void:
	var b := StreamPeerBuffer.new()
	b.put_float(game.plane_t)
	b.put_u8(game.actors.size())
	for a in game.actors:
		var st: String = game.fly[a]["st"] if game.fly.has(a) else "ground"
		_put_pos(b, a.global_position)
		_put_angle(b, a.view_yaw)
		b.put_8(int(clampf(a.view_pitch, -1.57, 1.57) / 1.57 * 127.0))
		b.put_u8(int(clampf(a.crouch_t, 0.0, 1.0) * 255.0))
		b.put_u8(int(clampf(a.prone_t, 0.0, 1.0) * 255.0))
		b.put_8(int(clampf(a.lean, -1.0, 1.0) * 127.0))
		b.put_u8(clampi(a.hp, 0, 255))
		b.put_u8(clampi(a.armor, 0, 255))
		b.put_u8((1 if a.alive else 0) | (2 if a.helmet else 0) | (maxi(0, STATES.find(st)) << 2))
		b.put_u8(wid_index(a.cur))
		b.put_8(game.vehicles.find(a.vehicle) if a.vehicle else -1)
	b.put_u8(game.vehicles.size())
	for v in game.vehicles:
		var vh := v as Vehicle
		_put_pos(b, vh.global_position)
		var q := vh.global_basis.get_rotation_quaternion()
		for c in [q.x, q.y, q.z, q.w]:
			b.put_16(int(round(clampf(c, -1.0, 1.0) * 32767.0)))
		b.put_u16(clampi(int(vh.hp), 0, 65535))
		b.put_8((game.actors.find(vh.driver) if vh.driver else -1))
		b.put_8(int(clampf(vh.steering, -1.0, 1.0) * 127.0))
		b.put_u8(1 if vh.wrecked else 0)
		var vel := vh.linear_velocity
		b.put_8(clampi(int(vel.x * 2.0), -127, 127))
		b.put_8(clampi(int(vel.y * 2.0), -127, 127))
		b.put_8(clampi(int(vel.z * 2.0), -127, 127))
	_all("h_snap", [b.data_array])

@rpc("authority", "call_remote", "unreliable_ordered")
func h_snap(raw: PackedByteArray) -> void:
	if not started:
		return
	var b := StreamPeerBuffer.new()
	b.data_array = raw
	game.plane_t = maxf(game.plane_t, b.get_float())
	var n := b.get_u8()
	for i in n:
		var pos := _get_pos(b)
		var yaw := _get_angle(b)
		var pitch := b.get_8() / 127.0 * 1.57
		var crouch := b.get_u8() / 255.0
		var prone_v := b.get_u8() / 255.0
		var lean_v := b.get_8() / 127.0
		var hp := b.get_u8()
		var armor := b.get_u8()
		var flags := b.get_u8()
		var wid := wid_at(b.get_u8())
		var vi := b.get_8()
		if i >= game.actors.size():
			continue
		var alive := (flags & 1) != 0
		var helmet := (flags & 2) != 0
		var st: String = STATES[clampi(flags >> 2, 0, 3)]
		var a: Actor = game.actors[i]
		if a == game.player:
			# my own fighter: only what the host decides (health, armour, death, the vehicle I sit in)
			a.hp = hp
			a.armor = armor
			a.helmet = helmet
			if a.alive and not alive:
				game.net_player_down()
			_my_vehicle(vi)
			continue
		var p := a as NetPuppet
		if p == null:
			continue
		p.apply_pose(pos, yaw, pitch, crouch, prone_v, lean_v, wid)
		p.target_hp = hp
		p.target_armor = armor
		p.target_helmet = helmet
		if p.alive and not alive:
			p.net_die()
		game.net_flight(a, st)
		p.vehicle = game.vehicles[vi] if vi >= 0 and vi < game.vehicles.size() else null
	var nv := b.get_u8()
	for i in nv:
		var vpos := _get_pos(b)
		var q := Quaternion(b.get_16() / 32767.0, b.get_16() / 32767.0, b.get_16() / 32767.0, b.get_16() / 32767.0).normalized()
		var vhp := b.get_u16()
		var di := b.get_8()
		var steer := b.get_8() / 127.0
		var wrecked := b.get_u8() != 0
		var vel := Vector3(b.get_8() / 2.0, b.get_8() / 2.0, b.get_8() / 2.0)
		if i >= game.vehicles.size():
			continue
		var vh := game.vehicles[i] as Vehicle
		vh.net_pose(vpos, q, vel, steer)
		vh.hp = float(vhp)
		if wrecked and not vh.wrecked:
			vh.net_wreck()
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
	if p == null or not p.alive:
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
	_all("h_item", [int(l.get_meta("nid", -1)), l.id, l.count, l.global_position, l.has_meta("drop")])

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
	_all("h_item_gone", [int(l.get_meta("nid", -1))])

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
	_all("h_feed", [game.actors.find(v), game.actors.find(killer) if killer else -1, wid, headshot])

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
	_all("h_drop", [at])

@rpc("authority", "call_remote", "reliable")
func h_drop(at: Vector3) -> void:
	game.hud.announce("طائرة إمداد في الطريق", 4.0, "صندوق نادر يسقط داخل المنطقة الآمنة — ابحث عن الدخان الأحمر", Color(1.0, 0.35, 0.25))
	game.drops._drop(at)

func over(winner: Actor) -> void:
	_all("h_over", [game.actors.find(winner) if winner else -1])
	if dedicated:
		Online.battle_done(15.0)

@rpc("authority", "call_remote", "reliable")
func h_over(wi: int) -> void:
	var w: Actor = game.actors[wi] if wi >= 0 and wi < game.actors.size() else null
	game.net_over(w)
