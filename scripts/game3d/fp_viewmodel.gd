extends Node3D
## First-person arms + rifle (animated model). The model carries its own FPS_Camera bone; each frame
## the model is placed so that bone sits exactly on the game camera, so hands and weapon appear as
## the animator framed them (including the camera sway baked into the animations).
## Animation clips share one timeline: each clip is a [start, end] segment of it.

## per weapon: model, animation clips [name, start, end] and how the model meets the camera
## (cam_bone: the model carries a camera bone; otherwise `offset` places the model in camera space)
const MODELS := {
	"m4": {
		"path": "res://assets/models/fps/m4_arms.glb",
		"clips": {
			"draw": ["Draw", 8.97, 10.0],
			"fire": ["Fire", 7.53, 8.33],
			"reload": ["Reload", 0.03, 3.67],
			"reload_empty": ["Reload_Empty", 3.7, 7.5],
			"holster": ["Holster", 8.37, 8.93],
		},
		"cam_bone": true,
	},
	"glock": {
		"path": "res://assets/models/fps/pistol_arms.glb",
		"clips": {
			"draw": ["Armature|Unhide", 0.0, 0.28],
			"idle": ["Armature|Idle", 0.0, 1.33],
			"fire": ["Armature|Fire", 0.0, 0.42],
			"reload": ["Armature|ReloadClip", 0.0, 1.13],
			"reload_empty": ["Armature|EmptyClipReload", 0.0, 1.62],
			"holster": ["Armature|Hide", 0.0, 0.33],
		},
		"cam_bone": false,
		"offset": Transform3D(Basis(Vector3.UP, PI), Vector3(0.08, -0.26, -0.11)),
	},
}
var weapon_id := "m4"
var CLIPS := {}
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
	var cfg: Dictionary = MODELS[weapon_id]
	CLIPS = cfg.clips
	model = load(cfg.path).instantiate()
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
		clip = ""
		if CLIPS.has("idle"):
			play("idle")       # loop the idle sway
			clip = ""
		else:
			anim.seek(_end - 0.001, true)
			anim.pause()


## place the model so its FPS_Camera bone coincides with `cam`
func cam_xf() -> Transform3D:
	if skel and cam_bone >= 0:
		return skel.global_transform * skel.get_bone_global_pose(cam_bone)
	if cam_node:
		return cam_node.global_transform
	return global_transform


func follow(cam: Camera3D) -> void:
	var cfg: Dictionary = MODELS[weapon_id]
	if not cfg.cam_bone or ((skel == null or cam_bone < 0) and cam_node == null):
		global_transform = cam.global_transform * (cfg.get("offset", Transform3D()) as Transform3D)
		return
	var rel: Transform3D = global_transform.affine_inverse() * cam_xf()
	rel.basis = rel.basis.orthonormalized() * CAM_FIX   # keep the model's own scale
	global_transform = cam.global_transform * rel.affine_inverse()
