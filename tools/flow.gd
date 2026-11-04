extends Node
var main
var out := ""
func run() -> void:
	await get_tree().create_timer(1.0).timeout
	main.go("loading", {"team": "cops"})
	await get_tree().create_timer(12.0).timeout
	print("SCENE NOW: ", get_tree().current_scene.name if get_tree().current_scene else "none")
