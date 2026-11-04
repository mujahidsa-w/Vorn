extends Node
## Starts offline play, waits for the city, then runs ui_shots.gd on it.
## Run: godot --path . -- --uishots <out_dir>
var main
var out := ""


func _w(s: float) -> void:
	await get_tree().create_timer(s).timeout


func run() -> void:
	await _w(0.5)
	get_parent().remove_child.call_deferred(self)
	get_tree().root.add_child.call_deferred(self)
	await _w(2.0)
	main.current._offline()
	await _w(1.5)
	main.current._on_item("offline")
	await _w(1.5)
	main.current._pick(0)
	for k in 150:
		await _w(2.0)
		var cs := get_tree().current_scene
		if cs and cs.get("player") != null and cs.get("hud") != null:
			break
	await _w(4.0)
	var w = get_tree().current_scene
	var shots: Node = load("res://tools/ui_shots.gd").new()
	shots.world = w
	shots.out = out
	add_child(shots)
	shots.run()
