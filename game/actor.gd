class_name Actor
extends CharacterBody3D
## Боец (игрок или бот): движение в духе CS (ускорение/трение, прыжок, присед, шаг), оружие, отдача, урон.

signal shot(wid: String)
signal weapon_changed(wid: String)
signal reload_started(wid: String, time: float)
signal hurt(amount: int, from_pos: Vector3)
signal died()

const EYE_STAND := 1.62
const EYE_CROUCH := 1.12
const H_STAND := 1.8
const H_CROUCH := 1.3
const RADIUS := 0.36
const GRAVITY := 20.3
const JUMP_V := 7.67
const ACCEL := 5.6
const FRICTION := 5.2
const STOP := 1.9
const AIR_ACCEL := 12.0
const AIR_CAP := 0.76

var game                        # Match
var team := "t"
var nick := "مقاتل"
var is_bot := true
var model_name := "t_1"
var alive := false
var hp := 100
var armor := 0
var helmet := false
var kit := false
var money := 800
var inv := {1: "", 2: "", 3: "knife", 5: ""}
var nades: Array[String] = []
var cur := "knife"
var prev := "knife"
var ammo := {}                  # wid -> [в магазине, в запасе]
var view_yaw := 0.0
var view_pitch := 0.0
var punch := Vector2.ZERO       # (тангаж, рыскание) в градусах — увод прицела от отдачи
var crouch_t := 0.0
var walking := false
var fire_cd := 0.0
var reload_t := 0.0
var reload_total := 0.0
var switch_t := 0.0
var shots := 0
var shot_age := 9.0
var scoped := false
var step_acc := 0.0
var step_ph := 0.0
const STRIDE := 2.35            # длина шага на бегу, м
var flash_t := 0.0              # ослепление
var kills := 0
var deaths := 0
var assists := 0
var score := 0
var mvps := 0
var dmg_given := 0
var dmg_from := {}
var round_kills := 0
var throwing := 0.0
var throw_alt := false
var knife_t := 0.0
var knife_alt := false
var plant_t := -1.0
var defuse_t := -1.0
var landed_v := 0.0
var _col: CollisionShape3D
var _cap: CapsuleShape3D
var hit_rids: Array[RID] = []
var _hit_nodes := {}
var body: Node3D                # FighterBody (вид от третьего лица)
var skin_seed := 0

func setup(g, t: String, n: String, bot: bool, model: String) -> void:
	game = g
	team = t
	nick = n
	is_bot = bot
	model_name = model
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.25
	floor_max_angle = deg_to_rad(50)
	max_slides = 5
	_cap = CapsuleShape3D.new()
	_cap.radius = RADIUS
	_cap.height = H_STAND
	_col = CollisionShape3D.new()
	_col.shape = _cap
	_col.position.y = H_STAND / 2.0
	add_child(_col)
	hit_rids.append(get_rid())
	_hitbox("head", SphereShape3D.new(), Vector3(0, 1.62, 0))
	(_hit_nodes["head"].get_child(0).shape as SphereShape3D).radius = 0.155
	var chest := CapsuleShape3D.new()
	chest.radius = 0.24
	chest.height = 0.66
	_hitbox("chest", chest, Vector3(0, 1.20, 0))
	var st := BoxShape3D.new()
	st.size = Vector3(0.46, 0.24, 0.3)
	_hitbox("stomach", st, Vector3(0, 0.92, 0))
	var legs := BoxShape3D.new()
	legs.size = Vector3(0.44, 0.82, 0.3)
	_hitbox("legs", legs, Vector3(0, 0.41, 0))

