extends Node
## Online match sync over Firebase RTDB:
##   matches/<id>/p/<uid>   each player's state (position, animation, weapon, car...) ~12x/s
##   matches/<id>/ev        events: shots, hits, rockets, C4, deaths, car explosions
## Every client simulates itself and shows the others; damage is applied by the victim.

const Remote = preload("res://scripts/net/remote_player.gd")
const W = preload("res://scripts/game3d/weapons.gd")
const SEND_HZ := 12.0
const POLL_HZ := 10.0
const EV_HZ := 8.0

var world
var db
var mid := ""
var uid := ""
var remotes := {}
var _send_t := 0.0
var _poll_t := 0.0
var _ev_t := 0.0
var _ev_key := ""
var _ev_ready := false
var _hb := {}               # uid -> [last ts value, local time it changed]
var ping_ms := 0


func _ready() -> void:
	db = Online.db
	mid = Online.match_id
	uid = Online.uid
	# start reading events from "now" (skip what happened before we arrived)
	db.request("ev", HTTPClient.METHOD_GET, "matches/%s/ev" % mid, null, func(res, ok):
		if ok and res is Dictionary and res.size() > 0:
			var ks: Array = res.keys()
			ks.sort()
			_ev_key = str(ks[-1])
		_ev_ready = true, 'orderBy="$key"&limitToLast=1'.uri_encode().replace("%3D", "=").replace("%26", "&"))


func _process(delta: float) -> void:
	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = 1.0 / SEND_HZ
		_send_state()
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = 1.0 / POLL_HZ
		_poll_states()
	_ev_t -= delta
	if _ev_t <= 0.0 and _ev_ready:
		_ev_t = 1.0 / EV_HZ
		_poll_events()


# ---------------------------------------------------------------- my state
func _r(v: float) -> float:
	return snappedf(v, 0.01)


func _send_state() -> void:
	var pl = world.player
	if pl == null:
		return
	var s := {"n": str(Game.player.name), "tm": world.team, "cs": str(world.get("comp_side")), "hp": int(pl.hp), "dead": pl.dead,
		"st": pl.stance, "w": pl.current, "am": pl.aiming or pl.fire_hold_t < 1.0, "pt": _r(pl.pitch),
		"t": {".sv": "timestamp"}}
	if pl.dead:
		s["dc"] = pl.rig.death_clip
	var car = world.active_car
	if car:
		var ci: int = world.cars.find(car)
		var p: Vector3 = car.global_position
		s.merge({"car": ci, "x": _r(p.x), "y": _r(p.y), "z": _r(p.z), "ry": _r(car.rotation.y),
			"cs": _r(car.speed), "sr": car.siren_on, "sm": car.siren_mode, "en": car.engine_state == 2,
			"vx": _r(car.velocity.x), "vz": _r(car.velocity.z)})
	else:
		var p2: Vector3 = pl.global_position
		s.merge({"car": -1, "x": _r(p2.x), "y": _r(p2.y), "z": _r(p2.z), "ry": _r(pl.rotation.y),
			"vx": _r(pl.velocity.x), "vz": _r(pl.velocity.z)})
	db.request("state", HTTPClient.METHOD_PUT, "matches/%s/p/%s" % [mid, uid], s, Callable(), "", "me")


func leave() -> void:
	db.request("misc", HTTPClient.METHOD_DELETE, "matches/%s/p/%s" % [mid, uid])
	db.request("misc", HTTPClient.METHOD_DELETE, "matches/%s/players/%s" % [mid, uid])
	if remotes.is_empty():
		db.request("misc", HTTPClient.METHOD_DELETE, "matches/" + mid)
	Online.match_id = ""
	Online.set_status("lobby")


# ---------------------------------------------------------------- others
func _poll_states() -> void:
	if db.pending("poll") > 0:
		return
	var t0 := Time.get_ticks_msec()
	db.request("poll", HTTPClient.METHOD_GET, "matches/%s/p" % mid, null, func(res, ok):
		if ok:
			ping_ms = Time.get_ticks_msec() - t0
			_on_states(res if res is Dictionary else {}))


func _on_states(all: Dictionary) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for u in all:
		if u == uid or not (all[u] is Dictionary):
			continue
		var s: Dictionary = all[u]
		var ts := str(s.get("t", ""))
		if not _hb.has(u) or _hb[u][0] != ts:
			_hb[u] = [ts, now]
		if now - float(_hb[u][1]) > 8.0:
			continue          # stale: that player left or lost connection
		var r = remotes.get(u)
		if r == null or not is_instance_valid(r):
			r = Remote.new()
			r.uid = u
			r.pname = str(s.get("n", "PLAYER"))
			r.team = str(s.get("tm", "robbers"))
			r.side = str(s.get("cs", "a"))
			r.net = self
			r.world = world
			world.add_child(r)
			r.global_position = Vector3(float(s.get("x", 0)), float(s.get("y", 0)), float(s.get("z", 0)))
			remotes[u] = r
			if world.hud:
				world.hud.notify(r.pname + "  JOINED")
		var was_car: int = r.in_car
		r.apply_state(s)
		_sync_car(r, s, was_car)
	# remove players that are gone
	for u in remotes.keys():
		var gone: bool = not all.has(u) or (now - float(_hb.get(u, [0, 0])[1]) > 8.0)
		if gone:
			var r2 = remotes[u]
			if is_instance_valid(r2):
				_release_car(r2.in_car)
				if world.hud:
					world.hud.notify(str(r2.pname) + "  LEFT")
				r2.queue_free()
			remotes.erase(u)


