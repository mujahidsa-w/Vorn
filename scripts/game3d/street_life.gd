extends Node3D
## Life in the city streets:
##  - traffic cars that drive in their lane, slow for curves, brake for obstacles and stop at red lights
##  - traffic signals with crosswalks, and pedestrians who cross while the light is red
##  - pedestrians walking along the roadside (they flee from gunfire, can be run over)
##  - street props (bins, cones, bags, hydrants, benches, newspaper boxes, litter, puddles)
## Everything is streamed in and out around the player in chunks along the road, so the
## cost stays the same however big the map is.

const Car = preload("res://scripts/game3d/car.gd")
const Npc = preload("res://scripts/game3d/npc.gd")

const STEP := 8.0              # metres between route points
const CHUNK := 20              # route points per prop chunk (~160 m)
const PAINTS := [Color(0.85, 0.86, 0.88), Color(0.55, 0.57, 0.6), Color(0.05, 0.05, 0.06), Color(0.08, 0.13, 0.3),
	Color(0.45, 0.04, 0.04), Color(0.25, 0.26, 0.28), Color(0.62, 0.55, 0.42), Color(0.06, 0.2, 0.12), Color(0.9, 0.9, 0.86)]
const MODELS := ["mustang_gt", "mustang_rtr", "mustang69"]

var world
var Q := 1
var route: Array = []
var n := 0
var _edges := {}               # route index -> Vector2(left, right) road half widths
var player_i := 0
var traffic: Array = []        # {car, dir, i, vmax, stuck, panic, honk}
var peds: Array = []           # Npc nodes
var signals: Array = []        # {i, pos}
var phase := 0                 # 0 green, 1 yellow, 2 red (for the road traffic)
var phase_t := 0.0
var chunks := {}               # chunk id -> {node, rigid: Array}
var max_cars := 6
var max_peds := 8
var _t := 0.0
var _spawn_t := 0.0
var _beam_t := 0.0
var mat_lens := []             # [red, yellow, green]
var puddle_mat: StandardMaterial3D
var _m := {}


func _ready() -> void:
	Q = clampi(int(Game.settings.quality), 0, 2)
	route = world.route
	n = route.size()
	max_cars = [4, 6, 9][Q]
	max_peds = [4, 7, 11][Q]
	if Game.touch:
		max_cars = mini(max_cars, 4)
		max_peds = mini(max_peds, 5)
	_make_materials()
	if n > 40:
		_build_signals()


# ---------------------------------------------------------------- route helpers
func _tan(i: int) -> Vector3:
	i = clampi(i, 1, n - 2)
	var t: Vector3 = route[i + 1] - route[i - 1]
	t.y = 0
	return t.normalized() if t.length() > 0.001 else Vector3.FORWARD


func _nrm(i: int) -> Vector3:
	return _tan(i).cross(Vector3.UP).normalized()


func edges(i: int) -> Vector2:
	i = clampi(i, 1, n - 2)
	if not _edges.has(i):
		var e: Vector2 = world._road_edges(route[i], _nrm(i))
		_edges[i] = Vector2(clampf(e.x, 2.5, 14.0), clampf(e.y, 2.5, 14.0))
	return _edges[i]


func lane_lat(i: int, dir: int) -> float:
	var e := edges(i)
	return clampf((e.y if dir > 0 else e.x) * 0.5, 1.9, 3.6) * (1.0 if dir > 0 else -1.0)


func _lane_point(i: int, dir: int) -> Vector3:
	i = clampi(i, 1, n - 2)
	return route[i] + _nrm(i) * lane_lat(i, dir)


func nearest_index(p: Vector3, guess: int) -> int:
	var best := clampi(guess, 0, n - 1)
	var bd: float = p.distance_squared_to(route[best])
	for k in range(maxi(0, guess - 40), mini(n, guess + 41)):
		var d: float = p.distance_squared_to(route[k])
		if d < bd:
			bd = d
			best = k
	if bd > 90.0 * 90.0:
		for k in n:
			var d2: float = p.distance_squared_to(route[k])
			if d2 < bd:
				bd = d2
				best = k
	return best


func _sidewalk(i: int, side: int, extra := 1.6) -> Variant:
	# a walkable point beside the road, or null when there is no flat ground there
	i = clampi(i, 1, n - 2)
	var e := edges(i)
	var p: Vector3 = route[i] + _nrm(i) * side * ((e.y if side > 0 else e.x) + extra)
	var g: Dictionary = world._ground(p)
	if g.is_empty():
		return null
	if absf(g.position.y - route[i].y) > 1.2 or g.normal.y < 0.8:
		return null
	return g.position