func _hitbox(zone: String, shape: Shape3D, pos: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 4
	b.collision_mask = 0
	b.set_meta("actor", self)
	b.set_meta("zone", zone)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	b.add_child(cs)
	b.position = pos
	add_child(b)
	_hit_nodes[zone] = b
	hit_rids.append(b.get_rid())

func _set_hit_enabled(on: bool) -> void:
	for z in _hit_nodes:
		(_hit_nodes[z] as StaticBody3D).collision_layer = 4 if on else 0
	collision_layer = 2 if on else 0
	collision_mask = 1 if on else 0

# ------------------------------------------------------------------ раунд, инвентарь
func full_reset() -> void:
	money = DB.START_MONEY
	armor = 0
	helmet = false
	kit = false
	inv = {1: "", 2: ("glock" if team == "t" else "usp"), 3: "knife", 5: ""}
	nades.clear()
	ammo.clear()
	_fill(inv[2])
	kills = 0; deaths = 0; assists = 0; score = 0; mvps = 0

func spawn_at(pos: Vector3, yaw: float, keep: bool) -> void:
	if not keep:
		armor = 0
		helmet = false
		kit = false
		inv = {1: "", 2: ("glock" if team == "t" else "usp"), 3: "knife", 5: ""}
		nades.clear()
		ammo.clear()
		_fill(inv[2])
	else:
		inv[5] = ""
		for wid in ammo.keys():
			_fill(wid)
	hp = 100
	alive = true
	global_position = pos
	velocity = Vector3.ZERO
	view_yaw = yaw
	view_pitch = 0.0
	punch = Vector2.ZERO
	crouch_t = 0.0
	fire_cd = 0.0
	reload_t = 0.0
	switch_t = 0.0
	shots = 0
	scoped = false
	flash_t = 0.0
	throwing = 0.0
	knife_t = 0.0
	plant_t = -1.0
	defuse_t = -1.0
	dmg_from.clear()
	round_kills = 0
	_set_hit_enabled(true)
	_apply_crouch()
	var best: String = inv[1] if inv[1] != "" else inv[2]
	cur = ""
	switch_to(best, true)
	if body:
		body.revive()

func _fill(wid: String) -> void:
	if wid == "" or not DB.W.has(wid):
		return
	var d: Dictionary = DB.W[wid]
	if d.has("mag") and d["mag"] > 0:
		ammo[wid] = [d["mag"], d["res"]]

func give(id: String) -> void:
	if DB.GEAR.has(id):
		if id == "kevlar":
			armor = 100
		elif id == "helmet":
			armor = 100
			helmet = true
		elif id == "kit":
			kit = true
		return
	var d: Dictionary = DB.W[id]
	if d["cls"] == "nade":
		nades.append(id)
		return
	var slot: int = d["slot"]
	if slot in [1, 2] and inv[slot] != "" and inv[slot] != id:
		ammo.erase(inv[slot])
		if cur == inv[slot]:
			cur = ""
	inv[slot] = id
	_fill(id)
	if slot in [1, 2] and (cur == "" or DB.W.get(cur, {}).get("slot", 3) >= slot):
		switch_to(id, true)

func can_buy(id: String) -> String:
	var price := price_of(id)
	if DB.GEAR.has(id):
		var gd: Dictionary = DB.GEAR[id]
		if gd.has("team") and gd["team"] != team:
			return "ليس لفريقك"
		if id == "kit" and kit:
			return "موجود لديك"
		if id == "kevlar" and armor >= 100:
			return "موجود لديك"
		if id == "helmet" and armor >= 100 and helmet:
			return "موجود لديك"
	else:
		var d: Dictionary = DB.W[id]
		if d.has("team") and d["team"] != team:
			return "ليس لفريقك"
		if d["cls"] == "nade":
			if nades.size() >= 4:
				return "لا يوجد مكان"
			var lim := 2 if id == "flash" else 1
			if nades.count(id) >= lim:
				return "لا يوجد مكان"
		elif inv[d["slot"]] == id:
			return "موجود لديك"
	if money < price:
		return "المال لا يكفي"
	return ""

func price_of(id: String) -> int:
	if DB.GEAR.has(id):
		if id == "helmet" and armor >= 100 and not helmet:
			return 350
		return DB.GEAR[id]["price"]
	return DB.W[id]["price"]

func buy(id: String) -> bool:
	if can_buy(id) != "":
		return false
	money -= price_of(id)
	give(id)
	return true

func wd() -> Dictionary:
	return DB.W.get(cur, DB.W["knife"])

func mag() -> int:
	return ammo[cur][0] if ammo.has(cur) else -1

func reserve() -> int:
	return ammo[cur][1] if ammo.has(cur) else -1

func owned() -> Array[String]:
	var a: Array[String] = []
	if inv[1] != "":
		a.append(inv[1])
	if inv[2] != "":
		a.append(inv[2])
	a.append("knife")
	for n in nades:
		if not a.has(n):
			a.append(n)
	if inv[5] != "":
		a.append("c4")
	return a

func switch_to(id: String, instant := false) -> void:
	if id == "" or id == cur or not owned().has(id):
		return
	if cur != "":
		prev = cur
	cur = id
	reload_t = 0.0
	scoped = false
	throwing = 0.0
	knife_t = 0.0
	plant_t = -1.0
	shots = 0
	var cls: String = wd()["cls"]
	switch_t = 0.0 if instant else (0.55 if cls in ["rifle", "sniper", "shotgun"] else 0.38)
	fire_cd = maxf(fire_cd, switch_t)
	weapon_changed.emit(cur)

func switch_slot(slot: int) -> void:
	if slot == 4:
		if nades.is_empty():
			return
		var i := nades.find(cur)
		switch_to(nades[(i + 1) % nades.size()])
	elif slot == 5:
		if inv[5] != "":
			switch_to("c4")
	elif inv[slot] != "":
		switch_to(inv[slot])

func cycle(dir: int) -> void:
	var o := owned()
	var i := o.find(cur)
	switch_to(o[posmod(i + dir, o.size())])

# ------------------------------------------------------------------ движение
func eye() -> Vector3:
	return global_position + Vector3(0, lerpf(EYE_STAND, EYE_CROUCH, crouch_t), 0)

func aim_basis(with_punch := true) -> Basis:
	var p := view_pitch + (deg_to_rad(punch.x) if with_punch else 0.0)
	var y := view_yaw + (deg_to_rad(punch.y) if with_punch else 0.0)
	return Basis(Vector3.UP, y) * Basis(Vector3.RIGHT, p)

func aim_dir() -> Vector3:
	return -aim_basis().z

func max_speed() -> float:
	var s: float = wd().get("speed", 6.0)
	if scoped and wd().has("sight"):
		s *= float(DB.SIGHTS[wd()["sight"]]["move"])
	if crouch_t > 0.5:
		s *= 0.34
	elif walking:
		s *= 0.52
	if plant_t >= 0.0 or defuse_t >= 0.0:
		s = 0.0
	return s

func _apply_crouch() -> void:
	var h := lerpf(H_STAND, H_CROUCH, crouch_t)
	_cap.height = h
	_col.position.y = h / 2.0
	var k := crouch_t
	(_hit_nodes["head"] as Node3D).position = Vector3(0, lerpf(1.62, 1.14, k), -0.1 * k)
	(_hit_nodes["chest"] as Node3D).position = Vector3(0, lerpf(1.20, 0.84, k), -0.04 * k)
	(_hit_nodes["stomach"] as Node3D).position = Vector3(0, lerpf(0.92, 0.6, k), 0)
	(_hit_nodes["legs"] as Node3D).position = Vector3(0, lerpf(0.41, 0.3, k), 0)
	(_hit_nodes["legs"].get_child(0).shape as BoxShape3D).size.y = lerpf(0.82, 0.6, k)
	for z in _hit_nodes:
		(_hit_nodes[z] as Node3D).rotation.y = view_yaw

func move_step(wish: Vector2, want_jump: bool, want_crouch: bool, want_walk: bool, dt: float) -> void:
	walking = want_walk
	var target := 1.0 if want_crouch else 0.0
	if target < crouch_t and not _headroom():
		target = 1.0
	if not is_equal_approx(crouch_t, target):
		crouch_t = move_toward(crouch_t, target, dt * 7.5)
	_apply_crouch()
	var yb := Basis(Vector3.UP, view_yaw)
	var wd3 := yb.x * wish.x - yb.z * wish.y
	wd3.y = 0.0
	var wl := wd3.length()
	if wl > 1.0:
		wd3 /= wl
		wl = 1.0
	var wishspeed := max_speed() * wl
	var wdir := wd3.normalized() if wl > 0.001 else Vector3.ZERO
	var on := is_on_floor()
	if on:
		if want_jump:
			velocity.y = JUMP_V
			on = false
			if not is_bot or true:
				game.sound_at("jump", global_position, -8.0, self)
		else:
			var hv := Vector3(velocity.x, 0, velocity.z)
			var sp := hv.length()
			if sp > 0.01:
				var drop := maxf(sp, STOP) * FRICTION * dt
				hv *= maxf(sp - drop, 0.0) / sp
			var cs := hv.dot(wdir)
			var add := wishspeed - cs
			if add > 0.0:
				hv += wdir * minf(ACCEL * wishspeed * dt, add)
			velocity.x = hv.x
			velocity.z = hv.z
	if not on:
		var hv2 := Vector3(velocity.x, 0, velocity.z)
		var ws := minf(wishspeed, AIR_CAP)
		var add2 := ws - hv2.dot(wdir)
		if add2 > 0.0:
			hv2 += wdir * minf(AIR_ACCEL * wishspeed * dt, add2)
		velocity.x = hv2.x
		velocity.z = hv2.z
		velocity.y -= GRAVITY * dt
	var was_air := not is_on_floor()
	var vy := velocity.y
	move_and_slide()
	if was_air and is_on_floor() and vy < -4.0:
		game.sound_at("land", global_position, -4.0 if vy < -8.0 else -10.0, self)
		landed_v = vy
		velocity.x *= 0.72
		velocity.z *= 0.72
	# шаги: слышны только на бегу. Фаза шага идёт от пройденного пути (PI — один шаг); по ней же качается камера и оружие,
	# звук шага звучит в нижней точке качания. У бойцов с телом шаг даёт анимация — в момент касания стопой земли.
	if is_on_floor():
		var sp2 := Vector2(velocity.x, velocity.z).length()
		var ph0 := step_ph
		step_ph += PI * sp2 * dt / STRIDE
		if body == null and sp2 > 3.3 and crouch_t < 0.5:
			if floor((step_ph - PI * 0.5) / PI) > floor((ph0 - PI * 0.5) / PI):
				game.footstep(self)
		if step_ph > 1000.0:
			step_ph -= 200.0 * PI

func _headroom() -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, H_CROUCH - 0.1, 0), global_position + Vector3(0, H_STAND + 0.05, 0), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func speed_h() -> float:
	return Vector2(velocity.x, velocity.z).length()

