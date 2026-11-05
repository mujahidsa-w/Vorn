extends Control
## Vorn City lobby: intentionally empty for now. The screen stays registered so navigation keeps working.

var main
var data := {}
var bg_dim := 0.0
var show_top := false
var buttons: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func on_back() -> void:
	main.confirm("خروج", "هل تريد مغادرة Vorn City؟", "خروج", func(): Online._quit_cleanly())
