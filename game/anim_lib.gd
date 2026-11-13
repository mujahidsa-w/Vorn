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
	G.log_line("anims -> %s: %d clips in %d ms" % [key, lib.get_animation_list().size(), Time.get_ticks_msec() - t0])
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
