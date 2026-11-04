extends Node
## In-game GPS: a road graph of the whole world (the city road + every countryside road),
## shortest-path routing with A*, automatic re-routing, turn-by-turn hints, zone / street
## names and the list of named places shown on the maps.

const CITY_STREET := "SUNSET BOULEVARD"

var world
var nodes := PackedVector3Array()
var node_road := PackedInt32Array()      # -1 = city road, otherwise index into road_names
var adj: Array = []                       # node -> Array of [neighbour, metres]
var road_names: Array = []
var road_kind: Array = []
var _grid := {}                           # Vector2i(100 m cell) -> Array of node ids
var places: Array = []                    # {name, kind, pos, color, glyph}

var dest_set := false
var dest := Vector3.ZERO
var dest_name := ""
var path := PackedInt32Array()
var path_pts := PackedVector3Array()
var remaining := 0.0
var turn_dir := 0                         # -1 left, 1 right, 0 none
var turn_dist := 0.0
var _t := 0.0
var _beeped := false
var zone := ""
var street := ""
var _last_zone := ""
var zone_flash := 0.0
var _beacon: MeshInstance3D


func _ready() -> void:
	# a tall light beam marks the destination in the world
	_beacon = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.6
	cm.bottom_radius = 1.6
	cm.height = 60.0
	cm.cap_top = false
	cm.cap_bottom = false
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(0.9, 0.3, 1.0, 0.28)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	cm.material = bm
	_beacon.mesh = cm
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beacon.visible = false
	world.add_child.call_deferred(_beacon)
	_build_graph()
	_build_places()
	var saved = Game.player.get("gps_dest", null)
	if saved is Array and saved.size() == 4:
		set_destination(Vector3(saved[0], saved[1], saved[2]), str(saved[3]), false)


# ---------------------------------------------------------------- graph
func _add_node(p: Vector3, road: int) -> int:
	nodes.append(p)
	node_road.append(road)
	adj.append([])
	var k := Vector2i(int(floor(p.x / 100.0)), int(floor(p.z / 100.0)))
	if not _grid.has(k):
		_grid[k] = []
	_grid[k].append(nodes.size() - 1)
	return nodes.size() - 1


func _link(a: int, b: int) -> void:
	var d := nodes[a].distance_to(nodes[b])
	adj[a].append([b, d])
	adj[b].append([a, d])


func _build_graph() -> void:
	var route: Array = world.route
	for i in route.size():
		_add_node(route[i], -1)
		if i > 0:
			_link(i - 1, i)
	var C = world.country
	if C == null or not C.ready_ok:
		return
	var ends: Array = []     # [node id, road index] for endpoints that are not on the city road
	for ri in C.roads.size():
		var rd: Dictionary = C.roads[ri]
		road_names.append(rd.name)
		road_kind.append(rd.kind)
		var pts: PackedVector3Array = rd.pts
		var first := -1
		var prev := -1
		for k in pts.size():
			var id := _add_node(pts[k], ri)
			if prev >= 0:
				_link(prev, id)
			else:
				first = id
			prev = id
		if rd.start_route >= 0:
			_link(first, int(rd.start_route))
		else:
			ends.append([first, ri])
		if rd.end_route >= 0:
			_link(prev, int(rd.end_route))
		else:
			ends.append([prev, ri])
	# junctions: loose road ends join the closest point of another road
	for e in ends:
		var id: int = e[0]
		var best := -1
		var bd := 60.0
		for k in _near_ids(nodes[id], 1):
			if node_road[k] == e[1]:
				continue
			var d := nodes[id].distance_to(nodes[k])
			if d < bd:
				bd = d
				best = k
		if best >= 0:
			_link(id, best)


func _near_ids(p: Vector3, ring: int) -> Array:
	var out: Array = []
	var c := Vector2i(int(floor(p.x / 100.0)), int(floor(p.z / 100.0)))
	for dz in range(-ring, ring + 1):
		for dx in range(-ring, ring + 1):
			var k := c + Vector2i(dx, dz)
			if _grid.has(k):
				out.append_array(_grid[k])
	return out


func nearest_node(p: Vector3, max_ring := 6) -> int:
	for ring in range(1, max_ring + 1):
		var best := -1
		var bd := INF
		for k in _near_ids(p, ring):
			var d := Vector2(p.x - nodes[k].x, p.z - nodes[k].z).length_squared()
			if d < bd:
				bd = d
				best = k
		if best >= 0:
			return best
	# far from everything: brute force
	var b2 := 0
	var d2 := INF
	for k in nodes.size():
		var d := p.distance_squared_to(nodes[k])
		if d < d2:
			d2 = d
			b2 = k
	return b2


