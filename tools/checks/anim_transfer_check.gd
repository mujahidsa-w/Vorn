extends SceneTree
## Numeric check of AnimLib.transfer_clip: a clip moved from skeleton E to skeleton S (same bones, different
## rest orientations) must give every bone the same world-space turn away from rest.
##   godot --headless --path . --script res://tools/checks/anim_transfer_check.gd

const BONES := ["mixamorig_Hips", "mixamorig_Spine", "mixamorig_Spine1", "mixamorig_LeftUpLeg", "mixamorig_LeftLeg"]
const PARENT := {"mixamorig_Hips": "", "mixamorig_Spine": "mixamorig_Hips", "mixamorig_Spine1": "mixamorig_Spine",
	"mixamorig_LeftUpLeg": "mixamorig_Hips", "mixamorig_LeftLeg": "mixamorig_LeftUpLeg"}

func _rq(r: RandomNumberGenerator) -> Quaternion:
	return Quaternion(Vector3(r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1)).normalized(), r.randf_range(-PI, PI))

func _rest(r: RandomNumberGenerator, hips_y: float) -> Dictionary:
	## global rests built from random local rests down the chain
	var loc := {}
	var glob := {}
	for b in BONES:
		loc[b] = Transform3D(Basis(_rq(r)), Vector3(0, hips_y if b == "mixamorig_Hips" else 0.2, 0))
		var p: String = PARENT[b]
		glob[b] = (glob[p] as Transform3D) * (loc[b] as Transform3D) if p != "" else loc[b]
	return glob

func _global(a: Animation, rest: Dictionary, t: float) -> Dictionary:
	var g := {}
	for b in BONES:
		var ti := a.find_track(NodePath("Skeleton3D:" + b), Animation.TYPE_ROTATION_3D)
		var q: Quaternion = a.rotation_track_interpolate(ti, t)
		var p: String = PARENT[b]
		g[b] = (g[p] as Quaternion) * q if p != "" else q
	return g

func _init() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var re := _rest(r, 0.9)
	var rs := _rest(r, 1.05)
	var a := Animation.new()
	a.length = 1.0
	for b in BONES:
		var ti := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(ti, NodePath("Armature/Skeleton3D:" + String(b).replace("mixamorig_", "mixamorig:")))
		for k in 3:
			a.rotation_track_insert_key(ti, k * 0.5, _rq(r))
	var hp := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(hp, NodePath("Armature/Skeleton3D:mixamorig1_Hips"))
	a.position_track_insert_key(hp, 0.0, Vector3(0.1, 0.9, 0.0))
	var out := AnimLib.transfer_clip(a, re, PARENT, rs, PARENT)
	var worst := 0.0
	for k in 3:
		var t := k * 0.5
		var ge := _global(a_renamed(a), re, t)
		var gs := _global(out, rs, t)
		for b in BONES:
			var de: Quaternion = (ge[b] as Quaternion) * (re[b] as Transform3D).basis.get_rotation_quaternion().inverse()
			var ds: Quaternion = (gs[b] as Quaternion) * (rs[b] as Transform3D).basis.get_rotation_quaternion().inverse()
			worst = maxf(worst, de.angle_to(ds))
	var hips := out.position_track_interpolate(out.find_track(NodePath("Skeleton3D:mixamorig_Hips"), Animation.TYPE_POSITION_3D), 0.0)
	var ok := worst < 0.001 and absf(hips.y - 1.05) < 0.001 and out.get_track_count() == BONES.size() + 1
	print("transfer check: worst %.6f rad, hips %s, tracks %d -> %s" % [worst, hips, out.get_track_count(), "OK" if ok else "FAIL"])
	print("names: ", AnimLib.clip_name("Prone Forward.fbx"), " ", AnimLib.clip_name("Rifle Run-Left (1).glb"), " ", AnimLib.norm_bone("mixamorig2:LeftHand"))
	quit(0 if ok else 1)

func a_renamed(a: Animation) -> Animation:
	## the source clip with plain bone paths, to evaluate it on skeleton E
	var c := Animation.new()
	c.length = a.length
	for i in a.get_track_count():
		if a.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var p := String(a.track_get_path(i))
		var ti := c.add_track(Animation.TYPE_ROTATION_3D)
		c.track_set_path(ti, NodePath("Skeleton3D:" + AnimLib.norm_bone(p.substr(p.find(":") + 1))))
		for k in a.track_get_key_count(i):
			c.rotation_track_insert_key(ti, a.track_get_key_time(i, k), a.track_get_key_value(i, k))
	return c
