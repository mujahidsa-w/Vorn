extends Node3D
## Development tool: renders the loading-screen key art on the battle royale island at golden hour.
##   godot --path . -- --test keyart --shots <dir>     (needs a display; not part of exported builds)

const SHOTS := [
	# name, camera (x, height above ground, z), look-at (x, height above ground, z), fov
	["keyart_1", Vector3(-30, 16, 160), Vector3(-62, 4, 40), 52.0],
	["keyart_2", Vector3(196, 30, -70), Vector3(246, 2, -178), 50.0],
	["keyart_3", Vector3(70, 14, 125), Vector3(-40, 6, 50), 50.0],
]

func _ready() -> void:
	var land: BRLand = BRIsland.new() if BRIsland.available() else BRLand.new()
	add_child(land)
	land.build(731)
	land.evening()
	var cam := Camera3D.new()
	cam.far = 1600.0
	add_child(cam)
	cam.current = true
	var dir: String = G.shots_dir if G.shots_dir != "" else "user://keyart"
	DirAccess.make_dir_recursive_absolute(dir)
	var only := String(G.args.get("only", ""))
	for s in SHOTS:
		if only != "" and only != s[0]:
			continue
		var p: Vector3 = s[1]
		var l: Vector3 = s[2]
		cam.fov = float(s[3])
		cam.position = Vector3(p.x, land.height_at(p.x, p.z) + p.y, p.z)
		cam.look_at(Vector3(l.x, land.height_at(l.x, l.z) + l.y, l.z), Vector3.UP)
		for i in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, s[0]])
		print("KEYART ", s[0])
	get_tree().quit()