# ------------------------------------------------------------------ оружие
func tick_weapon(dt: float) -> void:
	fire_cd = maxf(0.0, fire_cd - dt)
	switch_t = maxf(0.0, switch_t - dt)
	shot_age += dt
	flash_t = maxf(0.0, flash_t - dt)
	if shot_age > 0.42 and shots > 0:
		shots = 0
	var rec: Array = wd().get("rec", [1.0, 0.5, 6.0])
	punch = punch.lerp(Vector2.ZERO, 1.0 - exp(-float(rec[2]) * dt))
	if reload_t > 0.0:
		reload_t -= dt
		if reload_t <= 0.0:
			_finish_reload()
	if throwing > 0.0:
		throwing -= dt
		if throwing <= 0.0:
			_release_nade()
	if knife_t > 0.0:
		knife_t -= dt
		if knife_t <= 0.0:
			game.knife_hit(self, knife_alt)

func spread_deg() -> float:
	var d := wd()
	var sp: Array = d.get("spread", [0.3, 3.0, 6.0])
	var s: float = sp[0]
	if d.get("scope", false):
		s = 0.04 if scoped else sp[0]
	elif scoped and d.has("sight"):
		s *= float(DB.SIGHTS[d["sight"]]["spread_k"])
	var ms: float = d.get("speed", 6.0)
	var k := clampf((speed_h() / ms - 0.34) / 0.66, 0.0, 1.0)
	s += float(sp[1]) * k * (0.85 if scoped else 1.0)
	if not is_on_floor():
		s += float(sp[2])
	if crouch_t > 0.5:
		s *= 0.8
	s += minf(shots, 12) * 0.035
	return s

