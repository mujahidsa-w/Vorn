extends Node3D
## Bank compound: plaza, large bank hall with tellers, vault, ATMs,
## a luxury underground-style garage, and NPCs (civilians, employees, guards).
## Local frame: +Z faces the road (front), Y up, origin at plaza level.

const NPC = preload("res://scripts/game3d/npc.gd")
const Car = preload("res://scripts/game3d/car.gd")

var world
var npcs: Array = []
var mats := {}
var q := 1
# automatic sliding entrance doors
var doors: Array = []          # {body, closed_x, dir}
var door_open := 0.0
var _door_was := false
# hall lights + wall switch
var hall_lights: Array = []
var hall_glow: Array = []      # emissive materials of the chandeliers
var lights_on := true
var switch_local := Vector3(-5.2, 1.4, 14.55)
var switch_mesh: MeshInstance3D


func _m(name: String, col: Color, rough := 0.6, metal := 0.0, emis := 0.0, alpha := 1.0) -> StandardMaterial3D:
	if mats.has(name):
		return mats[name]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.roughness = rough
	m.metallic = metal
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emis > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emis
	mats[name] = m
	return m


func box(size: Vector3, pos: Vector3, mat: Material, collide := true, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	mi.rotation.y = rot_y
	add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


func cyl(r: float, h: float, pos: Vector3, mat: Material, collide := true, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 20
	c.material = mat
	mi.mesh = c
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = r
		sh.height = h
		cs.shape = sh
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


func light(pos: Vector3, col: Color, energy: float, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.position = pos
	l.distance_fade_enabled = true
	l.distance_fade_begin = 70.0
	l.distance_fade_length = 20.0
	add_child(l)
	return l


func label(text: String, pos: Vector3, size: int, col: Color, rot_y := 0.0, px := 0.01) -> Label3D:
	var lb := Label3D.new()
	lb.text = text
	lb.font = Game.font_wide
	lb.font_size = size
	lb.pixel_size = px
	lb.modulate = col
	lb.position = pos
	lb.rotation.y = rot_y
	add_child(lb)
	return lb


func is_inside(p_world: Vector3) -> bool:
	var p := to_local(p_world)
	return absf(p.x) < 20.0 and p.z > -15.0 and p.z < 15.0


func build() -> void:
	q = clampi(int(Game.settings.quality), 0, 2)
	var paving := _m("paving", Color(0.55, 0.53, 0.5), 0.8)
	var marble := _m("marble", Color(0.92, 0.9, 0.86), 0.12, 0.05)
	var dark_marble := _m("dmarble", Color(0.12, 0.12, 0.13), 0.15, 0.1)
	var stone := _m("stone", Color(0.82, 0.79, 0.72), 0.55)
	var gold := _m("gold", Color(1.0, 0.76, 0.3), 0.25, 0.9)
	var glass := _m("glass", Color(0.55, 0.7, 0.8), 0.05, 0.3, 0.0, 0.28)
	var wood := _m("wood", Color(0.32, 0.18, 0.1), 0.45)
	var steel := _m("steel", Color(0.6, 0.62, 0.66), 0.3, 0.9)
	var epoxy := _m("epoxy", Color(0.08, 0.085, 0.1), 0.1, 0.2)
	var led := _m("led", Color(0.85, 0.92, 1.0), 0.5, 0.0, 6.0)
	var warm := _m("warm", Color(1.0, 0.85, 0.6), 0.5, 0.0, 5.0)

	# ---- ground slab (deep skirt hides uneven terrain)
	box(Vector3(86, 8, 64), Vector3(4, -4, 0), paving)
	box(Vector3(30, 0.06, 10), Vector3(0, 0.03, 23), _m("plaza", Color(0.7, 0.66, 0.6), 0.5), false)
	# steps up to the portico
	for i in 3:
		box(Vector3(18, 0.18, 1.2 - i * 0.0), Vector3(0, 0.09 + i * 0.18, 19.6 - i * 0.6), stone)
	box(Vector3(18, 0.54, 4.2), Vector3(0, 0.27, 16.8), stone)

	# ---- bank hall shell (40 x 30, 12 high)
	box(Vector3(40, 0.3, 30), Vector3(0, 0.55, 0), marble)                       # floor
	box(Vector3(40.6, 0.6, 30.6), Vector3(0, 12.3, 0), stone)                     # roof
	box(Vector3(40, 12, 0.6), Vector3(0, 6.3, -15), stone)                        # back
	box(Vector3(0.6, 12, 30), Vector3(-20, 6.3, 0), stone)                        # left
	box(Vector3(0.6, 12, 30), Vector3(20, 6.3, 0), stone)                         # right
	# front: stone piers + big glass, door gap x in [-3, 3]
	for x in [-19.0, -13.0, -7.0, 7.0, 13.0, 19.0]:
		box(Vector3(1.2, 12, 0.8), Vector3(x, 6.3, 15), stone)
	for x in [-16.0, -10.0, 10.0, 16.0]:
		box(Vector3(4.8, 9.0, 0.08), Vector3(x, 5.3, 15), glass)
	box(Vector3(13, 3.2, 0.8), Vector3(0, 10.7, 15), stone)                       # lintel over door
	box(Vector3(3.0, 0.15, 0.1), Vector3(-4.6, 4.9, 15), glass, false)
	# glass frontage with automatic sliding doors (opening x in [-1.8, 1.8], 3.2 m high)
	var frame := _m("doorframe", Color(0.1, 0.1, 0.11), 0.35, 0.8)
	for sx in [-1.0, 1.0]:
		box(Vector3(4.5, 9.0, 0.08), Vector3(sx * 4.15, 5.2, 15.1), glass)
		box(Vector3(0.14, 9.0, 0.14), Vector3(sx * 1.87, 5.2, 15.1), frame)
	box(Vector3(3.6, 5.6, 0.08), Vector3(0, 6.9, 15.1), glass, false)
	box(Vector3(3.9, 0.16, 0.16), Vector3(0, 4.05, 15.1), frame, false)
	for sx in [-1.0, 1.0]:
		var body := AnimatableBody3D.new()
		body.sync_to_physics = false
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(1.8, 3.2, 0.1)
		cs.shape = sh
		body.add_child(cs)
		var panel := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(1.8, 3.2, 0.06)
		pb.material = glass
		panel.mesh = pb
		body.add_child(panel)
		var edge := MeshInstance3D.new()
		var eb := BoxMesh.new()
		eb.size = Vector3(0.06, 3.2, 0.09)
		eb.material = frame
		edge.mesh = eb
		edge.position.x = -sx * 0.88
		body.add_child(edge)
		var handle := MeshInstance3D.new()
		var hb := BoxMesh.new()
		hb.size = Vector3(0.04, 0.9, 0.14)
		hb.material = steel
		handle.mesh = hb
		handle.position = Vector3(-sx * 0.75, 0.0, 0.0)
		body.add_child(handle)
		add_child(body)
		body.position = Vector3(sx * 0.9, 2.3, 15.1)
		doors.append({"body": body, "x": sx * 0.9, "dir": sx})
	# light switch beside the door (inside)
	box(Vector3(0.18, 0.28, 0.04), switch_local, _m("switchplate", Color(0.9, 0.88, 0.84), 0.4), false)
	switch_mesh = box(Vector3(0.06, 0.1, 0.05), switch_local + Vector3(0, 0.03, -0.03), _m("switchkey", Color(0.15, 0.15, 0.15), 0.4), false)
	# portico columns + roof
	for x in [-8.0, -4.8, -1.6, 1.6, 4.8, 8.0]:
		cyl(0.55, 11.0, Vector3(x, 6.0, 18.4), stone)
	box(Vector3(19, 1.0, 5.0), Vector3(0, 12.0, 17.0), stone)
	box(Vector3(19.4, 0.25, 5.4), Vector3(0, 11.4, 17.0), gold, false)
	label("UNION BANK", Vector3(0, 12.6, 19.55), 220, Color(1.0, 0.82, 0.4), 0.0, 0.012)
	light(Vector3(0, 9.5, 18.0), Color(1.0, 0.85, 0.6), 3.0, 16.0)

	# ---- interior
	# teller counter with glass screen
	box(Vector3(26, 1.15, 1.0), Vector3(0, 1.27, -4.5), wood)
	box(Vector3(26.2, 0.08, 1.2), Vector3(0, 1.88, -4.5), dark_marble, false)
	box(Vector3(26, 1.1, 0.05), Vector3(0, 2.5, -4.6), glass, false)
	for i in 5:
		var x := -10.0 + i * 5.0
		box(Vector3(0.6, 0.4, 0.4), Vector3(x, 2.1, -4.9), _m("screen", Color(0.05, 0.08, 0.12), 0.3), false)
		label("%d" % (i + 1), Vector3(x, 3.4, -4.4), 64, Color(1.0, 0.8, 0.4), 0.0, 0.006)
	# offices behind
	box(Vector3(40, 3.5, 0.3), Vector3(0, 2.45, -11.0), _m("wall2", Color(0.88, 0.86, 0.8), 0.6))
	for x in [-14.0, -6.0, 2.0]:
		box(Vector3(1.6, 0.8, 0.8), Vector3(x, 1.1, -8.5), wood)
	# vault: back-right room with big round door
	box(Vector3(0.6, 11.5, 4.0), Vector3(10.0, 6.0, -13.0), dark_marble)
	box(Vector3(10, 0.4, 4.0), Vector3(15.0, 11.5, -13.0), dark_marble)
	cyl(1.7, 0.6, Vector3(13.0, 2.4, -11.0), steel, true, Vector3(PI / 2, 0, 0))
	cyl(0.25, 0.2, Vector3(13.0, 2.4, -10.6), gold, false, Vector3(PI / 2, 0, 0))
	for i in 3:
		box(Vector3(0.12, 1.6, 0.12), Vector3(13.0, 2.4, -10.65), gold, false, i * PI / 3)
	for i in 6:
		for j in 2:
			box(Vector3(0.9, 0.25, 0.45), Vector3(12.5 + j * 1.2, 0.85 + i * 0.26, -14.2), gold, false)
	label("VAULT", Vector3(13.0, 4.8, -10.65), 72, Color(0.9, 0.9, 0.95), 0.0, 0.008)
	# waiting area, plants, rug
	box(Vector3(10, 0.03, 6), Vector3(0, 0.72, 6), _m("rug", Color(0.45, 0.08, 0.1), 0.9), false)
	for x in [-6.0, 6.0]:
		box(Vector3(3.0, 0.45, 0.8), Vector3(x, 0.92, 7.0), _m("leather", Color(0.12, 0.08, 0.06), 0.4))
	for x in [-17.0, 17.0]:
		cyl(0.45, 0.9, Vector3(x, 1.15, 12.5), dark_marble)
		cyl(0.6, 1.2, Vector3(x, 2.2, 12.5), _m("plant", Color(0.12, 0.3, 0.12), 0.8), false)
	# chandeliers
	var chand := _m("chand", Color(1.0, 0.85, 0.6), 0.5, 0.0, 5.0)
	hall_glow.append(chand)
	for p in [Vector3(-10, 10.5, 4), Vector3(10, 10.5, 4), Vector3(0, 10.5, -2)]:
		cyl(1.2, 0.25, p, chand, false)
		hall_lights.append(light(p + Vector3(0, -1.0, 0), Color(1.0, 0.88, 0.7), [1.6, 2.2, 2.6][q], 18.0))
	light(Vector3(13, 5, -13), Color(1.0, 0.9, 0.6), 1.5, 8.0)

	# ---- ATMs on the facade
	for x in [-10.0, -16.0]:
		box(Vector3(1.0, 1.9, 0.5), Vector3(x, 1.65, 15.65), steel)
		box(Vector3(0.6, 0.4, 0.05), Vector3(x, 2.1, 15.92), _m("atm", Color(0.2, 0.6, 1.0), 0.3, 0.0, 2.5), false)
		label("ATM", Vector3(x, 2.9, 15.95), 48, Color(1, 1, 1), 0.0, 0.006)

	# ---- luxury garage (x 22..42, z -24..24)
	box(Vector3(20, 0.2, 48), Vector3(32, 0.1, 0), epoxy)
	box(Vector3(20.6, 0.5, 48.6), Vector3(32, 4.55, 0), _m("gconc", Color(0.22, 0.22, 0.24), 0.7))
	box(Vector3(0.5, 4.4, 48), Vector3(42, 2.4, 0), _m("gwall", Color(0.15, 0.15, 0.17), 0.5))
	box(Vector3(20, 4.4, 0.5), Vector3(32, 2.4, -24), _m("gwall", Color(0.15, 0.15, 0.17), 0.5))
	for z in [-16.0, -8.0, 0.0, 8.0, 16.0]:
		for x in [26.0, 38.0]:
			box(Vector3(0.6, 4.3, 0.6), Vector3(x, 2.35, z), _m("pillar", Color(0.9, 0.9, 0.92), 0.3))
			box(Vector3(0.62, 0.06, 0.62), Vector3(x, 1.0, z), gold, false)
	for x in [27.0, 32.0, 37.0]:
		box(Vector3(0.12, 0.05, 46), Vector3(x, 4.27, 0), led, false)
	for z in [-18.0, -6.0, 6.0, 18.0]:
		light(Vector3(32, 3.6, z), Color(0.9, 0.95, 1.0), [1.2, 1.6, 2.0][q], 11.0)
	label("PRIVATE GARAGE", Vector3(32, 3.6, 24.3), 96, Color(0.85, 0.92, 1.0), 0.0, 0.008)
	box(Vector3(0.1, 0.1, 5.0), Vector3(30.0, 1.1, 24.6), _m("barrier", Color(0.95, 0.2, 0.2), 0.5), false, PI / 2)
	# parking bay lines
	for i in 6:
		box(Vector3(0.12, 0.01, 5.0), Vector3(23.2 + 0.0, 0.21, -21.0 + i * 8.0), _m("line", Color(0.9, 0.9, 0.9), 0.5), false, PI / 2)

	# ---- outdoor lights
	for x in [-14.0, 14.0]:
		cyl(0.08, 6.0, Vector3(x, 3.0, 28.0), steel)
		cyl(0.3, 0.2, Vector3(x, 6.0, 28.0), warm, false)
		light(Vector3(x, 5.6, 28.0), Color(1.0, 0.85, 0.6), 2.5, 14.0)


func switch_world() -> Vector3:
	return global_transform * switch_local


func toggle_lights() -> void:
	lights_on = not lights_on
	for l in hall_lights:
		l.visible = lights_on
	for m in hall_glow:
		m.emission_energy_multiplier = 5.0 if lights_on else 0.0
	switch_mesh.position.y = switch_local.y + (0.03 if lights_on else -0.03)
	Game.play_sfx("click", 0.8, -4.0)


func _physics_process(delta: float) -> void:
	if doors.is_empty() or world == null:
		return
	# doors open when anyone walks up to them
	var c := global_transform * Vector3(0, 1.0, 15.1)
	var near := false
	var who: Array = world.npcs.duplicate()
	if world.player and not world.player.dead and world.player.active:
		who.append(world.player)
	if world.net:
		who.append_array(world.net.remotes.values())
	for w in who:
		if is_instance_valid(w) and w.get("state") != NPC.DEAD and w.global_position.distance_to(c) < 3.4:
			near = true
			break
	if near != _door_was:
		_door_was = near
		var cam: Camera3D = world.current_camera()
		var d := cam.global_position.distance_to(c) if cam else 10.0
		Game.play_sfx("whoosh", 1.6, clampf(-8.0 - d * 0.5, -30.0, -8.0))
	door_open = move_toward(door_open, 1.0 if near else 0.0, delta * (1.6 if near else 0.9))
	var e := door_open * door_open * (3.0 - 2.0 * door_open)
	for dr in doors:
		dr.body.position.x = dr.x + dr.dir * e * 1.75


func spawn_cars(parent: Node) -> Array:
	var out: Array = []
	var list := [["mustang_gt", "MUSTANG GT"], ["mustang_rtr", "MUSTANG RTR"], ["mustang69", "MUSTANG BOSS 302"], ["mustang_gt", "MUSTANG GT"]]
	for i in list.size():
		var c := Car.new()
		c.model_path = "res://assets/models/cars/%s.glb" % list[i][0]
		c.display_name = list[i][1]
		c.kind = "robber"
		c.world = world
		parent.add_child(c)
		c.global_transform = global_transform * Transform3D(Basis(Vector3.UP, PI / 2), Vector3(28.0, 0.6, -17.0 + i * 8.0))
		out.append(c)
	return out


func spawn_npcs(parent: Node) -> void:
	var gt := global_transform
	var yaw := global_rotation.y
	var wp := [Vector3(-12, 0.3, 25), Vector3(12, 0.3, 25), Vector3(-10, 0.3, 16.9), Vector3(-16, 0.3, 16.9),
		Vector3(-10, 0.8, -3.2), Vector3(-5, 0.8, -3.2), Vector3(0, 0.8, -3.2), Vector3(5, 0.8, -3.2), Vector3(10, 0.8, -3.2),
		Vector3(-5, 0.8, 7), Vector3(5, 0.8, 7), Vector3(0, 0.3, 30)]
	var wpw: Array = []
	for p in wp:
		wpw.append(gt * p)
	var door_w := gt * Vector3(0, 0.8, 16.5)
	var civs: int = [4, 7, 10][q]
	for i in civs:
		_npc(parent, "civ", wpw[randi() % wpw.size()], yaw, wpw, door_w)
	for x in [-10.0, -5.0, 5.0, 10.0]:
		_npc(parent, "employee", gt * Vector3(x, 0.8, -6.0), yaw, [], door_w)
	for p in [Vector3(-4.0, 0.6, 21.0), Vector3(4.0, 0.6, 21.0), Vector3(-15, 0.8, 10), Vector3(15, 0.8, 10), Vector3(11, 0.8, -9)]:
		_npc(parent, "guard", gt * p, yaw, [], door_w)


func _npc(parent: Node, role: String, pos: Vector3, yaw: float, wp: Array, door_w: Vector3) -> void:
	var n := NPC.new()
	n.role = role
	n.world = world
	n.waypoints = wp
	n.door = door_w
	n.inside_test = is_inside
	parent.add_child(n)
	n.global_position = pos + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)) if role == "civ" else pos
	n.rotation.y = yaw
	n.home = n.global_position
	n.home_yaw = yaw
	n.face_yaw = yaw
	npcs.append(n)