## A* over the road graph; returns node ids from a to b.
func find_path(a: int, b: int) -> PackedInt32Array:
	var n := nodes.size()
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	var heap_f: Array = []
	var heap_i: Array = []
	g[a] = 0.0
	_push(heap_f, heap_i, nodes[a].distance_to(nodes[b]), a)
	while heap_i.size() > 0:
		var cur: int = _pop(heap_f, heap_i)
		if cur == b:
			break
		if closed[cur] == 1:
			continue
		closed[cur] = 1
		for e in adj[cur]:
			var nb: int = e[0]
			var ng: float = g[cur] + e[1]
			if ng < g[nb]:
				g[nb] = ng
				prev[nb] = cur
				_push(heap_f, heap_i, ng + nodes[nb].distance_to(nodes[b]), nb)
	var out := PackedInt32Array()
	if prev[b] < 0 and a != b:
		return out
	var c := b
	while c >= 0:
		out.append(c)
		if c == a:
			break
		c = prev[c]
	out.reverse()
	return out


func _push(hf: Array, hi: Array, f: float, id: int) -> void:
	hf.append(f)
	hi.append(id)
	var i := hf.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if hf[p] <= hf[i]:
			break
		var tf = hf[p]; hf[p] = hf[i]; hf[i] = tf
		var ti = hi[p]; hi[p] = hi[i]; hi[i] = ti
		i = p


func _pop(hf: Array, hi: Array) -> int:
	var top: int = hi[0]
	var lf = hf.pop_back()
	var li = hi.pop_back()
	if hf.size() > 0:
		hf[0] = lf
		hi[0] = li
		var i := 0
		var n := hf.size()
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < n and hf[l] < hf[m]:
				m = l
			if r < n and hf[r] < hf[m]:
				m = r
			if m == i:
				break
			var tf = hf[m]; hf[m] = hf[i]; hf[i] = tf
			var ti = hi[m]; hi[m] = hi[i]; hi[i] = ti
			i = m
	return top


# ---------------------------------------------------------------- destination
func set_destination(p: Vector3, name := "", save := true) -> void:
	dest_set = true
	dest = p
	dest_name = name if name != "" else "WAYPOINT"
	_beeped = false
	_reroute()
	_beacon.visible = true
	_beacon.position = p + Vector3(0, 30, 0)
	if save:
		Game.player["gps_dest"] = [p.x, p.y, p.z, dest_name]
		Game.save_data()


func clear_destination() -> void:
	dest_set = false
	_beacon.visible = false
	path = PackedInt32Array()
	path_pts = PackedVector3Array()
	remaining = 0.0
	turn_dir = 0
	Game.player["gps_dest"] = null
	Game.save_data()


func _focus() -> Vector3:
	if world.active_car:
		return world.active_car.global_position
	return world.player.global_position


func _reroute() -> void:
	var me := _focus()
	var a := nearest_node(me)
	var b := nearest_node(dest)
	path = find_path(a, b)
	path_pts = PackedVector3Array()
	for id in path:
		path_pts.append(nodes[id])
	if dest.distance_to(nodes[b]) > 6.0:
		path_pts.append(dest)
	_measure(me)


func _measure(me: Vector3) -> void:
	if path_pts.is_empty():
		remaining = me.distance_to(dest)
		return
	var ci := _closest_index(me)
	var d := Vector2(me.x - path_pts[ci].x, me.z - path_pts[ci].z).length()
	for k in range(ci, path_pts.size() - 1):
		d += path_pts[k].distance_to(path_pts[k + 1])
	remaining = d
	# next turn: the first sharp change of direction ahead (within 450 m)
	turn_dir = 0
	var acc := 0.0
	for k in range(ci + 1, path_pts.size() - 3):
		acc += path_pts[k].distance_to(path_pts[k - 1])
		if acc > 450.0:
			break
		var a := path_pts[k] - path_pts[k - 2]
		var b := path_pts[k + 2] - path_pts[k]
		var ang := Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z))
		if acc > 15.0 and absf(ang) > 0.55 and a.length() > 4.0 and b.length() > 4.0:
			turn_dir = 1 if ang > 0.0 else -1
			turn_dist = acc
			break


