extends Control
## Full-screen cinematic video (the chase + shootout intro). Any key skips once allowed.

signal finished

const PATH := "res://assets/video/intro.ogv"

var player: VideoStreamPlayer
var can_skip := true
var skip_label: Label
var t := 0.0
var _done := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	player = VideoStreamPlayer.new()
	player.set_anchors_preset(Control.PRESET_FULL_RECT)
	player.expand = true
	player.bus = "Music"
	add_child(player)
	skip_label = Game.label("", 20, Game.font_tag, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_RIGHT)
	Game.lay(skip_label, [1, 1, 1, 1], [-700, -60, -40, -24])
	add_child(skip_label)
	if ResourceLoader.exists(PATH):
		player.stream = load(PATH)
		player.finished.connect(_end)
		player.play()
	else:
		_end.call_deferred()


func _process(delta: float) -> void:
	t += delta
	skip_label.text = "PRESS SPACE TO SKIP" if can_skip and t > 1.0 else ""


func _input(event: InputEvent) -> void:
	if _done or not can_skip or t < 1.0:
		return
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
		get_viewport().set_input_as_handled()
		_end()


func _end() -> void:
	if _done:
		return
	_done = true
	player.stop()
	finished.emit()