func _sync_car(r, s: Dictionary, was_car: int) -> void:
	if was_car >= 0 and was_car != r.in_car:
		_release_car(was_car)
	if r.in_car < 0 or r.in_car >= world.cars.size():
		return
	var car = world.cars[r.in_car]
	if car == world.active_car:
		return
	car.net_driver = r.uid
	car.set_physics_process(false)
	var p := Vector3(float(s.get("x", 0)), float(s.get("y", 0)), float(s.get("z", 0)))
	car.net_target = Transform3D(Basis(Vector3.UP, float(s.get("ry", 0))), p)
	car.net_speed = float(s.get("cs", 0))
	var sm := int(s.get("sm", 0))
	if car.kind == "police" and sm != car.siren_mode:
		car.siren_mode = sm
		car.siren_on = sm > 0
		car.siren.stop()
		car.siren_yelp.stop()
		if sm == 1:
			car.siren.play()
		elif sm == 2:
			car.siren_yelp.play()


func _release_car(ci: int) -> void:
	if ci < 0 or ci >= world.cars.size():
		return
	var car = world.cars[ci]
	if car.net_driver != "":
		car.net_driver = ""
		car.speed = 0.0
		car.stop_engine()
		car.set_physics_process(true)


func teammates() -> Array:
	var out: Array = []
	for r in remotes.values():
		if is_instance_valid(r) and r.team == world.team and not r.dead:
			out.append(r)
	return out


func remote_by_uid(u: String):
	return remotes.get(u)


# ---------------------------------------------------------------- events
func _v(v: Vector3) -> Array:
	return [_r(v.x), _r(v.y), _r(v.z)]


func _pv(a) -> Vector3:
	if a is Array and a.size() == 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


func _send_ev(e: Dictionary) -> void:
	e["f"] = uid
	db.request("ev_out", HTTPClient.METHOD_POST, "matches/%s/ev" % mid, e)


func send_shot(origin: Vector3, end: Vector3, wid: String) -> void:
	_send_ev({"k": "shot", "o": _v(origin), "e": _v(end), "w": wid})


func send_hit(to: String, dmg: float, dir: Vector3) -> void:
	_send_ev({"k": "hit", "to": to, "d": snappedf(dmg, 0.1), "dir": _v(dir)})


func send_rocket(pos: Vector3, dir: Vector3) -> void:
	_send_ev({"k": "rk", "o": _v(pos), "d": _v(dir)})


func send_blast(pos: Vector3, radius: float) -> void:
	_send_ev({"k": "bx", "p": _v(pos), "r": radius})


func send_death(by: String) -> void:
	_send_ev({"k": "die", "by": by})


func send_car_boom(ci: int) -> void:
	_send_ev({"k": "cx", "ci": ci})


func _poll_events() -> void:
	if db.pending("ev") > 0:
		return
	var q := 'orderBy="$key"'.uri_encode().replace("%3D", "=")
	if _ev_key != "":
		q += "&" + ('startAt="%s"' % _ev_key).uri_encode().replace("%3D", "=")
	db.request("ev", HTTPClient.METHOD_GET, "matches/%s/ev" % mid, null, func(res, ok):
		if ok and res is Dictionary:
			_on_events(res), q)


func _on_events(evs: Dictionary) -> void:
	var ks: Array = evs.keys()
	ks.sort()
	for k in ks:
		if str(k) <= _ev_key:
			continue
		_ev_key = str(k)
		var e = evs[k]
		if not (e is Dictionary) or str(e.get("f", "")) == uid:
			continue
		_handle(e)


func _handle(e: Dictionary) -> void:
	var from = remotes.get(str(e.get("f", "")))
	match str(e.get("k", "")):
		"shot":
			var o := _pv(e.get("o"))
			var en := _pv(e.get("e"))
			if from and is_instance_valid(from):
				o = from.muzzle_pos()
				from.rig.recoil = minf(from.rig.recoil + 0.35, 1.0)
			var dir := (en - o).normalized()
			world.fx.muzzle(o, dir)
			world.fx.tracer(o, en)
			world.fx.impact(en, -dir, false)
			var cam: Camera3D = world.current_camera()
			var dist: float = cam.global_position.distance_to(o) if cam else 30.0
			var wid := str(e.get("w", "akm"))
			var snd: String = str(W.DATA[wid].get("sound", "shot_rifle")) if W.DATA.has(wid) else "shot_rifle"
			Game.play_sfx(snd, randf_range(0.95, 1.05), clampf(6.0 - dist * 0.18, -26.0, 4.0))
			world.alert(o, 30.0, null)
		"hit":
			if str(e.get("to", "")) == uid and world.player and not world.player.dead:
				world.player.take_damage(float(e.get("d", 0)), from, _pv(e.get("dir")))
		"rk":
			world.fire_rocket(_pv(e.get("o")), _pv(e.get("d")), from.get_rid() if from and is_instance_valid(from) else RID(), from)
		"bx":
			world.explode(_pv(e.get("p")), float(e.get("r", 9.0)), from, null, false)
		"die":
			var killer = remotes.get(str(e.get("by", "")))
			var victim := str(from.pname) if from else "PLAYER"
			var by_name := str(Game.player.name) if str(e.get("by", "")) == uid else (str(killer.pname) if killer else "")
			if world.hud:
				world.hud.notify(victim + "  WASTED" + ("  BY  " + by_name if by_name != "" else ""))
		"cx":
			var ci := int(e.get("ci", -1))
			if ci >= 0 and ci < world.cars.size() and not world.cars[ci].wrecked:
				world.cars[ci].net_boom = true
				world.cars[ci].explode_car(from)