func _closest_index(me: Vector3) -> int:
	var best := 0
	var bd := INF
	for k in path_pts.size():
		var d := Vector2(me.x - path_pts[k].x, me.z - path_pts[k].z).length_squared()
		if d < bd:
			bd = d
			best = k
	return best


func off_route(me: Vector3) -> bool:
	if path_pts.size() < 2:
		return true
	var k := _closest_index(me)
	return Vector2(me.x - path_pts[k].x, me.z - path_pts[k].z).length() > 40.0


func _process(delta: float) -> void:
	if world.player == null:
		return
	_t += delta
	zone_flash = maxf(0.0, zone_flash - delta)
	var me := _focus()
	if fmod(_t, 0.5) < delta:
		_update_names(me)
	if not dest_set:
		return
	if me.distance_to(dest) < 22.0:
		var nm := dest_name
		clear_destination()
		if world.hud:
			world.hud.notify("YOU HAVE ARRIVED  •  " + nm)
		Game.play_sfx("ready", 1.0, -4.0)
		return
	if fmod(_t, 1.0) < delta:
		if off_route(me):
			_reroute()
		else:
			_measure(me)
		if turn_dir != 0 and turn_dist < 90.0 and not _beeped and bool(Game.settings.get("gps_beep", true)):
			_beeped = true
			Game.play_sfx("beep", 1.3, -8.0)
		elif turn_dir == 0 or turn_dist > 150.0:
			_beeped = false


## Rough travel time in seconds: by car at a typical 50 km/h, on foot at 5 km/h.
func eta(by_car: bool) -> float:
	return remaining / (13.9 if by_car else 1.4)


# ---------------------------------------------------------------- names
func _update_names(me: Vector3) -> void:
	var z := ""
	var C = world.country
	var ni := nearest_node(me, 3)
	var dn := Vector2(me.x - nodes[ni].x, me.z - nodes[ni].z).length() if ni >= 0 else INF
	if ni >= 0 and node_road[ni] == -1 and dn < 160.0 and C:
		for cz in C.info.city_zones:
			if ni >= int(cz[0]) and ni < int(cz[1]):
				z = cz[2]
	if z == "" and C:
		z = C.zone_at(me.x, me.z)
	if z == "":
		z = "LOS ANGELES"
	street = ""
	if ni >= 0 and dn < 30.0:
		street = CITY_STREET if node_road[ni] == -1 else str(road_names[node_road[ni]])
	zone = z
	if z != _last_zone:
		if _last_zone != "":
			zone_flash = 4.0
		_last_zone = z


# ---------------------------------------------------------------- places
func _build_places() -> void:
	for p in world.poi:
		var kind := "bank" if str(p.name) == "BANK" else ("police" if str(p.name).contains("POLICE") else "hideout")
		places.append({"name": p.name if str(p.name) != "BANK" else "UNION BANK", "kind": kind, "pos": p.pos, "color": p.color})
	for team in world.bases:
		var b: Dictionary = world.bases[team]
		places.append({"name": ("POLICE ARMORY" if team == "cops" else "HIDEOUT ARMORY"), "kind": "armory", "pos": b.pos + Vector3(4, 0, 4), "color": Color(1.0, 0.6, 0.15)})
	if world.bank:
		places.append({"name": "PRIVATE GARAGE", "kind": "garage", "pos": world.bank.global_transform * Vector3(32, 0, 20), "color": Color(0.75, 0.8, 0.85)})
	var C = world.country
	if C and C.ready_ok:
		var cols := {"tower": Color(1, 0.3, 0.25), "ranch": Color(0.8, 0.55, 0.3), "gas": Color(1.0, 0.85, 0.2), "lake": Color(0.35, 0.7, 1.0), "lookout": Color(0.5, 0.9, 0.5), "zone": Color(0.85, 0.85, 0.85)}
		for p in C.places:
			var y: float = float(p.get("y", C.height_at(p.x, p.z)))
			var nm: String = p.name
			if p.kind == "lake":
				nm = "BLUE LAKE PIER"
			places.append({"name": nm, "kind": p.kind, "pos": Vector3(p.x, y, p.z), "color": cols.get(p.kind, Color.WHITE)})


func search(text: String) -> Array:
	var t := text.strip_edges().to_upper()
	var out: Array = []
	for p in places:
		if t == "" or str(p.name).contains(t):
			out.append(p)
	return out
