extends "res://game/match.gd"
## Battle royale «Golden Valley»: 30 fighters, every one for himself. A cargo plane crosses the desert, everybody
## jumps, falls free, opens the parachute and lands; loot lies in the houses, on market stalls, by rocks and in crates;
## the sandstorm closes in phase by phase and burns whoever is caught in it; the last one standing wins.
## The shared match code (bullets, damage, grenades, sounds, effects) is reused as it is.

const BOTS := 29
const ALT := 300.0
const PLANE_SPEED := 32.0
const FALL_V := -46.0
const DIVE_V := -62.0
const CHUTE_V := -5.2
const CHUTE_AT := 105.0
const STORM := [  # wait before it moves, time to close, radius after, damage per second while caught
	[80.0, 45.0, 330.0, 1.0],
	[55.0, 40.0, 190.0, 2.0],
	[45.0, 32.0, 110.0, 4.0],
	[35.0, 26.0, 60.0, 6.0],
	[28.0, 22.0, 28.0, 9.0],
	[18.0, 28.0, 0.0, 14.0],
]
const LOOT_TABLE := [
	["glock", 6.0], ["usp", 5.0], ["deagle", 3.0], ["mac10", 5.0], ["mp9", 5.0], ["shotgun", 4.0], ["ak", 3.0], ["m4", 3.0], ["awp", 1.0],
	["ammo_light", 12.0], ["ammo_rifle", 8.0], ["ammo_shell", 4.0], ["ammo_sniper", 2.0],
	["bandage", 12.0], ["medkit", 5.0], ["vest1", 7.0], ["vest2", 3.0], ["helmet", 5.0], ["he", 4.0], ["smoke", 3.0], ["flash", 3.0],
]
const NICKS := ["صقر الصحراء", "الذيب", "أبو فهد", "الكاسر", "ريم", "الشبح", "نمر", "سيف", "الجوكر", "الإعصار", "ليث", "قناص الليل",
	"الفارس", "زين", "راكان", "هوك", "الثعلب", "الملثم", "الأسطورة", "برق", "ظل", "المحارب", "سهم", "نور", "صخر", "العقاب", "جمر", "رعد", "شاهين", "غيث"]

var land: BRLand
var phase := "plane"                  # plane, live, over
var plane: Node3D
var plane_from := Vector3.ZERO
var plane_dir := Vector3.FORWARD
var plane_t := 0.0
var plane_len := 1300.0
var fly := {}                         # actor -> {st, vel, jump_at, target, chute}
var items: Array = []
var meds := {}                        # actor -> {bandage, medkit}
var heal := {}                        # actor -> {id, t, total}
var storm := {"c": Vector2.ZERO, "r": 720.0, "c0": Vector2.ZERO, "r0": 720.0, "c1": Vector2.ZERO, "r1": 720.0, "k": -1, "t": 0.0, "closing": false, "dmg": 0.0, "n": STORM.size()}
var storm_wall: MeshInstance3D
var storm_tick := 0.0
var air: AirSound
var match_t := 0.0
var player_place := 0
var result := {}
var dmg_done := 0
var overlay: CanvasLayer

# ------------------------------------------------------------------ start
func _ready() -> void:
	rng.randomize()
	if G.args.has("seed"):
		rng.seed = int(G.args["seed"])
	auto = G.args.has("auto")
	bullet_range = 650.0
	if G.args.has("timescale"):
		Engine.time_scale = float(G.args["timescale"])
	_loading_overlay()
	await get_tree().process_frame
	await get_tree().process_frame
	land = BRLand.new()
	land.name = "World"
	world = land
	add_child(land)
	land.build(rng.randi())
	fx = Fx.new()
	fx.name = "Fx"
	add_child(fx)
	_spawn_people()
	hud = preload("res://game/br/br_hud.gd").new()
	hud.name = "HUD"
	hud.game = self
	add_child(hud)
	Touch.game = self
	air = AirSound.new()
	add_child(air)
	Sfx.stop_all()
	Sfx.music("")
	Sfx.ambient("amb_desert", -16.0)
	G.set_mouse(Input.MOUSE_MODE_CAPTURED)
	state = S.LIVE
	_storm_wall()
	_scatter_loot()
	_start_plane()
	overlay.queue_free()
	hud.announce("وادي الذهب", 4.0, "اقفز من الطائرة عندما تكون فوق المكان الذي تريد الهبوط فيه", UI.GOLD)
	if G.shots_dir != "":
		_auto_shots()

func _loading_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.layer = 50
	add_child(overlay)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)
	var art := TextureRect.new()
	art.texture = UI.tex("res://assets/brand/keyart_2.jpg")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.modulate = Color(0.75, 0.75, 0.75)
	overlay.add_child(art)
	var l := UI.label("جارٍ تجهيز وادي الذهب...", 34, UI.GOLD_HI, true)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	l.offset_top = -150
	l.offset_left = -400
	l.offset_right = 400
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(l)

