extends Node
## Renders the lobby character to transparent PNG frames (one per turn angle).
## Run: godot --path . -- --charrender <out_dir>
var main
var out := ""
const FRAMES := 24
const W := 470
const H := 984


func run() -> void:
	await get_tree().create_timer(1.0).timeout
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.72)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 35, 0)
	sun.light_energy = 1.6
	vp.add_child(sun)

	var pivot := Node3D.new()
	vp.add_child(pivot)
	var model: Node3D = (load("res://assets/models/chars/hero.glb") as PackedScene).instantiate()
	pivot.add_child(model)
	await get_tree().process_frame
	# the game renders this model at its own scale (scale 1), so no fitting

	var cam := Camera3D.new()
	cam.fov = 28.0
	cam.position = Vector3(0, 1.0, 4.4)
	vp.add_child(cam)
	cam.look_at(Vector3(0, 0.92, 0), Vector3.UP)
	cam.current = true

	DirAccess.make_dir_recursive_absolute(out)
	for i in FRAMES:
		pivot.rotation.y = TAU * float(i) / float(FRAMES)
		for _k in 3:
			await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.save_png(out + "/frame_%02d.png" % i)
		print("frame ", i, " px=", img.get_pixel(W / 2, H - 40))
	print("char render done")
	get_tree().quit()


func _fit(model: Node3D, height: float) -> void:
	var box := AABB()
	var first := true
	for m in _meshes(model):
		var lb: AABB = (model.global_transform.affine_inverse() * m.global_transform) * m.get_aabb()
		box = lb if first else box.merge(lb)
		first = false
	if first or box.size.y <= 0.0:
		return
	print("CHARINFO box=", box, " model_scale=", model.scale, " skeletons=", model.find_children("*", "Skeleton3D", true, false).size())
	var sc := height / box.size.y
	model.scale = Vector3.ONE * sc
	var c := box.get_center()
	model.position = Vector3(-c.x * sc, -box.position.y * sc, -c.z * sc)


func _meshes(n: Node) -> Array:
	var out_a := []
	if n is MeshInstance3D:
		out_a.append(n)
	for ch in n.get_children():
		out_a.append_array(_meshes(ch))
	return out_a
