extends Node3D
## Character animator (players and NPCs), driven by Mixamo motion-capture clips.
## 1. Clips from anims.glb are sampled and blended in code (no shared skeleton needed).
## 2. The blended Mixamo pose is retargeted onto the CC "composer" skeleton (hero.glb),
##    fingers included (real fists when punching, real grip on weapons).
## 3. Procedural extras: aim pitch through the spine, prone, recoil, reload hand.
## 4. For cop-based characters the composer pose is retargeted onto the visible cop.
## 5. Rifles are placed from the two hands, so the barrel/muzzle follows every animation.

const LIB_PATH := "res://assets/models/chars/anims.glb"
const W = preload("res://scripts/game3d/weapons.gd")
const X := Vector3.RIGHT
const Y := Vector3.UP
const Z := Vector3.BACK

const MAP := {
	"Hips": "CC_Base_Hip", "Spine": "CC_Base_Waist", "Spine1": "CC_Base_Spine01", "Spine2": "CC_Base_Spine02",
	"Neck": "CC_Base_NeckTwist01", "Head": "CC_Base_Head",
	"LeftShoulder": "CC_Base_L_Clavicle", "LeftArm": "CC_Base_L_Upperarm", "LeftForeArm": "CC_Base_L_Forearm", "LeftHand": "CC_Base_L_Hand",
	"RightShoulder": "CC_Base_R_Clavicle", "RightArm": "CC_Base_R_Upperarm", "RightForeArm": "CC_Base_R_Forearm", "RightHand": "CC_Base_R_Hand",
	"LeftUpLeg": "CC_Base_L_Thigh", "LeftLeg": "CC_Base_L_Calf", "LeftFoot": "CC_Base_L_Foot", "LeftToeBase": "CC_Base_L_ToeBase",
	"RightUpLeg": "CC_Base_R_Thigh", "RightLeg": "CC_Base_R_Calf", "RightFoot": "CC_Base_R_Foot", "RightToeBase": "CC_Base_R_ToeBase",
}
const FINGERS := {"Thumb": "Thumb", "Index": "Index", "Middle": "Mid", "Ring": "Ring", "Pinky": "Pinky"}
const ARM_KEYS := ["Shoulder", "Arm", "ForeArm", "Hand"]

# ---------------------------------------------------------------- shared clip library
static var L := {}


static func _lib() -> Dictionary:
	if not L.is_empty():
		return L
	var scene: Node = load(LIB_PATH).instantiate()
	var root: Node3D = scene.get_node("Rig")
	var names: Array = []
	var parent := PackedInt32Array()
	var rest_q: Array = []
	var nodes: Array = []
	var stack: Array = [[root.get_child(0), -1]]
	while stack.size() > 0:
		var it: Array = stack.pop_back()
		var n: Node3D = it[0]
		var idx := names.size()
		names.append(str(n.name).replace("mixamorig_", "").replace("mixamorig:", ""))
		parent.append(it[1])
		rest_q.append(n.transform.basis.get_rotation_quaternion())
		nodes.append(n)
		var kids := n.get_children()
		kids.reverse()
		for k in kids:
			if k is Node3D:
				stack.append([k, idx])
	var root_q := root.transform.basis.get_rotation_quaternion()
	var rest_g: Array = []
	rest_g.resize(names.size())
	for b in names.size():
		rest_g[b] = (rest_g[parent[b]] if parent[b] >= 0 else root_q) * rest_q[b]
	var by_name := {}
	for b in names.size():
		by_name[names[b]] = b
	var hips_rest_y: float = (root.transform * (nodes[0] as Node3D).position).y
	var ap: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
	var anims := {}
	for an_name in ap.get_animation_list():
		var an: Animation = ap.get_animation(an_name)
		var rot := PackedInt32Array()
		rot.resize(names.size())
		rot.fill(-1)
		var hp := -1
		for ti in an.get_track_count():
			var bn := str(an.track_get_path(ti)).get_file().replace("mixamorig_", "").replace("mixamorig:", "")
			if not by_name.has(bn):
				continue
			if an.track_get_type(ti) == Animation.TYPE_ROTATION_3D:
				rot[by_name[bn]] = ti
			elif an.track_get_type(ti) == Animation.TYPE_POSITION_3D and bn == "Hips":
				hp = ti
		anims[an_name] = {"a": an, "rot": rot, "hp": hp, "len": an.length}
	L = {"names": names, "parent": parent, "rest_q": rest_q, "rest_g": rest_g, "root_q": root_q,
		"root_xf": root.transform, "by_name": by_name, "hips_rest_y": hips_rest_y, "anims": anims}
	scene.free()
	_bake_cop_walk()
	return L


