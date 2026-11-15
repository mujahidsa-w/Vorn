class_name FighterBody
extends Node3D
## Тело бойца от третьего лица: модель Tripo на скелете Mixamo, общая библиотека из 82 клипов,
## оружие в правой руке, наклон корпуса по прицелу, смерть.

const DIRS := ["forward", "forward_right", "right", "backward_right", "backward", "backward_left", "left", "forward_left"]
static var _scenes := {}
static var _grip_cache := {}

var actor: Actor
var model: Node3D
var skel: Skeleton3D
var ap: AnimationPlayer
var up: AnimationPlayer            # верх тела: перезарядка, бросок, удар
var hand: BoneAttachment3D
var weapon: Node3D
var weapon_id := ""
var dead := false
var cur := ""
var spine: Array[int] = []
var aim_mod: SkeletonModifier3D
var _flash: MeshInstance3D
var _muzzle: Node3D
var _feet: Array[int] = []
var mname := ""
var alib: AnimationLibrary
var b_rh := -1                     # кости кистей и оснований средних пальцев
var b_rm := -1
var b_lh := -1
var b_lm := -1
var two_hand := false              # оружие лежит в двух руках: ствол тянется от правой ладони к левой
var w_grip := Vector3.ZERO
var w_linv := Basis.IDENTITY
var gun_mod: SkeletonModifier3D
var _foot_up := [false, false]
var _foot_min := 1.0
var _step_cd := 0.0

static func available(n: String) -> bool:
	## character models come from the original game archive at build time; local checkouts may not have them
	return ResourceLoader.exists(char_path(n)) and ResourceLoader.exists(AnimLib.SRC)

## the original game's characters, or the soldiers baked from Last Circle (lc_a .. lc_d, Mixamo bone names)
static func char_path(n: String) -> String:
	if n.begins_with("lc_"):
		return "res://assets/lc_chars/%s.scn" % n
	return "res://assets/models/chars/%s.scn" % n

static func scene(n: String) -> PackedScene:
	if not _scenes.has(n):
		_scenes[n] = load(char_path(n))
	return _scenes[n]

func setup(a: Actor, model_name: String) -> void:
	actor = a
	model = scene(model_name).instantiate()
	model.rotation.y = PI
	add_child(model)
	skel = model.find_child("Skeleton3D", true, false)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		m.extra_cull_margin = 2.0
	mname = model_name
	alib = AnimLib.lib_for(skel, model_name)
	var lib := alib
	ap = AnimationPlayer.new()
	skel.get_parent().add_child(ap)
	ap.root_node = NodePath("..")
	ap.add_animation_library("", lib)
	ap.playback_default_blend_time = 0.18
	up = AnimationPlayer.new()
	skel.get_parent().add_child(up)
	up.root_node = NodePath("..")
	up.add_animation_library("", AnimLib.upper_for(skel, model_name))
	up.playback_default_blend_time = 0.1
	for b in ["mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2"]:
		var i := skel.find_bone(b)
		if i >= 0:
			spine.append(i)
	for b in ["mixamorig_LeftFoot", "mixamorig_RightFoot"]:
		var fi := skel.find_bone(b)
		if fi >= 0:
			_feet.append(fi)
			_foot_min = minf(_foot_min, skel.get_bone_global_rest(fi).origin.y)
	hand = BoneAttachment3D.new()
	hand.bone_name = "mixamorig_RightHand"
	skel.add_child(hand)
	b_rh = skel.find_bone("mixamorig_RightHand")
	b_rm = skel.find_bone("mixamorig_RightHandMiddle1")
	b_lh = skel.find_bone("mixamorig_LeftHand")
	b_lm = skel.find_bone("mixamorig_LeftHandMiddle1")
	aim_mod = AimMod.new()
	aim_mod.body = self
	skel.add_child(aim_mod)
	gun_mod = GunMod.new()
	gun_mod.body = self
	skel.add_child(gun_mod)
	_prone_setup()
	gear_helmet = model.find_child("GearHelmet", true, false) as Node3D
	gear_vest = model.find_child("GearVest", true, false) as Node3D
	if gear_helmet:
		gear_helmet.visible = false
	_play("rifle_idle_aiming")

