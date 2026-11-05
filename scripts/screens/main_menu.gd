extends Control
## Vorn City lobby: intentionally empty for now. The screen stays registered so navigation keeps working.

var main
var data := {}
var bg_dim := 0.0
var show_top := false
var buttons: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# hide the app-wide background and rain while the lobby is open
	main.bg.visible = false
	main.rain.visible = false


func _exit_tree() -> void:
	if main:
		main.bg.visible = true
		main.rain.visible = Game.settings.rain


func on_back() -> void:
	main.confirm("خروج", "هل تريد مغادرة Vorn City؟", "خروج", func(): Online._quit_cleanly())