func _spawn_people() -> void:
	var models := ["t_1", "t_2", "ct_1", "ct_2"]
	var names := NICKS.duplicate()
	names.shuffle()
	var pteam := String(G.settings.get("team", "ct"))
	var pmodel: String = {"ct": ["ct_1", "ct_2"], "t": ["t_1", "t_2"]}[pteam][int(G.settings.get("outfit", 0)) % 2]
	for i in BOTS + 1:
		var is_p := i == 0
		var model: String = pmodel if is_p else models[rng.randi() % models.size()]
		var team := "t" if model.begins_with("t") else "ct"
		var a: Actor
		if is_p:
			player = Player.new()
			a = player
		else:
			a = Bot.new()
		a.name = "Fighter_%d" % i
		add_child(a)
		a.setup(self, team, String(G.settings["name"]) if is_p else String(names[i % names.size()]), not is_p, model)
		a.full_reset()
		_strip(a)
		if is_p:
			player.init_player()
			player.cam.far = 1600.0
		if is_p and auto:
			var pb := BRBrain.new()
			pb.name = "Brain"
			a.add_child(pb)
			pb.setup(a, self)
			a.set_meta("brain", pb)
		if not is_p:
			var br := BRBrain.new()
			br.name = "Brain"
			a.add_child(br)
			br.setup(a, self)
			a.set_meta("brain", br)
			if FighterBody.available(model):
				var fb := FighterBody.new()
				fb.name = "Body"
				a.add_child(fb)
				fb.setup(a, model)
				a.body = fb
				a.shot.connect(fb.on_shot.unbind(1))
				a.reload_started.connect(func(_w, t): fb.on_reload(t))
				for mi in fb.find_children("*", "GeometryInstance3D", true, false):
					(mi as GeometryInstance3D).visibility_range_end = 320.0
		meds[a] = {"bandage": 0, "medkit": 0}
		actors.append(a)

func _strip(a: Actor) -> void:
	a.inv = {1: "", 2: "", 3: "knife", 5: ""}
	a.ammo.clear()
	a.nades.clear()
	a.armor = 0
	a.helmet = false
	a.money = 0
	a.hp = 100
	a.alive = true
	a.cur = ""
	a.switch_to("knife", true)

# ------------------------------------------------------------------ the plane and the jump
func _start_plane() -> void:
	var ang := rng.randf() * TAU
	plane_dir = Vector3(cos(ang), 0, sin(ang))
	var side := Vector3(-plane_dir.z, 0, plane_dir.x) * rng.randf_range(-150.0, 150.0)
	plane_from = side - plane_dir * plane_len * 0.5 + Vector3(0, ALT, 0)
	plane_t = 0.0
	plane = _plane_model()
	add_child(plane)
	for a in actors:
		var f := {"st": "plane", "vel": Vector3.ZERO, "jump_at": 99.0, "target": Vector3.ZERO, "chute": null}
		if a != player or auto:
			# each bot picks a landing spot under the route and leaves when the plane is closest to it
			# a gun lying not too far from the route (the landing spot is its doorway)
			var guns := items.filter(func(it): return it.kind == "weapon" and _dist_to_route(it.global_position) < 330.0)
			var spot: Vector3 = land.loot_points[rng.randi() % land.loot_points.size()]["pos"]
			if guns.size() > 0:
				var g: Loot = guns[rng.randi() % guns.size()]
				var path: Array = g.get_meta("path", [])
				spot = path[0] if path.size() > 0 else g.global_position
			f["target"] = spot
			var along := (spot - plane_from).dot(plane_dir)
			f["jump_at"] = clampf(along / PLANE_SPEED - rng.randf_range(4.0, 9.0), 6.0, plane_len / PLANE_SPEED - 2.0)
		fly[a] = f
		a.set_physics_process(false)
		a._set_hit_enabled(false)
		if a.body:
			a.body.visible = false
	player.cam_mode = "free"
	air.mode = "plane"
	phase = "plane"

func _dist_to_route(p: Vector3) -> float:
	var q := Vector3(p.x, 0, p.z) - Vector3(plane_from.x, 0, plane_from.z)
	return (q - plane_dir * q.dot(plane_dir)).length()

func _plane_pos() -> Vector3:
	return plane_from + plane_dir * PLANE_SPEED * plane_t