func try_fire(alt := false) -> bool:
	if not alive or switch_t > 0.0 or fire_cd > 0.0 or game.frozen():
		return false
	var d := wd()
	var cls: String = d["cls"]
	if cls == "knife":
		knife_alt = alt
		knife_t = 0.12 if not alt else 0.22
		fire_cd = 0.45 if not alt else 1.0
		shot.emit(cur)
		game.sound_at("knife_swing", eye(), -4.0, self)
		return true
	if cls == "nade":
		if throwing > 0.0:
			return false
		throw_alt = alt
		throwing = 0.32
		fire_cd = 0.9
		shot.emit(cur)
		return true
	if cls == "c4":
		return false
	if reload_t > 0.0:
		if cls == "shotgun" and mag() > 0:
			reload_t = 0.0
		else:
			return false
	if alt:
		if d.has("sight"):
			scoped = not scoped
			fire_cd = 0.12
			game.sound_at("scope", eye(), -10.0 if d["sight"] == "sniper" else -18.0, self)
		return false
	if mag() <= 0:
		fire_cd = 0.25
		game.sound_at("click", eye(), -6.0, self)
		start_reload()
		return false
	ammo[cur][0] -= 1
	fire_cd = 60.0 / float(d["rpm"])
	var sdeg := spread_deg()
	var ab := aim_basis()
	var pellets: int = d.get("pellets", 1)
	for i in pellets:
		var a := randf() * TAU
		var r := deg_to_rad(sdeg) * sqrt(randf()) * (1.0 if pellets == 1 else 1.0)
		var dir := (ab * Vector3(cos(a) * tan(r), sin(a) * tan(r), -1.0)).normalized()
		if Network.online and self == game.player and not Network.is_host:
			if i == 0:
				Network.request_shot(eye(), dir, cur)
		else:
			game.bullet(self, eye(), dir, cur, i == 0)
	# отдача: вверх, потом змейкой влево-вправо
	var rec: Array = d.get("rec", [1.0, 0.5, 6.0])
	var up: float = rec[0] * (1.0 if shots < 9 else 0.22)
	var side := 0.0
	if shots >= 3:
		var ph := int((shots - 3) / 6) % 2
		side = float(rec[1]) * (-1.0 if ph == 0 else 1.0) * (0.6 + 0.4 * randf())
	else:
		side = float(rec[1]) * randf_range(-0.25, 0.25)
	if crouch_t > 0.5:
		up *= 0.8
		side *= 0.8
	punch.x += up
	punch.y += side
	shots += 1
	shot_age = 0.0
	if d.get("scope", false) and is_bot:
		scoped = false          # bots re-scope between bolt shots; the player stays on the optic
	shot.emit(cur)
	game.gun_sound(self, cur)
	if mag() <= 0 and reserve() > 0 and is_bot:
		start_reload()
	return true