# ---------------------------------------------------------------- materials
func _mat(key: String, col: Color, rough := 0.7, metal := 0.0, emis := 0.0) -> StandardMaterial3D:
	if _m.has(key):
		return _m[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if emis > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emis
	_m[key] = m
	return m


func _make_materials() -> void:
	_vc_mat = StandardMaterial3D.new()
	_vc_mat.vertex_color_use_as_albedo = true
	_vc_mat.roughness = 0.55
	_vc_mat.metallic = 0.15
	for c in [Color(1.0, 0.08, 0.05), Color(1.0, 0.65, 0.05), Color(0.1, 1.0, 0.4)]:
		var m := StandardMaterial3D.new()
		m.albedo_color = c * 0.25
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.0
		mat_lens.append(m)
	puddle_mat = StandardMaterial3D.new()
	puddle_mat.albedo_color = Color(0.05, 0.06, 0.07, 0.0)
	puddle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puddle_mat.roughness = 0.02
	puddle_mat.metallic = 0.3
	puddle_mat.metallic_specular = 1.0
	puddle_mat.render_priority = -1
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.55, Color(1, 1, 1, 0.9))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	puddle_mat.albedo_texture = gt


## Merges many small primitive meshes into one mesh per material, so a whole prop or traffic
## signal costs one draw call instead of ten. Plain colours become vertex colours.
class Baker:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	func add(mesh: Mesh, xf: Transform3D, col: Color) -> void:
		var arr := mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var uv = arr[Mesh.ARRAY_TEX_UV]
		var ii = arr[Mesh.ARRAY_INDEX]
		var base := verts.size()
		var nb := xf.basis.inverse().transposed()
		for k in v.size():
			verts.append(xf * v[k])
			norms.append((nb * nn[k]).normalized())
			uvs.append(uv[k] if uv != null and k < uv.size() else Vector2.ZERO)
			cols.append(col)
		if ii == null or ii.is_empty():
			for k in v.size():
				idx.append(base + k)
		else:
			for k in ii:
				idx.append(base + k)

	func build() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


var _batch = null              # Dictionary material key -> Baker while batching
var _batch_xf := Transform3D()
var _baked := {}               # prop type -> {material key: ArrayMesh}
var _vc_mat: StandardMaterial3D


func _begin() -> void:
	_batch = {}
	_batch_xf = Transform3D()


func _finish() -> Dictionary:
	var out := {}
	for k in _batch:
		out[k] = _batch[k].build()
	_batch = null
	return out


func _instance(parent: Node3D, baked: Dictionary, range_end := -1.0) -> void:
	for k in baked:
		var mi := MeshInstance3D.new()
		mi.mesh = baked[k]
		mi.material_override = _vc_mat if str(k) == "vc" else k
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = range_end if range_end > 0.0 else [70.0, 100.0, 150.0][Q]
		mi.visibility_range_end_margin = 8.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF if Q > 0 else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		parent.add_child(mi)


## Builds a prop from primitives once, then reuses the merged mesh for every copy.
func _proto(parent: Node3D, key: String, builder: Callable) -> void:
	if not _baked.has(key):
		_begin()
		builder.call()
		_baked[key] = _finish()
	_instance(parent, _baked[key])


func _mesh(parent: Node3D, mesh: Mesh, xf: Transform3D, mat: Material) -> MeshInstance3D:
	if _batch != null:
		var sm := mat as StandardMaterial3D
		var key = mat if (sm == null or sm.emission_enabled or sm.albedo_texture != null or sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED) else "vc"
		if not _batch.has(key):
			_batch[key] = Baker.new()
		_batch[key].add(mesh, _batch_xf * xf, sm.albedo_color if sm else Color.WHITE)
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = [70.0, 100.0, 150.0][Q]
	mi.visibility_range_end_margin = 8.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF if Q > 0 else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	parent.add_child(mi)
	return mi