## The unarmed walk comes from cop.glb (different bone rest), so it is converted
## frame by frame into the library skeleton's local rotations.
static func _bake_cop_walk() -> void:
	var cs: Node = load("res://assets/models/chars/cop.glb").instantiate()
	var sk: Skeleton3D = cs.find_children("*", "Skeleton3D", true, false)[0]
	var aps := cs.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		cs.free()
		return
	var ap: AnimationPlayer = aps[0]
	var an: Animation = ap.get_animation(ap.get_animation_list()[0])
	var skq := Quaternion.IDENTITY
	var n: Node = sk
	while n and n != cs:
		if n is Node3D:
			skq = (n as Node3D).transform.basis.get_rotation_quaternion() * skq
		n = n.get_parent()
	var nb := sk.get_bone_count()
	var crest_l: Array = []
	var crest_g: Array = []
	crest_l.resize(nb)
	crest_g.resize(nb)
	for b in nb:
		crest_l[b] = sk.get_bone_rest(b).basis.get_rotation_quaternion()
		var p := sk.get_bone_parent(b)
		crest_g[b] = (crest_g[p] * crest_l[b]) if p >= 0 else skq * crest_l[b]
	var trk := PackedInt32Array()
	trk.resize(nb)
	trk.fill(-1)
	var hp := -1
	for ti in an.get_track_count():
		var path := str(an.track_get_path(ti))
		var bn := path.substr(path.find(":") + 1)
		var bi := sk.find_bone(bn)
		if bi < 0:
			continue
		if an.track_get_type(ti) == Animation.TYPE_ROTATION_3D:
			trk[bi] = ti
		elif an.track_get_type(ti) == Animation.TYPE_POSITION_3D and bn.contains("Hips"):
			hp = ti
	# lib bone -> cop bone by short name
	var lnames: Array = L.names
	var map := PackedInt32Array()
	map.resize(lnames.size())
	var suffix := RegEx.create_from_string("_\\d+$")
	var hips_b := 0
	for lb in lnames.size():
		map[lb] = -1
		for b in nb:
			var nm := suffix.sub(sk.get_bone_name(b).replace("mixamorig_", "").replace("mixamorig:", ""), "")
			if nm == "Hips":
				hips_b = b
			if nm == lnames[lb]:
				map[lb] = b
				break
	var hips_rest_c: float = (skq * sk.get_bone_global_rest(hips_b).origin).y
	var fps := 30.0
	var frames: Array = []
	var hips: PackedFloat32Array = []
	var count := int(an.length * fps)
	for f in count:
		var t := f / fps
		var g: Array = []
		g.resize(nb)
		for b in nb:
			var q: Quaternion = an.rotation_track_interpolate(trk[b], t) if trk[b] >= 0 else crest_l[b]
			var p := sk.get_bone_parent(b)
			g[b] = (g[p] * q) if p >= 0 else skq * q
		var lg: Array = []
		lg.resize(lnames.size())
		var loc: Array = []
		loc.resize(lnames.size())
		for lb in lnames.size():
			var par: int = L.parent[lb]
			var cb: int = map[lb]
			if cb >= 0:
				var delta: Quaternion = g[cb] * (crest_g[cb] as Quaternion).inverse()
				lg[lb] = delta * (L.rest_g[lb] as Quaternion)
			else:
				lg[lb] = ((lg[par] if par >= 0 else L.root_q) as Quaternion) * L.rest_q[lb]
			loc[lb] = (((lg[par] if par >= 0 else L.root_q) as Quaternion).inverse() * lg[lb]).normalized()
		frames.append(loc)
		var hy: float = L.hips_rest_y
		if hp >= 0:
			hy = float(L.hips_rest_y) * ((skq * an.position_track_interpolate(hp, t)).y / maxf(hips_rest_c, 0.0001))
		hips.append(hy)
	L.anims["walk"] = {"baked": frames, "hips": hips, "fps": fps, "len": an.length}
	cs.free()


# ---------------------------------------------------------------- instance
var variant := "hero"
var hero: Node3D
var hero_sk: Skeleton3D
var cop: Node3D
var cop_sk: Skeleton3D
var visual: Node3D
var vis_sk: Skeleton3D
var map_lh: Array = []        # [lib bone, hero bone]
var pairs_hc: Array = []
var rest_hc := {}
var rel_lh := Quaternion.IDENTITY
var rel_hc := Quaternion.IDENTITY
var hero_rest_g: Array = []
var hb := {}
var hrest := {}
var arm_mask := PackedByteArray()  # lib bones belonging to the arms
var hip_scale := 1.0
var ik_bones := {}
var palm_bones := {}
var head_bone := -1
var _seed := 0.0

# state set by the owner
var stance := 0               # 0 stand, 1 crouch, 2 prone
var dead := false
var death_clip := "death_front"
var weapon: Node3D = null
var weapon_id := ""
var grips := {}
var aiming := false
var punch_t := -1.0           # seconds into the punch clip, -1 = not punching
var punch_side := 1
var guard_w := 0.0
var reload_t := -1.0          # 0..1 progress of a reload
var recoil := 0.0
var in_air := false

# blend state
var _w := {}                  # smoothed weights
var _phase := 0.0
var _idle_t := 0.0
var _dead_t := 0.0
var _prone_w := 0.0
var _armed_w := 0.0
var _unarmed_run_w := 0.0
var _calib_id := ""
var _calib := Transform3D()


func _find(sk: Skeleton3D, key: String) -> int:
	var re := RegEx.create_from_string("(?i)mixamorig[:_]" + key + "(_\\d+)?$")
	for b in sk.get_bone_count():
		if re.search(sk.get_bone_name(b)):
			return b
	return -1


func _skel(n: Node) -> Skeleton3D:
	var s := n.find_children("*", "Skeleton3D", true, false)
	return s[0] if s.size() > 0 else null


