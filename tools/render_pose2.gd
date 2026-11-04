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
	var X := Vector3.RIGHT; var Y := Vector3.UP; var Z := Vector3.BACK
	# [R_up_fwd, R_fore, L_up_fwd, L_fore, L_inward]
	var tests := [[0.7,1.0,-1.4,0.2,0.4,0.25],[0.7,1.0,-1.4,-0.4,0.0,0.25],[0.7,1.0,-1.2,-0.6,-0.3,0.25],[0.7,1.0,-1.5,-0.3,0.2,0.25]]
	var wrot := [Vector3(0,-90,12), Vector3(0,-90,-12), Vector3(0,-90,-12), Vector3(0,-90,-12)]
	for row in 2:
		for i in tests.size():
			var h: Node3D = load("res://assets/models/chars/hero.glb").instantiate(); root.add_child(h)
			h.position = Vector3(-3.6 + i * 2.4, 0, 0)
			if row == 1: h.position.y = -2.2; h.rotation.y = PI / 2
			var sk: Skeleton3D = h.find_children("*", "Skeleton3D", true, false)[0]
			var t = tests[i]
			q(sk, "CC_Base_R_Upperarm", Quaternion(Z, 1.2 + t[5]) * Quaternion(X, t[0]))
			q(sk, "CC_Base_R_Forearm", Quaternion(X, t[1]))
			q(sk, "CC_Base_L_Upperarm", Quaternion(Z, -1.2 - t[4]) * Quaternion(X, t[2]))
			q(sk, "CC_Base_L_Forearm", Quaternion(X, t[3]))
			var w: Node3D = load("res://assets/models/weapons/m4.glb").instantiate(); h.add_child(w)
			w.position = Vector3(-0.1, 1.36, 0.45); w.rotation_degrees = wrot[i]
	var cam := Camera3D.new(); root.add_child(cam); cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.size = 4.8
	cam.position = Vector3(0, 0.1, 12); cam.current = true
	for k in 3: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out)
	quit()
