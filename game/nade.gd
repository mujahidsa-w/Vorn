class_name Nade
extends Node3D
## Брошенная граната: баллистика с отскоками, запал, срабатывание.

var game
var thrower: Actor
var id := "he"
var vel := Vector3.ZERO
var t := 0.0
var fuse := 1.7
var rest := false
var done := false
var model: Node3D

func launch(g, who: Actor, nid: String, pos: Vector3, v: Vector3) -> void:
	game = g
	thrower = who
	id = nid
	vel = v
	fuse = {"he": 1.75, "flash": 1.65, "smoke": 2.6, "molotov": 2.6, "decoy": 2.2}.get(nid, 1.7)
	var path := "res://assets/models/weapons/%s.scn" % nid
	if ResourceLoader.exists(path):
		model = (load(path) as PackedScene).instantiate()
		add_child(model)
	global_position = pos

func _physics_process(dt: float) -> void:
	if done:
		return
	t += dt
	if not rest:
		vel.y -= 11.0 * dt
		var from := global_position
		var to := from + vel * dt
		var q := PhysicsRayQueryParameters3D.create(from, to + vel.normalized() * 0.06, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			global_position = to
		else:
			var n: Vector3 = hit["normal"]
			if id == "molotov" and n.y > 0.5:
				global_position = hit["position"] + n * 0.05
				_burst()
				return
			var sp := vel.length()
			vel = vel.bounce(n) * 0.45
			global_position = (hit["position"] as Vector3) + n * 0.07
			if sp > 2.0:
				Sfx.at("nade_bounce", global_position, -8.0, randf_range(0.9, 1.1), 4.0, 40.0)
			if vel.length() < 1.0 and n.y > 0.7:
				rest = true
				vel = Vector3.ZERO
		if model:
			model.rotate_x(dt * 9.0)
			model.rotate_z(dt * 5.0)
	if id == "smoke":
		if (rest and t > 1.0) or t > 3.2:
			_burst()
	elif t >= fuse:
		_burst()

func _burst() -> void:
	if done:
		return
	done = true
	game.nade_burst(self)
	if model:
		model.visible = false
	get_tree().create_timer(0.2).timeout.connect(queue_free)