func _strip_meshes(n: Node) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		mi.queue_free()


func _in_group(mi: Node, key: String) -> bool:
	if mi is MeshInstance3D and mi.mesh:
		for si in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(si)
			if m and m.resource_name.contains(key.trim_suffix("s")):
				return true
	var p := mi
	while p:
		if str(p.name).contains(key):
			return true
		p = p.get_parent()
	return false


func _all_map() -> Dictionary:
	var m := MAP.duplicate()
	for side in [["Left", "L"], ["Right", "R"]]:
		for f in FINGERS:
			for i in [1, 2, 3]:
				m["%sHand%s%d" % [side[0], f, i]] = "CC_Base_%s_%s%d" % [side[1], FINGERS[f], i]
	return m


func setup(cop_team) -> void:
	if cop_team is bool:
		variant = "cop" if cop_team else "hero"
	else:
		variant = str(cop_team)
	_seed = randf() * 100.0
	_idle_t = randf() * 8.0
	var lib := _lib()
	hero = load("res://assets/models/chars/hero.glb").instantiate()
	add_child(hero)
	hero_sk = _skel(hero)
	for a in hero.find_children("*", "AnimationPlayer", true, false):
		a.queue_free()
	if variant != "hero":
		cop = load("res://assets/models/chars/cop.glb").instantiate()
		add_child(cop)
		cop_sk = _skel(cop)
		for a in cop.find_children("*", "AnimationPlayer", true, false):
			a.queue_free()
		_strip_meshes(hero)
		visual = cop
		vis_sk = cop_sk
		_normalize_height(cop)
		var rs := _find(cop_sk, "RightArm")
		if rs >= 0:
			var sh_y: float = (global_transform.affine_inverse() * (cop_sk.global_transform * cop_sk.get_bone_global_rest(rs).origin)).y
			if sh_y > 0.5:
				cop.scale *= 1.48 / sh_y
		_dress(cop)
	else:
		visual = hero
		vis_sk = hero_sk
	var q: int = clampi(int(Game.settings.quality), 0, 2)
	for mi in visual.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if q > 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for b in hero_sk.get_bone_count():
		hb[hero_sk.get_bone_name(b)] = b
		hrest[hero_sk.get_bone_name(b)] = hero_sk.get_bone_rest(b).basis.get_rotation_quaternion()
	hero_rest_g = _globals(hero_sk)
	var full := _all_map()
	arm_mask.resize(lib.names.size())
	arm_mask.fill(0)
	for k in full:
		var lb: int = lib.by_name.get(k, -1)
		var h: int = hb.get(full[k], -1)
		if lb >= 0 and h >= 0:
			map_lh.append([lb, h])
			if cop_sk:
				var c := _find(cop_sk, k)
				if c >= 0:
					pairs_hc.append([h, c])
	for b in lib.names.size():
		var nm: String = lib.names[b]
		if nm.begins_with("Left") or nm.begins_with("Right"):
			if nm.contains("Hand") or nm.ends_with("Shoulder") or nm.ends_with("Arm"):
				arm_mask[b] = 1
	var hq := (global_transform.affine_inverse() * hero_sk.global_transform).basis.get_rotation_quaternion()
	rel_lh = hq.inverse()
	if cop_sk:
		rest_hc = {"h": hero_rest_g, "c": _globals(cop_sk)}
		var cq := (global_transform.affine_inverse() * cop_sk.global_transform).basis.get_rotation_quaternion()
		rel_hc = cq.inverse() * hq
	var hip: int = hb.get("CC_Base_Hip", -1)
	if hip >= 0:
		var hy: float = (global_transform.affine_inverse() * (hero_sk.global_transform * hero_sk.get_bone_global_rest(hip).origin)).y
		hip_scale = hy / maxf(float(lib.hips_rest_y), 0.01)
	if cop_sk:
		ik_bones["R"] = [_find(cop_sk, "RightArm"), _find(cop_sk, "RightForeArm"), _find(cop_sk, "RightHand")]
		ik_bones["L"] = [_find(cop_sk, "LeftArm"), _find(cop_sk, "LeftForeArm"), _find(cop_sk, "LeftHand")]
		palm_bones = {"R": _find(cop_sk, "RightHandMiddle1"), "L": _find(cop_sk, "LeftHandMiddle1")}
		head_bone = _find(cop_sk, "Head")
	else:
		ik_bones["R"] = [hb.get("CC_Base_R_Upperarm", -1), hb.get("CC_Base_R_Forearm", -1), hb.get("CC_Base_R_Hand", -1)]
		ik_bones["L"] = [hb.get("CC_Base_L_Upperarm", -1), hb.get("CC_Base_L_Forearm", -1), hb.get("CC_Base_L_Hand", -1)]
		palm_bones = {"R": hb.get("CC_Base_R_Mid1", -1), "L": hb.get("CC_Base_L_Mid1", -1)}
		head_bone = hb.get("CC_Base_Head", -1)


func _normalize_height(n: Node3D) -> void:
	var ab := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = (n.global_transform.affine_inverse() * mi.global_transform) * (mi as MeshInstance3D).get_aabb()
		if first:
			ab = a
			first = false
		else:
			ab = ab.merge(a)
	if ab.size.y > 0.5:
		n.scale = Vector3.ONE * (1.82 / ab.size.y)