# ------------------------------------------------------------------ lying down
## Without prone clips (they can be dropped into assets/anims_extra as prone_idle / prone_forward) the body is laid
## face down about the hips and the spine bends up (AimMod) so that the rifle in the aiming pose stays level.
const PRONE_BEND := 1.25
var _hips_m := Vector3(0, 0.95, 0)      # hips in model space at rest, metres
var _prone_clips := false

func _prone_setup() -> void:
	var hi := skel.find_bone("mixamorig_Hips")
	if hi >= 0:
		_hips_m = Gear._xf(model, skel) * skel.get_bone_global_rest(hi).origin
	_prone_clips = alib != null and alib.has_animation("prone_idle")

func prone_bend() -> float:
	return 0.0 if _prone_clips else actor.prone_t * PRONE_BEND

func _prone_pose() -> void:
	var t0 := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	var k := 0.0 if _prone_clips else actor.prone_t
	if k <= 0.001:
		model.transform = t0
		return
	var r := Basis(Vector3.RIGHT, -PI / 2.0) * Basis(Vector3.UP, PI)
	var t1 := Transform3D(r, Vector3(0, 0.17, 0.18) - r * _hips_m)
	model.transform = t0.interpolate_with(t1, k)

# ------------------------------------------------------------------ helmet worn on the head (assets/gear/helmet.glb)
const HELMET_FIT := 1.04
var helmet_node: Node3D
var helmet_on := false
var gear_helmet: Node3D           # soldiers that model their own helmet and vest
var gear_vest: Node3D
var vest_on := true

func _wear_helmet(on: bool) -> void:
	helmet_on = on
	if gear_helmet:
		gear_helmet.visible = on
		return
	if on and helmet_node == null:
		helmet_node = _make_helmet()
	if helmet_node:
		helmet_node.visible = on

func _make_helmet() -> Node3D:
	if skel == null or not ResourceLoader.exists(Gear.HELMET):
		return null
	var bi := skel.find_bone("mixamorig_Head")
	if bi < 0:
		return null
	var ti := skel.find_bone("mixamorig_HeadTop_End")
	# skeleton units -> metres (the character scene may be scaled)
	var k := Gear._xf(self, skel).basis.get_scale().x
	if k <= 0.0:
		k = 1.0
	var head := skel.get_bone_global_rest(bi)
	var top: Vector3 = skel.get_bone_global_rest(ti).origin if ti >= 0 else head.origin + Vector3(0, 0.2 / k, 0)
	var att := BoneAttachment3D.new()
	att.name = "HelmetAt"
	att.bone_name = "mixamorig_Head"
	skel.add_child(att)
	var h := (load(Gear.HELMET) as PackedScene).instantiate() as Node3D
	# helmet space: face +Z like the Mixamo skeleton, rim at y -0.05, crown of the shell ~0.2 m over the rim
	var want := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * HELMET_FIT / k), top + Vector3(0, -0.185, -0.005) / k)
	h.transform = head.affine_inverse() * want
	att.add_child(h)
	for g in h.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return att

func set_weapon(wid: String) -> void:
	if wid == weapon_id:
		return
	weapon_id = wid
	if weapon:
		weapon.queue_free()
		weapon = null
	_muzzle = null
	_flash = null
	if wid == "" or not ResourceLoader.exists(DB.model(wid)):
		return
	weapon = (load(DB.model(wid)) as PackedScene).instantiate()
	hand.add_child(weapon)
	var hold: String = DB.W[wid]["hold"]
	weapon.transform = _grip(hold, weapon)
	# двуручный хват: направление «рукоять → цевьё» в осях оружия
	var gr := weapon.find_child("p_grip_r", true, false) as Node3D
	var gl := weapon.find_child("p_grip_l", true, false) as Node3D
	two_hand = hold in ["rifle", "smg"] and gr != null and gl != null and b_lh >= 0
	if two_hand:
		w_grip = _rel(weapon, gr).origin
		var v := _rel(weapon, gl).origin - w_grip
		two_hand = v.length() > 0.08
		if two_hand:
			w_linv = Basis.looking_at(v.normalized(), Vector3.UP).inverse()
	var sk := G.equipped_skin(wid) if (actor == null or not actor.is_bot) else ""
	Skins.apply(weapon, wid, sk)
	Sight.attach(weapon, wid, false)
	_muzzle = weapon.find_child("p_muzzle", true, false)
	if _muzzle and actor:
		_flash = MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.5, 0.5)
		_flash.mesh = qm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = actor.game.fx.flash_tex
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_flash.material_override = mat
		_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flash.visible = false
		_muzzle.add_child(_flash)

