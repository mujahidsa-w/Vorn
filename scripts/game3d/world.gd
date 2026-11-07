extends Node3D
## Free-roam city: night LA map, street lights, rain, player, drivable cars, HUD, pause menu.

const Player = preload("res://scripts/game3d/player.gd")
const Car = preload("res://scripts/game3d/car.gd")
const Hud = preload("res://scripts/game3d/hud.gd")
const Effects = preload("res://scripts/game3d/effects.gd")
const Bank = preload("res://scripts/game3d/bank.gd")
const CityCenter = preload("res://scripts/game3d/city_center.gd")
const MatchNet = preload("res://scripts/net/match_net.gd")
const SkyCycle = preload("res://scripts/game3d/sky_cycle.gd")
const StreetLife = preload("res://scripts/game3d/street_life.gd")
const Country = preload("res://scripts/game3d/country.gd")
const Gps = preload("res://scripts/game3d/gps.gd")
const CityBusinesses = preload("res://scripts/game3d/city_businesses.gd")
const WorldAudio = preload("res://scripts/game3d/world_audio.gd")

const MAP_PATH := "res://assets/models/map/la.glb"
const MAP_SCALE := 0.01
const HIDE_KEYS := ["arrow", "traffic_", "customspline", "dir_light", "box_sun", "bollywood", "CENTER_ROUTE", "camera_", "mmm_road"]
const NO_COLLIDE := ["alpha", "ocean", "waterflow"]

var map: Node3D
var route: Array = []          # ordered world points of the race line
var player
var cars: Array = []
var hud
var active_car = null
var team := "citizen"
var roleplay := true
var spawn_xf := Transform3D()
var rain: GPUParticles3D
var space: PhysicsDirectSpaceState3D
var fx
var net                      # online match sync (null when offline)
var sky                      # day/night + weather
var life                     # traffic, pedestrians, signals, props
var country                  # open world outside the city ring (terrain, roads, villages)
var gps                      # road graph, routing, zone names
var last_car = null          # the car the player drove last (shown on the map)
var bank
var businesses
var audio_world
var npcs: Array = []
var poi: Array = []          # map points of interest {name,pos,color}
var spec_cam: Camera3D
var spec_target = null
var spec_index := -1
var spec_t := 0.0


var Q := 1


func _ready() -> void:
	Q = clampi(int(Game.settings.quality), 0, 2)
	# Legacy team data remains only as an internal compatibility bridge while RP systems replace it.
	team = "robbers"
	roleplay = true
	Game.stop_music()
	Engine.time_scale = 1.0
	fx = Effects.new()
	fx.world = self
	add_child(fx)
	_setup_env()
	audio_world = WorldAudio.new()
	audio_world.world = self
	add_child(audio_world)
	_load_map()
	await get_tree().physics_frame
	space = get_world_3d().direct_space_state
	_build_route()
	_spawn_lights()
	sky.refresh()
	_spawn_actors()
	Gangs.configure_world(self)
	_businesses_setup()
	_build_bank()
	_build_city_center()
	_setup_rain()
	if not OS.get_cmdline_user_args().has("--nocountry"):
		country = Country.new()
		country.world = self
		add_child(country)
	var amb: Node = load("res://scripts/game3d/ambience.gd").new()
	amb.set("world", self)
	add_child(amb)
	if not OS.get_cmdline_user_args().has("--cine") and not OS.get_cmdline_user_args().has("--nolife"):
		life = StreetLife.new()
		life.world = self
		add_child(life)
	gps = Gps.new()
	gps.world = self
	add_child(gps)
	hud = Hud.new()
	hud.world = self
	add_child(hud)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var args := OS.get_cmdline_user_args()
	if Game.touch and not args.has("--cine"):
		var tc: CanvasLayer = load("res://scripts/game3d/touch_controls.gd").new()
		tc.set("world", self)
		add_child(tc)
	if Online.match_id != "" and not args.has("--cine"):
		net = MatchNet.new()
		net.world = self
		add_child(net)
	if args.has("--touchtest") and ResourceLoader.exists("res://tools/touch_test.gd"):
		var tt: Node = load("res://tools/touch_test.gd").new()
		tt.set("world", self)
		tt.set("out", args[args.find("--touchtest") + 1])
		add_child(tt)
		tt.call("run")
	if args.has("--nettest") and ResourceLoader.exists("res://tools/net_city.gd"):
		var nt: Node = load("res://tools/net_city.gd").new()
		nt.set("world", self)
		add_child(nt)
		nt.call("run")
	if args.has("--cine"):
		sky.set_hour(22.5)
		sky.set_weather(2)
		hud.visible = false
		player.set_active(false)
		var cine: Node = load("res://scripts/game3d/cinematic.gd").new()
		cine.set("world", self)
		add_child(cine)
		cine.call("run")
		return
	var tools := {"--citytour": "city_tour", "--cityprobe": "city_probe", "--drivetest": "drive_test", "--p1tour": "p1_tour", "--p2tour": "p2_tour", "--gfxtour": "gfx_tour", "--lifetour": "life_tour", "--perf": "perf_probe", "--mapinfo": "map_info", "--worldtour": "world_tour", "--gpstest": "gps_test"}
	if args.size() >= 2 and tools.has(args[0]) and ResourceLoader.exists("res://tools/%s.gd" % tools[args[0]]):
		var tour: Node = load("res://tools/%s.gd" % tools[args[0]]).new()
		tour.set("world", self)
		tour.set("out", args[1])
		add_child(tour)
		tour.call("run")


# ---------------------------------------------------------------- environment
func _setup_env() -> void:
	sky = SkyCycle.new()
	sky.world = self
	add_child(sky)


# ---------------------------------------------------------------- map
func _mat_name(mi: MeshInstance3D) -> String:
	var names := ""
	for si in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(si)
		names += (str(m.resource_name) if m else "") + "|"
	return names


