class_name AnimLib
extends RefCounted
## Общая библиотека анимаций бойцов: 82 клипа Mixamo на исходном скелете клипов (Т-поза).
## У каждого бойца своя поза покоя (руки вниз под 50–57°), поэтому клипы переносятся на его скелет при загрузке:
## каждая кость бойца ставится параллельно той же кости исходного скелета. Смещение есть только у таза и
## масштабируется по росту.

const SRC := "res://assets/models/chars/anims.scn"
const HIPS := "mixamorig_Hips"
const PREF := {"mixamorig_Hips": "mixamorig_Spine", "mixamorig_Spine2": "mixamorig_Neck",
	"mixamorig_LeftHand": "mixamorig_LeftHandMiddle1", "mixamorig_RightHand": "mixamorig_RightHandMiddle1"}
static var _src: AnimationLibrary          # клипы в осях исходного скелета
static var _src_rest := {}                 # кость -> глобальный покой исходного скелета
static var _src_local := {}                # кость -> локальный поворот покоя
static var _src_parent := {}
static var _libs := {}
static var _uppers := {}

static func is_loop(n: String) -> bool:
	for bad in ["death", "_to_", "turn", "jump_up", "jump_down", "pistol_jump"]:
		if n.contains(bad):
			return false
	for w in ["walk", "run", "sprint", "strafe", "idle", "jump_loop", "breathing"]:
		if n.contains(w):
			return true
	return false

static func _load_src() -> void:
	if _src:
		return
	var inst: Node = (load(SRC) as PackedScene).instantiate()
	var sk: Skeleton3D = inst.find_child("Skeleton3D", true, false)
	for i in sk.get_bone_count():
		var bn := sk.get_bone_name(i)
		_src_rest[bn] = sk.get_bone_global_rest(i)
		_src_local[bn] = sk.get_bone_rest(i).basis.get_rotation_quaternion()
		var p := sk.get_bone_parent(i)
		_src_parent[bn] = sk.get_bone_name(p) if p >= 0 else ""
	var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
	_src = AnimationLibrary.new()
	for n in ap.get_animation_list():
		var a: Animation = ap.get_animation(n).duplicate(true)
		for i in range(a.get_track_count() - 1, -1, -1):
			var p2 := String(a.track_get_path(i))
			var bone := p2.get_slice(":", 1) if p2.contains(":") else p2.get_slice("/", p2.get_slice_count("/") - 1)
			var t := a.track_get_type(i)
			if t == Animation.TYPE_SCALE_3D or (t == Animation.TYPE_POSITION_3D and bone != HIPS) or (t != Animation.TYPE_POSITION_3D and t != Animation.TYPE_ROTATION_3D):
				a.remove_track(i)
			else:
				a.track_set_path(i, NodePath("Skeleton3D:" + bone))
		a.loop_mode = Animation.LOOP_LINEAR if is_loop(n) else Animation.LOOP_NONE
		_src.add_animation(n, a)
	inst.free()
	_load_extra()

# ------------------------------------------------------------------ extra clips
## Extra Mixamo clips dropped into assets/anims_extra (FBX or GLB, "In Place", any Mixamo character) join the
## shared library under their file name in snake_case ("Prone Idle.fbx" -> "prone_idle"); a clip with the
## name of an existing one replaces it. They are moved onto the library's source skeleton here and then
## reach every fighter through lib_for(), like the built-in clips.
const EXTRA_DIR := "res://assets/anims_extra"

static func norm_bone(b: String) -> String:
	## "mixamorig:Hips", "mixamorig1_Hips", "Armature/mixamorig:Hips" -> "mixamorig_Hips"
	var s := b.get_slice("/", b.get_slice_count("/") - 1)
	if s.begins_with("mixamorig"):
		var rest := s.substr(9).lstrip("0123456789")
		if rest.begins_with(":") or rest.begins_with("_"):
			return "mixamorig_" + rest.substr(1)
	return s

static func clip_name(file: String) -> String:
	var n := file.get_file().get_basename().to_snake_case()
	var re := RegEx.create_from_string("[^a-z0-9]+")
	n = re.sub(n, "_", true)
	while n.contains("__"):
		n = n.replace("__", "_")
	return n.strip_edges().trim_prefix("_").trim_suffix("_")

