extends SceneTree
## Pulls the models, animations, sounds and music that ship only inside the original game
## executable (they are not part of the distributed sources) and writes them into the project.
##
##   godot --headless --path tools/unpack --script unpack_assets.gd -- <FableStrike2.exe|.pck> <project dir>
##
## Scenes and audio are copied as native Godot resources (.scn / .sample / .oggvorbisstr / .mp3str).
## Textures are decoded, scaled down for phones and written as images with VRAM-compressed import settings.

const TEX_MAX := {"chars": 1024, "weapons": 1024}

var out := ""
var n_files := 0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- <exe or pck> <project dir>")
		quit(2)
		return
	out = String(args[1]).trim_suffix("/")
	if not ProjectSettings.load_resource_pack(args[0], true):
		push_error("cannot open pack: " + args[0])
		quit(3)
		return
	var ok := true
	for sub in ["chars", "weapons"]:
		ok = _models("res://assets/models/" + sub, sub) and ok
	ok = _audio("res://assets/sounds") and ok
	ok = _audio("res://assets/music") and ok
	print("unpack: %d files written to %s" % [n_files, out])
	quit(0 if ok and n_files > 0 else 4)

func _remap(import_path: String) -> Dictionary:
	var cf := ConfigFile.new()
	if cf.parse(FileAccess.get_file_as_string(import_path)) != OK:
		return {}
	return {"path": String(cf.get_value("remap", "path", "")), "uid": String(cf.get_value("remap", "uid", "")), "type": String(cf.get_value("remap", "type", ""))}

func _copy(src: String, dst: String) -> bool:
	var data := FileAccess.get_file_as_bytes(src)
	if data.is_empty():
		push_error("empty or missing: " + src)
		return false
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	var f := FileAccess.open(dst, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()
	n_files += 1
	return true

func _list(dir: String) -> PackedStringArray:
	var d := DirAccess.open(dir)
	if d == null:
		push_error("missing in pack: " + dir)
		return PackedStringArray()
	return d.get_files()

func _models(dir: String, sub: String) -> bool:
	var ok := true
	for f in _list(dir):
		if not f.ends_with(".import"):
			continue
		var name := f.trim_suffix(".import")
		var rm := _remap(dir + "/" + f)
		if rm.is_empty() or rm["path"] == "":
			continue
		var dst_dir := out + "/assets/models/" + sub + "/"
		if name.ends_with(".glb"):
			ok = _copy(rm["path"], dst_dir + name.get_basename() + ".scn") and ok
		else:
			ok = _texture(dir + "/" + name, dst_dir + name, rm["uid"], int(TEX_MAX[sub])) and ok
	return ok

func _texture(res_path: String, dst: String, uid: String, max_size: int) -> bool:
	var tex := load(res_path) as Texture2D
	if tex == null:
		push_error("cannot load texture " + res_path)
		return false
	var img := tex.get_image()
	if img == null:
		push_error("no image data in " + res_path)
		return false
	if img.is_compressed():
		img.decompress()
	if img.has_mipmaps():
		img.clear_mipmaps()
	var big: int = maxi(img.get_width(), img.get_height())
	if big > max_size:
		var k := float(max_size) / float(big)
		img.resize(maxi(1, int(round(img.get_width() * k))), maxi(1, int(round(img.get_height() * k))), Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	var err := OK
	if dst.get_extension().to_lower() == "png":
		err = img.save_png(dst)
	else:
		img.convert(Image.FORMAT_RGB8)
		err = img.save_jpg(dst, 0.92)
	if err != OK:
		push_error("cannot save " + dst)
		return false
	var is_normal := dst.get_basename().ends_with("_normal")
	var cf := "[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n"
	if uid != "":
		cf += "uid=\"%s\"\n" % uid
	cf += "\n[params]\n\ncompress/mode=2\ncompress/high_quality=false\ncompress/lossy_quality=0.7\ncompress/uastc_level=0\ncompress/rdo_quality_loss=0.0\n"
	cf += "compress/hdr_compression=1\ncompress/normal_map=%d\ncompress/channel_pack=0\nmipmaps/generate=true\nmipmaps/limit=-1\n" % (1 if is_normal else 2)
	cf += "roughness/mode=0\nroughness/src_normal=\"\"\nprocess/channel_remap/red=0\nprocess/channel_remap/green=1\nprocess/channel_remap/blue=2\nprocess/channel_remap/alpha=3\n"
	cf += "process/fix_alpha_border=true\nprocess/premult_alpha=false\nprocess/normal_map_invert_y=false\nprocess/hdr_as_srgb=false\nprocess/hdr_clamp_exposure=false\nprocess/size_limit=0\ndetect_3d/compress_to=0\n"
	var f := FileAccess.open(dst + ".import", FileAccess.WRITE)
	f.store_string(cf)
	f.close()
	n_files += 1
	return true

func _audio(dir: String) -> bool:
	var ok := true
	for f in _list(dir):
		var dst_dir := out + "/" + dir.trim_prefix("res://") + "/"
		if f.ends_with(".import"):
			var rm := _remap(dir + "/" + f)
			if rm.is_empty() or rm["path"] == "":
				continue
			var base := f.trim_suffix(".import").get_basename()
			ok = _copy(rm["path"], dst_dir + base + "." + String(rm["path"]).get_extension()) and ok
		elif f.ends_with(".json"):
			ok = _copy(dir + "/" + f, dst_dir + f) and ok
	return ok