func _plane_model() -> Node3D:
	var root := Node3D.new()
	root.name = "Plane"
	var body := Node3D.new()
	root.add_child(body)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.46, 0.48, 0.44)
	metal.metallic = 0.55
	metal.roughness = 0.45
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.13, 0.14)
	dark.metallic = 0.4
	dark.roughness = 0.5
	var parts := [
		[CapsuleMesh.new(), Vector3(0, 0, 0), Vector3(PI / 2.0, 0, 0), Vector3(2.4, 13.0, 2.4), metal],
		[BoxMesh.new(), Vector3(0, 0.6, -1.0), Vector3.ZERO, Vector3(34.0, 0.35, 4.2), metal],
		[BoxMesh.new(), Vector3(0, 1.4, 11.5), Vector3.ZERO, Vector3(11.0, 0.25, 2.6), metal],
		[BoxMesh.new(), Vector3(0, 3.6, 11.8), Vector3(-0.35, 0, 0), Vector3(0.3, 5.2, 3.0), metal],
	]
	for pt in parts:
		var mi := MeshInstance3D.new()
		var mesh: PrimitiveMesh = pt[0]
		if mesh is CapsuleMesh:
			(mesh as CapsuleMesh).radius = 1.0
			(mesh as CapsuleMesh).height = 2.0
		mi.mesh = mesh
		mi.position = pt[1]
		mi.rotation = pt[2]
		mi.scale = pt[3]
		mi.material_override = pt[4]
		body.add_child(mi)
	for x in [-11.0, -5.5, 5.5, 11.0]:
		var eng := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.75
		cm.bottom_radius = 0.6
		cm.height = 4.0
		eng.mesh = cm
		eng.rotation.x = PI / 2.0
		eng.position = Vector3(x, 0.2, -2.6)
		eng.material_override = dark
		body.add_child(eng)
		var prop := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 2.1
		pm.bottom_radius = 2.1
		pm.height = 0.05
		prop.mesh = pm
		var blur := StandardMaterial3D.new()
		blur.albedo_color = Color(0.1, 0.1, 0.1, 0.35)
		blur.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		prop.material_override = blur
		prop.rotation.x = PI / 2.0
		prop.position = Vector3(x, 0.2, -4.7)
		body.add_child(prop)
	return root

func _jump(a: Actor) -> void:
	var f: Dictionary = fly[a]
	if f["st"] != "plane":
		return
	f["st"] = "fall"
	f["vel"] = plane_dir * PLANE_SPEED * 0.6 + Vector3(0, -4.0, 0)
	a.global_position = _plane_pos() + Vector3(0, -4.0, 0) + Vector3(-plane_dir.z, 0, plane_dir.x) * rng.randf_range(-2.0, 2.0)
	a.view_yaw = atan2(-plane_dir.x, -plane_dir.z)
	if a.body:
		a.body.visible = true
	if a == player:
		player.cam_mode = "sky"
		player.view_pitch = -0.7
		air.mode = "fall"
		Sfx.play("draw", -6.0, 0.6)

func _open_chute(a: Actor) -> void:
	var f: Dictionary = fly[a]
	if f["st"] != "fall":
		return
	f["st"] = "chute"
	var c := _chute_model()
	a.add_child(c)
	f["chute"] = c
	a._set_hit_enabled(true)
	if a == player:
		air.mode = "chute"
		player.shake(0.6)
	sound_at("draw", a.global_position + Vector3(0, 3, 0), -2.0, a)

func _chute_model() -> Node3D:
	var root := Node3D.new()
	root.name = "Chute"
	var canopy := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 3.4
	sm.height = 6.8
	sm.is_hemisphere = true
	sm.radial_segments = 20
	sm.rings = 6
	canopy.mesh = sm
	canopy.scale = Vector3(1.0, 0.42, 0.8)
	canopy.position = Vector3(0, 5.6, 0)
	var m := StandardMaterial3D.new()
	var t := load("res://assets/maps/kasbah_fabric_stripes_base.jpg") as Texture2D
	m.albedo_texture = t
	m.uv1_scale = Vector3(3, 1, 1)
	m.albedo_color = Color(1.0, 0.85, 0.6)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.85
	canopy.material_override = m
	root.add_child(canopy)
	var line_m := StandardMaterial3D.new()
	line_m.albedo_color = Color(0.15, 0.13, 0.1)
	for p in [Vector3(-2.8, 5.6, -2.0), Vector3(2.8, 5.6, -2.0), Vector3(-2.8, 5.6, 2.0), Vector3(2.8, 5.6, 2.0)]:
		var from := Vector3(sign(p.x) * 0.3, 2.3, sign(p.z) * 0.15)
		var ln := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.006
		cm.bottom_radius = 0.006
		cm.height = from.distance_to(p)
		ln.mesh = cm
		ln.material_override = line_m
		ln.position = (from + p) * 0.5
		var up: Vector3 = (p - from).normalized()
		var x: Vector3 = up.cross(Vector3.FORWARD).normalized()
		ln.basis = Basis(x, up, x.cross(up))
		root.add_child(ln)
	return root

