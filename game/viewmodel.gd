class_name ViewModel
extends Node3D
## Оружие и руки от первого лица. Кисти ставятся на рукоять и цевьё по опорным точкам модели (p_grip_r, p_grip_l, mv_mag…),
## предплечья тянутся к локтям за кадром; анимации процедурные: доставание, отдача, перезарядка, осмотр, удар ножом, бросок.

const PALM := Vector3(0.0, 0.088, -0.026)          # центр ладони в осях кости кисти
const ELBOW := {"r": Vector3(0.36, -0.56, 0.16), "l": Vector3(-0.30, -0.56, 0.02)}
# локти по видам хвата (точка за кадром, от которой тянется предплечье)
const ELBOWS := {
	"rifle": {"r": Vector3(0.33, -0.50, 0.12), "l": Vector3(-0.10, -0.55, 0.05)},
	"smg": {"r": Vector3(0.33, -0.50, 0.12), "l": Vector3(-0.10, -0.55, 0.05)},
	"pistol": {"r": Vector3(0.32, -0.46, 0.0), "l": Vector3(-0.03, -0.50, 0.0)},
}
const FINGERS := ["thumb", "index", "middle", "ring", "pinky"]

# положение оружия в кадре (точка рукояти в осях камеры) и повороты, град
const HOLD := {
	"rifle": {"pos": Vector3(0.120, -0.255, -0.390), "rot": Vector3(1.5, 4.0, -3.0)},
	"smg": {"pos": Vector3(0.115, -0.205, -0.440), "rot": Vector3(1.5, 4.0, -3.0)},
	"pistol": {"pos": Vector3(0.105, -0.150, -0.560), "rot": Vector3(4.0, 6.0, -3.0)},
	"knife": {"pos": Vector3(0.200, -0.175, -0.480), "rot": Vector3(28.0, 24.0, -12.0)},
	"nade": {"pos": Vector3(0.175, -0.160, -0.460), "rot": Vector3(10.0, 10.0, 0.0)},
	"c4": {"pos": Vector3(0.020, -0.240, -0.500), "rot": Vector3(62.0, 0.0, 0.0)},
}
const HOLD_W := {"awp": Vector3(0.0, -0.02, 0.0), "shotgun": Vector3(0.0, 0.0, -0.04), "m4": Vector3(0.0, -0.035, 0.02)}
# кисть: якорь (узел оружия), смещение ладони p, направление «запястье → костяшки» f, нормаль тыла кисти b; сгибы пальцев
const HANDS := {
	"rifle": {
		"r": {"at": "p_grip_r", "p": Vector3(0.019, 0.006, 0.012), "f": Vector3(-0.10, 0.32, -0.94), "b": Vector3(0.94, 0.30, 0.0), "curl": "grip"},
		"l": {"at": "p_grip_l", "p": Vector3(-0.010, -0.018, 0.0), "f": Vector3(0.52, 0.10, -0.85), "b": Vector3(-0.40, -0.90, -0.17), "curl": "cup"},
	},
	"pistol": {
		"r": {"at": "p_grip_r", "p": Vector3(0.010, 0.027, 0.022), "f": Vector3(-0.38, 0.30, -0.87), "b": Vector3(0.78, 0.25, 0.57), "curl": "grip"},
		"l": {"at": "p_grip_r", "p": Vector3(-0.024, 0.001, -0.002), "f": Vector3(0.42, 0.40, -0.81), "b": Vector3(-0.88, 0.0, -0.47), "curl": "wrap"},
	},
	"knife": {
		"r": {"at": "p_grip_r", "p": Vector3(0.016, -0.004, 0.0), "f": Vector3(-0.15, 0.80, -0.58), "b": Vector3(0.96, 0.25, 0.08), "curl": "fist"},
	},
	"nade": {
		"r": {"at": "p_grip_r", "p": Vector3(0.028, 0.0, 0.0), "f": Vector3(-0.2, 0.45, -0.87), "b": Vector3(0.9, 0.3, 0.2), "curl": "ball"},
	},
	"c4": {
		"r": {"at": "p_grip_r", "p": Vector3(0.085, 0.01, 0.02), "f": Vector3(-0.55, 0.15, -0.82), "b": Vector3(0.8, 0.3, -0.5), "curl": "cup"},
		"l": {"at": "p_grip_r", "p": Vector3(-0.085, 0.01, 0.02), "f": Vector3(0.55, 0.15, -0.82), "b": Vector3(-0.8, 0.3, -0.5), "curl": "cup"},
	},
}
const CURLS := {      # thumb, index, middle, ring, pinky: [сгиб1, сгиб2, сгиб3]
	"open": [[0.1, 0.1, 0.1], [0.15, 0.2, 0.1], [0.15, 0.2, 0.1], [0.15, 0.2, 0.1], [0.2, 0.2, 0.1]],
	"grip": [[0.55, 0.45, 0.35, 0.35], [0.62, 0.95, 0.45], [1.15, 1.45, 0.75], [1.22, 1.5, 0.8], [1.28, 1.5, 0.85]],
	"trigger": [[0.55, 0.45, 0.35, 0.35], [0.80, 1.25, 0.6], [1.15, 1.45, 0.75], [1.22, 1.5, 0.8], [1.28, 1.5, 0.85]],
	"cup": [[0.25, 0.3, 0.2, 0.6], [0.85, 1.05, 0.55], [0.9, 1.1, 0.6], [0.92, 1.1, 0.6], [0.95, 1.1, 0.6]],
	"wrap": [[0.4, 0.4, 0.3, 0.5], [1.0, 1.25, 0.6], [1.05, 1.3, 0.65], [1.1, 1.3, 0.65], [1.1, 1.3, 0.7]],
	"fist": [[0.6, 0.6, 0.5], [1.3, 1.55, 0.9], [1.35, 1.6, 0.95], [1.35, 1.6, 0.95], [1.35, 1.6, 0.95]],
	"ball": [[0.45, 0.4, 0.3], [0.75, 0.9, 0.5], [0.8, 0.95, 0.5], [0.85, 0.95, 0.5], [0.9, 0.95, 0.5]],
	"pinch": [[0.5, 0.5, 0.4], [0.9, 1.2, 0.5], [1.0, 1.3, 0.6], [1.1, 1.3, 0.6], [1.2, 1.3, 0.6]],
}

