extends Node
## Prints frame cost numbers at a street spot (used to compare settings).
var world
var out := ""
func run() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var pl = world.player
	var L = world.life
	var i := 300
	pl.global_position = world._route_xf(i, 7.0).origin + Vector3(0, 0.3, 0)
	var f: Vector3 = -world._route_xf(i, 0.0).basis.z
	pl.yaw = atan2(-f.x, -f.z)
	if world.sky:
		world.sky.set_hour(float(OS.get_cmdline_user_args()[2]) if OS.get_cmdline_user_args().size() > 2 else 13.0)
	await get_tree().create_timer(10.0).timeout
	var acc := {"proc": 0.0, "phys": 0.0, "draw": 0.0, "prim": 0.0, "obj": 0.0, "fps": 0.0}
	for k in 20:
		await get_tree().create_timer(0.25).timeout
		acc.proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		acc.phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		acc.draw += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		acc.prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		acc.obj += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		acc.fps += Engine.get_frames_per_second()
	for k in acc:
		acc[k] /= 20.0
	print("PERF ", acc, " cars ", L.traffic.size() if L else 0, " peds ", L.peds.size() if L else 0)
	get_tree().quit()