func _load_map() -> void:
	var ps: PackedScene = load(MAP_PATH)
	map = ps.instantiate()
	map.scale = Vector3.ONE * MAP_SCALE
	add_child(map)
	var wet := {}
	for mi in map.find_children("*", "MeshInstance3D", true, false):
		var mn := _mat_name(mi) + str(mi.name)
		var hide := false
		for k in HIDE_KEYS:
			if mn.contains(k):
				hide = true
		if hide:
			mi.visible = false
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# roads / pavements get wet in the rain (driven by the sky cycle); foliage sways in the wind
		for si in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(si)
			if m is StandardMaterial3D:
				var nm := str(m.resource_name)
				if nm == "alpha":
					if not wet.has(m):
						wet[m] = _foliage_mat(m)
					mi.set_surface_override_material(si, wet[m])
				elif not wet.has(m):
					wet[m] = true
					if nm.begins_with("road") or nm.begins_with("pave") or nm.begins_with("sand") or nm == "mmm_road":
						sky.wet_mats.append({"mat": m, "col": m.albedo_color})
					else:
						m.roughness = maxf(m.roughness, 0.75)
		var skip := false
		for k in NO_COLLIDE:
			if mn.contains(k):
				skip = true
		if skip:
			continue
		var shape: Shape3D = mi.mesh.create_trimesh_shape()
		if shape:
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
			body.set_meta("surface", mn)
			mi.add_child(body)


func _foliage_mat(src: StandardMaterial3D) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/fx/foliage.gdshader")
	sm.set_shader_parameter("albedo_tex", src.albedo_texture)
	sm.set_shader_parameter("albedo_col", src.albedo_color)
	sky.foliage_mats.append(sm)
	return sm


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	return space.intersect_ray(q)


func _ground(p: Vector3) -> Dictionary:
	return _ray(p + Vector3(0, 60, 0), p + Vector3(0, -120, 0))


func _is_road(hit: Dictionary) -> bool:
	if hit.is_empty():
		return false
	var c = hit.collider
	return c.has_meta("surface") and str(c.get_meta("surface")).contains("road")


func _build_route() -> void:
	var src: MeshInstance3D = null
	for mi in map.find_children("*", "MeshInstance3D", true, false):
		if str(mi.name).contains("CENTER_ROUTE"):
			src = mi
	if src == null:
		return
	var pts: Array = []
	for si in src.mesh.get_surface_count():
		var va: PackedVector3Array = src.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		for v in va:
			var w: Vector3 = src.global_transform * v
			var dup := false
			for p in pts:
				if p.distance_to(w) < 3.0:
					dup = true
					break
			if not dup:
				pts.append(w)
	# order by nearest neighbour
	var ordered: Array = [pts.pop_front()]
	while pts.size() > 0:
		var last: Vector3 = ordered[-1]
		var bi := 0
		var bd := INF
		for i in pts.size():
			var d: float = last.distance_squared_to(pts[i])
			if d < bd:
				bd = d
				bi = i
		ordered.append(pts[bi])
		pts.remove_at(bi)
	# resample every ~8m and snap to ground
	route.clear()
	for i in ordered.size() - 1:
		var a: Vector3 = ordered[i]
		var b: Vector3 = ordered[i + 1]
		if a.distance_to(b) > 400.0:
			continue
		var n := int(ceil(a.distance_to(b) / 8.0))
		for k in n:
			var p := a.lerp(b, float(k) / n)
			var h := _ground(p)
			if not h.is_empty():
				route.append(h.position)
	print("route points: ", route.size())


func _road_edges(p: Vector3, nrm: Vector3) -> Vector2:
	# returns distances to left/right edge of road from p along nrm
	var e := Vector2(6, 6)
	for side in [-1, 1]:
		var d := 1.0
		while d < 24.0:
			var h := _ground(p + nrm * side * d)
			if not _is_road(h):
				break
			d += 1.0
		if side < 0:
			e.x = d
		else:
			e.y = d
	return e


# ---------------------------------------------------------------- street lights
func _spawn_lights() -> void:
	if route.size() < 4:
		return
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.08
	pole_mesh.bottom_radius = 0.12
	pole_mesh.height = 8.0
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.12, 0.13, 0.15)
	pole_mat.metallic = 0.6
	pole_mat.roughness = 0.4
	pole_mesh.material = pole_mat
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(0.12, 0.12, 2.2)
	arm_mesh.material = pole_mat
	var bulb_mesh := BoxMesh.new()
	bulb_mesh.size = Vector3(0.35, 0.12, 0.7)
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bulb_mat.albedo_color = Color(1.0, 0.8, 0.5)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.75, 0.45)
	bulb_mat.emission_energy_multiplier = 4.0
	bulb_mesh.material = bulb_mat
	sky.lamp_mats.append(bulb_mat)
	var last_pos := Vector3(INF, INF, INF)
	var side := 1
	var count := 0
	for i in range(1, route.size() - 1):
		var p: Vector3 = route[i]
		if p.distance_to(last_pos) < 34.0:
			continue
		last_pos = p
		var tan: Vector3 = (route[i + 1] - route[i - 1])
		tan.y = 0
		if tan.length() < 0.01:
			continue
		tan = tan.normalized()
		var nrm := tan.cross(Vector3.UP).normalized()
		var edges := _road_edges(p, nrm)
		var off := (edges.y if side > 0 else edges.x) + 0.8
		var base := p + nrm * side * off
		var g := _ground(base)
		if not g.is_empty():
			base = g.position
		var pole := Node3D.new()
		add_child(pole)
		pole.global_position = base
		pole.look_at(base - nrm * side, Vector3.UP)   # -Z of pole points toward road
		var pm := MeshInstance3D.new()
		pm.mesh = pole_mesh
		pm.position.y = 4.0
		pole.add_child(pm)
		var am := MeshInstance3D.new()
		am.mesh = arm_mesh
		am.position = Vector3(0, 7.9, -1.0)
		pole.add_child(am)
		var bm := MeshInstance3D.new()
		bm.mesh = bulb_mesh
		bm.position = Vector3(0, 7.8, -1.9)
		pole.add_child(bm)
		for lm in [pm, am, bm]:
			lm.visibility_range_end = [220.0, 320.0, 480.0][Q]
			lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var lamp := Lamp.new()
		lamp.world = self
		lamp.bulb = bm
		var lcs := CollisionShape3D.new()
		var lsh := BoxShape3D.new()
		lsh.size = Vector3(0.45, 0.25, 0.8)
		lcs.shape = lsh
		lamp.add_child(lcs)
		bm.add_child(lamp)
		var pcs := StaticBody3D.new()
		var pcol := CollisionShape3D.new()
		var psh := CylinderShape3D.new()
		psh.radius = 0.13
		psh.height = 8.0
		pcol.shape = psh
		pcs.add_child(pcol)
		pm.add_child(pcs)
		if count % [3, 2, 1][Q] == 0:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.72, 0.42)
			l.light_energy = [3.6, 3.2, 3.0][Q]
			l.omni_range = [26.0, 25.0, 24.0][Q]
			l.omni_attenuation = 1.3
			l.position = Vector3(0, 7.4, -1.9)
			l.distance_fade_enabled = true
			l.distance_fade_begin = [60.0, 100.0, 160.0][Q]
			l.distance_fade_length = 30.0
			pole.add_child(l)
			sky.lamps.append(l)
			lamp.light = l
		side = -side
		count += 1
	print("street lights: ", count)