func _box(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = sz
	return b


func _cyl(r_top: float, r_bot: float, h: float, seg := 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


# ---------------------------------------------------------------- traffic signals
func _build_signals() -> void:
	var i := 30
	while i < n - 30:
		var bend := _tan(i - 3).angle_to(_tan(i + 3))
		var near_base := false
		var near_bank := false
		if bend < 0.1 and not near_base and not near_bank and route[i].distance_to(route[i - 6]) > 40.0:
			_signal(i)
			i += 38
		else:
			i += 3
	print("traffic signals: ", signals.size())


func _signal(i: int) -> void:
	var node := Node3D.new()
	add_child(node)
	var tan := _tan(i)
	var nrm := _nrm(i)
	var e := edges(i)
	var pole_m := _mat("pole", Color(0.16, 0.17, 0.18), 0.45, 0.7)
	var head_m := _mat("sighead", Color(0.06, 0.06, 0.05), 0.5, 0.2)
	var white := _mat("zebra", Color(0.92, 0.92, 0.9), 0.65)
	var lens := SphereMesh.new()
	lens.radius = 0.12
	lens.height = 0.12
	lens.radial_segments = 10
	lens.rings = 4
	_begin()
	for side in [1, -1]:
		var base: Vector3 = route[i] + nrm * side * ((e.y if side > 0 else e.x) + 0.6)
		var g: Dictionary = world._ground(base)
		if not g.is_empty():
			base = g.position
		var face: Vector3 = -tan * side            # lights face the oncoming traffic of this lane
		var b := Basis.looking_at(face, Vector3.UP)
		_batch_xf = Transform3D(b, base)
		_mesh(null, _cyl(0.07, 0.09, 5.4), Transform3D(Basis(), Vector3(0, 2.7, 0)), pole_m)
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.12
		sh.height = 5.4
		cs.shape = sh
		cs.position = base + Vector3(0, 2.7, 0)
		sb.add_child(cs)
		node.add_child(sb)
		var arm_len := 2.6
		# the arm reaches out over the lane, toward the middle of the road
		var arm_dir: Vector3 = b.inverse() * (-nrm * side)
		_mesh(null, _box(Vector3(0.09, 0.09, arm_len)), Transform3D(Basis.looking_at(arm_dir, Vector3.UP), Vector3(0, 5.25, 0) + arm_dir * arm_len * 0.5), pole_m)
		for hp in [Vector3(0, 3.0, 0.12), Vector3(0, 4.62, 0) + arm_dir * (arm_len - 0.2)]:
			_mesh(null, _box(Vector3(0.36, 1.05, 0.26)), Transform3D(Basis(), hp), head_m)
			for k in 3:
				_mesh(null, lens, Transform3D(Basis(), hp + Vector3(0, 0.32 - k * 0.32, -0.14)), mat_lens[k])
	_instance(node, _finish(), 320.0)
	# zebra crossing across the whole road
	_begin()
	var w := e.x + e.y
	var stripes := int(w / 1.1)
	var q := QuadMesh.new()
	q.size = Vector2(0.55, 3.2)
	q.orientation = PlaneMesh.FACE_Y
	for k in stripes:
		var lat := -e.x + 0.55 + k * 1.1
		var p: Vector3 = route[i] + nrm * lat
		var g2: Dictionary = world._ground(p)
		if g2.is_empty():
			continue
		var up: Vector3 = g2.normal
		_mesh(null, q, Transform3D(Basis(nrm, up, nrm.cross(up).normalized()).orthonormalized(), g2.position + up * 0.03), white)
	_instance(node, _finish(), 160.0)
	signals.append({"i": i, "pos": route[i]})


func _set_phase(p: int) -> void:
	phase = p
	for k in 3:
		var on := (k == 0 and p == 2) or (k == 1 and p == 1) or (k == 2 and p == 0)
		mat_lens[k].emission_energy_multiplier = 3.0 if on else 0.0
	if p == 2:
		_spawn_crossers()


# ---------------------------------------------------------------- update
func _physics_process(delta: float) -> void:
	if n < 40 or world.player == null:
		return
	_t += delta
	var focus: Vector3 = world.player.global_position
	if world.active_car:
		focus = world.active_car.global_position
	player_i = nearest_index(focus, player_i)
	# lights: 16 s green, 3 s yellow, 11 s red
	phase_t += delta
	var cyc := fmod(phase_t, 30.0)
	var want := 0 if cyc < 16.0 else (1 if cyc < 19.0 else 2)
	if want != phase or _t < delta * 1.5:
		_set_phase(want)
	_drive_traffic(delta)
	_props_physics()
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = 0.5
		_stream_chunks()
		_manage_traffic()
		_manage_peds()
	_beam_t -= delta
	if _beam_t <= 0.0:
		_beam_t = 1.0
		_assign_beams()
	if world.sky:
		puddle_mat.albedo_color.a = clampf(world.sky.wet * 0.85, 0.0, 0.85)


# ---------------------------------------------------------------- traffic
func _manage_traffic() -> void:
	var cam: Camera3D = world.current_camera()
	for k in range(traffic.size() - 1, -1, -1):
		var t: Dictionary = traffic[k]
		var c = t.car
		if not is_instance_valid(c):
			traffic.remove_at(k)
			continue
		var d: float = c.global_position.distance_to(route[player_i])
		var seen: bool = cam != null and cam.is_position_in_frustum(c.global_position) and d < 200.0
		var gone: bool = d > 230.0 or (t.stuck > 14.0 and not seen) or (c.wrecked and d > 120.0) or t.get("end", false)
		if gone and c != world.active_car:
			c.queue_free()
			traffic.remove_at(k)
	if traffic.size() < max_cars:
		_spawn_car(cam)


func _spawn_car(cam: Camera3D) -> void:
	for _try in 4:
		var dir := 1 if randf() < 0.5 else -1
		var off := randi_range(9, 21) * (1 if randf() < 0.5 else -1)
		var i := clampi(player_i + off, 3, n - 4)
		var p := _lane_point(i, dir)
		var g: Dictionary = world._ground(p)
		if g.is_empty():
			continue
		p = g.position
		if cam and cam.is_position_in_frustum(p) and p.distance_to(cam.global_position) < 110.0:
			continue
		var clear := true
		for t in traffic:
			if is_instance_valid(t.car) and t.car.global_position.distance_to(p) < 16.0:
				clear = false
		for c in world.cars:
			if is_instance_valid(c) and c.global_position.distance_to(p) < 10.0:
				clear = false
		if world.player.global_position.distance_to(p) < 25.0:
			clear = false
		if not clear:
			continue
		var c := Car.new()
		c.model_path = "res://assets/models/cars/%s.glb" % MODELS[randi() % MODELS.size()]
		c.display_name = "CIVILIAN CAR"
		c.kind = "civilian"
		c.paint = PAINTS[randi() % PAINTS.size()]
		c.world = world
		c.traffic = true
		c.ai_on = true
		c.beams_allowed = false
		world.add_child(c)
		var fwd := _tan(i) * dir
		c.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), p + Vector3(0, 0.45, 0))
		var vmax := randf_range(10.0, 14.5)
		c.engine_state = Car.ON
		c.engine.play()
		c.speed = vmax * 0.8
		c.gear = 3
		c._set_lights(true)
		traffic.append({"car": c, "dir": dir, "i": i, "vmax": vmax, "stuck": 0.0, "panic": 0.0, "honk": 0.0})
		return