func _tint(mi: MeshInstance3D, col: Color) -> void:
	for si in mi.mesh.get_surface_count():
		var m = mi.mesh.surface_get_material(si)
		if m is StandardMaterial3D:
			var m2: StandardMaterial3D = m.duplicate()
			m2.albedo_color = col
			mi.set_surface_override_material(si, m2)


func _dress(n: Node3D) -> void:
	var tops := [Color(0.85, 0.85, 0.85), Color(0.6, 0.15, 0.12), Color(0.2, 0.35, 0.6), Color(0.25, 0.45, 0.25), Color(0.75, 0.6, 0.35), Color(0.4, 0.4, 0.42)]
	var bottoms := [Color(0.25, 0.25, 0.28), Color(0.6, 0.55, 0.45), Color(0.18, 0.2, 0.3), Color(0.5, 0.5, 0.5)]
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		match variant:
			"civ":
				if _in_group(mi, "Hats"):
					mi.visible = false
				elif _in_group(mi, "Tops"):
					_tint(mi, tops[randi() % tops.size()] * 1.6)
				elif _in_group(mi, "Bottoms"):
					_tint(mi, bottoms[randi() % bottoms.size()] * 1.5)
			"employee":
				if _in_group(mi, "Hats"):
					mi.visible = false
				elif _in_group(mi, "Tops"):
					_tint(mi, Color(1.8, 1.8, 1.8))
				elif _in_group(mi, "Bottoms"):
					_tint(mi, Color(0.35, 0.35, 0.4))
			"guard":
				if _in_group(mi, "Tops"):
					_tint(mi, Color(0.35, 0.35, 0.38))
				elif _in_group(mi, "Bottoms"):
					_tint(mi, Color(0.3, 0.3, 0.32))


func _globals(sk: Skeleton3D) -> Array:
	var n := sk.get_bone_count()
	var g := []
	g.resize(n)
	for b in n:
		var q: Quaternion = sk.get_bone_rest(b).basis.get_rotation_quaternion()
		var p := sk.get_bone_parent(b)
		g[b] = (g[p] * q) if (p >= 0 and p < b) else q
	return g


# ---------------------------------------------------------------- sampling
## clips: Array of [name, time, weight]; returns [locals: Array[Quaternion], hips_y]
func _sample(clips: Array, mask_only := false) -> Array:
	var lib := L
	var nb: int = lib.names.size()
	var acc: Array = []
	acc.resize(nb)
	var tw := 0.0
	var hy := 0.0
	for c in clips:
		var w: float = c[2]
		if w <= 0.001:
			continue
		var d: Dictionary = lib.anims.get(c[0], {})
		if d.is_empty():
			continue
		var t: float = c[1]
		var baked: bool = d.has("baked")
		var an: Animation = null if baked else d.a
		var rot: PackedInt32Array = PackedInt32Array() if baked else d.rot
		var fa: Array = []
		var fb: Array = []
		var ft := 0.0
		if baked:
			var fr: Array = d.baked
			var fx: float = fmod(t, float(d.len)) * float(d.fps)
			var i0 := int(fx) % fr.size()
			fa = fr[i0]
			fb = fr[(i0 + 1) % fr.size()]
			ft = fx - floorf(fx)
		for b in nb:
			if mask_only and arm_mask[b] == 0:
				continue
			var q: Quaternion
			if baked:
				q = (fa[b] as Quaternion).slerp(fb[b], ft)
			else:
				q = an.rotation_track_interpolate(rot[b], t) if rot[b] >= 0 else lib.rest_q[b]
			var v := Vector4(q.x, q.y, q.z, q.w)
			if acc[b] == null:
				acc[b] = v * w
			else:
				var a4: Vector4 = acc[b]
				if a4.dot(v) < 0.0:
					v = -v
				acc[b] = a4 + v * w
		if baked:
			var hs: PackedFloat32Array = d.hips
			hy += hs[int(fmod(t, float(d.len)) * float(d.fps)) % hs.size()] * w
		elif d.hp >= 0:
			hy += ((lib.root_xf as Transform3D) * an.position_track_interpolate(d.hp, t)).y * w
		else:
			hy += float(lib.hips_rest_y) * w
		tw += w
	var out: Array = []
	out.resize(nb)
	for b in nb:
		if acc[b] == null:
			out[b] = lib.rest_q[b]
		else:
			var v2: Vector4 = acc[b]
			out[b] = Quaternion(v2.x, v2.y, v2.z, v2.w).normalized()
	return [out, hy / tw if tw > 0.0 else float(lib.hips_rest_y)]


func _apply_lib_pose(loc: Array) -> void:
	var lib := L
	var nb: int = lib.names.size()
	var g: Array = []
	g.resize(nb)
	var par: PackedInt32Array = lib.parent
	var rest_g: Array = lib.rest_g
	for b in nb:
		g[b] = (g[par[b]] if par[b] >= 0 else lib.root_q) * loc[b]
	var target := {}
	for pr in map_lh:
		var lb: int = pr[0]
		var h: int = pr[1]
		var delta: Quaternion = g[lb] * (rest_g[lb] as Quaternion).inverse()
		target[h] = (rel_lh * delta * rel_lh.inverse()) * (hero_rest_g[h] as Quaternion)
	_write_globals(hero_sk, target)


