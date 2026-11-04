extends Control
## Generic custom-drawn control: set `painter` to a Callable(ci: Control).

var painter: Callable
var animate := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_d: float) -> void:
	if animate:
		queue_redraw()


func _draw() -> void:
	if painter.is_valid():
		painter.call(self)