func _land(a: Actor, ground: float) -> void:
	var f: Dictionary = fly[a]
	f["st"] = "ground"
	if f["chute"]:
		(f["chute"] as Node3D).queue_free()
		f["chute"] = null
	var p := a.global_position
	a.global_position = Vector3(p.x, ground + 0.05, p.z)
	a.velocity = Vector3(f["vel"].x, 0, f["vel"].z) * 0.3
	a.set_physics_process(true)
	a._set_hit_enabled(true)
	if a == player:
		player.cam_mode = ""
		air.mode = ""
		hud.announce("", 0.1)
	sound_at("land", a.global_position, -6.0, a)

func _flight(a: Actor, dt: float) -> void:
	var f: Dictionary = fly[a]
	var st: String = f["st"]
	if st == "plane":
		a.global_position = _plane_pos() + Vector3(0, -2.0, 0)
		if (a != player or auto) and plane_t >= float(f["jump_at"]):
			_jump(a)
		elif plane_t * PLANE_SPEED > plane_len - 30.0:
			_jump(a)
		return
	# steering: the player with the stick, bots towards their landing spot
	var wish := Vector3.ZERO
	if a == player and not auto:
		var iv := Input.get_vector("left", "right", "back", "fwd")
		var yb := Basis(Vector3.UP, player.view_yaw)
		wish = yb.x * iv.x - yb.z * iv.y
	else:
		var to: Vector3 = (f["target"] as Vector3) - a.global_position
		to.y = 0.0
		if to.length() > 2.0:
			wish = to.normalized() * clampf(to.length() / 60.0, 0.2, 1.0)
		if wish.length() > 0.1:
			a.view_yaw = lerp_angle(a.view_yaw, atan2(-wish.x, -wish.z), 1.0 - exp(-2.0 * dt))
	var vel: Vector3 = f["vel"]
	var hmax := 34.0 if st == "fall" else 9.5
	var vy := FALL_V
	if st == "fall" and a == player and player.view_pitch < -0.9:
		vy = DIVE_V
	if st == "chute":
		vy = CHUTE_V
	var hv := Vector3(vel.x, 0, vel.z).lerp(wish * hmax, 1.0 - exp(-(1.2 if st == "fall" else 1.6) * dt))
	vel = Vector3(hv.x, lerpf(vel.y, vy, 1.0 - exp(-(1.5 if st == "fall" else 2.5) * dt)), hv.z)
	f["vel"] = vel
	var p := a.global_position + vel * dt
	p.x = clampf(p.x, -BRLand.HALF + 20.0, BRLand.HALF - 20.0)
	p.z = clampf(p.z, -BRLand.HALF + 20.0, BRLand.HALF - 20.0)
	a.global_position = p
	a.velocity = vel
	var ground := land.ground_at(p.x, p.z, p.y + 1.0)
	var agl := p.y - ground
	if st == "fall" and agl < CHUTE_AT:
		_open_chute(a)
	elif st == "chute" and agl < 0.4:
		_land(a, ground)

# ------------------------------------------------------------------ the sandstorm
func _storm_wall() -> void:
	storm_wall = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 1.0
	cm.radial_segments = 96
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	storm_wall.mesh = cm
	var sh := Shader.new()
	sh.code = "shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float t = 0.0;
varying float wy;
void vertex() { wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y; }
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec2 uv = vec2(UV.x * 90.0, UV.y * 9.0);
	float a = n2(uv + vec2(t * 1.7, t * 0.3)) * 0.55 + n2(uv * 2.3 - vec2(t * 2.9, 0.0)) * 0.3 + n2(uv * 5.1 + vec2(t * 4.0, t)) * 0.15;
	float fade = smoothstep(360.0, 90.0, wy);
	ALBEDO = mix(vec3(0.72, 0.42, 0.16), vec3(0.98, 0.72, 0.38), a);
	ALPHA = clamp((0.30 + a * 0.45) * fade, 0.0, 0.85);
}"
	var m := ShaderMaterial.new()
	m.shader = sh
	storm_wall.material_override = m
	storm_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(storm_wall)
	_storm_next()

func _storm_next() -> void:
	var k: int = int(storm["k"]) + 1
	storm["k"] = k
	if k >= STORM.size():
		storm["closing"] = false
		storm["t"] = INF
		return
	var cfg: Array = STORM[k]
	var r_new: float = cfg[2]
	var c: Vector2 = storm["c"]
	var r: float = storm["r"]
	var off := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, maxf(0.0, r - r_new) * 0.85)
	var c_new := c + off
	c_new = c_new.clamp(Vector2(-380, -380), Vector2(380, 380)) if k < 2 else c_new
	storm["c0"] = c
	storm["r0"] = r
	storm["c1"] = c_new
	storm["r1"] = r_new
	storm["t"] = cfg[0]
	storm["closing"] = false
	storm["dmg"] = cfg[3]
	if k > 0:
		hud.announce("العاصفة الرملية تتحرك", 3.5, "المنطقة الآمنة الجديدة على الخريطة", Color(1.0, 0.7, 0.3))

