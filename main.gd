extends Node3D
# Vorn — world, rounds, economy, bomb and effects. The interface lives in hud.gd.

const BotS = preload("res://bot.gd")
const PlayerS = preload("res://player.gd")
const HudS = preload("res://hud.gd")

const W := {
	"knife": {"name": "سكين", "dmg": 55, "rate": 0.5, "mag": 0, "res": 0, "auto": false, "spread": 0.0, "kick": 0.0, "snd": "knife", "reload": 0.0, "slot": 3, "price": 0},
	"pistol": {"name": "مسدس", "dmg": 26, "rate": 0.15, "mag": 12, "res": 36, "auto": false, "spread": 0.010, "kick": 0.018, "snd": "pistol_shot", "reload": 1.6, "slot": 2, "price": 0},
	"ak": {"name": "كلاشنكوف", "dmg": 34, "rate": 0.1, "mag": 30, "res": 90, "auto": true, "spread": 0.006, "kick": 0.017, "snd": "ak_shot", "reload": 2.3, "slot": 1, "price": 2700},
	"m4": {"name": "إم 4", "dmg": 30, "rate": 0.09, "mag": 30, "res": 90, "auto": true, "spread": 0.004, "kick": 0.012, "snd": "m4_shot", "reload": 2.1, "slot": 1, "price": 3100},
	"sniper": {"name": "قنّاصة", "dmg": 115, "rate": 1.35, "mag": 5, "res": 20, "auto": false, "spread": 0.05, "kick": 0.06, "snd": "sniper_shot", "reload": 3.0, "slot": 1, "price": 4750},
}
# shop: key, title, description
const BUY := [
	["ak", "كلاشنكوف", "قوي مع ارتداد شديد"],
	["m4", "إم 4", "دقيق وثابت"],
	["sniper", "قنّاصة", "تقتل برصاصة واحدة"],
	["armor", "سترة واقية", "تخفّف نصف الضرر"],
	["he", "قنبلة يدوية", "انفجار واسع المدى"],
]
const PRICE := {"armor": 650, "he": 300}
const KILL_NAMES := {"bomb": "القنبلة", "he": "قنبلة يدوية", "test": "اختبار"}
const TEAM_NAME := {"ct": "القوات الخاصة", "t": "الإرهابيون"}
const SITE_AR := {"A": "أ", "B": "ب"}
const NAMES_CT := ["رعد", "صقر", "فهد", "أرز", "جبل"]
const NAMES_T := ["ضبع", "غراب", "كوبرا", "أسمر", "بومة"]
const C_CT := Color(0.42, 0.69, 1.0)
const C_T := Color(1.0, 0.69, 0.29)
const C_TXT := Color(1, 1, 1, 0.92)
const C_HEAD := Color(1.0, 0.78, 0.30)
var win_score := 5

# bot waypoints
const NODES := [Vector3(-31, 0, 0), Vector3(-26, 0, -22), Vector3(-26, 0, 22), Vector3(-2, 0, -22), Vector3(-2, 0, 22), Vector3(-2, 0, 0),
	Vector3(-2, 0, -9), Vector3(7, 0, -8), Vector3(18, 0, -8), Vector3(22, 0, -12), Vector3(16, 0, -22), Vector3(14.5, 0, 3), Vector3(32, 0, 4), Vector3(7, 0, 14), Vector3(16, 0, 22),
	Vector3(20, 0, 18), Vector3(14.5, 0, 13), Vector3(30, 0, -8), Vector3(30, 0, 13)]
const LINKS := [[0, 1], [0, 2], [0, 5], [1, 3], [2, 4], [3, 6], [6, 5], [5, 4], [6, 7], [7, 8], [8, 9], [3, 10], [10, 9], [4, 13], [13, 14], [4, 14], [8, 11], [11, 16], [16, 13], [16, 15], [14, 15], [9, 17], [17, 12], [12, 18], [18, 15]]
const SITES := {"A": 9, "B": 15}
const DEFEND := [9, 8, 17, 10, 15, 16, 18, 14, 11, 13]
const BUILDINGS := [[-22, -6, -18, -6, 6.0, 0], [-22, -6, 6, 18, 6.5, 1], [2, 12, -4, 10, 7.0, 2], [2, 12, -18, -12, 5.0, 1], [17, 27, 0, 9, 6.0, 0]]