var player: Actor
var rig: Node3D
var pivot: Node3D
var weapon: Node3D
var wroot: Node3D
var wid := ""
var hold := "rifle"
var arms: Node3D
var skel: Skeleton3D
var bones := {}
var rest := {}
var fore_len := 0.30
var parts := {}                 # узлы оружия по имени
var part_rest := {}
var flash: MeshInstance3D
var draw_t := 0.0
var draw_len := 0.5
var kick_pos := Vector3.ZERO
var kick_rot := Vector3.ZERO
var kick_vel := Vector3.ZERO
var rkick_vel := Vector3.ZERO
var sway := Vector2.ZERO
var bob_ph := 0.0
var bob_amt := 0.0
var rel_t := -1.0
var rel_len := 1.0
var rel_wid := ""
var inspect_t := -1.0
var cycle_t := -1.0             # затвор «Кречета» / цевьё дробовика после выстрела
var swing_t := -1.0
var swing_alt := false
var throw_t := -1.0
var trig := 0.0
var slide_back := 0.0
var bolt_k := 0.0
var land := 0.0
var idle_t := 0.0
var fov_world := 90.0
var fov_vm := 62.0
var team_arms := ""
var grip_cam := Vector3(0.19, -0.2, -0.5)
# прицел на оружии и вскидка к глазу
var sight: Sight
var ads := 0.0                  # 0 — от бедра, 1 — глаз у окуляра
var ads_e := 0.0                # то же со сглаживанием
var hip_xf := Transform3D.IDENTITY
var ads_xf := Transform3D.IDENTITY
var grip_w := Vector3.ZERO      # рукоять в осях оружия
var scope_vp: SubViewport
var scope_cam: Camera3D
var shake_t := 0.0              # дрожь оружия после выстрела
var shake_k := 0.0

func setup(p: Actor) -> void:
	player = p
	rig = Node3D.new()
	rig.name = "Rig"
	add_child(rig)
	pivot = Node3D.new()
	pivot.name = "Pivot"
	rig.add_child(pivot)
	_load_arms(p.team)
	# picture for magnified optics: a second camera in the world, rendered only while aiming through one
	scope_vp = SubViewport.new()
	scope_vp.name = "ScopeView"
	var px := 384 if G.mobile else 640
	scope_vp.size = Vector2i(px, px)
	scope_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	scope_vp.msaa_3d = Viewport.MSAA_DISABLED if G.mobile else Viewport.MSAA_2X
	scope_vp.audio_listener_enable_3d = false
	add_child(scope_vp)
	scope_cam = Camera3D.new()
	scope_cam.cull_mask = 0xFFFFF & ~2
	scope_cam.near = 0.3
	scope_cam.far = 400.0
	scope_vp.add_child(scope_cam)
	scope_cam.current = true