func _storm_tick(dt: float) -> void:
	var k: int = storm["k"]
	if k < STORM.size():
		storm["t"] = float(storm["t"]) - dt
		if not storm["closing"] and float(storm["t"]) <= 0.0:
			storm["closing"] = true
			storm["t"] = STORM[k][1]
			hud.announce("العاصفة تقترب!", 3.0, "تحرّك إلى داخل الدائرة البيضاء", Color(1.0, 0.55, 0.2))
		if storm["closing"]:
			var dur: float = STORM[k][1]
			var p := clampf(1.0 - float(storm["t"]) / dur, 0.0, 1.0)
			storm["c"] = (storm["c0"] as Vector2).lerp(storm["c1"], p)
			storm["r"] = lerpf(storm["r0"], storm["r1"], p)
			if p >= 1.0:
				storm["c"] = storm["c1"]
				storm["r"] = storm["r1"]
				_storm_next()
	var c: Vector2 = storm["c"]
	var r: float = maxf(0.5, storm["r"])
	storm_wall.visible = r < 600.0
	storm_wall.position = Vector3(c.x, 150.0, c.y)
	storm_wall.scale = Vector3(r, 420.0, r)
	(storm_wall.material_override as ShaderMaterial).set_shader_parameter("t", match_t)
	storm_tick -= dt
	if storm_tick <= 0.0:
		storm_tick = 1.0
		var dmg: float = maxf(1.0, float(storm["dmg"]))
		for a in actors:
			if a.alive and fly[a]["st"] == "ground" and not in_safe(a.global_position):
				a.take_damage(dmg, null, "zone", "chest", a.global_position + Vector3(0, 1, 0))

func in_safe(p: Vector3) -> bool:
	return Vector2(p.x, p.z).distance_to(storm["c"]) <= float(storm["r"])

# ------------------------------------------------------------------ loot
func _pick_table() -> String:
	var tot := 0.0
	for e in LOOT_TABLE:
		tot += float(e[1])
	var r := rng.randf() * tot
	for e in LOOT_TABLE:
		r -= float(e[1])
		if r <= 0.0:
			return e[0]
	return "bandage"

func _scatter_loot() -> void:
	for lp in land.loot_points:
		if rng.randf() > (0.85 if lp["inside"] else 0.65):
			continue
		var n := rng.randi_range(1, 3) if lp["inside"] else rng.randi_range(1, 2)
		for i in n:
			var id := _pick_table()
			var p: Vector3 = (lp["pos"] as Vector3) + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
			var it := spawn_item(id, -1, p)
			if it:
				it.set_meta("path", lp["path"])
			if DB.W.has(id) and Loot.kind_of(id) == "weapon" and rng.randf() < 0.75:
				spawn_item(Loot.ammo_for(id), -1, p + Vector3(0.5, 0, 0.3))

func spawn_item(id: String, n: int, p: Vector3) -> Loot:
	if id == "":
		return null
	var l := Loot.make(id, n)
	add_child(l)
	var y := land.ground_at(p.x, p.z, p.y + 1.2)
	l.global_position = Vector3(p.x, y + 0.02, p.z)
	l.rotation.y = rng.randf() * TAU
	items.append(l)
	return l

func _remove_item(l: Loot) -> void:
	l.taken = true
	items.erase(l)
	l.queue_free()

func nearest_item(a: Actor, radius := 1.9, only_weapons := false) -> Loot:
	var best: Loot = null
	var bd := radius
	var p := a.global_position
	for l in items:
		var it := l as Loot
		if only_weapons and it.kind != "weapon":
			continue
		var d := Vector2(it.global_position.x - p.x, it.global_position.z - p.z).length()
		if d < bd and absf(it.global_position.y - p.y) < 1.7:
			bd = d
			best = it
	return best

func wants(a: Actor, l: Loot) -> bool:
	## automatic pickup: anything useful that does not replace what the fighter already carries
	match l.kind:
		"ammo":
			for slot in [1, 2]:
				if a.inv[slot] != "" and Loot.ammo_for(a.inv[slot]) == l.id and a.ammo.has(a.inv[slot]) and int(a.ammo[a.inv[slot]][1]) < 240:
					return true
			return false
		"med":
			var cap := 8 if l.id == "bandage" else 3
			return int(meds[a][l.id]) < cap
		"armor":
			if l.id == "helmet":
				return not a.helmet
			return a.armor < (50 if l.id == "vest1" else 100)
		"nade":
			return a.nades.size() < 3
		"weapon":
			return a.inv[int(DB.W[l.id]["slot"])] == ""
	return false

