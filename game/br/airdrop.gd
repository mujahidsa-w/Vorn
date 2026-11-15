class_name AirDrops
extends Node3D
## Supply drops: a cargo plane crosses the map and drops a crate on a parachute into the safe zone; a red flare smokes
## where it lands. The crate holds the rare guns that are not found on the ground, heavy armour and a first-aid kit.

const RARE := ["awm", "groza", "mk14", "m24", "aug", "slr"]
const ALT := 210.0
const SPEED := 58.0
const FALL := -7.5
const TIMES := [120.0, 280.0, 440.0]   # seconds into the match
const CRATE_LEN := 1.6

var game: Node
var rng := RandomNumberGenerator.new()
var next := 0
var flights: Array = []                # {plane, from, dir, t, len, target, dropped, drone}
var crates: Array = []                 # {node, chute, target, landed, t, loot}

func setup(g: Node, seed_v: int) -> void:
	game = g
	rng.seed = seed_v

## positions of crates in the air or on the ground with loot still in them, for the maps
func markers() -> Array:
	var out := []
	for c in crates:
		if c["landed"]:
			var any := false
			for l in c["loot"]:
				if is_instance_valid(l) and not (l as Loot).taken:
					any = true
			if not any:
				continue
		out.append((c["node"] as Node3D).global_position)
	return out

func planes() -> Array:
	var out := []
	for f in flights:
		out.append([(f["plane"] as Node3D).global_position, f["dir"]])
	return out

func _physics_process(dt: float) -> void:
	if game == null or game.phase == "over":
		return
	if next < TIMES.size() and game.match_t >= TIMES[next] and game.phase == "live" and game.net_role != "client":
		next += 1
		_launch()
	for f in flights.duplicate():
		_fly(f, dt)
	for c in crates:
		if not c["landed"]:
			_fall(c, dt)

func launch_now() -> void:
	_launch()

func _launch() -> void:
	var st: Dictionary = game.storm
	var c1: Vector2 = st["c1"] if float(st["r1"]) > 40.0 else st["c"]
	var r1: float = maxf(float(st["r1"]) if float(st["r1"]) > 40.0 else float(st["r"]), 30.0)
	var land: BRLand = game.land
	var target := Vector2.ZERO
	for tries in 12:
		target = c1 + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, r1 * 0.7)
		target = target.clamp(Vector2(-BRLand.HALF + 60, -BRLand.HALF + 60), Vector2(BRLand.HALF - 60, BRLand.HALF - 60))
		var clear := true
		for t in land.towns + land.hamlets:
			if target.distance_to(t["c"]) < float(t["r"]) + 8.0:
				clear = false
		if clear:
			break
	var ang := rng.randf() * TAU
	var dir := Vector3(cos(ang), 0, sin(ang))
	var length := 1500.0
	var mid := Vector3(target.x, ALT, target.y)
	var f := {"plane": game._plane_model(), "from": mid - dir * length * 0.5, "dir": dir, "t": 0.0, "len": length, "target": mid, "dropped": false}
	add_child(f["plane"])
	var drone := PlaneDrone.new()
	(f["plane"] as Node3D).add_child(drone)
	f["drone"] = drone
	flights.append(f)
	_fly(f, 0.0)
	game.hud.announce("طائرة إمداد في الطريق", 4.0, "صندوق نادر سيسقط داخل المنطقة الآمنة — ابحث عن الدخان الأحمر", Color(1.0, 0.35, 0.25))
	Sfx.ui("buy", -10.0)

func _fly(f: Dictionary, dt: float) -> void:
	f["t"] = float(f["t"]) + dt
	var p: Vector3 = (f["from"] as Vector3) + (f["dir"] as Vector3) * SPEED * float(f["t"])
	var plane := f["plane"] as Node3D
	plane.global_position = p
	plane.look_at(p + (f["dir"] as Vector3), Vector3.UP)
	if not f["dropped"] and float(f["t"]) * SPEED >= float(f["len"]) * 0.5:
		f["dropped"] = true
		var at := p - Vector3(0, 6.0, 0) - (f["dir"] as Vector3) * 14.0
		_drop(at)
		if game.net_role == "host":
			game.net.drop(at)
	if float(f["t"]) * SPEED > float(f["len"]):
		plane.queue_free()
		flights.erase(f)

func _drop(at: Vector3) -> void:
	var node := Node3D.new()
	node.name = "AirdropCrate"
	add_child(node)
	node.global_position = at
	var crate := Gear.crate(CRATE_LEN, 2000.0)
	node.add_child(crate)
	# a red and white painted band so the crate reads as a drop from afar
	var band := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var sz := Gear.crate_size(CRATE_LEN)
	bm.size = Vector3(sz.x + 0.02, sz.y * 0.35, sz.z * 0.3)
	band.mesh = bm
	band.position = Vector3(0, sz.y * 0.5, 0)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.75, 0.08, 0.05)
	red.roughness = 0.7
	band.material_override = red
	node.add_child(band)
	var chute: Node3D = game._chute_model()
	chute.scale = Vector3.ONE * 0.95
	chute.position = Vector3(0, sz.y - 2.2, 0)
	node.add_child(chute)
	crates.append({"node": node, "chute": chute, "landed": false, "t": 0.0, "loot": []})