static func _load_extra() -> void:
	var d := DirAccess.open(EXTRA_DIR)
	if d == null:
		return
	var seen := {}
	for f in d.get_files():
		var n := String(f).trim_suffix(".import").trim_suffix(".remap")
		if seen.has(n) or not (n.get_extension().to_lower() in ["glb", "gltf", "fbx", "scn", "tscn"]):
			continue
		seen[n] = true
		var ps := load(EXTRA_DIR + "/" + n) as PackedScene
		if ps == null:
			continue
		var inst := ps.instantiate()
		var sks := inst.find_children("*", "Skeleton3D", true, false)
		var aps := inst.find_children("*", "AnimationPlayer", true, false)
		if sks.size() > 0 and aps.size() > 0:
			var sk := sks[0] as Skeleton3D
			var ap := aps[0] as AnimationPlayer
			var best: Animation = null
			for an in ap.get_animation_list():
				var cand := ap.get_animation(an)
				if best == null or cand.length > best.length:
					best = cand
			if best:
				var rest_e := {}
				var parent_e := {}
				for i in sk.get_bone_count():
					var bn := norm_bone(sk.get_bone_name(i))
					rest_e[bn] = sk.get_bone_global_rest(i)
					var p := sk.get_bone_parent(i)
					parent_e[bn] = norm_bone(sk.get_bone_name(p)) if p >= 0 else ""
				var cn := clip_name(n)
				var a := transfer_clip(best, rest_e, parent_e, _src_rest, _src_parent)
				a.loop_mode = Animation.LOOP_LINEAR if is_loop(cn) else Animation.LOOP_NONE
				if _src.has_animation(cn):
					_src.remove_animation(cn)
				_src.add_animation(cn, a)
				print("[anims] extra clip: %s (%.2f s, %d tracks)" % [cn, a.length, a.get_track_count()])
		inst.free()

static func transfer_clip(src: Animation, rest_e: Dictionary, parent_e: Dictionary, rest_s: Dictionary, parent_s: Dictionary) -> Animation:
	## Moves a clip from skeleton E onto skeleton S with the same bone names: every bone keeps its turn away
	## from rest in world space, G_s = G_e · Re⁻¹ · Rs, so the local key becomes
	## L_s = Rs(parent)⁻¹ · Re(parent) · L_e · Re(bone)⁻¹ · Rs(bone). The hip track is scaled by the hip heights.
	var a := Animation.new()
	a.length = src.length
	var re_q := func(d: Dictionary, b: String) -> Quaternion:
		return (d[b] as Transform3D).basis.orthonormalized().get_rotation_quaternion() if d.has(b) else Quaternion.IDENTITY
	var hs := 1.0
	if rest_e.has(HIPS) and rest_s.has(HIPS):
		hs = (rest_s[HIPS] as Transform3D).origin.y / maxf(0.01, (rest_e[HIPS] as Transform3D).origin.y)
	for i in src.get_track_count():
		var tt := src.track_get_type(i)
		var p := String(src.track_get_path(i))
		var bone := norm_bone(p.substr(p.find(":") + 1) if p.contains(":") else p)
		if not rest_s.has(bone):
			continue
		if tt == Animation.TYPE_ROTATION_3D:
			var pe: String = parent_e.get(bone, "")
			var ps_: String = parent_s.get(bone, "")
			var ap: Quaternion = re_q.call(rest_s, ps_).inverse() * re_q.call(rest_e, pe)
			var bq: Quaternion = re_q.call(rest_e, bone).inverse() * re_q.call(rest_s, bone)
			var ti := a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(ti, NodePath("Skeleton3D:" + bone))
			for k in src.track_get_key_count(i):
				var q: Quaternion = src.track_get_key_value(i, k)
				a.rotation_track_insert_key(ti, src.track_get_key_time(i, k), (ap * q * bq).normalized())
		elif tt == Animation.TYPE_POSITION_3D and bone == HIPS:
			var pe2: String = parent_e.get(bone, "")
			var ps2: String = parent_s.get(bone, "")
			var ap2: Quaternion = re_q.call(rest_s, ps2).inverse() * re_q.call(rest_e, pe2)
			var ti2 := a.add_track(Animation.TYPE_POSITION_3D)
			a.track_set_path(ti2, NodePath("Skeleton3D:" + bone))
			for k in src.track_get_key_count(i):
				var v: Vector3 = src.track_get_key_value(i, k)
				a.position_track_insert_key(ti2, src.track_get_key_time(i, k), ap2 * (v * hs))
	return a

static func _child(skel: Skeleton3D, i: int) -> int:
	## кость, по которой меряется направление: главный ребёнок
	var bn := skel.get_bone_name(i)
	if PREF.has(bn):
		return skel.find_bone(String(PREF[bn]))
	var kids := skel.get_bone_children(i)
	for k in kids:
		if _src_rest.has(skel.get_bone_name(k)):
			return k
	return -1