func take(a: Actor, l: Loot, swap := false) -> bool:
	if l == null or l.taken:
		return false
	match l.kind:
		"ammo":
			var got := false
			for slot in [1, 2]:
				var w: String = a.inv[slot]
				if w != "" and Loot.ammo_for(w) == l.id and a.ammo.has(w):
					a.ammo[w][1] = mini(int(a.ammo[w][1]) + l.count, 300)
					got = true
			if not got:
				return false
		"med":
			meds[a][l.id] = int(meds[a][l.id]) + l.count
		"armor":
			if l.id == "helmet":
				a.helmet = true
			else:
				a.armor = maxi(a.armor, 50 if l.id == "vest1" else 100)
		"nade":
			a.give(l.id)
		"weapon":
			var slot: int = DB.W[l.id]["slot"]
			var old: String = a.inv[slot]
			if old != "" and not swap:
				return false
			if old != "":
				var keep: int = int(a.ammo.get(old, [0, 0])[0]) + int(a.ammo.get(old, [0, 0])[1])
				spawn_item(old, -1, a.global_position + Vector3(0.6, 0.3, 0.4))
				if keep > 0:
					spawn_item(Loot.ammo_for(old), keep, a.global_position + Vector3(-0.5, 0.3, 0.5))
			a.give(l.id)
			var d: Dictionary = DB.W[l.id]
			if a.ammo.has(l.id):
				a.ammo[l.id] = [int(d["mag"]), int(d["mag"])]
			a.cur = ""
			a.switch_to(l.id, false)
	if a == player:
		Sfx.ui("buy" if Sfx.has("buy") else "ui_click", -6.0)
		hud.pickup_note(Loot.title(l.id), l.count if l.kind in ["ammo", "med"] else 0)
	_remove_item(l)
	return true

# ------------------------------------------------------------------ healing
func can_buy(a: Actor) -> bool:
	## the touch «buy» slot is the heal button in the battle royale
	return a.alive and a.hp < 100 and (int(meds[a]["bandage"]) > 0 or int(meds[a]["medkit"]) > 0) and not heal.has(a)

func use_heal(a: Actor) -> void:
	if not a.alive or heal.has(a) or a.hp >= 100:
		return
	var id := ""
	if a.hp < 70 and int(meds[a]["medkit"]) > 0:
		id = "medkit"
	elif a.hp < 75 and int(meds[a]["bandage"]) > 0:
		id = "bandage"
	elif int(meds[a]["medkit"]) > 0:
		id = "medkit"
	if id == "":
		return
	var t := 6.0 if id == "medkit" else 3.0
	heal[a] = {"id": id, "t": t, "total": t, "hp": a.hp}
	if a.scoped:
		a.scoped = false
	if a == player:
		Sfx.ui("ui_click", -6.0)

func _heal_tick(dt: float) -> void:
	for a in heal.keys():
		var h: Dictionary = heal[a]
		if not a.alive or a.shots > 0 or a.reload_t > 0.0:
			heal.erase(a)
			continue
		h["t"] = float(h["t"]) - dt
		a.velocity.x *= 0.92
		a.velocity.z *= 0.92
		if float(h["t"]) <= 0.0:
			meds[a][h["id"]] = int(meds[a][h["id"]]) - 1
			a.hp = 100 if h["id"] == "medkit" else mini(75, maxi(a.hp, a.hp + 20))
			heal.erase(a)
			if a == player:
				Sfx.ui("ui_click", -4.0, 1.3)

# ------------------------------------------------------------------ loop
func frozen() -> bool:
	return state == S.OVER

func try_plant(_a: Actor, _holding: bool) -> void:
	pass

func try_defuse(_a: Actor, _holding: bool) -> void:
	pass

func hostile(a: Actor, b: Actor) -> bool:
	return a != b