var adj := {}
var mats := {}
var snd := {}
var actors: Array = []
var player = null
var score := {"ct": 0, "t": 0}
var round_n := 0
var phase := "menu"
var t_phase := 0.0
var round_time := 0.0
var bomb: Node3D = null
var bomb_t := 0.0
var beep_t := 0.0
var bomb_carrier = null
var bomb_drop_t := 0.0
var defuse_prog := 0.0
var plant_prog := 0.0
var route_via := 6
var site_node := 9
var site_name := "A"
var nofire := false
var god := false
var tdie := false
var selftest := false
var boom := false
var feed: Array = []
var msg := ""
var msg_t := 0.0
var hint := ""
var match_won := false
var fx_root: Node3D
var cam_menu: Camera3D
var hud
var mobile := false
var test := ""
var shots_dir := ""
var shot_times: Array = []
var t_all := 0.0
var shot_n := 0
var loss_streak := 0
var menu_a := 0.6

func _ready() -> void:
	mobile = OS.has_feature("mobile")
	var dev := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="): test = a.split("=")[1]
		if a.begins_with("--shots="): shots_dir = a.split("=")[1]
		if a.begins_with("--dev="): dev = a.split("=")[1]
		if a == "--nofire": nofire = true
		if a == "--god": god = true
		if a == "--tdie": tdie = true
		if a == "--boom": boom = true
		if a == "--selftest":
			selftest = true
			win_score = 1
	randomize()
	for l in LINKS:
		for k in 2:
			if not adj.has(l[k]): adj[l[k]] = []
			adj[l[k]].append(l[1 - k])
	fx_root = Node3D.new()
	add_child(fx_root)
	hud = HudS.new()
	hud.main = self
	add_child(hud)
	build_env()
	build_map()
	build_sounds()
	cam_menu = Camera3D.new()
	add_child(cam_menu)
	cam_menu.position = Vector3(-34, 30, 34)
	cam_menu.look_at(Vector3(4, 0, -2))
	cam_menu.current = true
	if dev != "":
		# development helper script (screenshots, input simulation); never shipped
		var d = load(dev).new()
		d.main = self
		add_child(d)
		return
	if shots_dir != "" and test == "": shot_times = [3.0]
	if test != "":
		shot_times = [1.0, 6.5, 9.0, 14.0, 22.0, 30.0, 40.0, 55.0] if (test == "ct" and not nofire) else [2.0, 14.0, 22.0, 28.0, 36.0, 48.0, 62.0, 80.0]
		if selftest: shot_times = [2.5, 4.0, 7.7, 10.85, 11.5, 15.5, 22.6, 30.0]
		choose_team(test)
		get_tree().create_timer(0.6).timeout.connect(check_links)

func check_links() -> void:
	for l in LINKS:
		if not los(NODES[l[0]] + Vector3(0, 1, 0), NODES[l[1]] + Vector3(0, 1, 0)): print("BLOCKED LINK ", l)

# ------------------------------------------------------------------ WORLD
func build_env() -> void:
	var env := Environment.new()
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color(0.25, 0.45, 0.75)
	sky.sky_horizon_color = Color(0.85, 0.78, 0.62)
	sky.ground_horizon_color = Color(0.7, 0.62, 0.48)
	sky.ground_bottom_color = Color(0.4, 0.34, 0.26)
	sky.sun_angle_max = 40
	env.sky = Sky.new()
	env.sky.sky_material = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.ssao_enabled = not mobile
	env.ssao_intensity = 2.5
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.fog_enabled = true
	env.fog_light_color = Color(0.86, 0.76, 0.6)
	env.fog_density = 0.004
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80 if mobile else 110
	sun.shadow_blur = 1.5
	add_child(sun)

func nmat(key: String, c1: Color, c2: Color, sc := 0.2, freq := 0.012, bump := 3.0, rough := 0.92) -> StandardMaterial3D:
	if mats.has(key): return mats[key]
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = 5
	n.seed = key.hash() % 9999
	var g := Gradient.new()
	g.set_color(0, c1)
	g.set_color(1, c2)
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.noise = n
	t.color_ramp = g
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.noise = n
	nt.as_normal_map = true
	nt.bump_strength = bump
	var m := StandardMaterial3D.new()
	m.albedo_texture = t
	m.normal_enabled = true
	m.normal_texture = nt
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * sc
	m.roughness = rough
	mats[key] = m
	return m