func start_reload() -> void:
	if not ammo.has(cur) or reload_t > 0.0 or switch_t > 0.0:
		return
	var d := wd()
	var need: int = int(d["mag"]) - int(ammo[cur][0])
	if need <= 0 or ammo[cur][1] <= 0:
		return
	scoped = false
	var t: float = d["reload"]
	if d["cls"] == "shotgun":
		t = 0.5 + 0.5 * mini(need, ammo[cur][1])
	reload_t = t
	reload_total = t
	reload_started.emit(cur, t)
	game.reload_sound(self, cur)

func _finish_reload() -> void:
	if not ammo.has(cur):
		return
	var d := wd()
	var need: int = int(d["mag"]) - int(ammo[cur][0])
	var take := mini(need, ammo[cur][1])
	ammo[cur][0] += take
	ammo[cur][1] -= take

func _release_nade() -> void:
	if not alive or not nades.has(cur):
		return
	var id := cur
	nades.erase(id)
	var power := 19.0 if not throw_alt else 9.0
	var dir := -aim_basis(false).z
	var v := dir * power + Vector3(0, 2.2, 0) + velocity * 0.6
	game.throw_nade(self, id, eye() + dir * 0.4 - Vector3(0, 0.1, 0), v)
	if nades.has(id):
		switch_t = 0.5
		fire_cd = 0.6
		weapon_changed.emit(cur)
	else:
		cur = ""
		switch_to(inv[1] if inv[1] != "" else (inv[2] if inv[2] != "" else "knife"))

# ------------------------------------------------------------------ урон
func take_damage(dmg: float, attacker: Actor, wid: String, zone: String, from_pos: Vector3) -> void:
	if not alive or game.round_over_no_damage():
		return
	var real := dmg
	var absorbed := false
	if armor > 0 and zone != "legs" and (zone != "head" or helmet) and wid != "fall" and wid != "fire":
		var pen: float = DB.W.get(wid, {}).get("pen", 0.5)
		real = dmg * pen
		var loss := (dmg - real) * 0.5
		if loss > armor:
			real = dmg - armor * 2.0
			loss = armor
		armor = maxi(0, armor - int(ceil(loss)))
		absorbed = true
	var n := maxi(1, int(round(real)))
	n = mini(n, hp)
	hp -= n
	if attacker and attacker != self:
		dmg_from[attacker] = dmg_from.get(attacker, 0) + n
		attacker.dmg_given += n
	velocity.x *= 0.55
	velocity.z *= 0.55
	punch.x += randf_range(0.4, 1.2)
	punch.y += randf_range(-0.8, 0.8)
	hurt.emit(n, from_pos)
	game.on_hurt(self, attacker, n, zone, absorbed, from_pos)
	if hp <= 0:
		_die(attacker, wid, zone == "head")

func _die(killer: Actor, wid: String, headshot: bool) -> void:
	alive = false
	hp = 0
	deaths += 1
	scoped = false
	reload_t = 0.0
	throwing = 0.0
	plant_t = -1.0
	defuse_t = -1.0
	_set_hit_enabled(false)
	velocity = Vector3.ZERO
	if body:
		body.die(headshot, killer.global_position if killer else global_position)
	died.emit()
	game.on_death(self, killer, wid, headshot)
