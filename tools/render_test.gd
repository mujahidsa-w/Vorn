extends SceneTree
func _box(root, pos, col):
	var m := MeshInstance3D.new(); var b := BoxMesh.new(); b.size = Vector3(0.3,0.3,0.3); m.mesh = b
	var mat := StandardMaterial3D.new(); mat.albedo_color = col; mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.material_override = mat
	m.position = pos; root.add_child(m)
func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var root := Node3D.new(); get_root().add_child(root)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.4,0.45,0.5)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(1,1,1); e.ambient_light_energy = 0.7
	env.environment = e; root.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45, 30, 0); root.add_child(sun)
	var c1: Node3D = load("res://assets/models/cars/police_gt500.glb").instantiate(); root.add_child(c1); c1.position = Vector3(-3,0,0); c1.scale = Vector3.ONE*100
	var c2: Node3D = load("res://assets/models/cars/mustang69.glb").instantiate(); root.add_child(c2); c2.position = Vector3(3,0,0); c2.scale = Vector3.ONE*100
	_box(root, Vector3(-3,0.2,4), Color.RED)   # +Z marker
	_box(root, Vector3(3,0.2,4), Color.RED)
	var tests := [["none",Vector3.ZERO,0.0],["thighX",Vector3.RIGHT,0.6],["thighZ",Vector3.BACK,0.6],["armX",Vector3.RIGHT,1.2],["armZ",Vector3.BACK,1.2],["armY",Vector3.UP,1.2]]
	for i in tests.size():
		var h: Node3D = load("res://assets/models/chars/hero.glb").instantiate(); root.add_child(h)
		h.position = Vector3(-7.5 + i*3.0, 0, -6)
		var sk: Skeleton3D = h.find_children("*", "Skeleton3D", true, false)[0]
		var tn: String = tests[i][0]
		if tn.begins_with("thigh"):
			var b := sk.find_bone("CC_Base_L_Thigh"); sk.set_bone_pose_rotation(b, sk.get_bone_rest(b).basis.get_rotation_quaternion() * Quaternion(tests[i][1], tests[i][2]))
		elif tn.begins_with("arm"):
			var b2 := sk.find_bone("CC_Base_L_Upperarm"); sk.set_bone_pose_rotation(b2, sk.get_bone_rest(b2).basis.get_rotation_quaternion() * Quaternion(Vector3.BACK, -1.25) * Quaternion(tests[i][1], tests[i][2]*0.5))
			var b3 := sk.find_bone("CC_Base_R_Upperarm"); sk.set_bone_pose_rotation(b3, sk.get_bone_rest(b3).basis.get_rotation_quaternion() * Quaternion(Vector3.BACK, 1.25))
		if i == 0:
			var names := []
			for k in sk.get_bone_count(): names.append(sk.get_bone_name(k))
			print("BONES ", names)
	_box(root, Vector3(0,0.2,-2), Color.RED)  # +Z relative to heroes row
	var cam := Camera3D.new(); root.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.size = 22; cam.position = Vector3(0, 30, 0); cam.rotation_degrees = Vector3(-90,0,0); cam.current = true; cam.fov = 60
	for k in 4: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out)
	quit()