func _load_arms(team: String) -> void:
	if team_arms == team and arms:
		return
	team_arms = team
	if arms:
		arms.queue_free()
	var path := "res://assets/models/chars/arms_%s.scn" % team
	arms = (load(path) as PackedScene).instantiate()
	rig.add_child(arms)
	skel = arms.find_child("Skeleton3D", true, false)
	bones.clear()
	rest.clear()
	for i in skel.get_bone_count():
		bones[skel.get_bone_name(i)] = i
		rest[i] = skel.get_bone_rest(i)
	var a := skel.get_bone_global_rest(bones["forearm_r"]).origin
	var b := skel.get_bone_global_rest(bones["hand_r"]).origin
	fore_len = a.distance_to(b)
	_layer(arms)

func _layer(n: Node) -> void:
	for c in n.find_children("*", "VisualInstance3D", true, false):
		(c as VisualInstance3D).layers = 2
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(c as GeometryInstance3D).extra_cull_margin = 4.0

func set_weapon(id: String) -> void:
	_load_arms(player.team)
	if weapon:
		weapon.queue_free()
		weapon = null
	wid = id
	parts.clear()
	part_rest.clear()
	flash = null
	rel_t = -1.0
	inspect_t = -1.0
	cycle_t = -1.0
	swing_t = -1.0
	throw_t = -1.0
	slide_back = 0.0
	if id == "" or not DB.W.has(id):
		return
	hold = DB.W[id]["hold"]
	var path := "res://assets/models/weapons/%s.scn" % id
	if not ResourceLoader.exists(path):
		return
	weapon = (load(path) as PackedScene).instantiate()
	pivot.add_child(weapon)
	wroot = weapon.get_child(0) as Node3D
	for c in wroot.get_children():
		parts[String(c.name)] = c
		part_rest[String(c.name)] = (c as Node3D).transform
	sight = Sight.attach(weapon, id, true)
	if sight:
		sight.set_scope_texture(scope_vp.get_texture())
	_layer(weapon)
	Skins.apply(weapon, id, G.equipped_skin(id))
	var h: Dictionary = HOLD.get(hold, HOLD["rifle"])
	var g: Vector3 = (parts["p_grip_r"] as Node3D).position if parts.has("p_grip_r") else Vector3.ZERO
	var r: Vector3 = h["rot"]
	var b := Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z)))
	grip_cam = (h["pos"] as Vector3) + (HOLD_W.get(id, Vector3.ZERO) as Vector3)
	weapon.transform = Transform3D(b, grip_cam - b * g)
	hip_xf = weapon.transform
	grip_w = g
	ads = 0.0
	ads_e = 0.0
	if sight:
		# aiming: weapon axes along the camera, the eye point of the optic at the camera itself
		var eye_w: Vector3 = Sight._rel(weapon, sight) * sight.eye_local()
		ads_xf = Transform3D(Basis.IDENTITY, -eye_w)
		if G.args.has("vmtest"):
			print("SIGHT %s %s builtin %s eye_w %s mount %s scope %s" % [id, sight.kind, sight.builtin, eye_w.snapped(Vector3.ONE * 0.001), Sight._mounts.get(id, {}), Sight._builtins.get(id, {})])
	if parts.has("p_muzzle"):
		flash = MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.34, 0.34) if hold != "pistol" else Vector2(0.22, 0.22)
		flash.mesh = qm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = player.game.fx.flash_tex if player.game else null
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.no_depth_test = true
		flash.material_override = mat
		flash.layers = 2
		flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flash.visible = false
		(parts["p_muzzle"] as Node3D).add_child(flash)
		flash.position = Vector3(0, 0, -0.06)
	draw_len = 0.55 if hold in ["rifle"] else 0.4
	draw_t = draw_len

func on_shot() -> void:
	var d: Dictionary = DB.W.get(wid, {})
	var cls: String = d.get("cls", "")
	inspect_t = -1.0
	if cls == "knife":
		swing_t = 0.0
		swing_alt = player.knife_alt
		return
	if cls == "nade":
		throw_t = 0.0
		return
	var rec: Array = d.get("rec", [1.0, 0.5, 6.0])
	var k: float = clampf(float(rec[0]), 0.6, 5.0)
	kick_vel += Vector3(randf_range(-0.05, 0.05), 0.04, 0.55 + 0.16 * k)
	rkick_vel += Vector3(1.8 + 1.5 * k, randf_range(-0.9, 0.9), randf_range(-1.6, 1.6)) * 0.35
	trig = 1.0
	bolt_k = 1.0
	shake_t = 1.0
	shake_k = clampf(0.35 + 0.22 * k, 0.4, 1.6)
	if flash and (cls != "pistol" or wid != "usp"):
		flash.visible = true
		flash.rotation.z = randf() * TAU
		flash.scale = Vector3.ONE * randf_range(0.75, 1.25)
		get_tree().create_timer(0.04).timeout.connect(func():
			if is_instance_valid(flash):
				flash.visible = false)
	if cls == "sniper" or cls == "shotgun":
		cycle_t = 0.0
	if player.mag() == 0 and parts.has("mv_slide"):
		slide_back = 1.0