## A street lamp head that can be shot out.
class Lamp extends StaticBody3D:
	var world
	var light: OmniLight3D
	var bulb: MeshInstance3D
	var broken := false

	func take_damage(_amount: float, _attacker = null, _dir := Vector3.ZERO) -> void:
		if broken:
			return
		broken = true
		if light:
			light.set_meta("broken", true)
			light.visible = false
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.08, 0.08, 0.08)
		m.roughness = 0.6
		bulb.material_override = m
		if world:
			world.fx.impact(bulb.global_position, Vector3.DOWN, false)
			world.fx.splash(bulb.global_position - Vector3(0, 0.2, 0))
		Game.play_sfx("glass", randf_range(0.9, 1.1), -4.0)


# ---------------------------------------------------------------- actors
func _route_xf(i: int, lateral: float) -> Transform3D:
	i = clampi(i, 1, route.size() - 2)
	var p: Vector3 = route[i]
	var tan: Vector3 = route[i + 1] - route[i - 1]
	tan.y = 0
	tan = tan.normalized()
	var nrm := tan.cross(Vector3.UP).normalized()
	var pos := p + nrm * lateral
	var g := _ground(pos)
	if not g.is_empty():
		pos = g.position
	var xf := Transform3D(Basis.looking_at(tan, Vector3.UP), pos)
	return xf


const BASES := {
	"cops": {"frac": 0.0, "name": "POLICE HQ", "color": Color(0.3, 0.55, 1.0),
		"cars": [["police_gt500", "POLICE CRUISER", "police"], ["police_gt500", "POLICE INTERCEPTOR", "police"]],
		"weapons": ["glock", "m4", "sniper"]},
	"robbers": {"frac": 0.5, "name": "ROBBER HIDEOUT", "color": Color(1.0, 0.28, 0.4),
		"cars": [["mustang69", "MUSTANG BOSS 302", "robber"], ["mustang_gt", "MUSTANG GT", "robber"], ["mustang_rtr", "MUSTANG RTR", "robber"]],
		"weapons": ["glock", "akm", "rpg", "c4"]},
}
const Weapons = preload("res://scripts/game3d/weapons.gd")

var bases := {}
var pickups: Array = []
var rockets: Array = []
var c4s: Array = []


func _gp(o: Vector3, tan: Vector3, sd: Vector3, along: float, lat: float) -> Vector3:
	var q := o + tan * along + sd * lat
	var g := _ground(q)
	return g.position if not g.is_empty() else q