func cmat(c: Color, rough := 0.8, emit := 0.0) -> StandardMaterial3D:
	var key := "c" + c.to_html() + str(emit)
	if mats.has(key): return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emit > 0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	mats[key] = m
	return m

func box(pos: Vector3, size: Vector3, m: Material, solid := true) -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	if not solid:
		mi.position = pos
		add_child(mi)
		return mi
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(mi)
	b.add_child(cs)
	b.position = pos
	add_child(b)
	return b

func prop(file: String, pos: Vector3, rot_deg: float, size: Vector3) -> void:
	var b := StaticBody3D.new()
	b.add_child(load("res://models/" + file + ".glb").instantiate())
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position.y = size.y / 2
	b.add_child(cs)
	b.position = pos
	b.rotation_degrees.y = rot_deg
	add_child(b)

func build_map() -> void:
	var sand := nmat("sand", Color(0.50, 0.41, 0.28), Color(0.68, 0.58, 0.42), 0.12, 0.02, 2.0)
	var walls := [nmat("w0", Color(0.72, 0.60, 0.42), Color(0.86, 0.76, 0.58)), nmat("w1", Color(0.66, 0.50, 0.38), Color(0.80, 0.66, 0.50)), nmat("w2", Color(0.74, 0.70, 0.60), Color(0.90, 0.86, 0.76))]
	var trim := nmat("trim", Color(0.42, 0.34, 0.25), Color(0.55, 0.46, 0.34), 0.3)
	var win := cmat(Color(0.08, 0.1, 0.13), 0.3)
	var wood := nmat("wood", Color(0.36, 0.24, 0.13), Color(0.5, 0.36, 0.2), 0.5, 0.05)
	box(Vector3(0, -0.5, 0), Vector3(76, 1, 56), sand)
	# outer walls
	box(Vector3(0, 3.5, -26.5), Vector3(74, 7, 1), walls[0])
	box(Vector3(0, 3.5, 26.5), Vector3(74, 7, 1), walls[0])
	box(Vector3(-36.5, 3.5, 0), Vector3(1, 7, 54), walls[1])
	box(Vector3(36.5, 3.5, 0), Vector3(1, 7, 54), walls[1])
	for bd in BUILDINGS:
		var w: float = bd[1] - bd[0]
		var d: float = bd[3] - bd[2]
		var h: float = bd[4]
		var c := Vector3((bd[0] + bd[1]) / 2.0, 0, (bd[2] + bd[3]) / 2.0)
		box(c + Vector3(0, h / 2, 0), Vector3(w, h, d), walls[bd[5]])
		box(c + Vector3(0, 0.4, 0), Vector3(w + 0.16, 0.8, d + 0.16), trim, false)
		box(c + Vector3(0, h + 0.15, 0), Vector3(w + 0.7, 0.3, d + 0.7), trim, false)
		var nx := int(w / 4.0)
		for i in nx:
			var x: float = bd[0] + (i + 0.5) * w / nx
			for s in [-1, 1]:
				box(Vector3(x, 3.4, c.z + s * d / 2.0), Vector3(1.3, 1.5, 0.12), win, false)
				box(Vector3(x, 2.55, c.z + s * (d / 2.0 + 0.1)), Vector3(1.7, 0.14, 0.3), trim, false)
		var nz := int(d / 4.0)
		for i in nz:
			var z: float = bd[2] + (i + 0.5) * d / nz
			for s in [-1, 1]:
				box(Vector3(c.x + s * w / 2.0, 3.4, z), Vector3(0.12, 1.5, 1.3), win, false)
				box(Vector3(c.x + s * (w / 2.0 + 0.1), 2.55, z), Vector3(0.3, 0.14, 1.7), trim, false)
		box(c + Vector3(0, 1.1, d / 2.0), Vector3(1.3, 2.2, 0.14), wood, false)
	# arch over the short passage and canopies
	box(Vector3(7, 4.6, -8), Vector3(10, 0.8, 1.2), walls[2], false)
	box(Vector3(-2, 4.2, -12), Vector3(8, 0.3, 3), wood, false)
	box(Vector3(22, 3.4, 23.5), Vector3(8, 0.2, 5), wood, false)
	for x in [18.2, 25.8]: box(Vector3(x, 1.7, 21.2), Vector3(0.2, 3.4, 0.2), wood)
	# bomb sites
	for sn in SITES:
		var site: Vector3 = NODES[SITES[sn]]
		var la := Label3D.new()
		la.text = SITE_AR[sn]
		la.font = hud.f_bk
		la.font_size = 600
		la.pixel_size = 0.006
		la.modulate = Color(0.62, 0.14, 0.09, 0.75)
		la.rotation_degrees = Vector3(-90, 0, 0)
		la.position = site + Vector3(0, 0.05, 0)
		add_child(la)
		var la2: Label3D = la.duplicate()
		la2.pixel_size = 0.005
		if sn == "A":
			la2.rotation_degrees = Vector3(0, -90, 0)
			la2.position = Vector3(35.9, 4.2, -12)
		else:
			la2.rotation_degrees = Vector3(0, 180, 0)
			la2.position = Vector3(20, 4.2, 25.9)
		add_child(la2)
		box(site + Vector3(0, 0.02, 0), Vector3(9, 0.04, 9), cmat(Color(0.5, 0.42, 0.3), 1.0), false)
	# cover (kept away from bot routes)
	var P := [["crate", 25.5, -15.5, 8], ["crate", 26.8, -15.3, -5], ["crate", 19.6, -14.4, 20], ["crate", 27.5, -5.2, 0], ["barrel", 24.6, -5.6, 0], ["barrier", 12.8, -1, 90],
		["crate", -12, -4.6, 0], ["crate", -15, 4.6, 12], ["barrel", -13.6, 4.4, 0], ["barrier", -8, 3.8, 0], ["crate", -4.9, -14, 0], ["barrel", 0.8, -15, 0],
		["truck", 33.8, -17, 4], ["crate", 34.6, 9.5, 0], ["barrel", 34.8, 22, 0], ["barrier", 22, 13, 0], ["crate", 10, 24.6, 15],
		["crate", 23, 21.2, 5], ["crate", 24.3, 21, -8], ["barrel", 25.2, 16.2, 0], ["crate", 19.4, 24.2, 0], ["barrier", 28.5, 19, 90],
		["truck", -33, -9, 175], ["crate", -33, 8, 0], ["barrel", -31.5, 9, 0], ["crate", -12, -24.4, 0], ["barrier", 6, -24.2, 0], ["crate", -10, 24.4, 0], ["barrel", 6, 24.5, 0], ["crate", 0.6, 4.5, 0], ["barrier", 8, 12.2, 0],
		["stall", -18.5, -4.9, 180], ["stall", -19.5, 4.8, 0], ["stall", 2.2, 24.7, 0], ["stall", 33.9, 13.5, 90],
		["palm", -34.5, -24.5, 20], ["palm", -34.5, 24.5, 140], ["palm", 34.5, -24.8, 250], ["palm", 34.6, 24.6, 60], ["palm", 14.5, -25, 100], ["palm", -34.3, 3.5, 200], ["palm", 10, 21, 320], ["palm", 28.5, -22.5, 30], ["palm", -4.8, 3.5, 80],
		["sandbags", 28.5, -12, 90], ["sandbags", 16, 17.5, 90], ["sandbags", 1.0, -1.5, 0], ["sandbags", -27, -3.5, 75],
		["pots", -12.6, -5.5, 0], ["pots", 8.5, 10.6, 40], ["pots", 23.5, 9.6, 200], ["pots", -12.5, 18.6, 100], ["pots", 8.4, -11.5, 300]]
	var SZ := {"crate": Vector3(1.2, 1.2, 1.2), "barrel": Vector3(0.6, 0.9, 0.6), "barrier": Vector3(2.4, 0.95, 0.6), "truck": Vector3(1.95, 2.0, 5.2), "stall": Vector3(2.4, 2.2, 1.7), "palm": Vector3(0.45, 5.0, 0.45), "sandbags": Vector3(2.0, 0.66, 0.42), "pots": Vector3(0.95, 0.55, 0.8)}
	for p in P: prop(p[0], Vector3(p[1], 0, p[2]), p[3], SZ[p[0]])
	prop("crate", Vector3(26.1, 1.2, -15.4), 30, SZ["crate"])
	prop("crate", Vector3(23.6, 1.2, 21.1), 10, SZ["crate"])

