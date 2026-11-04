extends Node3D
const Rig = preload("res://scripts/game3d/rig.gd")
func _ready() -> void:
	var r := Rig.new()
	add_child(r)
	r.setup("hero")
	var line := ""
	var t := 0.0
	while t < 2.2:
		r.punch_t = t
		r.update(1.0/30.0, Vector2.ZERO, true, "", 0.0, 0.0)
		var pr: Vector3 = r._palm("R")
		var pl: Vector3 = r._palm("L")
		line += "%.2f R%.2f L%.2f | " % [t, pr.z, pl.z]
		t += 0.1
	print(line)
	get_tree().quit()
