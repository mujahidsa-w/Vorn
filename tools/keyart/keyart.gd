extends Node3D
## Development tool: renders loading-screen key art candidates from the Kasbah map at golden hour.
##   godot --path . -- --test keyart --shots <dir>     (needs a display; not part of exported builds)

const SHOTS := [
	# name, camera (map x, y, height), look-at (map x, y, height), fov
	["keyart_1", Vector3(40, 76, 10), Vector3(0, 46, 9), 55.0],
	["keyart_2", Vector3(94, 78, 18), Vector3(30, 30, 7), 48.0],
	["keyart_3", Vector3(90, 56, 11), Vector3(40, 40, 8), 50.0],
]

func _ready() -> void:
	var world := World.new()
	add_child(world)
	world.load_map("kasbah")
	world.golden_hour()
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var dir: String = G.shots_dir if G.shots_dir != "" else "user://keyart"
	DirAccess.make_dir_recursive_absolute(dir)
	for s in SHOTS:
		var p: Vector3 = s[1]
		var l: Vector3 = s[2]
		cam.fov = float(s[3])
		cam.position = World.w(p.x, p.y, p.z)
		cam.look_at(World.w(l.x, l.y, l.z), Vector3.UP)
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, s[0]])
		print("KEYART ", s[0])
	get_tree().quit()