func build_sounds() -> void:
	for f in ["m4_shot", "ak_shot", "ak_far", "pistol_shot", "sniper_shot", "reload", "click", "explosion", "step1", "step2", "step3", "step4", "beep", "plant", "defuse", "buy", "knife", "win", "lose"]:
		snd[f] = load("res://sounds/" + f + ".wav")
	snd["hit"] = load("res://sounds/hit.ogg")
	snd["switch"] = load("res://sounds/weapon_change.ogg")

func play(n: String, vol := 0.0) -> void:
	if not snd.has(n): return
	var p := AudioStreamPlayer.new()
	p.stream = snd[n]
	p.volume_db = vol
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

func play3d(n: String, pos: Vector3, vol := 0.0, dist := 60.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = snd[n]
	p.volume_db = vol
	p.max_distance = dist
	p.unit_size = 14
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)

# ------------------------------------------------------------------ PATHS
func nearest_node(p: Vector3) -> int:
	var best := 0
	var bd := 1e9
	for i in NODES.size():
		var d: float = Vector2(p.x - NODES[i].x, p.z - NODES[i].z).length()
		if d < bd and (d < 3.0 or los(p + Vector3(0, 1, 0), NODES[i] + Vector3(0, 1, 0))):
			bd = d
			best = i
	return best