func _write_globals(dst: Skeleton3D, target: Dictionary) -> void:
	var n := dst.get_bone_count()
	var g := []
	g.resize(n)
	for b in n:
		var p := dst.get_bone_parent(b)
		var pg: Quaternion = g[p] if (p >= 0 and p < b) else Quaternion.IDENTITY
		if target.has(b):
			g[b] = target[b]
			dst.set_bone_pose_rotation(b, (pg.inverse() * target[b]).normalized())
		else:
			var r: Quaternion = dst.get_bone_rest(b).basis.get_rotation_quaternion()
			g[b] = pg * r
			dst.set_bone_pose_rotation(b, r)


func _hero_to_cop() -> void:
	var sg := []
	var n := hero_sk.get_bone_count()
	sg.resize(n)
	for b in n:
		var p := hero_sk.get_bone_parent(b)
		var q: Quaternion = hero_sk.get_bone_pose_rotation(b)
		sg[b] = (sg[p] * q) if (p >= 0 and p < b) else q
	var target := {}
	var hr: Array = rest_hc.h
	var cr: Array = rest_hc.c
	for pr in pairs_hc:
		var delta: Quaternion = sg[pr[0]] * (hr[pr[0]] as Quaternion).inverse()
		target[pr[1]] = (rel_hc * delta * rel_hc.inverse()) * (cr[pr[1]] as Quaternion)
	_write_globals(cop_sk, target)


func _hq(name: String) -> Quaternion:
	return hero_sk.get_bone_pose_rotation(hb[name]) if hb.has(name) else Quaternion.IDENTITY


func _hset(name: String, q: Quaternion) -> void:
	if hb.has(name):
		hero_sk.set_bone_pose_rotation(hb[name], q.normalized())


func _add(name: String, q: Quaternion) -> void:
	if hb.has(name):
		_hset(name, _hq(name) * q)


func _layer(pose: Dictionary, w: float) -> void:
	if w <= 0.001:
		return
	for k in pose:
		if hb.has(k):
			_hset(k, _hq(k).slerp(hrest[k] * pose[k], w))


func head_position() -> Vector3:
	if head_bone < 0 or vis_sk == null:
		return global_position + Vector3(0, 1.65, 0)
	return vis_sk.global_transform * vis_sk.get_bone_global_pose(head_bone).origin


func _clip_len(n: String) -> float:
	var d: Dictionary = L.anims.get(n, {})
	return float(d.get("len", 1.0))


func _smooth(key: String, target: float, rate: float, delta: float) -> float:
	var v: float = _w.get(key, 0.0)
	v = move_toward(v, target, rate * delta)
	_w[key] = v
	return v