func _anim_global(a: Animation, bone: int, t: float) -> Transform3D:
	## положение кости в пространстве скелета в момент t клипа — считается прямо по дорожкам, без проигрывателя
	var chain: Array[int] = []
	var b := bone
	while b >= 0:
		chain.push_front(b)
		b = skel.get_bone_parent(b)
	var g := Transform3D.IDENTITY
	for bi in chain:
		var rest := skel.get_bone_rest(bi)
		var pos := rest.origin
		var rot := rest.basis.get_rotation_quaternion()
		var path := NodePath("Skeleton3D:" + skel.get_bone_name(bi))
		var ti := a.find_track(path, Animation.TYPE_ROTATION_3D)
		if ti >= 0:
			rot = a.rotation_track_interpolate(ti, t)
		var pi := a.find_track(path, Animation.TYPE_POSITION_3D)
		if pi >= 0:
			pos = a.position_track_interpolate(pi, t)
		g = g * Transform3D(Basis(rot), pos)
	return g

func _grip(hold: String, w: Node3D) -> Transform3D:
	# положение оружия относительно кости кисти: считается один раз по опорной позе клипа (ствол — вперёд, рукоять — в ладони)
	var key := mname + ":" + hold
	var grip := w.find_child("p_grip_r", true, false) as Node3D
	var g_local := Vector3.ZERO
	if grip:
		g_local = _rel(w, grip).origin
	if not _grip_cache.has(key):
		var pose := "pistol_idle" if hold in ["pistol", "knife", "nade", "c4"] else "rifle_idle_aiming"
		var a: Animation = alib.get_animation(pose)
		var ht := _anim_global(a, b_rh, 0.0)
		var mt := _anim_global(a, b_rm, 0.0) if b_rm >= 0 else ht
		var palm := ht.origin.lerp(mt.origin, 0.62)
		# желаемая ориентация оружия в пространстве скелета: ствол (-Z оружия) по +Z модели, верх — вверх
		var wb := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))
		if hold in ["pistol", "nade", "c4"]:
			# пистолет смотрит туда же, куда предплечье в позе прицеливания
			var et := _anim_global(a, skel.get_bone_parent(b_rh), 0.0)
			var fd := ht.origin - et.origin
			if fd.length() > 0.05 and absf(fd.normalized().y) < 0.8:
				wb = Basis.looking_at(fd.normalized(), Vector3.UP)
		_grip_cache[key] = {"hinv": ht.affine_inverse(), "wb": wb, "palm": palm}
	var c: Dictionary = _grip_cache[key]
	var wb2: Basis = c["wb"]
	if hold == "knife":
		wb2 = wb2 * Basis(Vector3.RIGHT, deg_to_rad(-35))
	var want := Transform3D(wb2, (c["palm"] as Vector3) - wb2 * g_local)
	return (c["hinv"] as Transform3D) * want