func _mat(col: Color, emis := 0.0, metal := 0.0, rough := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	if emis > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emis
	return m


func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, basis_: Basis, collide := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	parent.add_child(mi)
	mi.global_transform = Transform3D(basis_, pos)
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


func _build_base(team: String) -> void:
	var cfg: Dictionary = BASES[team]
	var idx := clampi(int(route.size() * float(cfg.frac)) + 40, 2, route.size() - 3)
	var o: Vector3 = route[idx]
	var tan: Vector3 = route[idx + 1] - route[idx - 1]
	tan.y = 0
	tan = tan.normalized()
	var nrm := tan.cross(Vector3.UP).normalized()
	var edges := _road_edges(o, nrm)
	var side := 1.0 if edges.y >= edges.x else -1.0
	var edge := maxf(edges.y if side > 0 else edges.x, 4.5)
	var sd := nrm * side                       # points toward the base side of the road
	var col: Color = cfg.color
	var face := Basis.looking_at(-sd, Vector3.UP)   # objects facing the road
	var along_b := Basis.looking_at(tan, Vector3.UP)
	var root := Node3D.new()
	add_child(root)

	# parked team cars along the curb
	var cars_cfg: Array = cfg.cars
	for i in cars_cfg.size():
		var c := Car.new()
		c.model_path = "res://assets/models/cars/%s.glb" % cars_cfg[i][0]
		c.display_name = cars_cfg[i][1]
		c.kind = cars_cfg[i][2]
		c.world = self
		add_child(c)
		var cp := _gp(o, tan, sd, -16.0 + i * 6.5, edge - 1.5)
		c.global_transform = Transform3D(Basis.looking_at(tan, Vector3.UP), cp + Vector3(0, 0.4, 0))
		cars.append(c)

	# sign pylon with team name
	var sign_pos := _gp(o, tan, sd, 2.0, edge + 0.4)
	_box(root, Vector3(0.5, 6.0, 0.5), _mat(Color(0.1, 0.11, 0.13), 0.0, 0.5, 0.4), sign_pos + Vector3(0, 3.0, 0), face, true)
	_box(root, Vector3(5.2, 1.3, 0.15), _mat(Color(0.03, 0.04, 0.07)), sign_pos + Vector3(0, 5.6, 0) - sd * 0.35, face)
	_box(root, Vector3(5.2, 0.08, 0.17), _mat(col, 6.0), sign_pos + Vector3(0, 4.95, 0) - sd * 0.35, face)
	var lbl := Label3D.new()
	lbl.text = cfg.name
	lbl.font = Game.font_wide
	lbl.font_size = 96
	lbl.pixel_size = 0.009
	lbl.modulate = col.lightened(0.35)
	lbl.outline_size = 0
	root.add_child(lbl)
	lbl.global_transform = Transform3D(Basis.looking_at(sd, Vector3.UP), sign_pos + Vector3(0, 5.65, 0) - sd * 0.45)
	var team_light := OmniLight3D.new()
	team_light.light_color = col
	team_light.light_energy = 1.2
	team_light.omni_range = 12.0
	root.add_child(team_light)
	team_light.global_position = sign_pos + Vector3(0, 4.5, 0) - sd * 2.0
	var flood := SpotLight3D.new()
	flood.light_color = Color(1.0, 0.95, 0.85)
	flood.light_energy = 2.5
	flood.spot_range = 30.0
	flood.spot_angle = 55.0
	root.add_child(flood)
	flood.global_position = sign_pos + Vector3(0, 6.2, 0)
	flood.look_at(_gp(o, tan, sd, -4.0, edge - 4.0), Vector3.UP)

	# armory table
	var tp := _gp(o, tan, sd, 6.5, edge - 1.0)
	var wood := _mat(Color(0.18, 0.16, 0.14), 0.0, 0.2, 0.6)
	_box(root, Vector3(0.9, 0.08, 3.2), wood, tp + Vector3(0, 0.95, 0), along_b, true)
	for lx in [-0.35, 0.35]:
		for lz in [-1.45, 1.45]:
			_box(root, Vector3(0.06, 0.95, 0.06), wood, tp + along_b * Vector3(lx, 0.475, lz), along_b)
	var al := Label3D.new()
	al.text = "ARMORY"
	al.font = Game.font_wide
	al.font_size = 64
	al.pixel_size = 0.006
	al.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	al.modulate = col.lightened(0.4)
	root.add_child(al)
	al.global_position = tp + Vector3(0, 1.9, 0)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.9, 0.75)
	lamp.light_energy = 2.0
	lamp.omni_range = 6.0
	root.add_child(lamp)
	lamp.global_position = tp + Vector3(0, 2.4, 0)
	var wl: Array = cfg.weapons
	for i in wl.size():
		var id: String = wl[i]
		var holder := Node3D.new()
		root.add_child(holder)
		var along := -1.2 + i * (2.4 / maxf(wl.size() - 1, 1))
		holder.global_transform = Transform3D(along_b, tp + along_b * Vector3(0, 1.0, along))
		var wm: Node3D = load(Weapons.DATA[id].path).instantiate()
		holder.add_child(wm)
		# lay the weapon flat on the table, barrel pointing across the table
		if id == "sniper":
			wm.rotation_degrees = Vector3(0, 90, 90)
		elif id == "c4":
			wm.rotation_degrees = Vector3(0, 0, 0)
		else:
			wm.rotation_degrees = Vector3(90, 0, 0)
		wm.position.y = 0.04
		pickups.append({"node": holder, "id": id})
	# body armor vest on a crate next to the table
	var vest := Node3D.new()
	root.add_child(vest)
	vest.global_transform = Transform3D(along_b, tp + along_b * Vector3(1.3, 0.0, 0.0))
	var crate_m := _mat(Color(0.22, 0.24, 0.2), 0.0, 0.1, 0.8)
	_box(vest, Vector3(0.7, 0.7, 0.7), crate_m, vest.global_position + Vector3(0, 0.35, 0), along_b, true)
	var vm := _mat(Color(0.08, 0.1, 0.14), 0.0, 0.0, 0.7)
	_box(vest, Vector3(0.48, 0.55, 0.16), vm, vest.global_position + Vector3(0, 0.98, 0), along_b.rotated(Vector3.UP, PI / 2))
	_box(vest, Vector3(0.3, 0.08, 0.17), _mat(col, 3.0), vest.global_position + Vector3(0, 1.12, 0), along_b.rotated(Vector3.UP, PI / 2))
	var vl := Label3D.new()
	vl.text = "ARMOR"
	vl.font = Game.font_wide
	vl.font_size = 48
	vl.pixel_size = 0.006
	vl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	vl.modulate = Color(0.45, 0.7, 1.0)
	vest.add_child(vl)
	vl.position = Vector3(0, 1.6, 0)
	pickups.append({"node": vest, "id": "armor"})

	# decoration
	if team == "cops":
		for k in 2:
			var g: Node3D = load("res://assets/models/props/swat_guard.glb").instantiate()
			root.add_child(g)
			g.global_transform = Transform3D(face.rotated(Vector3.UP, PI), _gp(o, tan, sd, -1.0 + k * 13.0, edge - 0.6))
		var stripe := _mat(Color(0.95, 0.95, 0.95))
		var blue := _mat(col, 1.5)
		for k in 4:
			var bp := _gp(o, tan, sd, 12.0 + k * 1.6, edge - 4.6)
			_box(root, Vector3(1.4, 0.9, 0.35), stripe, bp + Vector3(0, 0.45, 0), along_b.rotated(Vector3.UP, PI / 2), true)
			_box(root, Vector3(1.42, 0.12, 0.37), blue, bp + Vector3(0, 0.75, 0), along_b.rotated(Vector3.UP, PI / 2))
	else:
		var crate := _mat(Color(0.35, 0.25, 0.15), 0.0, 0.0, 0.9)
		for k in 5:
			var cp2 := _gp(o, tan, sd, 10.0 + (k % 3) * 1.3, edge - 0.4 - (k / 3) * 1.3)
			_box(root, Vector3(1.1, 1.1, 1.1), crate, cp2 + Vector3(0, 0.55 + (1.1 if k == 4 else 0.0), 0), along_b.rotated(Vector3.UP, k * 0.3), true)
		var fire_pos := _gp(o, tan, sd, 0.0, edge - 0.8)
		var barrel := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.3
		cyl.bottom_radius = 0.3
		cyl.height = 0.9
		cyl.material = _mat(Color(0.2, 0.18, 0.16), 0.0, 0.6, 0.5)
		barrel.mesh = cyl
		root.add_child(barrel)
		barrel.global_position = fire_pos + Vector3(0, 0.45, 0)
		var fl := OmniLight3D.new()
		fl.light_color = Color(1.0, 0.5, 0.15)
		fl.light_energy = 3.0
		fl.omni_range = 9.0
		fl.set_meta("flicker", true)
		root.add_child(fl)
		fl.global_position = fire_pos + Vector3(0, 1.3, 0)
		var fire := _fire_particles()
		root.add_child(fire)
		fire.global_position = fire_pos + Vector3(0, 0.9, 0)
		flickers.append(fl)

	# buildings behind the base
	if team == "cops":
		_place_building("res://assets/models/props/police_station.glb", o, tan, sd, 0.0, edge + 42.0, true)
		_place_building("res://assets/models/props/skyscraper.glb", o, tan, sd, 90.0, edge + 95.0, false)
	else:
		_place_building("res://assets/models/props/skyscraper.glb", o, tan, sd, -40.0, edge + 80.0, false)
		_place_building("res://assets/models/props/skyscraper.glb", o, tan, sd, 50.0, edge + 110.0, false, PI * 0.5)

	var spawn := _gp(o, tan, sd, 0.0, edge - 4.0) + Vector3(0, 0.3, 0)
	poi.append({"name": "HQ" if team == "cops" else "HIDEOUT", "pos": spawn, "color": col})
	bases[team] = {"pos": spawn, "yaw": atan2(-tan.x, -tan.z), "color": col, "name": cfg.name, "sign": sign_pos}