func _fall(c: Dictionary, dt: float) -> void:
	var node := c["node"] as Node3D
	c["t"] = float(c["t"]) + dt
	var p := node.global_position
	var ground: float = game.land.ground_at(p.x, p.z, p.y + 0.5)
	p.y += FALL * dt
	node.global_position = p
	# gentle swing under the canopy
	node.rotation = Vector3(sin(float(c["t"]) * 0.9) * 0.06, float(c["t"]) * 0.12, cos(float(c["t"]) * 0.7) * 0.05)
	if p.y <= ground + 0.02:
		node.global_position = Vector3(p.x, ground, p.z)
		node.rotation = Vector3(0, node.rotation.y, 0)
		_landed(c)

func _landed(c: Dictionary) -> void:
	c["landed"] = true
	var node := c["node"] as Node3D
	var chute := c["chute"] as Node3D
	var tw := create_tween()
	tw.tween_property(chute, "scale", Vector3(1.3, 0.05, 1.3), 1.6).set_ease(Tween.EASE_IN)
	tw.tween_callback(chute.queue_free)
	var sz := Gear.crate_size(CRATE_LEN)
	var body := StaticBody3D.new()
	body.set_meta("wood", true)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = sz
	cs.shape = bs
	cs.position = Vector3(0, sz.y * 0.5, 0)
	body.add_child(cs)
	node.add_child(body)
	if game.auto:
		G.log_line("DROP t=%d landed at %s" % [int(game.match_t), node.global_position.snapped(Vector3.ONE)])
	_flare(node.global_position + node.global_basis * Vector3(sz.x * 0.5 + 0.4, 0, 0))
	game.sound_at("land", node.global_position, 0.0, null)
	if game.net_role == "client":
		return              # the host sends the loot
	# loot on and around the crate
	var w: String = RARE[rng.randi() % RARE.size()]
	var b := node.global_basis
	var spots := [Vector3(0, sz.y + 0.02, -sz.z * 0.25), Vector3(0, sz.y + 0.02, sz.z * 0.25), Vector3(-sz.x * 0.5 - 0.6, 0, 0), Vector3(-sz.x * 0.5 - 0.6, 0, 0.7), Vector3(-sz.x * 0.5 - 0.6, 0, -0.7), Vector3(sz.x * 0.5 + 0.7, 0, 0.6)]
	var ids := [[w, -1], [Loot.ammo_for(w), Loot.INFO[Loot.ammo_for(w)]["n"] * 2], ["vest2", -1], ["helmet", -1], ["medkit", -1], ["medkit", -1]]
	for i in ids.size():
		var at: Vector3 = node.global_position + b * (spots[i] as Vector3)
		var it: Loot = game.spawn_item(String(ids[i][0]), int(ids[i][1]), at)
		if it:
			it.set_meta("drop", true)
			(c["loot"] as Array).append(it)

func _flare(pos: Vector3) -> void:
	## a red smoke flare burning for a minute, its column visible across the valley
	var p := CPUParticles3D.new()
	p.amount = 150
	p.lifetime = 11.0
	p.preprocess = 3.0
	p.direction = Vector3(0, 1, 0)
	p.spread = 14.0
	p.initial_velocity_min = 1.6
	p.initial_velocity_max = 2.8
	p.gravity = Vector3(0.6, 0.7, 0.25)
	p.damping_min = 0.2
	p.damping_max = 0.4
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.8
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(1, 4.0))
	p.scale_amount_curve = curve
	var qm := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = game.fx.soft_tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	qm.material = m
	qm.size = Vector2(3.2, 3.2)
	p.mesh = qm
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([Color(0.95, 0.12, 0.08, 0.6), Color(0.9, 0.28, 0.22, 0.38), Color(0.88, 0.55, 0.5, 0.0)])
	p.color_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-40, -2, -40), Vector3(80, 90, 80))
	add_child(p)
	p.global_position = pos
	p.emitting = true
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.25, 0.15)
	light.light_energy = 1.6
	light.omni_range = 5.0
	add_child(light)
	light.global_position = pos + Vector3(0, 0.4, 0)
	get_tree().create_timer(70.0).timeout.connect(func():
		if is_instance_valid(p):
			p.emitting = false
		if is_instance_valid(light):
			light.queue_free())

## the drone of a far plane, positional
class PlaneDrone extends AudioStreamPlayer3D:
	var _pb: AudioStreamGeneratorPlayback
	var _rate := 22050.0
	var _ph := 0.0
	var _am := 0.0
	var _lp := 0.0

	func _ready() -> void:
		var g := AudioStreamGenerator.new()
		g.mix_rate = _rate
		g.buffer_length = 0.25
		stream = g
		bus = "SFX"
		unit_size = 90.0
		max_distance = 1400.0
		volume_db = 4.0
		attenuation_filter_cutoff_hz = 3000.0
		play()
		_pb = get_stream_playback()

	func _process(_dt: float) -> void:
		if _pb == null:
			return
		for i in _pb.get_frames_available():
			_ph += TAU * 46.0 / _rate
			_am += TAU * 5.5 / _rate
			_lp += ((randf() * 2.0 - 1.0) - _lp) * 0.03
			var s := (sin(_ph) * 0.4 + sin(_ph * 2.0) * 0.25 + sin(_ph * 3.0) * 0.12) * (0.8 + 0.2 * sin(_am)) + _lp * 0.5
			_pb.push_frame(Vector2(s, s) * 0.5)
		if _ph > 1000.0:
			_ph -= TAU * 100.0
		if _am > 1000.0:
			_am -= TAU * 100.0