func _rel(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var x: Node = n
	while x != root and x != null:
		t = (x as Node3D).transform * t
		x = x.get_parent()
	return t

func _play(n: String, speed := 1.0) -> void:
	if cur == n and ap.is_playing():
		ap.speed_scale = speed
		return
	if not ap.has_animation(n):
		return
	cur = n
	ap.play(n, -1, speed)

func pose(n: String) -> void:
	cur = ""
	_play(n)

func revive() -> void:
	dead = false
	visible = true
	cur = ""
	up.stop()
	if weapon:
		weapon.visible = true
	_play("rifle_idle_aiming")

func die(headshot: bool, from: Vector3) -> void:
	dead = true
	up.stop()
	if weapon:
		weapon.visible = false
	if actor.prone_t > 0.5 and not _prone_clips:
		# shot while lying down: the body stays down, the head drops and the arms go slack
		ap.play("rifle_idle_aiming", 0.3, 0.0)
		var tw := create_tween()
		tw.tween_property(model, "position:y", model.position.y - 0.08, 0.5)
		return
	model.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	var fwd := -Basis(Vector3.UP, actor.view_yaw).z
	var to := (from - actor.global_position)
	to.y = 0
	var front := to.length() < 0.1 or fwd.dot(to.normalized()) > 0.0
	var opts: Array
	if headshot:
		opts = ["rifle_death_from_front_headshot"] if front else ["rifle_death_from_back_headshot"]
	elif front:
		opts = ["rifle_death_from_the_front", "standing_react_death_backward", "rifle_death_from_right"]
	else:
		opts = ["rifle_death_from_the_back", "standing_react_death_forward"]
	cur = opts[randi() % opts.size()]
	ap.play(cur, 0.12, 1.15)

func on_shot() -> void:
	if _flash:
		_flash.visible = true
		_flash.rotation.z = randf() * TAU
		_flash.scale = Vector3.ONE * randf_range(0.7, 1.2)
		get_tree().create_timer(0.045).timeout.connect(func():
			if is_instance_valid(_flash):
				_flash.visible = false)
	var cls: String = actor.wd()["cls"]
	if cls == "knife":
		up.play("stabbing", 0.05, 2.4)
	elif cls == "nade":
		up.play("toss_grenade", 0.05, 2.2)

func on_reload(t: float) -> void:
	var a: Animation = up.get_animation("reloading")
	if a:
		up.play("reloading", 0.1, a.length / maxf(0.4, t))

func muzzle_pos() -> Vector3:
	if _muzzle and is_instance_valid(_muzzle):
		return _muzzle.global_position
	return actor.eye() - Basis(Vector3.UP, actor.view_yaw).z * 0.5

func _steps(dt: float) -> void:
	## звук шага — в момент, когда стопа в анимации касается земли (а не по таймеру)
	_step_cd = maxf(0.0, _step_cd - dt)
	if _feet.size() < 2 or actor.game == null:
		return
	var run: bool = actor.alive and actor.is_on_floor() and actor.crouch_t < 0.5 and Vector2(actor.velocity.x, actor.velocity.z).length() > 3.3
	for k in 2:
		var y := skel.get_bone_global_pose(_feet[k]).origin.y
		if y > _foot_min + 0.085:
			_foot_up[k] = true
		elif y < _foot_min + 0.04 and _foot_up[k]:
			_foot_up[k] = false
			if run and _step_cd <= 0.0:
				_step_cd = 0.16
				actor.game.footstep(actor)
				if G.args.has("sndlog"):
					print("EV %d foot %s %d" % [Time.get_ticks_msec(), actor.name, k])

func _process(_dt: float) -> void:
	if actor == null or dead:
		return
	if actor.vehicle:
		# seated: the body faces the way the vehicle goes, in a low crouched pose
		global_basis = (actor.vehicle as Node3D).global_basis * Basis(Vector3.UP, PI)
		model.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, -0.35, 0))
		_play("rifle_idle_crouching_aiming" if actor.wd()["hold"] in ["rifle", "smg"] else "pistol_kneeling_idle")
		return
	_steps(_dt)
	rotation.y = actor.view_yaw
	# боец вплотную к камере игрока не рисуется (иначе видно модель изнутри)
	var cam := get_viewport().get_camera_3d()
	if cam and model:
		model.visible = cam.global_position.distance_to(actor.global_position + Vector3(0, 1.2, 0)) > 0.85
	if actor.cur != weapon_id:
		set_weapon(actor.cur)
	if actor.helmet != helmet_on:
		_wear_helmet(actor.helmet)
	if gear_vest and (actor.armor > 0) != vest_on:
		vest_on = actor.armor > 0
		gear_vest.visible = vest_on
	var hold: String = actor.wd()["hold"]
	var rifle := hold in ["rifle", "smg"]
	var v := actor.velocity
	var sp := Vector2(v.x, v.z).length()
	var crouch := actor.crouch_t > 0.5
	_prone_pose()
	if actor.prone_t > 0.5:
		if _prone_clips:
			_play("prone_forward" if sp > 0.3 and alib.has_animation("prone_forward") else "prone_idle", clampf(sp / 1.0, 0.6, 1.4))
		else:
			_play("rifle_idle_aiming" if rifle else "pistol_idle")
		return
	if not actor.is_on_floor() and absf(v.y) > 1.0:
		_play("rifle_jump_loop" if rifle else "pistol_jump")
		return
	if sp < 0.35:
		if rifle:
			_play("rifle_idle_crouching_aiming" if crouch else "rifle_idle_aiming")
		else:
			_play("pistol_kneeling_idle" if crouch else "pistol_idle")
		return
	var lv := Basis(Vector3.UP, actor.view_yaw).inverse() * Vector3(v.x, 0, v.z)
	var ang := atan2(lv.x, -lv.z)          # 0 — вперёд, +вправо
	var di := posmod(int(round(ang / (PI / 4.0))), 8)
	var dn: String = DIRS[di]
	if rifle:
		if crouch:
			_play("rifle_walk_crouching_" + dn, clampf(sp / 1.9, 0.6, 1.6))
		elif sp < 3.4:
			_play("rifle_walk_" + dn, clampf(sp / 2.0, 0.7, 1.6))
		else:
			_play("rifle_run_" + dn, clampf(sp / 5.2, 0.8, 1.35))
	else:
		var back := di in [3, 4, 5]
		var side := di in [2, 6]
		if crouch:
			_play("rifle_walk_crouching_" + dn, clampf(sp / 1.9, 0.6, 1.6))
		elif sp < 3.4:
			_play("pistol_walk_backward" if back else ("pistol_strafe" if di == 6 else ("pistol_strafe_b" if di == 2 else "pistol_walk")), clampf(sp / 2.0, 0.7, 1.6))
		else:
			_play("pistol_run_backward" if back else ("pistol_strafe" if di == 6 else ("pistol_strafe_b" if di == 2 else "pistol_run")), clampf(sp / 5.4, 0.8, 1.4) * (1.5 if side else 1.0))