var flickers: Array = []
var _soft: GradientTexture2D


func _soft_tex() -> GradientTexture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.4, Color(1, 1, 1, 0.55))
		_soft = GradientTexture2D.new()
		_soft.gradient = g
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(0.5, 0.0)
		_soft.width = 64
		_soft.height = 64
	return _soft


func _place_building(path: String, o: Vector3, tan: Vector3, sd: Vector3, along: float, lat: float, collide: bool, extra_rot := 0.0) -> void:
	if not ResourceLoader.exists(path):
		return
	var center := o + tan * along + sd * lat
	var hs: Array = []
	for off in [Vector3.ZERO, tan * 20.0, -tan * 20.0, sd * 20.0, -sd * 20.0]:
		var g := _ground(center + off)
		if not g.is_empty():
			hs.append(g.position.y)
	var y := o.y
	if hs.size() > 0:
		hs.sort()
		y = hs[0] - 0.3
	var b: Node3D = load(path).instantiate()
	add_child(b)
	b.global_transform = Transform3D(Basis.looking_at(-sd, Vector3.UP).rotated(Vector3.UP, extra_rot), Vector3(center.x, y, center.z))
	for mi in b.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = [500.0, 900.0, 1600.0][Q]
		if collide:
			var sh: Shape3D = mi.mesh.create_trimesh_shape()
			if sh:
				var sb := StaticBody3D.new()
				var cs := CollisionShape3D.new()
				cs.shape = sh
				sb.add_child(cs)
				mi.add_child(sb)


func _fire_particles() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.8
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.2
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0, 1.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.8, 0.3, 1.0))
	ramp.set_color(1, Color(0.6, 0.1, 0.0, 0.0))
	p.color_ramp = ramp
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = _soft_tex()
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.mesh = q
	return p


func _spawn_actors() -> void:
	_build_base("cops")
	_build_base("robbers")
	var b: Dictionary = bases[team]
	spawn_xf = Transform3D(Basis(Vector3.UP, b.yaw), b.pos)
	player = Player.new()
	player.world = self
	player.cop_team = team == "cops"
	add_child(player)
	player.global_transform = spawn_xf
	player.yaw = b.yaw
	player.cam.current = true


func _businesses_setup() -> void:
	businesses = CityBusinesses.new()
	businesses.world = self
	add_child(businesses)


# ---------------------------------------------------------------- city centre
func _build_city_center() -> void:
	# the centre of the race route is the middle of the map
	if route.is_empty():
		return
	var mn := Vector3(INF, 0, INF)
	var mx := Vector3(-INF, 0, -INF)
	for p in route:
		mn = mn.min(p)
		mx = mx.max(p)
	var mid := (mn + mx) * 0.5
	# street level: the median height of the route; the centre must be flat, near that level and near the middle
	var ys: Array = []
	for p in route:
		ys.append(p.y)
	ys.sort()
	var ref: float = ys[ys.size() / 2]
	var best_s := INF
	var c := mid
	var step := 20.0
	var half := maxf(mx.x - mn.x, mx.z - mn.z) * 0.35
	for ix in range(-int(half / step), int(half / step) + 1):
		for iz in range(-int(half / step), int(half / step) + 1):
			# start the ground ray at street level so it reaches the terrain of the centre
			var cand := Vector3(mid.x + ix * step, ref, mid.z + iz * step)
			var score := 0.0
			var ok := true
			for gx in [-50.0, 0.0, 50.0]:
				for gz in [-50.0, 0.0, 50.0]:
					var g := _ground(cand + Vector3(gx, 0, gz))
					if g.is_empty():
						ok = false
						break
					score += absf(g.position.y - ref) * 3.0
				if not ok:
					break
			if not ok:
				continue
			for bs in bases.values():
				if cand.distance_to(bs.pos) < 170.0:
					ok = false
			if not ok:
				continue
			score += cand.distance_to(mid) * 0.05
			if score < best_s:
				best_s = score
				c = cand
	var gc := _ground(c + Vector3(0, 0, 0))
	if not gc.is_empty():
		c.y = gc.position.y
	print("city centre search score ", best_s)
	var cc := CityCenter.new()
	cc.world = self
	add_child(cc)
	cc.global_transform = Transform3D(Basis(), c + Vector3(0, 0.05, 0))
	# the garage sits east of the plaza, so the cleared area reaches that far
	_clear_map_area(cc.global_transform, Rect2(-66, -66, 176, 132))
	cc.build()
	poi.append({"name": "CITY CENTER", "pos": c, "color": Color(0.4, 0.9, 1.0)})
	print("city centre at ", c)