func _drive_traffic(delta: float) -> void:
	var space: PhysicsDirectSpaceState3D = world.space
	for t in traffic:
		var c = t.car
		if not is_instance_valid(c) or c.wrecked or not c.ai_on:
			continue
		var pos: Vector3 = c.global_position
		var dir: int = t.dir
		# advance our place along the road
		var i: int = t.i
		for _k in 4:
			var ni := i + dir
			if ni < 1 or ni > n - 2:
				t["end"] = true
				break
			if pos.distance_squared_to(route[ni]) < pos.distance_squared_to(route[i]):
				i = ni
			else:
				break
		t.i = i
		var spd: float = c.speed
		# steer toward a point ahead in our lane (pure pursuit)
		var look := 7.0 + absf(spd) * 0.8
		var ti := clampi(i + dir * int(ceil(look / STEP)), 1, n - 2)
		var target := _lane_point(ti, dir)
		var lt: Vector3 = c.global_transform.affine_inverse() * target
		var ang := atan2(lt.x, -lt.z)
		c.ai_steer = clampf(-ang * 1.8, -1.0, 1.0)
		# speed: slower in bends, stop for obstacles and red lights
		var bend := _tan(i).angle_to(_tan(clampi(i + dir * 5, 1, n - 2)))
		var v: float = t.vmax * clampf(1.0 - bend * 1.1, 0.45, 1.0)
		t.panic = maxf(0.0, t.panic - delta)
		if t.panic > 0.0:
			v *= 1.45
		var stop_d := INF
		var fwd: Vector3 = -c.global_transform.basis.z
		var from := pos + fwd * 2.5 + Vector3(0, 0.8, 0)
		var reach := 5.0 + absf(spd) * 1.7
		var q := PhysicsRayQueryParameters3D.create(from, from + fwd * reach)
		q.collision_mask = 1 | 2 | 8
		q.exclude = [c.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and (hit.collider is CharacterBody3D):
			stop_d = from.distance_to(hit.position)
			var blocker = hit.collider
			if blocker == world.player or blocker == world.active_car:
				t.honk += delta
				if t.honk > 2.5:
					t.honk = -4.0
					_horn(c)
		else:
			t.honk = maxf(t.honk - delta, 0.0)
		if t.panic <= 0.0:
			for s in signals:
				var si: int = s.i
				var di: int = (si - i) * dir
				if di >= 1 and di <= 6 and phase != 0:
					var line := float(di - 1) * STEP + 2.0
					if phase == 2 or line > 10.0:
						stop_d = minf(stop_d, line)
		if stop_d < INF:
			v = minf(v, sqrt(maxf(stop_d - 3.0, 0.0) * 2.0 * 4.5))
		var want_stop := v < 0.6
		c.ai_thr = 1.0 if spd < v - 0.4 else (0.35 if spd < v else 0.0)
		c.ai_brake = spd > v + 0.8 and spd > 0.5
		if want_stop and spd < 0.6:
			c.ai_thr = 0.0
			c.ai_brake = false
		if spd < 0.4 and not want_stop:
			t.stuck += delta
		elif spd > 1.0:
			t.stuck = 0.0
		if spd < 0.4 and want_stop:
			t.stuck += delta * 0.15


func _horn(c) -> void:
	var cam: Camera3D = world.current_camera()
	var d := cam.global_position.distance_to(c.global_position) if cam else 20.0
	Game.play_sfx("horn", randf_range(0.92, 1.08), clampf(-2.0 - d * 0.35, -26.0, -2.0))


func _assign_beams() -> void:
	var cam: Camera3D = world.current_camera()
	if cam == null:
		return
	var list: Array = []
	for t in traffic:
		if is_instance_valid(t.car) and not t.car.wrecked:
			list.append([t.car.global_position.distance_squared_to(cam.global_position), t.car])
	list.sort_custom(func(a, b): return a[0] < b[0])
	for k in list.size():
		var c = list[k][1]
		var allow: bool = k < [2, 3, 4][Q]
		if allow != c.beams_allowed:
			c.beams_allowed = allow
			if c.lights_on:
				c._set_lights(true)


## Gunfire / explosions nearby: drivers floor it, pedestrians run.
func panic(pos: Vector3, radius: float) -> void:
	for t in traffic:
		if is_instance_valid(t.car) and t.car.global_position.distance_to(pos) < radius:
			t.panic = randf_range(8.0, 14.0)


## The player takes a car out of traffic: the driver jumps out and runs.
func carjack(c) -> void:
	for k in traffic.size():
		if traffic[k].car == c:
			traffic.remove_at(k)
			break
	c.ai_on = false
	c.traffic = false
	c.ai_thr = 0.0
	c.ai_brake = false
	c.beams_allowed = true
	c.speed = 0.0
	world.cars.append(c)
	var p: Vector3 = c.global_position - c.global_transform.basis.x * 2.0
	var g: Dictionary = world._ground(p)
	var ped := _new_ped(g.position if not g.is_empty() else p, [])
	if ped:
		ped.alert(world.player.global_position, world.player)


func traffic_cars() -> Array:
	var out: Array = []
	for t in traffic:
		if is_instance_valid(t.car):
			out.append(t.car)
	return out


# ---------------------------------------------------------------- pedestrians
func _new_ped(pos: Vector3, wps: Array) -> Node:
	var p := Npc.new()
	p.role = "civ"
	p.world = world
	p.waypoints = wps
	p.path_mode = wps.size() > 0
	p.walk_speed = randf_range(1.05, 1.5)
	p.path_i = -1
	world.add_child(p)
	p.global_position = pos + Vector3(0, 0.1, 0)
	if wps.size() > 0:
		var d: Vector3 = wps[0] - pos
		p.rotation.y = atan2(-d.x, -d.z)
		p.timer = 0.0
	world.npcs.append(p)
	peds.append(p)
	return p


func _ped_path(i: int, side: int, dir: int, count: int) -> Array:
	var wps: Array = []
	var k := i
	for _s in count:
		k += dir
		if k < 2 or k > n - 3:
			break
		var sp = _sidewalk(k, side)
		if sp == null:
			break
		wps.append(sp)
	return wps


func _manage_peds() -> void:
	var cam: Camera3D = world.current_camera()
	for k in range(peds.size() - 1, -1, -1):
		var p = peds[k]
		if not is_instance_valid(p):
			peds.remove_at(k)
			continue
		var d: float = p.global_position.distance_to(route[player_i])
		var done: bool = p.path_mode and p.state == Npc.IDLE and p.path_i >= p.waypoints.size() - 1 and p.timer <= 0.0 and p._route.is_empty()
		var seen: bool = cam != null and cam.is_position_in_frustum(p.global_position) and d < 60.0
		if (d > 140.0 or (done and not seen)) and p.state != Npc.DEAD:
			world.npcs.erase(p)
			p.queue_free()
			peds.remove_at(k)
	var alive := 0
	for p in peds:
		if p.state != Npc.DEAD:
			alive += 1
	if alive >= max_peds:
		return
	for _try in 3:
		var side := 1 if randf() < 0.5 else -1
		var dir := 1 if randf() < 0.5 else -1
		var i := clampi(player_i + randi_range(-12, 12), 3, n - 4)
		var sp = _sidewalk(i, side)
		if sp == null:
			continue
		if cam and cam.is_position_in_frustum(sp) and sp.distance_to(cam.global_position) < 35.0:
			continue
		var wps := _ped_path(i, side, dir, 26)
		if wps.size() < 4:
			continue
		_new_ped(sp, wps)
		return


func _spawn_crossers() -> void:
	var cam: Camera3D = world.current_camera()
	if cam == null:
		return
	for s in signals:
		if s.pos.distance_to(cam.global_position) > 110.0 or peds.size() >= max_peds + 3:
			continue
		if randf() > 0.6:
			continue
		var side := 1 if randf() < 0.5 else -1
		var a = _sidewalk(s.i, side, 0.8)
		var b = _sidewalk(s.i, -side, 0.8)
		if a == null or b == null:
			continue
		var wps: Array = [b]
		wps.append_array(_ped_path(s.i, -side, 1 if randf() < 0.5 else -1, 14))
		var p := _new_ped(a, wps)
		p.walk_speed = 1.55


# ---------------------------------------------------------------- props (streamed)
func _stream_chunks() -> void:
	var cc := player_i / CHUNK
	var keep := {}
	for k in range(cc - 2, cc + 3):
		if k < 0 or k * CHUNK >= n:
			continue
		keep[k] = true
		if not chunks.has(k):
			chunks[k] = _build_chunk(k)
	for k in chunks.keys():
		if not keep.has(k):
			chunks[k].node.queue_free()
			chunks.erase(k)


func _build_chunk(ci: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * ci + 13
	var node := Node3D.new()
	add_child(node)
	var rigid: Array = []
	var litter: Array = []
	var puddles: Array = []
	var a := maxi(ci * CHUNK, 2)
	var b := mini((ci + 1) * CHUNK, n - 3)
	for i in range(a, b):
		var near_signal := false
		for s in signals:
			if absi(s.i - i) <= 1:
				near_signal = true
		for side in [1, -1]:
			if rng.randf() > 0.62:
				continue
			var extra := rng.randf_range(0.5, 2.4)
			var sp = _sidewalk(i, side, extra)
			if sp == null:
				continue
			sp += _tan(i) * rng.randf_range(-3.5, 3.5)
			var g: Dictionary = world._ground(sp)
			if g.is_empty():
				continue
			var pos: Vector3 = g.position
			var yaw := rng.randf() * TAU
			var r := rng.randf()
			if near_signal:
				r = 0.95
			if r < 0.22:
				_trash_bags(node, pos, yaw, rng)
			elif r < 0.38:
				rigid.append(_bin(node, pos, yaw))
			elif r < 0.5:
				rigid.append(_cardboard(node, pos, yaw, rng))
			elif r < 0.6:
				_hydrant(node, pos, yaw)
			elif r < 0.7:
				_bench(node, pos, atan2(-(_nrm(i) * side).x, -(_nrm(i) * side).z) + PI)
			elif r < 0.78:
				rigid.append(_news_box(node, pos, yaw))
			elif r < 0.9:
				var e := edges(i)
				var cp: Vector3 = route[i] + _nrm(i) * side * ((e.y if side > 0 else e.x) - 0.5)
				var g2: Dictionary = world._ground(cp)
				if not g2.is_empty():
					rigid.append(_cone(node, g2.position, yaw))
			for _l in rng.randi_range(1, 4):
				var lp: Vector3 = pos + Vector3(rng.randf_range(-2.5, 2.5), 0, rng.randf_range(-2.5, 2.5))
				var gl: Dictionary = world._ground(lp)
				if not gl.is_empty():
					litter.append([gl.position, gl.normal, rng.randf() * TAU, rng.randf()])
		# puddles on the road surface (visible when it rains)
		if rng.randf() < 0.22:
			var e2 := edges(i)
			var pp: Vector3 = route[i] + _nrm(i) * rng.randf_range(-e2.x + 0.8, e2.y - 0.8)
			var gp: Dictionary = world._ground(pp)
			if not gp.is_empty() and world._is_road(gp):
				var up: Vector3 = gp.normal
				var sc := Vector3(rng.randf_range(1.2, 3.4), 1.0, rng.randf_range(1.0, 2.6))
				puddles.append(Transform3D(Basis(up, rng.randf() * TAU) * Basis(Quaternion(Vector3.UP, up)) * Basis.from_scale(sc), gp.position + up * 0.02))
	if litter.size() > 0:
		_litter(node, litter)
	if puddles.size() > 0:
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		q.orientation = PlaneMesh.FACE_Y
		_begin()
		for xf in puddles:
			_mesh(null, q, xf, puddle_mat)
		_instance(node, _finish(), [60.0, 90.0, 120.0][Q])
	return {"node": node, "rigid": rigid}


func _rigid(parent: Node3D, pos: Vector3, yaw: float, shape: Shape3D, shape_y: float, mass: float) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.collision_layer = 16
	rb.collision_mask = 1 | 16
	rb.mass = mass
	rb.can_sleep = true
	rb.sleeping = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = shape_y
	rb.add_child(cs)
	parent.add_child(rb)
	rb.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	rb.set_meta("hit_cd", 0.0)
	return rb


func _trash_bags(parent: Node3D, pos: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	var v := rng.randi_range(0, 4)
	_proto(root, "bags%d" % v, func():
		var r2 := RandomNumberGenerator.new()
		r2.seed = 91 + v
		var m := _mat("bag", Color(0.03, 0.035, 0.035), 0.3)
		var m2 := _mat("bag2", Color(0.08, 0.13, 0.09), 0.32)
		for k in 1 + v % 4:
			var sm := SphereMesh.new()
			sm.radius = r2.randf_range(0.26, 0.36)
			sm.height = sm.radius * 1.6
			sm.radial_segments = 10
			sm.rings = 6
			var off := Vector3(r2.randf_range(-0.5, 0.5), sm.height * 0.42, r2.randf_range(-0.4, 0.4))
			_mesh(null, sm, Transform3D(Basis(Vector3(r2.randf(), 1, r2.randf()).normalized(), r2.randf() * 0.5), off), m if r2.randf() < 0.7 else m2))


func _bin(parent: Node3D, pos: Vector3, yaw: float) -> RigidBody3D:
	var sh := CylinderShape3D.new()
	sh.radius = 0.32
	sh.height = 0.95
	var rb := _rigid(parent, pos, yaw, sh, 0.475, 14.0)
	_proto(rb, "bin", func():
		var body := _mat("bin", Color(0.12, 0.24, 0.16), 0.45, 0.35)
		var dark := _mat("bindark", Color(0.05, 0.06, 0.06), 0.6, 0.3)
		_mesh(null, _cyl(0.32, 0.28, 0.9), Transform3D(Basis(), Vector3(0, 0.45, 0)), body)
		_mesh(null, _cyl(0.35, 0.35, 0.06), Transform3D(Basis(), Vector3(0, 0.93, 0)), dark)
		_mesh(null, _cyl(0.33, 0.33, 0.03), Transform3D(Basis(), Vector3(0, 0.62, 0)), dark))
	return rb


const CARD_SIZES := [Vector3(0.45, 0.32, 0.42), Vector3(0.6, 0.45, 0.5), Vector3(0.75, 0.55, 0.65)]


func _cardboard(parent: Node3D, pos: Vector3, yaw: float, rng: RandomNumberGenerator) -> RigidBody3D:
	var v := rng.randi_range(0, 2)
	var sz: Vector3 = CARD_SIZES[v]
	var sh := BoxShape3D.new()
	sh.size = sz
	var rb := _rigid(parent, pos, yaw, sh, sz.y * 0.5, 2.0)
	_proto(rb, "card%d" % v, func():
		_mesh(null, _box(sz), Transform3D(Basis(), Vector3(0, sz.y * 0.5, 0)), _mat("card", Color(0.52, 0.38, 0.22), 0.9))
		_mesh(null, _box(Vector3(sz.x + 0.005, 0.05, 0.1)), Transform3D(Basis(), Vector3(0, sz.y, 0)), _mat("tape", Color(0.62, 0.5, 0.32), 0.5)))
	return rb


func _cone(parent: Node3D, pos: Vector3, yaw: float) -> RigidBody3D:
	var sh := CylinderShape3D.new()
	sh.radius = 0.2
	sh.height = 0.72
	var rb := _rigid(parent, pos, yaw, sh, 0.36, 3.0)
	_proto(rb, "cone", func():
		_mesh(null, _box(Vector3(0.42, 0.04, 0.42)), Transform3D(Basis(), Vector3(0, 0.02, 0)), _mat("conebase", Color(0.08, 0.08, 0.08), 0.8))
		_mesh(null, _cyl(0.03, 0.17, 0.7, 14), Transform3D(Basis(), Vector3(0, 0.39, 0)), _mat("cone", Color(1.0, 0.32, 0.03), 0.55))
		_mesh(null, _cyl(0.088, 0.115, 0.12, 14), Transform3D(Basis(), Vector3(0, 0.45, 0)), _mat("conestripe", Color(0.95, 0.95, 0.95), 0.3)))
	return rb


func _news_box(parent: Node3D, pos: Vector3, yaw: float) -> RigidBody3D:
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.5, 1.1, 0.45)
	var rb := _rigid(parent, pos, yaw, sh, 0.55, 26.0)
	var v := int(absf(pos.x * 7.0)) % 3
	_proto(rb, "news%d" % v, func():
		var c: Color = [Color(0.1, 0.25, 0.6), Color(0.65, 0.1, 0.08), Color(0.85, 0.75, 0.15)][v]
		var pole := _mat("pole", Color(0.16, 0.17, 0.18), 0.45, 0.7)
		_mesh(null, _box(Vector3(0.5, 0.75, 0.45)), Transform3D(Basis(), Vector3(0, 0.72, 0)), _mat("news%d" % v, c, 0.4, 0.4))
		_mesh(null, _box(Vector3(0.06, 0.35, 0.06)), Transform3D(Basis(), Vector3(-0.18, 0.17, 0)), pole)
		_mesh(null, _box(Vector3(0.06, 0.35, 0.06)), Transform3D(Basis(), Vector3(0.18, 0.17, 0)), pole)
		_mesh(null, _box(Vector3(0.36, 0.26, 0.02)), Transform3D(Basis(), Vector3(0, 0.82, -0.23)), _mat("newsglass", Color(0.7, 0.75, 0.78), 0.05, 0.6)))
	return rb


func _static(parent: Node3D, pos: Vector3, yaw: float, shape: Shape3D, shape_y: float) -> StaticBody3D:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = shape_y
	sb.add_child(cs)
	parent.add_child(sb)
	sb.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	return sb


func _hydrant(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var sh := CylinderShape3D.new()
	sh.radius = 0.2
	sh.height = 0.8
	var sb := _static(parent, pos, yaw, sh, 0.4)
	_proto(sb, "hydrant", func():
		var red := _mat("hydrant", Color(0.7, 0.07, 0.05), 0.4, 0.3)
		var metal := _mat("hydrantcap", Color(0.6, 0.6, 0.58), 0.35, 0.8)
		_mesh(null, _cyl(0.2, 0.22, 0.1), Transform3D(Basis(), Vector3(0, 0.05, 0)), red)
		_mesh(null, _cyl(0.15, 0.16, 0.58), Transform3D(Basis(), Vector3(0, 0.38, 0)), red)
		var dome := SphereMesh.new()
		dome.radius = 0.16
		dome.height = 0.2
		_mesh(null, dome, Transform3D(Basis(), Vector3(0, 0.68, 0)), red)
		_mesh(null, _cyl(0.04, 0.05, 0.06), Transform3D(Basis(), Vector3(0, 0.79, 0)), metal)
		for sgn in [-1.0, 1.0]:
			_mesh(null, _cyl(0.065, 0.065, 0.14), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(sgn * 0.19, 0.48, 0)), red)
			_mesh(null, _cyl(0.05, 0.05, 0.03), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(sgn * 0.27, 0.48, 0)), metal))


func _bench(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.8, 0.85, 0.6)
	var sb := _static(parent, pos, yaw, sh, 0.42)
	_proto(sb, "bench", func():
		var wood := _mat("wood", Color(0.36, 0.22, 0.12), 0.75)
		var iron := _mat("iron", Color(0.07, 0.07, 0.075), 0.5, 0.8)
		for k in 3:
			_mesh(null, _box(Vector3(1.8, 0.04, 0.13)), Transform3D(Basis(), Vector3(0, 0.45, -0.17 + k * 0.17)), wood)
		for k in 2:
			_mesh(null, _box(Vector3(1.8, 0.12, 0.035)), Transform3D(Basis(Vector3.RIGHT, -0.22), Vector3(0, 0.62 + k * 0.17, 0.3 + k * 0.035)), wood)
		for sx in [-0.75, 0.75]:
			_mesh(null, _box(Vector3(0.06, 0.45, 0.5)), Transform3D(Basis(), Vector3(sx, 0.22, 0.0)), iron)
			_mesh(null, _box(Vector3(0.05, 0.5, 0.05)), Transform3D(Basis(Vector3.RIGHT, -0.22), Vector3(sx, 0.68, 0.3)), iron))


func _litter(parent: Node3D, items: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.3)
	q.orientation = PlaneMesh.FACE_Y
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	mm.mesh = q
	mm.instance_count = items.size()
	for k in items.size():
		var it: Array = items[k]
		var up: Vector3 = it[1]
		var b := Basis(up, it[2]) * Basis(Quaternion(Vector3.UP, up))
		mm.set_instance_transform(k, Transform3D(b.scaled(Vector3.ONE * lerpf(0.6, 1.4, it[3])), it[0] + up * 0.015))
		var tone: float = it[3]
		mm.set_instance_color(k, Color(0.85, 0.83, 0.78) if tone < 0.5 else (Color(0.55, 0.42, 0.28) if tone < 0.8 else Color(0.75, 0.12, 0.1)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = [40.0, 60.0, 90.0][Q]
	parent.add_child(mmi)


## Cars and people knock props over (they sit on their own physics layer, so they never stop a car).
func _props_physics() -> void:
	var movers: Array = []
	for c in world.cars:
		if is_instance_valid(c) and absf(c.speed) > 1.5:
			movers.append([c.global_position, c.velocity, 2.7, 1.0])
	for c in traffic_cars():
		if absf(c.speed) > 1.5:
			movers.append([c.global_position, c.velocity, 2.7, 1.0])
	var pl = world.player
	if pl and pl.active and not pl.dead:
		movers.append([pl.global_position, pl.velocity, 0.75, 0.35])
	if movers.is_empty():
		return
	var now := _t
	for ch in chunks.values():
		for rb in ch.rigid:
			if not is_instance_valid(rb):
				continue
			if now < float(rb.get_meta("hit_cd")):
				continue
			for mv in movers:
				var to: Vector3 = rb.global_position - mv[0]
				to.y = 0
				if to.length() < mv[2]:
					var v: Vector3 = mv[1]
					if v.length() < 0.5:
						continue
					rb.sleeping = false
					var imp: Vector3 = (v * 0.9 + to.normalized() * 1.5 + Vector3(0, v.length() * 0.35 + 1.0, 0)) * rb.mass * mv[3]
					rb.apply_impulse(imp, Vector3(randf_range(-0.1, 0.1), 0.4, randf_range(-0.1, 0.1)))
					rb.set_meta("hit_cd", now + 0.6)
					if mv[3] >= 1.0 and rb.mass > 5.0:
						Game.play_sfx("door", randf_range(0.7, 0.9), -10.0)
					break