class AimMod extends SkeletonModifier3D:
	## наклон корпуса вверх-вниз по прицелу: поворот трёх костей позвоночника вокруг поперечной оси модели
	var body: FighterBody

	func _process_modification() -> void:
		if body == null or body.dead or body.actor == null:
			return
		var sk := get_skeleton()
		var pitch := body.actor.view_pitch + body.prone_bend()
		var roll := body.actor.lean * 0.38
		if absf(pitch) < 0.01 and absf(roll) < 0.01:
			return
		var per := pitch / 3.0
		# модель смотрит в +Z, вправо от неё -X; наклон вверх — вращение вокруг оси X скелета,
		# наклон вбок (выглядывание из-за угла) — вокруг оси Z: положительный угол клонит вправо
		var q := Quaternion(Vector3(0, 0, 1), roll / 3.0) * Quaternion(Vector3(1, 0, 0), -per)
		for i in body.spine:
			var gp := sk.get_bone_global_pose(i)
			var o := gp.origin
			gp.basis = Basis(q) * gp.basis
			gp.origin = o
			sk.set_bone_global_pose(i, gp)


class GunMod extends SkeletonModifier3D:
	## винтовка в двух руках: рукоять в правой ладони, ствол направлен на левую ладонь под цевьём.
	## Так оружие лежит в руках в любой анимации, а не торчит под углом, заданным одной позой.
	var body: FighterBody

	func _process_modification() -> void:
		if body == null or body.dead or body.weapon == null or not body.two_hand or not is_instance_valid(body.weapon):
			return
		if body.up and body.up.is_playing():
			return          # перезарядка, бросок: левая рука ушла с цевья — оружие остаётся в правой
		var sk := get_skeleton()
		var ht := sk.get_bone_global_pose(body.b_rh)
		var r := ht.origin.lerp(sk.get_bone_global_pose(body.b_rm).origin, 0.62)
		var l := sk.get_bone_global_pose(body.b_lh).origin.lerp(sk.get_bone_global_pose(body.b_lm).origin, 0.62) + Vector3(0, 0.03, 0)
		var d := l - r
		if d.length() < 0.14 or absf(d.normalized().y) > 0.92:
			return
		var b := Basis.looking_at(d.normalized(), Vector3.UP) * body.w_linv
		var want := Transform3D(b, r - b * body.w_grip)
		body.weapon.transform = ht.affine_inverse() * want