# ---------------------------------------------------------------- bank
func _build_bank() -> void:
	# choose the flattest spot along the route, away from both bases
	var best_score := INF
	var best := {}
	for k in 24:
		var idx := clampi(int(route.size() * (0.12 + k * 0.03)), 3, route.size() - 4)
		var o: Vector3 = route[idx]
		var far_ok := true
		for b in bases.values():
			if o.distance_to(b.pos) < 160.0:
				far_ok = false
		if not far_ok:
			continue
		var tan: Vector3 = route[idx + 1] - route[idx - 1]
		tan.y = 0
		tan = tan.normalized()
		var nrm := tan.cross(Vector3.UP).normalized()
		var edges := _road_edges(o, nrm)
		for side in [1.0, -1.0]:
			var edge := maxf(edges.y if side > 0 else edges.x, 4.5)
			var sd: Vector3 = nrm * side
			var base_y := o.y
			var score := 0.0
			var center := o + sd * (edge + 33.0)
			for gx in [-36.0, -18.0, 0.0, 18.0, 40.0]:
				for gz in [-28.0, -10.0, 10.0, 28.0]:
					var p: Vector3 = center + tan * gx - sd * gz
					var g := _ground(p + Vector3(0, 60, 0))
					if g.is_empty():
						score += 400.0      # off the map
						continue
					var h: float = g.position.y
					score += maxf(h - base_y, 0.0) * 3.0 + minf(maxf(base_y - h, 0.0), 30.0) * 0.5
			if score < best_score:
				best_score = score
				best = {"o": o, "tan": tan, "sd": sd, "edge": edge}
	if best.is_empty():
		return
	bank = Bank.new()
	bank.world = self
	add_child(bank)
	var sd2: Vector3 = best.sd
	var tan2: Vector3 = best.tan
	var origin: Vector3 = best.o + sd2 * (best.edge + 33.0)
	origin.y = best.o.y + 0.05
	# local +Z faces the road, local +X along the road
	var bz := -sd2
	var bx := Vector3.UP.cross(bz).normalized()
	bank.global_transform = Transform3D(Basis(bx, Vector3.UP, bz), origin)
	_clear_map_area(bank.global_transform, Rect2(-46, -34, 92, 72))
	bank.build()
	cars.append_array(bank.spawn_cars(self))
	bank.spawn_npcs(self)
	npcs.append_array(bank.npcs)
	poi.append({"name": "BANK", "pos": origin, "color": Color(1.0, 0.8, 0.3)})
	print("bank at ", origin, " score ", best_score)


func _clear_map_area(xf: Transform3D, r: Rect2) -> void:
	# hide map props/buildings standing on the bank lot
	var inv := xf.affine_inverse()
	var n := 0
	for mi in map.find_children("*", "MeshInstance3D", true, false):
		if not mi.visible:
			continue
		var ab: AABB = mi.global_transform * mi.get_aabb()
		if ab.size.x > 130.0 or ab.size.z > 130.0:
			continue
		var c: Vector3 = inv * ab.get_center()
		if r.has_point(Vector2(c.x, c.z)) and c.y > -6.0:
			mi.visible = false
			for b in mi.find_children("*", "StaticBody3D", true, false):
				b.queue_free()
			n += 1
	print("cleared map meshes on bank lot: ", n)


# ---------------------------------------------------------------- player life
func respawn_player() -> void:
	if active_car and player.dead:
		active_car = null
	player.global_transform = spawn_xf
	player.velocity = Vector3.ZERO
	player.yaw = spawn_xf.basis.get_euler().y
	if player.dead:
		player.revive()
		player.set_active(true)
		_end_spectate()
		if hud:
			hud.hide_wasted()
	player.cam.current = true


func on_player_died(p, attacker) -> void:
	if active_car:
		active_car = null
	p.set_active(true)
	p.visible = true
	Engine.time_scale = 0.3
	get_tree().create_timer(2.6, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)
	Game.play_sfx("whoosh", 0.5, -2.0)
	if hud:
		hud.show_wasted(attacker == p)
	if net:
		net.send_death(str(attacker.uid) if attacker != null and attacker.get("uid") != null else "")
	spec_cam = Camera3D.new()
	spec_cam.fov = 55.0
	spec_cam.far = p.cam.far
	add_child(spec_cam)
	spec_cam.global_position = p.cam.global_position
	spec_cam.current = true
	spec_target = p
	spec_index = -1
	spec_t = 0.0


func teammates() -> Array:
	return net.teammates() if net else []


func spectate_next(step: int) -> void:
	var tm := teammates()
	if tm.is_empty():
		spec_target = player
		return
	spec_index = (spec_index + step + tm.size()) % tm.size()
	spec_target = tm[spec_index]


func _end_spectate() -> void:
	if spec_cam:
		spec_cam.queue_free()
		spec_cam = null
	spec_target = null
	Engine.time_scale = 1.0


func _spectate_tick(delta: float) -> void:
	if spec_cam == null:
		return
	spec_t += delta
	if spec_target == null or not is_instance_valid(spec_target):
		spec_target = player
	var tp: Vector3 = spec_target.global_position + Vector3(0, 1.0, 0)
	var ang: float = spec_t * (0.25 if spec_target == player else 0.0) + player.yaw
	var dist := lerpf(2.5, 6.5, clampf(spec_t / 4.0, 0.0, 1.0))
	var h := lerpf(1.2, 3.2, clampf(spec_t / 4.0, 0.0, 1.0))
	var want := tp + Vector3(sin(ang) * dist, h, cos(ang) * dist)
	spec_cam.global_position = spec_cam.global_position.lerp(want, 1.0 - exp(-delta * 3.0))
	spec_cam.look_at(tp, Vector3.UP)


func kill_driver(car, attacker) -> void:
	if car == active_car and player:
		var pos: Vector3 = car.global_position - car.global_transform.basis.x * 2.2 + Vector3(0, 0.6, 0)
		car.exit_car()
		active_car = null
		player.global_position = pos
		player.velocity = Vector3(0, 4.0, 0)
		player.set_active(true)
		player.die(attacker)


# ---------------------------------------------------------------- combat
func alert(pos: Vector3, radius: float, attacker) -> void:
	if life:
		life.panic(pos, radius * 1.5)
	for n in npcs:
		if is_instance_valid(n) and n.global_position.distance_to(pos) < radius:
			n.alert(pos, attacker if attacker == player else null)


