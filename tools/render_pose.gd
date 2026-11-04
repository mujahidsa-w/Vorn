extends SceneTree
func q(sk: Skeleton3D, n: String, rot: Quaternion) -> void:
	var b := sk.find_bone(n)
	sk.set_bone_pose_rotation(b, sk.get_bone_rest(b).basis.get_rotation_quaternion() * rot)
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var root := Node3D.new(); get_root().add_child(root)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.45,0.5,0.55)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(1,1,1); e.ambient_light_energy = 0.9
	env.environment = e; root.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-30, 60, 0); root.add_child(sun)
	var axes := {"X": Vector3.RIGHT, "Y": Vector3.UP, "Z": Vector3.BACK}
	var tests := []
	for sw in [-0.8, 0.8]:
		for ax in ["X", "Y", "Z"]:
			for sg in [-1.3, 1.3]:
				tests.append([sw, ax, sg])
	for i in tests.size():
		var h: Node3D = load("res://assets/models/chars/hero.glb").instantiate(); root.add_child(h)
		h.position = Vector3(-6.6 + i * 1.2, 0, 0)
		h.rotation.y = PI / 2
		var sk: Skeleton3D = h.find_children("*", "Skeleton3D", true, false)[0]
		var t = tests[i]
		q(sk, "CC_Base_L_Upperarm", Quaternion(Vector3.BACK, -1.2))
		q(sk, "CC_Base_R_Upperarm", Quaternion(Vector3.BACK, 1.2) * Quaternion(Vector3.RIGHT, t[0]))
		q(sk, "CC_Base_R_Forearm", Quaternion(axes[t[1]], t[2]))
	var cam := Camera3D.new(); root.add_child(cam); cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.size = 2.2
	cam.position = Vector3(0, 1.25, 12); cam.current = true
	for k in 3: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out)
	quit()
