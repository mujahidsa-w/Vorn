extends Node3D
const Rig = preload("res://scripts/game3d/rig.gd")
const W = preload("res://scripts/game3d/weapons.gd")
# [variant, weapon, speed(fwd), stance, aiming, punch_t, dead, label]
var cases := [
	["hero", "akm", 0.0, 0, false, -1.0, false, "idle"],
	["hero", "akm", 1.4, 0, false, -1.0, false, "walk"],
	["hero", "akm", 3.3, 0, false, -1.0, false, "run"],
	["hero", "akm", 3.3, 0, true, -1.0, false, "run+fire"],
	["hero", "akm", 0.0, 0, true, -1.0, false, "aim"],
	["hero", "akm", 1.4, 0, true, -1.0, false, "walk aim"],
	["cop", "m4", 0.0, 0, false, -1.0, false, "m4 idle"],
	["cop", "m4", 1.4, 0, false, -1.0, false, "m4 walk"],
	["cop", "m4", 3.3, 0, false, -1.0, false, "m4 run"],
	["hero", "akm", 0.8, 1, false, -1.0, false, "crouch walk"],
	["hero", "rpg", 1.4, 0, false, -1.0, false, "rpg walk"],
	["hero", "akm", -1.2, 0, false, -1.0, false, "back"],
]
func _ready() -> void:
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.3,0.3,0.35)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1,1,1); env.environment.ambient_light_energy = 0.8
	add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 30, 0); add_child(sun)
	var side := OS.get_cmdline_user_args().has("--side")
	var rigs := []
	for i in cases.size():
		var cs: Array = cases[i]
		var hold := Node3D.new()
		add_child(hold)
		hold.position = Vector3((i % 6) * 1.25 - 3.1, (1 - i / 6) * 2.25 - 1.0, 0)
		hold.rotation.y = (PI / 2.0 if i % 2 == 0 else PI - 0.6) if side else 0.0
		var model := Node3D.new(); hold.add_child(model)
		var r := Rig.new()
		model.add_child(r)
		r.setup(cs[0])
		var wt := ""
		if cs[1] != "":
			var d: Dictionary = W.DATA[cs[1]]
			var wn: Node3D = load(d.path).instantiate()
			model.add_child(wn)
			wn.position = d.pos
			wn.rotation_degrees = d.rot
			r.weapon = wn
			r.weapon_id = cs[1]
			r.grips = W.grips_for(cs[1], wn)
			wt = d.type
		r.stance = cs[3]
		r.aiming = cs[4]
		r.dead = cs[6]
		rigs.append([r, wt, cs])
		var lb := Label3D.new(); lb.text = cs[7]; lb.pixel_size = 0.004; lb.position = Vector3(0, 2.05, 0); lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		hold.add_child(lb)
	var cam := Camera3D.new(); add_child(cam)
	cam.position = Vector3(0, 1.0, 7.0); cam.look_at(Vector3(0, 0.9, 0)); cam.current = true
	for f in 45:
		for it in rigs:
			var r = it[0]
			var cs: Array = it[2]
			if cs[5] >= 0.0:
				r.punch_t = cs[5]
			r.update(1.0/30.0, Vector2(0, cs[2]), true, it[1], 1.0 if it[1] != "" else 0.0, 0.0)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	get_tree().quit()