func fire_bullet(shooter, origin: Vector3, dir: Vector3, muzzle: Vector3, dmg: float) -> Vector3:
	if shooter == player:
		var territory := Gangs.territory_at(player.global_position)
		Security.record_player_shot(str(territory.get("id", "")))
	if audio_world:
		audio_world.play_gunshot(muzzle, shooter.current if shooter and shooter.get("current") != null else "shot_pistol")
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 600.0)
	q.collision_mask = 1 | 2 | 8 | 16
	var ex: Array[RID] = [shooter.get_rid()]
	if shooter == player and active_car:
		ex.append(active_car.get_rid())
	q.exclude = ex
	var hit := space.intersect_ray(q)
	var end := origin + dir * 250.0
	if not hit.is_empty():
		end = hit.position
		var c = hit.collider
		if c is RigidBody3D:
			c.sleeping = false
			c.apply_impulse(dir * 6.0, hit.position - c.global_position)
		var flesh: bool = c is CharacterBody3D and c.has_method("take_damage") and not c.has_method("enter")
		if c != null and c.has_method("take_damage"):
			var d := dmg
			if flesh:
				var hy: float = hit.position.y - c.global_position.y
				if hy > 1.5 and int(c.get("stance") if c.get("stance") != null else 0) == 0:
					d *= 2.5     # headshot
				c.take_damage(d, shooter, dir)
				if c.has_method("push"):
					c.push(dir * 0.8)
			else:
				c.take_damage(d * 0.3, shooter, dir)
		if not flesh:
			fx.impact(hit.position, hit.normal, false)
	fx.tracer(muzzle, end)
	if shooter == player:
		alert(origin, 40.0, player)
		if not hit.is_empty():
			alert(hit.position, 12.0, player)
		if net:
			net.send_shot(muzzle, end, player.current)
	return end


func melee(attacker, pos: Vector3, dir: Vector3, rng: float, dmg: float) -> void:
	var targets: Array = npcs.duplicate()
	if attacker != player:
		targets.append(player)
	elif net:
		targets.append_array(net.remotes.values())
	var hit_any := false
	for t in targets:
		if not is_instance_valid(t) or t == attacker or t.get("dead") == true:
			continue
		var to: Vector3 = t.global_position + Vector3(0, 1.2, 0) - pos
		if to.length() < rng + 0.3 and dir.dot(Vector3(to.x, 0, to.z).normalized()) > 0.4:
			t.take_damage(dmg, attacker, dir)
			t.push(dir * 2.5)
			hit_any = true
	if hit_any:
		Game.play_sfx("click", 0.5, -2.0)
	alert(pos, 15.0, attacker)


func burn_damage(pos: Vector3, r: float, dmg: float) -> void:
	for n in npcs:
		if is_instance_valid(n) and n.global_position.distance_to(pos) < r:
			n.take_damage(dmg, null, Vector3.UP)
	if player and player.active and not player.dead and player.global_position.distance_to(pos) < r:
		player.take_damage(dmg, null, Vector3.UP)


func explode(pos: Vector3, radius: float, attacker = null, ignore = null, _broadcast := true) -> void:
	fx.explosion(pos, radius)
	var cam := current_camera()
	var dist := cam.global_position.distance_to(pos) if cam else 30.0
	Game.play_sfx("explosion", randf_range(0.9, 1.05), clampf(4.0 - dist * 0.12, -24.0, 4.0))
	var rr := radius * 1.25
	for n in npcs:
		if not is_instance_valid(n):
			continue
		var d: float = n.global_position.distance_to(pos)
		if d < rr:
			var f := 1.0 - d / rr
			n.take_damage(170.0 * f, attacker, (n.global_position - pos).normalized())
			n.push(((n.global_position - pos).normalized() * 9.0 + Vector3(0, 4.0, 0)) * f)
	var all_cars: Array = cars.duplicate()
	if life:
		all_cars.append_array(life.traffic_cars())
	for c in all_cars:
		if c == ignore or not is_instance_valid(c):
			continue
		var d2: float = c.global_position.distance_to(pos)
		if d2 < radius:
			var f2 := 1.0 - d2 / radius
			var away: Vector3 = c.global_position - pos
			away.y = 0
			c.push(away.normalized() * 10.0 * f2 + Vector3(0, 7.0 * f2, 0))
			c.take_damage(150.0 * f2 + 10.0, attacker)
	if player and player.active and not player.dead:
		var d3: float = player.global_position.distance_to(pos)
		if d3 < rr:
			var f3 := 1.0 - d3 / rr
			player.push(((player.global_position - pos).normalized() * 8.0 + Vector3(0, 5.0, 0)) * f3)
			player.take_damage(150.0 * f3, attacker, (player.global_position - pos).normalized())
	if player:
		player._shake = maxf(player._shake, clampf(3.0 - dist * 0.06, 0.0, 3.0))
	alert(pos, 70.0, attacker)


func fire_rocket(pos: Vector3, dir: Vector3, exclude: RID, shooter = null) -> void:
	var r := Node3D.new()
	add_child(r)
	r.global_position = pos
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.05
	cm.height = 0.5
	cm.material = _mat(Color(0.25, 0.3, 0.2), 0.0, 0.4, 0.5)
	mi.mesh = cm
	mi.rotation_degrees = Vector3(90, 0, 0)
	r.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.2)
	l.light_energy = 3.0
	l.omni_range = 8.0
	r.add_child(l)
	var smoke := _fire_particles()
	smoke.amount = 60
	smoke.lifetime = 1.4
	smoke.local_coords = false
	smoke.color_ramp.set_color(0, Color(1.0, 0.7, 0.3, 0.9))
	smoke.color_ramp.set_color(1, Color(0.45, 0.45, 0.45, 0.0))
	r.add_child(smoke)
	r.look_at(pos + dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
	var ex: Array[RID] = [exclude]
	if shooter == player and active_car:
		ex.append(active_car.get_rid())
	rockets.append({"node": r, "vel": dir * 70.0, "life": 4.0, "ex": ex, "shooter": shooter})
	if shooter == player and net:
		net.send_rocket(pos, dir)


func nearest_pickup(maxd: float):
	var best = null
	var bd := maxd
	for pk in pickups:
		var d: float = (pk.node.global_position + (Vector3(0, 1.0, 0) if pk.id == "armor" else Vector3.ZERO)).distance_to(player.global_position + Vector3(0, 1.0, 0))
		if d < bd:
			bd = d
			best = pk
	return best


func place_c4(origin: Vector3, dir: Vector3, exclude: RID):
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 6.0)
	q.exclude = [exclude]
	var hit := space.intersect_ray(q)
	var pos: Vector3
	var n := Vector3.UP
	if hit.is_empty():
		var g := _ground(player.global_position - player.global_transform.basis.z * 1.0)
		if g.is_empty():
			return null
		pos = g.position
	else:
		pos = hit.position
		n = hit.normal
	var c: Node3D = load(Weapons.DATA.c4.path).instantiate()
	add_child(c)
	c.global_position = pos + n * 0.05
	var bl := OmniLight3D.new()
	bl.light_color = Color(1, 0.05, 0.05)
	bl.omni_range = 2.0
	bl.light_energy = 0.0
	c.add_child(bl)
	bl.position = Vector3(0, 0.12, 0)
	c4s.append(bl)
	return c