func find_path(a: int, b: int) -> Array:
	var dist := {a: 0.0}
	var prev := {}
	var open := [a]
	while open.size() > 0:
		var cur: int = open[0]
		for o in open:
			if dist[o] < dist[cur]: cur = o
		open.erase(cur)
		if cur == b: break
		for nb in adj[cur]:
			var nd: float = dist[cur] + NODES[cur].distance_to(NODES[nb]) * randf_range(1.0, 1.25)
			if not dist.has(nb) or nd < dist[nb]:
				dist[nb] = nd
				prev[nb] = cur
				if not open.has(nb): open.append(nb)
	var path := [b]
	var c := b
	while prev.has(c) and c != a:
		c = prev[c]
		path.push_front(c)
	return path

func los(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

# ------------------------------------------------------------------ SHOOTING AND EFFECTS
func fire(shooter, origin: Vector3, dir: Vector3, wkey: String, muzzle: Vector3) -> void:
	var w: Dictionary = W[wkey]
	var rng: float = 2.4 if wkey == "knife" else 200.0
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * rng, 3, [shooter.get_rid()])
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	var end: Vector3 = origin + dir * rng
	if not r.is_empty():
		end = r.position
		var c = r.collider
		if c.has_method("hurt"):
			if c.team != shooter.team:
				var head: bool = r.position.y - c.global_position.y > c.head_h
				c.hurt(w.dmg * (4.0 if head else 1.0), shooter, wkey, head)
				if shooter.is_player:
					shooter.hitmark = 0.25
					play("hit", -4)
				puff(end, Color(0.6, 0.05, 0.05), 10)
		else:
			if wkey != "knife":
				decal(end, r.normal)
				puff(end, Color(0.75, 0.65, 0.5), 6)
	if wkey != "knife": tracer(muzzle, end)