## Библиотека клипов, перенесённая на скелет бойца (key — имя модели; считается один раз).
static func lib_for(skel: Skeleton3D, key: String) -> AnimationLibrary:
	if _libs.has(key):
		return _libs[key]
	var t0 := Time.get_ticks_msec()
	_load_src()
	var kq := {}                   # кость -> поправка K = покой_исх⁻¹ · Q · покой_бойца
	var qd := {}
	for i in skel.get_bone_count():
		var bn := skel.get_bone_name(i)
		if not _src_rest.has(bn):
			continue
		var q := Quaternion.IDENTITY
		var found := false
		var c := _child(skel, i)
		if c >= 0:
			var cn := skel.get_bone_name(c)
			if _src_rest.has(cn):
				var dt := skel.get_bone_global_rest(c).origin - skel.get_bone_global_rest(i).origin
				var ds: Vector3 = (_src_rest[cn] as Transform3D).origin - (_src_rest[bn] as Transform3D).origin
				if dt.length() > 0.004 and ds.length() > 0.004 and dt.normalized().dot(ds.normalized()) > -0.95:
					q = Quaternion(dt.normalized(), ds.normalized())
					found = true
		if not found:
			var p := skel.get_bone_parent(i)
			if p >= 0 and qd.has(skel.get_bone_name(p)):
				q = qd[skel.get_bone_name(p)]
		qd[bn] = q
		var rs := (_src_rest[bn] as Transform3D).basis.orthonormalized().get_rotation_quaternion()
		var rt := skel.get_bone_global_rest(i).basis.orthonormalized().get_rotation_quaternion()
		kq[bn] = rs.inverse() * q * rt
	var hs := 1.0
	var hi := skel.find_bone(HIPS)
	if hi >= 0 and _src_rest.has(HIPS):
		hs = skel.get_bone_global_rest(hi).origin.y / maxf(0.2, (_src_rest[HIPS] as Transform3D).origin.y)
	var lib := AnimationLibrary.new()
	for an in _src.get_animation_list():
		var a: Animation = _src.get_animation(an).duplicate(true)
		var have := {}
		for ti in a.get_track_count():
			var bone := String(a.track_get_path(ti)).get_slice(":", 1)
			var tt := a.track_get_type(ti)
			if tt == Animation.TYPE_ROTATION_3D:
				have[bone] = true
				if not kq.has(bone):
					continue
				var kb: Quaternion = kq[bone]
				var pn: String = _src_parent.get(bone, "")
				var kpi: Quaternion = (kq[pn] as Quaternion).inverse() if kq.has(pn) else Quaternion.IDENTITY
				for ki in a.track_get_key_count(ti):
					var qv: Quaternion = a.track_get_key_value(ti, ki)
					a.track_set_key_value(ti, ki, (kpi * qv * kb).normalized())
			elif tt == Animation.TYPE_POSITION_3D:
				for ki in a.track_get_key_count(ti):
					a.track_set_key_value(ti, ki, (a.track_get_key_value(ti, ki) as Vector3) * hs)
		# кости без дорожки в клипе стоят в покое исходного скелета — им нужен свой постоянный ключ
		for bone in kq:
			if have.has(bone):
				continue
			var pn2: String = _src_parent.get(bone, "")
			var kpi2: Quaternion = (kq[pn2] as Quaternion).inverse() if kq.has(pn2) else Quaternion.IDENTITY
			var ti2 := a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(ti2, NodePath("Skeleton3D:" + String(bone)))
			a.rotation_track_insert_key(ti2, 0.0, (kpi2 * (_src_local[bone] as Quaternion) * (kq[bone] as Quaternion)).normalized())
		lib.add_animation(an, a)
	_libs[key] = lib
	print("[anims] %s: %d clips in %d ms" % [key, lib.get_animation_list().size(), Time.get_ticks_msec() - t0])
	return lib

const UPPER := ["Spine1", "Spine2", "Neck", "Head", "Shoulder", "Arm", "ForeArm", "Hand"]

## Клипы только для верха тела (перезарядка, бросок, удар) — играют поверх ходьбы.
static func upper_for(skel: Skeleton3D, key: String) -> AnimationLibrary:
	if _uppers.has(key):
		return _uppers[key]
	var up := AnimationLibrary.new()
	var src := lib_for(skel, key)
	for n in ["reloading", "stabbing", "toss_grenade", "firing_rifle", "hit_reaction"]:
		if not src.has_animation(n):
			continue
		var a: Animation = src.get_animation(n).duplicate(true)
		for i in range(a.get_track_count() - 1, -1, -1):
			var bone := String(a.track_get_path(i)).get_slice(":", 1)
			var keep := false
			for u in UPPER:
				if bone.contains(u):
					keep = true
					break
			if not keep or a.track_get_type(i) == Animation.TYPE_POSITION_3D:
				a.remove_track(i)
		a.loop_mode = Animation.LOOP_NONE
		up.add_animation(n, a)
	_uppers[key] = up
	return up