func _physics_process(dt: float) -> void:
	if land == null or player == null:
		return
	match_t += dt
	if phase == "plane":
		plane_t += dt
		plane.global_position = _plane_pos()
		plane.look_at(plane.global_position + plane_dir, Vector3.UP)
		var any := false
		for a in actors:
			if fly[a]["st"] == "plane":
				any = true
		if not any or plane_t * PLANE_SPEED > plane_len + 200.0:
			phase = "live"
			plane.queue_free()
	for a in actors:
		if a.alive and fly[a]["st"] != "ground":
			_flight(a, dt)
	if fly[player]["st"] == "plane" and not auto:
		if Input.is_action_just_pressed("use") or Input.is_action_just_pressed("jump"):
			_jump(player)
	elif fly[player]["st"] == "fall" and Input.is_action_just_pressed("use") and not auto:
		_open_chute(player)
	_storm_tick(dt)
	_heal_tick(dt)
	_areas_tick(dt)
	# pickups: automatic for useful things, the use key for swapping weapons
	for a in actors:
		if not a.alive or fly[a]["st"] != "ground":
			continue
		var l := nearest_item(a, 1.4 if a == player else 2.4)
		if l and wants(a, l):
			take(a, l)
	if player.alive and fly[player]["st"] == "ground" and not auto:
		if Input.is_action_just_pressed("use"):
			var w := nearest_item(player, 1.9, true)
			if w:
				take(player, w, true)
		if Input.is_action_just_pressed("buy"):
			use_heal(player)
	var inside: bool = in_safe(player.global_position) or not player.alive or fly[player]["st"] != "ground"
	air.mode = air.mode if fly[player]["st"] != "ground" else ("" if inside else "storm")
	_fog(dt, inside)
	if phase != "over":
		_check_end()
	if auto and G.args.has("brtrace") and fmod(match_t, 10.0) < dt and match_t > 35.0 and match_t < 90.0:
		for a in actors:
			if a.alive and a.inv[1] == "" and a.inv[2] == "" and fly[a]["st"] == "ground":
				var b = a.get_meta("brain")
				var it: String = b.item.id if (b.item and is_instance_valid(b.item)) else "-"
				var wp: Vector3 = b.route[0] if b.route.size() > 0 else b.goal
				var near_guns := 0
				for x in items:
					if x.kind == "weapon" and x.global_position.distance_to(a.global_position) < 120.0:
						near_guns += 1
				G.log_line("TRACE t=%d %s pos %s goal %s(%s) d=%.1f dy=%.1f route %d vel %.1f tgt %s guns<120m %d skip %d gt %.0f" % [int(match_t), a.nick, a.global_position.snapped(Vector3.ONE), b.goal_kind, it, Vector2(wp.x - a.global_position.x, wp.z - a.global_position.z).length(), wp.y - a.global_position.y, b.route.size(), a.speed_h(), b.target.nick if b.target else "-", near_guns, b.skip.size(), b.goal_t])
	if auto and fmod(match_t, 20.0) < dt:
		var armed := 0
		for a in actors:
			if a.alive and (a.inv[1] != "" or a.inv[2] != ""):
				armed += 1
		G.log_line("BR t=%d alive %d armed %d storm k=%d r=%d items %d" % [int(match_t), alive_count(), armed, int(storm["k"]), int(storm["r"]), items.size()])
		var shown := 0
		for a in actors:
			if a.alive and a.has_meta("brain") and shown < 6 and fly[a]["st"] == "ground":
				shown += 1
				var b = a.get_meta("brain")
				G.log_line("   %s at %s goal %s d=%.1f route %d stuck %d tgt %s hp %d cur %s" % [a.nick, a.global_position.snapped(Vector3.ONE), b.goal_kind, Vector2(b.goal.x - a.global_position.x, b.goal.z - a.global_position.z).length(), b.route.size(), b.stuck_n, b.target.nick if b.target else "-", a.hp, a.cur])
	if not result.is_empty():
		over_t += dt
		if (phase == "over" and over_t > 20.0) or (over_t > 3.0 and auto and phase == "over"):
			_finish()

var _fog_k := 0.0

func _fog(dt: float, inside: bool) -> void:
	## caught in the storm: the air turns orange and thick
	_fog_k = move_toward(_fog_k, 0.0 if inside else 1.0, dt * 0.8)
	land.env.fog_density = lerpf(0.0011, 0.03, _fog_k)
	land.env.fog_light_color = Color(0.86, 0.76, 0.62).lerp(Color(0.85, 0.48, 0.18), _fog_k)

func touch_use_label() -> String:
	## text of the touch «use» button, or "" to hide it
	if not player.alive:
		return ""
	var st: String = fly[player]["st"]
	if st == "plane":
		return "اقفز"
	if st == "fall":
		return "المظلة"
	if st == "ground":
		var w := nearest_item(player, 1.9, true)
		if w:
			return "التقط"
	return ""

func alive_count() -> int:
	var n := 0
	for a in actors:
		if a.alive:
			n += 1
	return n

func on_hurt(v: Actor, attacker: Actor, n: int, zone: String, armored: bool, from_pos: Vector3) -> void:
	super.on_hurt(v, attacker, n, zone, armored, from_pos)
	if attacker == player and v != player:
		dmg_done += n
	if heal.has(v):
		heal.erase(v)

func on_death(v: Actor, killer: Actor, wid: String, headshot: bool) -> void:
	var place := alive_count() + 1
	if auto:
		G.log_line("BR death #%d %s by %s (%s) at %s st=%s" % [place, v.nick, killer.nick if killer else "-", wid, v.global_position.snapped(Vector3.ONE), fly[v]["st"]])
	super.on_death(v, killer, wid, headshot)
	# everything he carried falls around the body
	var p := v.global_position + Vector3(0, 0.3, 0)
	var drops: Array = []
	for slot in [1, 2]:
		var w: String = v.inv[slot]
		if w != "":
			drops.append([w, -1])
			var left: int = int(v.ammo.get(w, [0, 0])[0]) + int(v.ammo.get(w, [0, 0])[1])
			if left > 0:
				drops.append([Loot.ammo_for(w), left])
	for m in ["bandage", "medkit"]:
		if int(meds[v][m]) > 0:
			drops.append([m, int(meds[v][m])])
	if v.armor > 0:
		drops.append(["vest2" if v.armor > 50 else "vest1", 1])
	if v.helmet:
		drops.append(["helmet", 1])
	for nd in v.nades:
		drops.append([nd, 1])
	for i in drops.size():
		var a := TAU * i / maxf(1.0, drops.size())
		spawn_item(drops[i][0], drops[i][1], p + Vector3(cos(a), 0, sin(a)) * 0.9)
	if v == player:
		player_place = place
		_results(false)
	if killer == player:
		hud.announce("قضيت على %s" % v.nick, 1.6, "%d متبقٍ" % (place - 1), UI.GOLD)