func _physics_process(delta: float) -> void:
	for i in range(rockets.size() - 1, -1, -1):
		var rk: Dictionary = rockets[i]
		var n: Node3D = rk.node
		rk.life -= delta
		var a := n.global_position
		var b: Vector3 = a + rk.vel * delta
		var q := PhysicsRayQueryParameters3D.create(a, b)
		q.collision_mask = 1 | 2 | 8
		q.exclude = rk.ex
		var hit := space.intersect_ray(q)
		if not hit.is_empty() or rk.life <= 0.0:
			var hp_: Vector3 = hit.position if not hit.is_empty() else a
			if not hit.is_empty():
				hp_ += hit.normal * 0.3
				if hit.collider != null and hit.collider.has_method("explode_car"):
					hit.collider.take_damage(1000.0, rk.shooter)
			explode(hp_, 10.0, rk.shooter)
			n.queue_free()
			rockets.remove_at(i)
		else:
			n.global_position = b


func respawn_car(c) -> void:
	var best := 0
	var bd := INF
	for i in route.size():
		var d: float = c.global_position.distance_squared_to(route[i])
		if d < bd:
			bd = d
			best = i
	c.global_transform = _route_xf(best, 0.0).translated(Vector3(0, 1.0, 0))
	c.velocity = Vector3.ZERO
	c.speed = 0.0


func reset_vehicle() -> void:
	if active_car:
		respawn_car(active_car)


# ---------------------------------------------------------------- rain
func _setup_rain() -> void:
	rain = GPUParticles3D.new()
	rain.amount = [1200, 2500, 5000][Q]
	rain.lifetime = 1.4
	rain.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(28, 1, 28)
	pm.direction = Vector3(0.15, -1, 0)
	pm.spread = 2.0
	pm.initial_velocity_min = 20.0
	pm.initial_velocity_max = 26.0
	pm.gravity = Vector3(0, -9.8, 0)
	rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.018, 0.7)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.82, 1.0, 0.28)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	q.material = m
	rain.draw_pass_1 = q
	rain.local_coords = false
	add_child(rain)
	rain.amount_ratio = 0.0


func current_camera() -> Camera3D:
	return get_viewport().get_camera_3d()


func _notification(what: int) -> void:
	# Windows key / alt-tab: release the mouse, keep the game fullscreen, recapture on return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if not get_tree().paused and (hud == null or not hud.blocks_mouse()):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_d: float) -> void:
	Driving.update_vehicle(self, _d)
	_spectate_tick(_d / maxf(Engine.time_scale, 0.01))
	var c := current_camera()
	if c and rain:
		rain.global_position = c.global_position + Vector3(0, 16, 0)
		rain.visible = sky.rain > 0.02 and not (bank and bank.is_inside(c.global_position))
	var tt := Time.get_ticks_msec() / 1000.0
	for fl in flickers:
		fl.light_energy = 2.4 + sin(tt * 13.0) * 0.4 + sin(tt * 7.3) * 0.5 + randf() * 0.3
	for bl in c4s:
		if is_instance_valid(bl):
			bl.light_energy = 3.0 if fmod(tt, 1.0) < 0.12 else 0.0


# ---------------------------------------------------------------- interaction
func nearest_car(maxd: float):
	var best = null
	var bd := maxd
	var list: Array = cars
	if life and net == null:
		list = cars + life.traffic_cars()
	for c in list:
		if not is_instance_valid(c) or c.wrecked:
			continue
		var d: float = c.global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = c
	return best


func near_switch() -> bool:
	return bank != null and active_car == null and player.global_position.distance_to(bank.switch_world()) < 1.8


func interact() -> void:
	if near_switch():
		bank.toggle_lights()
		return
	if businesses and active_car == null and businesses.interact(player.global_position):
		return
	if active_car == null:
		var pk = nearest_pickup(1.9)
		if pk:
			if pk.id == "armor":
				player.give_armor()
				if hud:
					hud.notify("BODY ARMOR EQUIPPED")
				return
			player.give_weapon(pk.id)
			if hud:
				hud.notify("PICKED UP  " + str(Weapons.DATA[pk.id].name))
			return
	toggle_car()


func toggle_car() -> void:
	if player.dead:
		return
	if active_car == null:
		var c = nearest_car(4.5)
		if c and c.net_driver != "":
			if hud:
				hud.notify("SOMEONE IS DRIVING THIS CAR")
			return
		if c and c.traffic and life:
			life.carjack(c)
			if hud:
				hud.notify("YOU TOOK THE CAR")
		if c and not c.wrecked:
			active_car = c
			last_car = c
			player.set_active(false)
			c.enter(player)
	else:
		var c = active_car
		var side: Vector3 = -c.global_transform.basis.x
		var pos: Vector3 = c.global_position + side * 2.4 + Vector3(0, 1.0, 0)
		var g := _ground(pos)
		if not g.is_empty():
			pos = g.position + Vector3(0, 0.2, 0)
		c.exit_car()
		active_car = null
		player.global_position = pos
		player.velocity = Vector3.ZERO
		player.yaw = c.rotation.y
		player.set_active(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E and not get_tree().paused:
			interact()
		elif event.physical_keycode == KEY_F5 and not get_tree().paused:
			if active_car:
				reset_vehicle()
			elif not player.dead:
				respawn_player()


func back_to_lobby() -> void:
	Input.emulate_mouse_from_touch = true
	if net:
		net.leave()
	Engine.time_scale = 1.0
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main.tscn")