func on_reload(id: String, t: float) -> void:
	rel_t = 0.0
	rel_len = maxf(0.3, t)
	rel_wid = id
	inspect_t = -1.0

func inspect() -> void:
	if rel_t < 0.0 and draw_t <= 0.0 and hold in ["rifle", "smg", "pistol", "knife"]:
		inspect_t = 0.0

func muzzle_world() -> Vector3:
	if not parts.has("p_muzzle"):
		return global_position - global_transform.basis.z * 0.5
	var cam := get_parent() as Node3D
	var local := cam.global_transform.affine_inverse() * (parts["p_muzzle"] as Node3D).global_position
	var k := tan(deg_to_rad(fov_vm) / 2.0) / tan(deg_to_rad(fov_world) / 2.0)
	local.x *= k
	local.y *= k
	return cam.global_transform * local

static func ss(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _rel(n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var x: Node = n
	while x != rig and x != null:
		t = (x as Node3D).transform * t
		x = x.get_parent()
	return t

func _hand_xf(spec: Dictionary) -> Transform3D:
	var anchor := parts.get(String(spec["at"]), null) as Node3D
	var at := _rel(anchor) if anchor else _rel(weapon)
	var f := (spec["f"] as Vector3).normalized()
	var b := (spec["b"] as Vector3)
	b = (b - f * b.dot(f)).normalized()
	var x := f.cross(b)
	var wb := _rel(weapon).basis.orthonormalized()
	var basis := wb * Basis(x, f, b)
	var palm := at.origin + wb * (spec["p"] as Vector3)
	return Transform3D(basis, palm - basis * PALM)

func _place(side: String, hx: Transform3D, curls: Array, elbow_off := Vector3.ZERO) -> void:
	var fi: int = bones["forearm_" + side]
	var hi: int = bones["hand_" + side]
	var wrist := hx.origin
	var elbow: Vector3 = ((ELBOWS[hold] as Dictionary)[side] if ELBOWS.has(hold) else ELBOW[side]) + elbow_off
	var dir := (wrist - elbow).normalized()
	var z := hx.basis.z
	z = (z - dir * z.dot(dir))
	z = z.normalized() if z.length() > 0.05 else dir.cross(Vector3.RIGHT).normalized()
	var x := dir.cross(z)
	skel.set_bone_global_pose(fi, Transform3D(Basis(x, dir, z), wrist - dir * fore_len))
	skel.set_bone_global_pose(hi, hx)
	for k in 5:
		var c: Array = curls[k]
		for j in 3:
			var name := "%s%d_%s" % [FINGERS[k], j + 1, side]
			if not bones.has(name):
				continue
			var bi: int = bones[name]
			var q: Quaternion = (rest[bi] as Transform3D).basis.get_rotation_quaternion()
			var ang: float = c[j]
			var rot := Quaternion(Vector3.RIGHT, -ang)
			if k == 0 and j == 0:
				# большой палец уходит под ладонь (противопоставление); 4-е число — приведение к указательному
				var sg := 1.0 if side == "r" else -1.0
				var add: float = c[3] if c.size() > 3 else 0.0
				rot = Quaternion(Vector3.BACK, -sg * add) * Quaternion(Vector3.UP, sg * ang * 1.1) * Quaternion(Vector3.RIGHT, -ang * 0.9)
			skel.set_bone_pose_rotation(bi, q * rot)

func _hide_arm(side: String) -> void:
	var down := Transform3D(Basis.IDENTITY, Vector3(0.25 if side == "r" else -0.25, -0.9, 0.2))
	_place(side, down, CURLS["open"])

func _mix_curl(a: Array, b: Array, t: float) -> Array:
	var out := []
	for k in 5:
		var row := [lerpf(a[k][0], b[k][0], t), lerpf(a[k][1], b[k][1], t), lerpf(a[k][2], b[k][2], t)]
		if k == 0:
			row.append(lerpf(a[0][3] if a[0].size() > 3 else 0.0, b[0][3] if b[0].size() > 3 else 0.0, t))
		out.append(row)
	return out

func _part(n: String, off: Vector3, rot := Vector3.ZERO) -> void:
	if not parts.has(n):
		return
	var r: Transform3D = part_rest[n]
	var node := parts[n] as Node3D
	node.transform = Transform3D(r.basis * Basis.from_euler(rot), r.origin + off)

func tick(dt: float, look_delta: Vector2) -> void:
	if weapon == null or player == null:
		return
	idle_t += dt
	var cls: String = DB.W[wid]["cls"]
	# ---- качание, шаг, отдача (пружины)
	sway = sway.lerp(Vector2(clampf(-look_delta.x * 0.9, -0.05, 0.05), clampf(look_delta.y * 0.9, -0.05, 0.05)), 1.0 - exp(-10.0 * dt))
	var sp := player.speed_h()
	var on := player.is_on_floor()
	bob_amt = lerpf(bob_amt, clampf(sp / 5.5, 0.0, 1.0) if on else 0.0, 1.0 - exp(-8.0 * dt))
	bob_ph = player.step_ph         # та же фаза, что у шагов и камеры: нижняя точка качания совпадает со звуком шага
	land = lerpf(land, clampf(-player.velocity.y * 0.006, -0.03, 0.03) if not on else 0.0, 1.0 - exp(-9.0 * dt))
	# пружины отдачи считаются мелкими шагами: при просадке кадров они не разлетаются
	var steps := clampi(int(ceil(dt / 0.006)), 1, 16)
	var h := minf(dt, 0.096) / steps
	for _i in steps:
		kick_vel += (-kick_pos * 260.0 - kick_vel * 26.0) * h
		kick_pos += kick_vel * h * 0.06
		rkick_vel += (-kick_rot * 240.0 - rkick_vel * 24.0) * h
		kick_rot += rkick_vel * h
	if not (kick_pos.is_finite() and kick_rot.is_finite() and kick_vel.is_finite() and rkick_vel.is_finite()):
		kick_pos = Vector3.ZERO
		kick_rot = Vector3.ZERO
		kick_vel = Vector3.ZERO
		rkick_vel = Vector3.ZERO
	trig = maxf(0.0, trig - dt * 9.0)
	bolt_k = maxf(0.0, bolt_k - dt * 14.0)
	# ---- вскидка к прицелу
	var want_ads := 1.0 if (sight and player.scoped and draw_t <= 0.0 and rel_t < 0.0 and inspect_t < 0.0) else 0.0
	var ads_time: float = float(DB.SIGHTS[sight.kind]["ads_t"]) if sight else 0.2
	ads = move_toward(ads, want_ads, dt / ads_time)
	ads_e = ss(0.0, 1.0, ads)
	var loose := 1.0 - 0.8 * ads_e          # у глаза оружие почти не качается
	var pos := Vector3(sin(bob_ph * 0.5) * 0.0055, -absf(sin(bob_ph)) * 0.0045, 0.0) * bob_amt * loose
	pos += Vector3(0, (sin(idle_t * 1.3) * 0.0012 + land - player.crouch_t * 0.012) * loose, 0)
	# дыхание у прицела
	pos += Vector3(sin(idle_t * 0.9) * 0.0005, sin(idle_t * 1.7) * 0.0004, 0) * ads_e
	var kk := 1.0 - 0.35 * ads_e
	pos += Vector3(kick_pos.x, kick_pos.y, kick_pos.z) * kk
	var rot := Vector3(deg_to_rad(kick_rot.x) * kk + sway.y * 0.9 * loose, sway.x * 1.1 * loose + deg_to_rad(kick_rot.y) * kk, deg_to_rad(kick_rot.z) * kk + sway.x * 1.4 * loose - sin(bob_ph * 0.5) * 0.012 * bob_amt * loose)
	# ---- дрожь после выстрела: короткая мелкая вибрация, затухает за ~0.12 с
	if shake_t > 0.0:
		shake_t = maxf(0.0, shake_t - dt * 8.5)
		var a := shake_t * shake_t * shake_k
		pos += Vector3(randf_range(-1, 1) * 0.0022, randf_range(-1, 1) * 0.0018, randf_range(-0.5, 1.0) * 0.003) * a
		rot += Vector3(randf_range(-1, 1) * 0.011, randf_range(-1, 1) * 0.008, randf_range(-1, 1) * 0.016) * a
	weapon.transform = hip_xf.interpolate_with(ads_xf, ads_e) if sight else hip_xf
	# ---- доставание
	if draw_t > 0.0:
		draw_t = maxf(0.0, draw_t - dt)
		var k := pow(draw_t / draw_len, 2.0)
		pos += Vector3(0.03, -0.24, 0.06) * k
		rot += Vector3(deg_to_rad(-38.0), deg_to_rad(12.0), deg_to_rad(18.0)) * k
	# ---- части оружия
	for n in parts:
		if String(n).begins_with("mv_"):
			(parts[n] as Node3D).transform = part_rest[n]
			(parts[n] as Node3D).visible = true
	_part("mv_trigger", Vector3(0, 0, 0.004 * trig), Vector3(-0.25 * trig, 0, 0))
	if parts.has("mv_slide"):
		_part("mv_slide", Vector3(0, 0, 0.036 * maxf(bolt_k, slide_back)))
	elif parts.has("mv_bolt") and cls != "sniper":
		_part("mv_bolt", Vector3(0, 0, 0.055 * bolt_k))
	var hs: Dictionary = HANDS.get(hold, HANDS["rifle"])
	var rspec: Dictionary = hs["r"]
	var lspec = hs.get("l", null)
	var rcurl: Array = _mix_curl(CURLS[String(rspec["curl"])], CURLS["trigger"], trig) if hold in ["rifle", "smg", "pistol"] else CURLS[String(rspec["curl"])]
	var lcurl: Array = CURLS[String(lspec["curl"])] if lspec else CURLS["open"]
	var l_over = null           # Transform3D левой кисти, если она снята с цевья
	var l_mix := 0.0
	var l_shift := Vector3.ZERO  # сдвиг левой кисти в осях оружия (цевьё дробовика)
	# ---- перезарядка
	if rel_t >= 0.0:
		var t_prev := rel_t / rel_len
		rel_t += dt
		var t := rel_t / rel_len
		# звуки перезарядки — по событиям анимации
		if cls == "shotgun":
			var sh0 := int(floor(maxf(0.0, t_prev * rel_len - 0.25) / 0.5))
			var sh1 := int(floor(maxf(0.0, t * rel_len - 0.25) / 0.5))
			if sh1 != sh0 or (t_prev * rel_len < 0.25 and t * rel_len >= 0.25):
				Sfx.play("shell_in", -7.0, randf_range(0.96, 1.05))
		else:
			var ev := [[0.24, "p_mag_out" if cls == "pistol" else "mag_out"], [0.66, "p_mag_in" if cls == "pistol" else "mag_in"], [0.84, "slide" if cls == "pistol" else "bolt"]]
			for e in ev:
				if t_prev < e[0] and t >= e[0]:
					if G.args.has("sndlog"):
						print("EV %d anim_%s" % [Time.get_ticks_msec(), e[1]])
					Sfx.play(e[1], -6.0, randf_range(0.97, 1.03))
		if t >= 1.0:
			rel_t = -1.0
			slide_back = 0.0
		else:
			var tilt := ss(0.0, 0.12, t) * (1.0 - ss(0.88, 1.0, t))
			if cls == "shotgun":
				rot += Vector3(deg_to_rad(10.0), deg_to_rad(-6.0), deg_to_rad(-34.0)) * tilt
				pos += Vector3(-0.02, 0.02, 0.02) * tilt
				var shells := maxf(1.0, (rel_len - 0.5) / 0.5)
				var ph := fmod(maxf(0.0, t * rel_len - 0.25), 0.5) / 0.5
				var feed := sin(ph * PI)
				var s := {"at": "p_load", "p": Vector3(-0.01, -0.05 + 0.03 * feed, 0.03 - 0.03 * feed), "f": Vector3(0.75, 0.45, -0.48), "b": Vector3(-0.3, -0.75, -0.6), "curl": "pinch"}
				l_over = _hand_xf(s)
				l_mix = tilt
				lcurl = CURLS["pinch"]
			else:
				var pistol := cls == "pistol"
				# ствол вверх, оружие заваливается магазином к центру кадра и поднимается: смена магазина видна целиком
				rot += Vector3(deg_to_rad(16.0 if not pistol else 22.0), deg_to_rad(3.0 if not pistol else -3.0), deg_to_rad(-34.0 if not pistol else -24.0)) * tilt
				pos += (Vector3(-0.03, 0.105, 0.02) if not pistol else Vector3(-0.02, 0.05, 0.03)) * tilt
				# магазин: вниз и наружу, затем новый вверх
				var out := ss(0.22, 0.40, t)
				var back := ss(0.50, 0.68, t)
				var mo := out * (1.0 - back)
				var drop := Vector3(-0.02, -0.26, 0.05) * mo
				_part("mv_mag", drop, Vector3(0.35 * mo, 0, 0.25 * mo))
				if parts.has("mv_mag") and t > 0.41 and t < 0.49:
					(parts["mv_mag"] as Node3D).visible = false
				var bump := sin(ss(0.66, 0.74, t) * PI)
				pos += Vector3(0, 0.006, 0) * bump
				# левая кисть: цевьё -> магазин -> затвор -> цевьё
				var mh := 0.13 if not pistol else 0.07
				var ms := {"at": "mv_mag", "p": Vector3(-0.012, -mh, 0.0), "f": Vector3(0.72, 0.52, -0.46), "b": Vector3(-0.45, -0.25, -0.86), "curl": "wrap"}
				var to_mag := ss(0.08, 0.22, t) * (1.0 - ss(0.70, 0.80, t))
				l_over = _hand_xf(ms)
				l_mix = to_mag
				lcurl = _mix_curl(lcurl, CURLS["wrap"], to_mag)
				# затвор / затворная задержка — то, что слышно в конце перезарядки, должно быть видно
				var rack := sin(ss(0.80, 0.92, t) * PI)
				var to_bolt := ss(0.74, 0.82, t) * (1.0 - ss(0.92, 0.99, t))
				var bs = null
				if pistol:
					if slide_back > 0.0:
						# затвор стоял на задержке: в момент щелчка уходит вперёд
						slide_back = 1.0 if t < 0.84 else 0.0
						_part("mv_slide", Vector3(0, 0, 0.036 * slide_back))
					else:
						# патрон в стволе: левая рука передёргивает затвор
						_part("mv_slide", Vector3(0, 0, 0.036 * rack))
						bs = {"at": "mv_slide", "p": Vector3(-0.024, 0.0, 0.03 + 0.03 * rack), "f": Vector3(0.25, 0.80, -0.55), "b": Vector3(-0.95, 0.15, -0.25), "curl": "pinch"}
				elif parts.has("mv_bolt"):
					_part("mv_bolt", Vector3(0, 0, 0.06 * rack))
					bs = {"at": "mv_bolt", "p": Vector3(0.03, -0.01, 0.0), "f": Vector3(0.9, 0.15, -0.4), "b": Vector3(-0.2, 0.95, -0.2), "curl": "pinch"}
					rot += Vector3(deg_to_rad(-6.0), 0, deg_to_rad(30.0)) * to_bolt
				else:
					# затворная задержка: шлепок ладонью по левой стороне ствольной коробки
					bs = {"at": "p_grip_r", "p": Vector3(-0.045 + 0.02 * rack, 0.09, -0.07), "f": Vector3(0.25, 0.62, -0.74), "b": Vector3(-0.95, 0.1, -0.28), "curl": "open"}
					rot += Vector3(0, deg_to_rad(-1.5), deg_to_rad(10.0)) * to_bolt + Vector3(0, 0, deg_to_rad(-3.0)) * rack
					pos += Vector3(0.006, 0, 0) * rack
				if bs != null and to_bolt > 0.01:
					l_over = _hand_xf(ms).interpolate_with(_hand_xf(bs), to_bolt) if l_mix > 0.01 else _hand_xf(bs)
					l_mix = maxf(l_mix, to_bolt)
	# ---- затвор снайперской винтовки / цевьё дробовика после выстрела
	if cycle_t >= 0.0:
		var c_prev := cycle_t
		cycle_t += dt
		var c_at := 0.24 if cls == "sniper" else 0.08
		if c_prev < c_at and cycle_t >= c_at:
			Sfx.play("bolt" if cls == "sniper" else "pump", -6.0)
		var ct := cycle_t / (0.95 if cls == "sniper" else 0.5)
		if ct >= 1.0:
			cycle_t = -1.0
		elif cls == "sniper":
			var k2 := ss(0.25, 0.5, ct) * (1.0 - ss(0.6, 0.85, ct))
			_part("mv_bolt", Vector3(0, 0, 0.085 * k2), Vector3(0, 0, -0.9 * ss(0.15, 0.3, ct) * (1.0 - ss(0.8, 0.95, ct))))
			rot += Vector3(deg_to_rad(-9.0), deg_to_rad(6.0), deg_to_rad(-20.0)) * sin(ct * PI)      # ствол клюёт, винтовка идёт на себя — затвор работает
			pos += Vector3(0.01, -0.04, 0.05) * sin(ct * PI)
		else:
			var k3 := sin(ss(0.15, 0.85, ct) * PI)
			_part("mv_pump", Vector3(0, 0, 0.075 * k3))
			l_shift = Vector3(0, 0, 0.075 * k3)          # левая кисть едет вместе с цевьём
			rot += Vector3(deg_to_rad(5.0), deg_to_rad(2.0), deg_to_rad(-7.0)) * k3
			pos += Vector3(0, -0.01, 0.02) * k3
	# ---- осмотр
	if inspect_t >= 0.0:
		inspect_t += dt
		var it := inspect_t / 3.4
		if it >= 1.0 or player.speed_h() > 4.5:
			inspect_t = -1.0
		else:
			var k4 := ss(0.0, 0.18, it) * (1.0 - ss(0.82, 1.0, it))
			var turn := sin(it * TAU * 1.0) * 0.5
			rot += Vector3(deg_to_rad(18.0), deg_to_rad(42.0 + 25.0 * turn), deg_to_rad(-58.0 - 30.0 * turn)) * k4
			pos += Vector3(-0.065, 0.05, 0.03) * k4
			if lspec:
				l_over = Transform3D(_hand_xf(lspec).basis, _hand_xf(lspec).origin + (Vector3(-0.10, -0.26, 0.0) if hold == "pistol" else Vector3(-0.12, -0.2, 0.06)))
				l_mix = k4
				lcurl = _mix_curl(lcurl, CURLS["open"], k4)
	# ---- нож
	if swing_t >= 0.0:
		swing_t += dt
		var st := swing_t / (0.42 if not swing_alt else 0.75)
		if st >= 1.0:
			swing_t = -1.0
		elif not swing_alt:
			var a := sin(ss(0.0, 1.0, st) * PI)
			var w := ss(0.0, 0.35, st) - ss(0.35, 1.0, st) * 1.0
			rot += Vector3(deg_to_rad(-8.0 * a), deg_to_rad(70.0 * w), deg_to_rad(-50.0 * a))
			pos += Vector3(-0.17 * ss(0.1, 0.5, st) * (1.0 - ss(0.6, 1.0, st)), -0.02 * a, -0.10 * a)
		else:
			var back2 := ss(0.0, 0.25, st) * (1.0 - ss(0.25, 0.4, st))
			var fwd2 := ss(0.25, 0.42, st) * (1.0 - ss(0.6, 1.0, st))
			pos += Vector3(-0.07 * fwd2, 0.03 * fwd2, 0.10 * back2 - 0.24 * fwd2)
			rot += Vector3(deg_to_rad(-24.0 * fwd2), deg_to_rad(10.0 * fwd2), 0)
	# ---- бросок гранаты
	if throw_t >= 0.0:
		throw_t += dt
		var tt := throw_t / 0.75
		if tt >= 1.0:
			throw_t = -1.0
		else:
			var back3 := ss(0.0, 0.3, tt) * (1.0 - ss(0.3, 0.45, tt))
			var fwd3 := ss(0.3, 0.5, tt)
			pos += Vector3(0.05 * back3, 0.10 * back3 - 0.5 * fwd3, 0.14 * back3 - 0.25 * fwd3 * (1.0 - fwd3))
			rot += Vector3(deg_to_rad(40.0 * back3 - 70.0 * fwd3), 0, 0)
			if tt > 0.42:
				weapon.visible = false
	else:
		weapon.visible = true
	if cls == "c4" and player.plant_t >= 0.0:
		var pk := player.plant_t / DB.T_PLANT
		pos += Vector3(0, -0.03 - 0.02 * pk, -0.04 * pk)
		rot += Vector3(deg_to_rad(8.0 * sin(player.plant_t * 9.0)), 0, 0) * 0.3
	if player.defuse_t >= 0.0:
		pos += Vector3(0, -0.3, 0.1)
	# повороты — вокруг рукояти (кисти), а не вокруг камеры
	var rb := Basis.from_euler(rot)
	var piv := (hip_xf * grip_w).lerp(ads_xf * grip_w, ads_e)
	rig.transform = Transform3D(rb, pos + piv - rb * piv)
	# ---- руки (у прицела локти сходятся к центру)
	var rx := _hand_xf(rspec)
	_place("r", rx, rcurl, Vector3(-0.15, 0.05, 0.06) * ads_e)
	if lspec:
		var lx := _hand_xf(lspec)
		if l_shift != Vector3.ZERO:
			lx.origin += _rel(weapon).basis.orthonormalized() * l_shift
		if l_over != null and l_mix > 0.001:
			lx = lx.interpolate_with(l_over, l_mix)
		_place("l", lx, lcurl, Vector3(0.05, 0.04, 0.0) * ads_e)
	else:
		_hide_arm("l")
	# ---- прицел: сетка коллиматора на бесконечности или картинка оптики
	if sight:
		var vcam := get_parent() as Camera3D
		var live := ss(0.45, 0.9, ads_e)
		var need_view := sight.magnified() and ads_e > 0.3 and visible
		scope_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if need_view else SubViewport.UPDATE_DISABLED
		sight.update_fp(vcam, fov_world, fov_vm, live, scope_cam)
	elif scope_vp.render_target_update_mode != SubViewport.UPDATE_DISABLED:
		scope_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
