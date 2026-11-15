extends SceneTree
## Physics check of the battle royale vehicles on flat ground: acceleration, top speed, braking, turning, roll.
##   godot --headless --path . --script res://tools/checks/vehicle_check.gd

func _initialize() -> void:
	_run.call_deferred()

func _ground() -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2000, 1, 2000)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	b.add_child(cs)
	get_root().add_child(b)
	# a ramp to drive over
	var r := StaticBody3D.new()
	var rc := CollisionShape3D.new()
	var rb := BoxShape3D.new()
	rb.size = Vector3(8, 0.4, 12)
	rc.shape = rb
	r.add_child(rc)
	r.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-14.0)), Vector3(40, 0.8, 300))
	get_root().add_child(r)

func _run() -> void:
	_ground()
	for kind in ["buggy", "bike"]:
		var v := Vehicle.new()
		v.setup(null, kind, Color.RED)
		v.autopilot = true
		get_root().add_child(v)
		v.global_position = Vector3(0, 1.0, 0)
		var log := []
		var t := 0.0
		var phases := [[3.0, Vector3(0, 0, 0)], [8.0, Vector3(0, 1, 0)], [4.0, Vector3(1, 1, 0)], [3.0, Vector3(-1, 1, 0)], [3.0, Vector3(0, -1, 0)], [3.0, Vector3(0, -1, 0)]]
		for ph in phases:
			v.controls = ph[1]
			var steps := int(float(ph[0]) * 60.0)
			for i in steps:
				await physics_frame
				t += 1.0 / 60.0
			var sp := v.linear_velocity.dot(v.global_basis.z)
			print("%s t=%.0f ctl %s speed %.1f m/s (%.0f km/h) pos %s up.y %.2f roll %.2f" % [kind, t, ph[1], sp, sp * 3.6, v.global_position.snapped(Vector3.ONE * 0.1), v.global_basis.y.y, v.global_basis.x.y])
		v.queue_free()
		await process_frame
	quit(0)