# ---------------------------------------------------------------- update
## vel_local: velocity in the character frame (x = right, y = forward), m/s
func update(delta: float, vel_local: Vector2, on_floor: bool, weapon_type: String, arm_w: float, pitch: float) -> void:
	if L.is_empty() or hero_sk == null:
		return
	var speed := vel_local.length()
	var rifle := weapon_type in ["rifle", "rpg"] and arm_w > 0.5
	_armed_w = move_toward(_armed_w, 1.0 if rifle else 0.0, delta * 5.0)
	_prone_w = move_toward(_prone_w, 1.0 if stance == 2 else 0.0, delta * 2.5)
	_idle_t += delta
	var hips_y := 0.0
	if dead:
		_dead_t += delta
		var dl := _clip_len(death_clip)
		var s1 := _sample([[death_clip, minf(_dead_t, dl - 0.01), 1.0]])
		var k := clampf(_dead_t / 0.2, 0.0, 1.0)
		var loc_d: Array = s1[0]
		if k < 1.0:
			var s0 := _sample(_loco(delta, speed, vel_local, rifle))
			for b in loc_d.size():
				loc_d[b] = (s0[0][b] as Quaternion).slerp(loc_d[b], k)
			hips_y = lerpf(s0[1], s1[1], k)
		else:
			hips_y = s1[1]
		_apply_lib_pose(loc_d)
	else:
		_dead_t = 0.0
		if rifle and weapon and _calib_id != weapon_id:
			_calibrate()
		var s := _sample(_loco(delta, speed, vel_local, rifle))
		var loc: Array = s[0]
		hips_y = s[1]
		# shooting on the move: upper body takes the aiming pose, legs keep walking/running
		var am: float = _w.get("aim", 0.0) * _w.get("move", 0.0) * _armed_w
		if am > 0.01:
			var crouch_k: float = _w.get("crouch", 0.0)
			var ua := _sample([["r_aim", fmod(_idle_t, _clip_len("r_aim")), 1.0 - crouch_k], ["c_aim", fmod(_idle_t, _clip_len("c_aim")), crouch_k]])
			for b in loc.size():
				var nm0: String = L.names[b]
				if arm_mask[b] == 1 or nm0 == "Spine1" or nm0 == "Spine2" or nm0 == "Neck" or nm0 == "Head":
					loc[b] = (loc[b] as Quaternion).slerp(ua[0][b], am)
		# unarmed run / crouch: legs from the rifle clips, natural arms from walk / idle
		var cw: float = _w.get("crouch", 0.0) * (1.0 - _armed_w)
		if cw > 0.01:
			var mw: float = _w.get("move", 0.0)
			var upw := _sample([["walk", _phase * _clip_len("walk"), mw], ["idle", fmod(_idle_t, _clip_len("idle")), 1.0 - mw]], true)
			var aw := cw
			for b in loc.size():
				if arm_mask[b] == 1:
					loc[b] = (loc[b] as Quaternion).slerp(upw[0][b], aw)
		# punches: upper body + fists from the punch clip
		if punch_t >= 0.0 or guard_w > 0.01:
			var pt := punch_t if punch_t >= 0.0 else 0.2
			var pw := 1.0 if punch_t >= 0.0 else guard_w
			var ps := _sample([["punch", minf(pt, _clip_len("punch") - 0.01), 1.0]])
			for b in loc.size():
				var nm: String = L.names[b]
				if arm_mask[b] == 1 or nm.begins_with("Spine") or nm == "Neck" or nm == "Head":
					loc[b] = (loc[b] as Quaternion).slerp(ps[0][b], pw)
		_apply_lib_pose(loc)
		# aim pitch through the spine (the weapon follows the hands)
		var pk := clampf(pitch, -1.0, 0.9)
		var pw2 := lerpf(0.3, 0.55, _armed_w)
		_add("CC_Base_Spine01", Quaternion(X, -pk * pw2 * 0.5))
		_add("CC_Base_Spine02", Quaternion(X, -pk * pw2 * 0.5))
		# head stays closer to level: the neck should not dip when the rifle is up
		_add("CC_Base_Head", Quaternion(X, -clampf(pk, -0.5, 0.25) * 0.1))
		# counter the neck dip of the rifle-ready clips so the head stays up while armed
		_add("CC_Base_NeckTwist01", Quaternion(X, -0.25 * _armed_w))
		if recoil > 0.0:
			_add("CC_Base_Spine02", Quaternion(X, -recoil * 0.1))
			recoil = maxf(0.0, recoil - delta * 9.0)
		# prone (procedural)
		if _prone_w > 0.0:
			var s2 := sin(_phase * TAU) * clampf(speed / 0.6, 0.0, 1.0)
			_layer({
				"CC_Base_L_Thigh": Quaternion(X, s2 * 0.25) * Quaternion(Z, 0.12), "CC_Base_R_Thigh": Quaternion(X, -s2 * 0.25) * Quaternion(Z, -0.12),
				"CC_Base_L_Calf": Quaternion(X, -0.15 - maxf(0.0, s2) * 0.5), "CC_Base_R_Calf": Quaternion(X, -0.15 - maxf(0.0, -s2) * 0.5),
				"CC_Base_L_Foot": Quaternion(X, 0.0), "CC_Base_R_Foot": Quaternion(X, 0.0),
				"CC_Base_Waist": Quaternion(X, -0.12), "CC_Base_Spine01": Quaternion(X, 0.0), "CC_Base_Spine02": Quaternion(X, -0.25),
				"CC_Base_NeckTwist01": Quaternion(X, -0.45), "CC_Base_Head": Quaternion(X, -0.55),
				"CC_Base_L_Upperarm": Quaternion(Z, -1.0) * Quaternion(X, 2.3 + s2 * 0.25), "CC_Base_R_Upperarm": Quaternion(Z, 1.0) * Quaternion(X, 2.3 - s2 * 0.25),
				"CC_Base_L_Forearm": Quaternion(X, 1.2), "CC_Base_R_Forearm": Quaternion(X, 1.2),
			}, _prone_w)
		# pistol: two-hand hold (no pistol clips); IK refines later
		if weapon_type == "pistol" and arm_w > 0.01 and _prone_w < 0.5:
			_layer({"CC_Base_R_Upperarm": Quaternion(Z, 1.55) * Quaternion(X, 1.3), "CC_Base_R_Forearm": Quaternion(X, 0.25),
				"CC_Base_L_Upperarm": Quaternion(Z, -1.6) * Quaternion(X, 1.3), "CC_Base_L_Forearm": Quaternion(X, 0.35)}, arm_w)
		elif weapon_type == "c4" and arm_w > 0.01:
			_layer({"CC_Base_R_Upperarm": Quaternion(Z, 1.2) * Quaternion(X, 0.5), "CC_Base_R_Forearm": Quaternion(X, 0.9)}, arm_w)

	if cop_sk:
		_hero_to_cop()

	# body placement (crouch height comes from the clips' hips)
	var y := (hips_y - float(L.hips_rest_y)) * hip_scale
	var e := _prone_w * _prone_w * (3.0 - 2.0 * _prone_w)
	rotation.x = e * (PI / 2)
	position = Vector3(0, lerpf(y, 0.18, e), -0.95 * e)

	# weapon in the hands
	if weapon and not dead:
		if rifle and _prone_w < 0.5:
			_place_rifle()
			if reload_t >= 0.0:
				_reload_hand()
		elif grips.size() > 0 and arm_w > 0.3 and punch_t < 0.0:
			var wk := clampf((arm_w - 0.3) / 0.7, 0.0, 1.0)
			for side in ["R", "L"]:
				if grips.has(side):
					_ik_arm(side, weapon.global_transform * grips[side], wk)