func tracer(a: Vector3, b: Vector3) -> void:
	if a.distance_to(b) < 1.5: return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, a.distance_to(b))
	mi.mesh = bm
	mi.material_override = cmat(Color(1, 0.85, 0.5), 0.5, 3.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_root.add_child(mi)
	mi.look_at_from_position((a + b) / 2, b + Vector3(0.001, 0.002, 0.0))
	get_tree().create_timer(0.05, false).timeout.connect(mi.queue_free)

func decal(p: Vector3, n: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.09, 0.09)
	mi.mesh = qm
	mi.material_override = cmat(Color(0.05, 0.04, 0.03), 1.0)
	fx_root.add_child(mi)
	var up := Vector3.UP if abs(n.y) < 0.9 else Vector3.RIGHT
	mi.look_at_from_position(p + n * 0.01, p - n, up)
	get_tree().create_timer(20.0, false).timeout.connect(mi.queue_free)

func puff(p: Vector3, col: Color, n := 8, spd := 2.5, life := 0.35, size := 0.05) -> void:
	var ps := CPUParticles3D.new()
	ps.one_shot = true
	ps.explosiveness = 1.0
	ps.amount = n
	ps.lifetime = life
	ps.spread = 180
	ps.initial_velocity_min = spd * 0.4
	ps.initial_velocity_max = spd
	ps.gravity = Vector3(0, -5, 0)
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 2
	sm.radial_segments = 6
	sm.rings = 3
	ps.mesh = sm
	ps.material_override = cmat(col, 1.0)
	fx_root.add_child(ps)
	ps.global_position = p
	ps.emitting = true
	get_tree().create_timer(life + 0.5, false).timeout.connect(ps.queue_free)

func flash(p: Vector3, energy := 4.0, rng := 6.0, time := 0.05) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1, 0.75, 0.4)
	l.light_energy = energy
	l.omni_range = rng
	fx_root.add_child(l)
	l.global_position = p
	get_tree().create_timer(time, false).timeout.connect(l.queue_free)
	if energy < 10.0:
		# muzzle flash: two crossed glowing quads
		for i in 2:
			var mi := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(0.22, 0.22) * randf_range(0.7, 1.2)
			mi.mesh = qm
			mi.material_override = muzzle_mat()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fx_root.add_child(mi)
			mi.global_position = p
			mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
			get_tree().create_timer(0.035, false).timeout.connect(mi.queue_free)

