extends Control
## Button layout editor: drag the on-screen phone buttons (and the joystick) to
## where they are comfortable, then save. Works on any device; the preview uses
## the same controls as the game.

const UI = preload("res://scripts/ui/ui.gd")
const TouchControls = preload("res://scripts/game3d/touch_controls.gd")

var main
var data := {}
var tc


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.rect(bg, 0, 0, 1920, 1080)
	add_child(bg)
	var hint := Game.label("DRAG THE BUTTONS TO MOVE THEM  •  DRAG THE STICK TOO", 26, Game.font_bold, Game.C_TEXT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.rect(hint, 300, 40, 1320, 70)
	add_child(hint)
	UI.button(self, "BACK", "back", 24, Rect2(40, 30, 220, 80), _cancel, Game.C_TEXT)
	UI.button(self, "RESET", "", 24, Rect2(1400, 30, 220, 80), _reset, Game.C_RED)
	UI.button(self, "SAVE", "", 24, Rect2(1660, 30, 220, 80), _save, Game.C_GREEN)
	tc = TouchControls.new()
	add_child(tc)
	tc.start_edit()


func _save() -> void:
	tc.save_layout()
	main.toast("BUTTON LAYOUT SAVED")
	_leave()


func _reset() -> void:
	tc.reset_layout()
	main.toast("BUTTON LAYOUT RESET")


func _cancel() -> void:
	_leave()


func _leave() -> void:
	tc.stop_edit()
	main.go("settings")