func _loco(delta: float, speed: float, vl: Vector2, rifle: bool) -> Array:
	var clips: Array = []
	var crouch := stance == 1
	var cycle := lerpf(1.4, 2.1, clampf((speed - 1.5) / 1.4, 0.0, 1.0))
	if crouch:
		cycle = 1.0
	_phase = fmod(_phase + delta * speed / cycle, 1.0)
	var move_w := _smooth("move", 1.0 if speed > 0.15 else 0.0, 4.0, delta)
	var run_w := _smooth("run", clampf((speed - 1.5) / 1.4, 0.0, 1.0), 3.0, delta)
	var crouch_w := _smooth("crouch", 1.0 if crouch else 0.0, 4.0, delta)
	var air_w := _smooth("air", 1.0 if in_air else 0.0, 6.0, delta)
	var aim_w := _smooth("aim", 1.0 if aiming else 0.0, 6.0, delta)
	_unarmed_run_w = run_w * (1.0 - _armed_w) * (1.0 - crouch_w) * move_w
	var dir := vl.normalized() if speed > 0.05 else Vector2(0, 1)
	var wf := maxf(dir.y, 0.0)
	var wb := maxf(-dir.y, 0.0)
	var wr := maxf(dir.x, 0.0)
	var wl := maxf(-dir.x, 0.0)
	var ds := wf + wb + wr + wl
	if ds > 0.0:
		wf /= ds
		wb /= ds
		wr /= ds
		wl /= ds
	var stand := 1.0 - crouch_w
	var idle_w := 1.0 - move_w
	var A := _armed_w
	var U := 1.0 - _armed_w
	if U > 0.001:
		clips.append(["idle", fmod(_idle_t, _clip_len("idle")), stand * idle_w * U])
		clips.append(["c_idle", fmod(_idle_t, _clip_len("c_idle")), crouch_w * idle_w * U])
		var wk := stand * move_w * U * (1.0 - run_w)
		clips.append(["walk", _phase * _clip_len("walk"), wk * (1.0 - wb)])
		clips.append(["walk_back", _phase * _clip_len("walk_back"), wk * wb])
		clips.append(["run", _phase * _clip_len("run"), stand * move_w * U * run_w])
		for c in [["c_walk_f", wf], ["c_walk_b", wb], ["c_walk_l", wl], ["c_walk_r", wr]]:
			clips.append([c[0], _phase * _clip_len(c[0]), crouch_w * move_w * U * c[1]])
	if A > 0.001:
		var ri := stand * idle_w * A
		clips.append(["r_idle", fmod(_idle_t, _clip_len("r_idle")), ri * (1.0 - aim_w)])
		clips.append(["r_aim", fmod(_idle_t, _clip_len("r_aim")), ri * aim_w])
		clips.append(["c_idle", fmod(_idle_t, _clip_len("c_idle")), crouch_w * idle_w * A * (1.0 - aim_w)])
		clips.append(["c_aim", fmod(_idle_t, _clip_len("c_aim")), crouch_w * idle_w * A * aim_w])
		var sets := [["r_walk_", stand * move_w * A * (1.0 - run_w)], ["r_run_", stand * move_w * A * run_w], ["c_walk_", crouch_w * move_w * A]]
		for st in sets:
			var base_w: float = st[1]
			if base_w <= 0.001:
				continue
			for dd in [["f", wf], ["b", wb], ["l", wl], ["r", wr]]:
				var nm: String = st[0] + dd[0]
				clips.append([nm, _phase * _clip_len(nm), base_w * dd[1]])
	if air_w > 0.01:
		var ks := 1.0 - air_w
		for c in clips:
			c[2] *= ks
		clips.append(["jump_loop", fmod(_idle_t, _clip_len("jump_loop")), air_w])
	return clips


# ---------------------------------------------------------------- weapon placement
func _palm(side: String) -> Vector3:
	var ids: Array = ik_bones[side]
	var hand: Vector3 = vis_sk.global_transform * vis_sk.get_bone_global_pose(ids[2]).origin
	var pb: int = palm_bones.get(side, -1)
	if pb < 0:
		return hand
	var mid: Vector3 = vis_sk.global_transform * vis_sk.get_bone_global_pose(pb).origin
	return hand.lerp(mid, 0.55)


func _hand_xf(side: String) -> Transform3D:
	var ids: Array = ik_bones[side]
	var g: Transform3D = vis_sk.global_transform * vis_sk.get_bone_global_pose(ids[2])
	return Transform3D(g.basis.orthonormalized(), g.origin)


## Work out how the weapon sits in the right hand, using the aiming pose (where both
## hands are clearly on the gun). Every other clip then carries the gun with the hand.
func _calibrate() -> void:
	_calib_id = weapon_id
	var s := _sample([["r_aim", 0.5, 1.0]])
	_apply_lib_pose(s[0])
	if cop_sk:
		_hero_to_cop()
	var wx := _line_xf()
	if wx == Transform3D():
		_calib = Transform3D()
		return
	_calib = _hand_xf("R").affine_inverse() * wx


func _place_rifle() -> void:
	if not grips.has("R") or not grips.has("L"):
		return
	if _calib != Transform3D():
		weapon.global_transform = _hand_xf("R") * _calib
		if reload_t < 0.0:
			_ik_arm("L", weapon.global_transform * (grips.L as Vector3), 1.0)
		return
	var lx := _line_xf()
	if lx != Transform3D():
		weapon.global_transform = lx


