extends SceneTree
## Bakes Last Circle's four soldiers (MakeHuman bodies with vest, helmet, backpack, cargo trousers and boots) into
## assets/lc_chars as lc_a .. lc_d:
##   - their skeleton uses Godot's humanoid names; the bones and skin binds are renamed to the Mixamo names the game's
##     animation library, hand placement and aiming already use, so the soldiers run the same animations;
##   - textures downsized (colour 1024 px, the rest 512 px) for phones.
## Run: LC_PCK=<LastCircle.pck> xvfb-run godot --path . --rendering-driver opengl3 --script res://tools/island/bake_chars.gd

const OUT := "res://assets/lc_chars"
const MAP := {
	"Hips": "Hips", "Spine": "Spine", "Chest": "Spine1", "UpperChest": "Spine2", "Neck": "Neck", "Head": "Head",
	"Shoulder": "Shoulder", "UpperArm": "Arm", "LowerArm": "ForeArm", "Hand": "Hand",
	"ThumbMetacarpal": "HandThumb1", "ThumbProximal": "HandThumb2", "ThumbDistal": "HandThumb3",
	"IndexProximal": "HandIndex1", "IndexIntermediate": "HandIndex2", "IndexDistal": "HandIndex3",
	"MiddleProximal": "HandMiddle1", "MiddleIntermediate": "HandMiddle2", "MiddleDistal": "HandMiddle3",
	"RingProximal": "HandRing1", "RingIntermediate": "HandRing2", "RingDistal": "HandRing3",
	"LittleProximal": "HandPinky1", "LittleIntermediate": "HandPinky2", "LittleDistal": "HandPinky3",
	"UpperLeg": "UpLeg", "LowerLeg": "Leg", "Foot": "Foot", "Toes": "ToeBase",
}

var ABS := ""
var tex_done := {}
var mat_done := {}

func _initialize() -> void:
	_run.call_deferred()

static func mixamo(n: String) -> String:
	for side in ["Left", "Right"]:
		if n.begins_with(side):
			var rest := n.substr(side.length())
			if MAP.has(rest):
				return "mixamorig_" + side + MAP[rest]
	if MAP.has(n):
		return "mixamorig_" + MAP[n]
	return n

func _run() -> void:
	ABS = ProjectSettings.globalize_path(OUT)
	if not ProjectSettings.load_resource_pack(OS.get_environment("LC_PCK"), false):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ABS + "/tex")
	var pass2 := OS.get_environment("CHAR_PASS") == "2"
	for k in ["a", "b", "c", "d"]:
		var src := "res://assets/characters/char_%s.glb" % k
		if not ResourceLoader.exists(src):
			continue
		var root := (load(src) as PackedScene).instantiate() as Node3D
		# bones and skin binds to the Mixamo names
		var renamed := 0
		for sk in root.find_children("*", "Skeleton3D", true, false):
			var s := sk as Skeleton3D
			for i in s.get_bone_count():
				var nn := mixamo(s.get_bone_name(i))
				if nn != s.get_bone_name(i):
					s.set_bone_name(i, nn)
					renamed += 1
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.skin:
				var skin := m.skin.duplicate() as Skin
				for b in skin.get_bind_count():
					var bn := String(skin.get_bind_name(b))
					if bn != "":
						skin.set_bind_name(b, mixamo(bn))
				m.skin = skin
			if m.mesh:
				var mesh := m.mesh.duplicate() as Mesh
				for s2 in mesh.get_surface_count():
					var mat := m.get_active_material(s2)
					mesh.surface_set_material(s2, _mat(mat, pass2))
				m.mesh = mesh
				for s3 in m.get_surface_override_material_count():
					m.set_surface_override_material(s3, null)
		for ap in root.find_children("*", "AnimationPlayer", true, false):
			ap.free()
		if pass2:
			_own(root, root)
			var ps := PackedScene.new()
			ps.pack(root)
			var err := ResourceSaver.save(ps, ABS + "/lc_%s.scn" % k, ResourceSaver.FLAG_COMPRESS)
			print("BAKE char lc_%s renamed %d bones, saved %d" % [k, renamed, err])
		root.free()
	if not pass2:
		print("BAKE textures ", tex_done.size())
	quit(0)

func _own(n: Node, o: Node) -> void:
	for c in n.get_children():
		c.owner = o
		_own(c, o)

func _mat(m: Material, pass2: bool) -> Material:
	if m == null:
		return null
	if mat_done.has(m.get_instance_id()):
		return mat_done[m.get_instance_id()]
	var d := m.duplicate() as Material
	for p in d.get_property_list():
		if p["type"] != TYPE_OBJECT:
			continue
		var t = d.get(p["name"])
		if not (t is Texture2D) or (t as Texture2D).resource_path == "":
			continue
		var file := _tex(t as Texture2D, String(p["name"]) == "albedo_texture")
		if pass2 and file != "":
			d.set(p["name"], load(OUT + "/tex/" + file))
	mat_done[m.get_instance_id()] = d
	return d

func _tex(t: Texture2D, colour: bool) -> String:
	var src := t.resource_path
	if tex_done.has(src):
		return tex_done[src]
	var img := t.get_image()
	if img == null:
		return ""
	if img.is_compressed():
		img.decompress()
	var mx := 1024 if colour else 512
	var k := minf(1.0, float(mx) / maxf(img.get_width(), img.get_height()))
	if k < 1.0:
		img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
	var alpha := img.detect_alpha() != Image.ALPHA_NONE
	var file := "%s.%s" % [src.get_file().get_basename(), "png" if alpha else "jpg"]
	if alpha:
		img.convert(Image.FORMAT_RGBA8)
		img.save_png(ABS + "/tex/" + file)
	else:
		img.convert(Image.FORMAT_RGB8)
		img.save_jpg(ABS + "/tex/" + file, 0.9)
	tex_done[src] = file
	return file