func muzzle_mat() -> StandardMaterial3D:
	if mats.has("muzzle"): return mats["muzzle"]
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.95, 0.7, 1))
	g.set_color(1, Color(1, 0.5, 0.1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	var mt := StandardMaterial3D.new()
	mt.albedo_texture = t
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	mats["muzzle"] = mt
	return mt

func explode(p: Vector3, radius: float, dmg: float, owner_a, wname: String) -> void:
	play3d("explosion", p, 6, 120)
	flash(p + Vector3(0, 1, 0), 30, radius * 3, 0.25)
	puff(p + Vector3(0, 0.5, 0), Color(1, 0.6, 0.2), 40, radius, 0.5, 0.25)
	puff(p + Vector3(0, 0.5, 0), Color(0.2, 0.18, 0.16), 50, radius * 0.6, 1.4, 0.4)
	for a in actors:
		if not a.alive: continue
		var d: float = a.global_position.distance_to(p)
		if d < radius and los(p + Vector3(0, 0.6, 0), a.global_position + Vector3(0, 1.0, 0)):
			if owner_a == null or a.team != owner_a.team or a == owner_a:
				a.hurt(dmg * (1.0 - d / radius), owner_a, wname, false)
	if player and player.alive: player.shake = max(player.shake, clamp(1.5 - player.global_position.distance_to(p) / 25.0, 0, 1))

# ------------------------------------------------------------------ ROUNDS
func choose_team(team: String) -> void:
	if phase != "menu": return
	player = PlayerS.new()
	player.main = self
	player.team = team
	player.nick = "أنت"
	add_child(player)
	actors.append(player)
	for tm in ["ct", "t"]:
		for i in (4 if tm == team else 5):
			var b = BotS.new()
			b.main = self
			b.team = tm
			b.nick = (NAMES_CT if tm == "ct" else NAMES_T)[i]
			add_child(b)
			actors.append(b)
	start_round()

func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func start_round() -> void:
	round_n += 1
	for c in fx_root.get_children(): c.queue_free()
	if bomb: bomb.queue_free()
	bomb = null
	bomb_carrier = null
	defuse_prog = 0.0
	plant_prog = 0.0
	site_name = ["A", "B"][randi() % 2]
	site_node = SITES[site_name]
	route_via = ([3, 6] if site_name == "A" else [4, 13])[randi() % 2]
	var n := {"ct": 0, "t": 0}
	for a in actors:
		var base: Vector3 = NODES[12] if a.team == "ct" else NODES[0]
		var k: int = n[a.team]
		n[a.team] += 1
		a.respawn(base + Vector3((k % 3 - 1) * 1.8, 0.1, (k / 3) * 2.0 - 1.0), 0.0 if a.team == "ct" else -PI / 2)
	var ts := actors.filter(func(a): return a.team == "t")
	bomb_carrier = player if player.team == "t" else ts[randi() % ts.size()]
	phase = "freeze"
	t_phase = 5.0
	round_time = 105.0
	show_msg("الجولة %d" % round_n, 3.0)
	if player.team == "t":
		if hud.touch_mode: hint = "الفريق يتجه إلى النقطة %s. القنبلة معك — أوصلها إلى النقطة أ أو ب ثم اضغط مطولاً على زر الزرع" % SITE_AR[site_name]
		else: hint = "الفريق يتجه إلى النقطة %s. القنبلة معك — أوصلها إلى النقطة أ أو ب ثم اضغط E مطولاً  ·  المتجر: B" % SITE_AR[site_name]
	else:
		if hud.touch_mode: hint = "دافع عن النقطتين أ و ب. إذا زُرعت القنبلة اقترب منها واضغط مطولاً على زر التفكيك"
		else: hint = "دافع عن النقطتين أ و ب. إذا زُرعت القنبلة اقترب منها واضغط E مطولاً  ·  المتجر: B"

func near_site(p: Vector3) -> bool:
	for sn in SITES:
		if NODES[SITES[sn]].distance_to(p) < 6.5: return true
	return false

func hold_nodes() -> Array:
	return [8, 9, 10, 17, 9] if site_node == 9 else [15, 16, 14, 18, 15]

func alive_n(team: String) -> int:
	return actors.filter(func(a): return a.team == team and a.alive).size()

func team_col(team: String) -> Color:
	return C_CT if team == "ct" else C_T

func on_kill(victim, killer, wkey: String, head: bool) -> void:
	var kn: String = killer.nick if killer else "انفجار"
	var col: Color = team_col(killer.team) if killer else C_T
	var wn: String = W[wkey].name if W.has(wkey) else KILL_NAMES.get(wkey, wkey)
	var seg := [[kn, col], [wn, C_TXT]]
	if head: seg.append(["إصابة رأس", C_HEAD])
	seg.append([victim.nick, team_col(victim.team)])
	feed.append({"t": 6.0, "seg": seg})
	victim.deaths += 1
	if killer and killer != victim and killer.team != victim.team:
		killer.money = min(killer.money + 300, 16000)
		killer.kills += 1
	if victim == bomb_carrier and bomb == null:
		bomb_drop_t = 1.5
	check_end()

func check_end() -> void:
	if phase != "live" and phase != "planted": return
	var ct := alive_n("ct")
	var t := alive_n("t")
	if phase == "live":
		if t == 0: end_round("ct", "تم القضاء على جميع الإرهابيين")
		elif ct == 0: end_round("t", "تم القضاء على القوات الخاصة")
	elif ct == 0: end_round("t", "تم القضاء على القوات الخاصة")

func end_round(winner: String, why: String) -> void:
	if phase == "over" or phase == "match": return
	phase = "over"
	t_phase = 5.0
	if test != "": print("EVENT end r%d %s: %s (t=%.1f)" % [round_n, winner, why, t_all])
	if boom:
		var snap := func():
			if shots_dir != "": get_viewport().get_texture().get_image().save_png(shots_dir + "/boom.png")
		get_tree().create_timer(0.25).timeout.connect(snap)
		get_tree().create_timer(3.0).timeout.connect(get_tree().quit)
	score[winner] += 1
	var won: bool = winner == player.team
	play("win" if won else "lose", -6)
	show_msg(("فازت القوات الخاصة" if winner == "ct" else "فاز الإرهابيون") + "\n" + why, 5.0)
	loss_streak = 0 if won else loss_streak + 1
	for a in actors:
		a.money = min(a.money + (3250 if a.team == winner else 1400 + min(loss_streak, 4) * 500), 16000)
		if not a.alive: a.lose_gear()

func plant_bomb(pos: Vector3, who) -> void:
	bomb = load("res://models/c4.glb").instantiate()
	add_child(bomb)
	bomb.global_position = Vector3(pos.x, 0.02, pos.z)
	bomb.rotation.y = randf() * TAU
	bomb_carrier = null
	phase = "planted"
	if test != "": print("EVENT plant by %s at %s (t=%.1f)" % [who.nick, str(pos), t_all])
	bomb_t = 4.0 if boom else 40.0
	beep_t = 0.0
	play("plant")
	for sn in SITES:
		if NODES[SITES[sn]].distance_to(pos) < 12.0:
			site_name = sn
			site_node = SITES[sn]
	show_msg("زُرعت القنبلة في النقطة " + SITE_AR[site_name], 3.0)
	feed.append({"t": 6.0, "seg": [[who.nick, C_T], ["زرع القنبلة", C_TXT]]})
	who.money += 300

func defused(who) -> void:
	play("defuse")
	feed.append({"t": 6.0, "seg": [[who.nick, C_CT], ["فكّك القنبلة", C_TXT]]})
	who.money += 300
	end_round("ct", "تم تفكيك القنبلة")

func show_msg(t: String, time: float) -> void:
	msg = t
	msg_t = time

func _process(dt: float) -> void:
	t_all += dt
	if shots_dir != "" and shot_times.size() > 0 and t_all >= shot_times[0]:
		get_viewport().get_texture().get_image().save_png("%s/shot_%02d.png" % [shots_dir, shot_n])
		print("SNAP t=%.1f phase=%s score=%s hp=%s" % [t_all, phase, str(score), str(player.hp if player else 0)])
		shot_times.pop_front()
		shot_n += 1
		if shot_times.is_empty(): get_tree().quit()
	msg_t -= dt
	for f in feed: f["t"] -= dt
	feed = feed.filter(func(f): return f["t"] > 0)
	if feed.size() > 6: feed = feed.slice(feed.size() - 6)
	if phase == "menu":
		menu_a += dt * 0.07
		cam_menu.position = Vector3(sin(menu_a) * 50.0, 30, cos(menu_a) * 50.0)
		cam_menu.look_at(Vector3(0, 0, 0))
		return
	t_phase -= dt
	match phase:
		"freeze":
			if t_phase <= 0:
				phase = "live"
				show_msg("انطلق!", 1.2)
		"live":
			round_time -= dt
			if round_time <= 0: end_round("ct", "انتهى الوقت")
			if bomb_carrier == null or not bomb_carrier.alive:
				bomb_drop_t -= dt
				if bomb_drop_t <= 0:
					var ts := actors.filter(func(a): return a.team == "t" and a.alive)
					if ts.size() > 0:
						bomb_carrier = ts[0]
						for a in ts:
							if not a.is_player: bomb_carrier = a
						feed.append({"t": 5.0, "seg": [[bomb_carrier.nick, C_T], ["التقط القنبلة", C_TXT]]})
					bomb_drop_t = 1.5
		"planted":
			bomb_t -= dt
			if tdie and bomb_t < 38.0:
				for a in actors:
					if a.team == "t" and a.alive: a.hurt(999.0, null, "test", false)
			beep_t -= dt
			if beep_t <= 0:
				beep_t = clamp(bomb_t / 40.0, 0.08, 1.0)
				play3d("beep", bomb.global_position, 2, 90)
				flash(bomb.global_position + Vector3(0, 0.2, 0), 2.0, 3.0, 0.08)
			if bomb_t <= 0:
				explode(bomb.global_position, 22.0, 400.0, null, "bomb")
				bomb.queue_free()
				bomb = null
				end_round("t", "انفجرت القنبلة")
		"over":
			if t_phase <= 0:
				if score["ct"] >= win_score or score["t"] >= win_score:
					phase = "match"
					match_won = score[player.team] >= win_score
					msg_t = 0.0
					if test != "":
						var snap := func():
							if shots_dir != "": get_viewport().get_texture().get_image().save_png(shots_dir + "/match.png")
						get_tree().create_timer(1.5).timeout.connect(snap)
						get_tree().create_timer(2.5).timeout.connect(get_tree().quit)
				else:
					start_round()

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if phase == "menu":
			if ev.keycode == KEY_1: choose_team("ct")
			elif ev.keycode == KEY_2: choose_team("t")
			elif ev.keycode == KEY_ESCAPE and not mobile: get_tree().quit()
		elif phase == "match":
			if ev.keycode == KEY_ENTER or ev.keycode == KEY_KP_ENTER: restart()
			elif ev.keycode == KEY_ESCAPE and not mobile: get_tree().quit()