func _line_xf() -> Transform3D:
	if not grips.has("R") or not grips.has("L"):
		return Transform3D()
	var d: Dictionary = W.DATA.get(weapon_id, {})
	var rz := Basis(Vector3.BACK, deg_to_rad(float((d.get("rot", Vector3.ZERO) as Vector3).z)))
	var pr := _palm("R")
	var pl := _palm("L")
	var gr: Vector3 = rz * (grips.R as Vector3)
	var gl: Vector3 = rz * (grips.L as Vector3)
	if (gl - gr).length() < 0.01 or (pl - pr).length() < 0.01:
		return Transform3D()
	var u := (gl - gr).normalized()
	var t := (pl - pr).normalized()
	var up_w := (Vector3.UP - u * u.dot(Vector3.UP)).normalized()
	var char_up: Vector3 = global_transform.basis.y.normalized()
	var up_t := (char_up - t * t.dot(char_up)).normalized()
	var wf := Basis(u.cross(up_w), up_w, u)
	var tf := Basis(t.cross(up_t), up_t, t)
	var b := tf * wf.inverse() * rz
	return Transform3D(b, pr - b * (grips.R as Vector3))


func _reload_hand() -> void:
	# left hand: grab the magazine, take it out, bring a new one, slap it in
	if not grips.has("L") or not grips.has("R"):
		return
	var mag: Vector3 = (grips.R as Vector3).lerp(grips.L as Vector3, 0.45) + Vector3(0, -0.1, 0)
	var start: Vector3 = weapon.global_transform * (grips.L as Vector3)
	var magw: Vector3 = weapon.global_transform * mag
	var low: Vector3 = global_transform * Vector3(0.18, 0.95, 0.15)
	var tgt := start
	if reload_t < 0.25:
		tgt = start.lerp(magw, reload_t / 0.25)
	elif reload_t < 0.5:
		tgt = magw.lerp(low, (reload_t - 0.25) / 0.25)
	elif reload_t < 0.8:
		tgt = low.lerp(magw, (reload_t - 0.5) / 0.3)
	else:
		tgt = magw.lerp(start, (reload_t - 0.8) / 0.2)
	_ik_arm("L", tgt, 1.0)


func magazine_world() -> Transform3D:
	if weapon == null or not grips.has("R"):
		return global_transform
	var mag: Vector3 = (grips.R as Vector3).lerp(grips.L as Vector3, 0.45) + Vector3(0, -0.1, 0)
	return Transform3D(weapon.global_transform.basis, weapon.global_transform * mag)


func left_hand_pos() -> Vector3:
	return _palm("L")


func _ik_arm(side: String, target_world: Vector3, w: float) -> void:
	var ids: Array = ik_bones[side]
	if ids[0] < 0 or ids[1] < 0 or ids[2] < 0:
		return
	var sk := vis_sk
	var to_sk := sk.global_transform.affine_inverse()
	var T: Vector3 = to_sk * target_world
	var ug := sk.get_bone_global_pose(ids[0])
	T = T - (T - ug.origin).normalized() * 0.05 / maxf(sk.global_transform.basis.get_scale().x, 0.0001)
	var fg := sk.get_bone_global_pose(ids[1])
	var hg := sk.get_bone_global_pose(ids[2])
	var S := ug.origin
	var E := fg.origin
	var Wp := hg.origin
	var a := S.distance_to(E)
	var b := E.distance_to(Wp)
	if a < 0.001 or b < 0.001:
		return
	var d := clampf(S.distance_to(T), 0.05, (a + b) * 0.999)
	var dir := (T - S).normalized()
	var rig_basis := global_transform.basis.orthonormalized()
	var sk_basis := sk.global_transform.basis.orthonormalized()
	var outward := Vector3(-1.0 if side == "R" else 1.0, 0, 0)
	var pole_dir: Vector3 = sk_basis.inverse() * (rig_basis * (outward * 0.45 + Vector3(0, -0.85, -0.25)))
	pole_dir = pole_dir - dir * pole_dir.dot(dir)
	if pole_dir.length() < 0.001:
		return
	pole_dir = pole_dir.normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var E2 := S + dir * (a * cos_a) + pole_dir * (a * sqrt(maxf(0.0, 1.0 - cos_a * cos_a)))
	var T2 := S + dir * d
	var q1 := Quaternion((E - S).normalized(), (E2 - S).normalized())
	var ug2 := Basis(q1) * ug.basis.orthonormalized()
	var q2 := Quaternion((q1 * (Wp - E)).normalized(), (T2 - E2).normalized())
	var fg2 := Basis(q2) * Basis(q1) * fg.basis.orthonormalized()
	var parent := sk.get_bone_parent(ids[0])
	var pg := sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis()
	var ul := (pg.inverse() * ug2).get_rotation_quaternion()
	var fl := (ug2.inverse() * fg2).get_rotation_quaternion()
	sk.set_bone_pose_rotation(ids[0], sk.get_bone_pose_rotation(ids[0]).slerp(ul, w))
	sk.set_bone_pose_rotation(ids[1], sk.get_bone_pose_rotation(ids[1]).slerp(fl, w))
