extends Control
## Cheap 2D rain streaks drawn over the background.

const N := 420
const WIND := -0.18
var drops: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in N:
		drops.append(_new_drop(true))


func _new_drop(anywhere: bool) -> Dictionary:
	var depth := randf()
	var w := maxf(size.x, 1920.0)
	var h := maxf(size.y, 1080.0)
	return {
		"x": randf_range(0.0, w + 320.0),
		"y": randf_range(-60.0, h) if anywhere else randf_range(-160.0, -20.0),
		"v": lerpf(900.0, 1900.0, depth),
		"l": lerpf(14.0, 44.0, depth),
		"a": lerpf(0.05, 0.24, depth),
		"w": lerpf(1.0, 1.8, depth),
	}


func _process(delta: float) -> void:
	if not visible:
		return
	var h := size.y
	for d in drops:
		d.y += d.v * delta
		d.x += d.v * WIND * delta
		if d.y > h + 50.0:
			d.merge(_new_drop(false), true)
	queue_redraw()


func _draw() -> void:
	var dir := Vector2(WIND, 1.0).normalized()
	for d in drops:
		var p := Vector2(d.x, d.y)
		draw_line(p, p + dir * float(d.l), Color(0.75, 0.85, 1.0, d.a), d.w)
