extends Node3D
## First-person arms + rifle (animated model). The model carries its own FPS_Camera bone; each frame
## the model is placed so that bone sits exactly on the game camera, so hands and weapon appear as
## the animator framed them (including the camera sway baked into the animations).
## Animation clips share one timeline: each clip is a [start, end] segment of it.

const MODEL := "res://assets/models/fps/m4_arms.glb"
const CLIPS := {
	"draw": ["Draw", 8.97, 10.0],
	"fire": ["Fire", 7.53, 8.33],
	"reload": ["Reload", 0.03, 3.67],
	"reload_empty": ["Reload_Empty", 3.7, 7.5],
	"holster": ["Holster", 8.37, 8.93],
}
## the FBX camera looks along its +X; turn it to Godot's -Z
const CAM_FIX := Basis(Vector3.UP, -PI * 0.5)

var model: Node3D
var anim: AnimationPlayer
var cam_node: Node3D
var skel: Skeleton3D
var cam_bone := -1
var clip := ""
var _end := 0.0
var _speed := 1.0


func _ready() -> void:
	top_level = true
	model = load(MODEL).instantiate()
	add_child(model)
	anim = model.find_children("*", "AnimationPlayer", true, false)[0] if model.find_children("*", "AnimationPlayer", true, false).size() > 0 else null
	var found := model.find_children("FPS_Camera", "", true, false)
	cam_node = found[0] if found.size() > 0 else null
	var sk := model.find_children("*", "Skeleton3D", true, false)
	if sk.size() > 0:
		skel = sk[0]
		for i in skel.get_bone_count():
			var bn := skel.get_bone_name(i)
			if bn.begins_with("FPS_Camera") and not bn.contains("_j"):
				cam_bone = i
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	play("draw")


func play(what: String, speed := 1.0) -> void:
	if anim == null or not CLIPS.has(what):
		return
	var c: Array = CLIPS[what]
	clip = what
	_speed = speed
	_end = float(c[2])
	anim.play(c[0], -1, speed)
	anim.seek(float(c[1]), true)


func busy() -> bool:
	return clip != "" and clip != "fire" and anim != null and anim.is_playing()


func _process(_d: float) -> void:
	if anim and anim.is_playing() and anim.current_animation_position >= _end - 0.001:
		# hold the last frame of the clip (idle pose after draw / fire / reload)
		anim.seek(_end - 0.001, true)
		anim.pause()
		clip = ""


## place the model so its FPS_Camera bone coincides with `cam`
func cam_xf() -> Transform3D:
	if skel and cam_bone >= 0:
		return skel.global_transform * skel.get_bone_global_pose(cam_bone)
	if cam_node:
		return cam_node.global_transform
	return global_transform


func follow(cam: Camera3D) -> void:
	if (skel == null or cam_bone < 0) and cam_node == null:
		global_transform = cam.global_transform
		return
	var rel: Transform3D = global_transform.affine_inverse() * cam_xf()
	rel.basis = rel.basis.orthonormalized() * CAM_FIX   # keep the model's own scale
	global_transform = cam.global_transform * rel.affine_inverse()