func _check_end() -> void:
	var n := alive_count()
	if n <= 1 and phase == "live":
		phase = "over"
		if player.alive:
			player_place = 1
			_results(true)
		else:
			state = S.OVER
			over_t = 0.0

func _results(won: bool) -> void:
	var kills := player.kills
	var credits := 60 + kills * 35 + (600 if won else maxi(0, (12 - player_place) * 20))
	G.profile["matches"] = int(G.profile["matches"]) + 1
	G.profile["kills"] = int(G.profile["kills"]) + kills
	if won:
		G.profile["wins"] = int(G.profile["wins"]) + 1
	G.add_credits(credits)
	G.last_result = {"res": "win" if won else "lose", "score": [player_place, actors.size()], "credits": credits, "kills": kills, "deaths": player.deaths, "br": true}
	result = {"won": won, "place": player_place, "of": actors.size(), "kills": kills, "dmg": dmg_done, "time": match_t, "credits": credits}
	hud.show_results(result)
	if won:
		phase = "over"
		state = S.OVER          # the winner's screen: everything stops
		Sfx.music("win_theme", 1.0, -6.0)
	over_t = 0.0
	G.set_mouse(Input.MOUSE_MODE_VISIBLE)
	G.log_line("BR RESULT place %d/%d kills %d dmg %d credits %d" % [player_place, actors.size(), kills, dmg_done, credits])

func leave() -> void:
	## «back to the lobby» on the results card
	if not result.is_empty() and over_t > 0.8:
		_finish()

func _process(_dt: float) -> void:
	# in the plane the camera circles it; looking around turns the view
	if player and player.cam_mode == "free" and is_instance_valid(plane):
		var pitch := clampf(player.view_pitch, -1.1, 0.45)
		var off := Basis(Vector3.UP, player.view_yaw) * Basis(Vector3.RIGHT, pitch) * Vector3(0, 0, 34.0)
		var target := plane.global_position
		player.head.global_position = target + off + Vector3(0, 7.0, 0)
		player.head.look_at(target + Vector3(0, 2.0, 0), Vector3.UP)
		player.cam.fov = 70.0

# ------------------------------------------------------------------ dev screenshots
func _auto_shots() -> void:
	await get_tree().create_timer(2.0).timeout
	await G.shot("br_1_plane")
	_jump(player)
	await get_tree().create_timer(2.5).timeout
	await G.shot("br_2_fall")
	_open_chute(player)
	player.view_pitch = -0.3
	await get_tree().create_timer(2.5).timeout
	await G.shot("br_3_chute")
	# skip the descent
	var p := player.global_position
	_land(player, land.ground_at(p.x, p.z, 400.0))
	await get_tree().create_timer(1.5).timeout
	await G.shot("br_4_landed")
	# in a village, by a house door, armed, aiming, the full map, the results card
	var lp: Dictionary = {}
	for q in land.loot_points:
		if q["inside"] and (q["path"] as Array).size() > 0 and Vector2(q["pos"].x, q["pos"].z).distance_to(land.towns[0]["c"]) < float(land.towns[0]["r"]):
			lp = q
			break
	if not lp.is_empty():
		var door: Vector3 = lp["path"][0]
		var to: Vector3 = (lp["pos"] as Vector3) - door
		player.global_position = door + Vector3(0, 0.2, 0) - to.normalized() * 5.0
		player.view_yaw = atan2(-to.x, -to.z)
		player.view_pitch = 0.05
	await get_tree().create_timer(1.2).timeout
	await G.shot("br_5_village")
	var m4 := Loot.make("m4")
	add_child(m4)
	items.append(m4)
	take(player, m4, true)
	await get_tree().create_timer(1.2).timeout
	await G.shot("br_6_armed")
	player.scoped = true
	await get_tree().create_timer(1.0).timeout
	await G.shot("br_7_ads")
	player.scoped = false
	Input.action_press("score")
	await get_tree().create_timer(0.5).timeout
	await G.shot("br_8_map")
	Input.action_release("score")
	player_place = 4
	_results(false)
	await get_tree().create_timer(0.6).timeout
	await G.shot("br_9_results")
	if G.args.has("quit_after"):
		get_tree().quit()
