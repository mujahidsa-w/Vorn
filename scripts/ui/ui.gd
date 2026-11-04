extends RefCounted
## Small factory helpers shared by screens.

const NeonButton = preload("res://scripts/ui/neon_button.gd")
const Paint = preload("res://scripts/ui/paint.gd")


static func rect(c: Control, x: float, y: float, w: float, h: float) -> Control:
	return Game.lay(c, [0, 0, 0, 0], [x, y, x + w, y + h])


static func button(parent: Control, cap: String, icon: String, fs: int, r: Rect2, cb: Callable, acc := Color(0.25, 0.85, 1.0)) -> Button:
	var b := NeonButton.new()
	b.setup(cap, icon, fs, acc)
	rect(b, r.position.x, r.position.y, r.size.x, r.size.y)
	if cb.is_valid():
		b.pressed.connect(cb)
	parent.add_child(b)
	return b


static func back_button(parent: Control, cb: Callable) -> Button:
	var b := button(parent, "BACK", "back", 28, Rect2(50, 40, 240, 60), cb)
	b.hint = "ESC"
	return b


static func header(parent: Control, title: String, sub: String) -> void:
	var t := Game.label(title, 60, Game.font_wide, Color.WHITE)
	rect(t, 50, 112, 1200, 70)
	parent.add_child(t)
	var s := Game.label(sub, 20, Game.font_tag, Game.C_DIM)
	rect(s, 54, 178, 1200, 30)
	parent.add_child(s)


static func paint(parent: Control, fn: Callable, r: Rect2, animate := false) -> Control:
	var p := Paint.new()
	p.painter = fn
	p.animate = animate
	rect(p, r.position.x, r.position.y, r.size.x, r.size.y)
	parent.add_child(p)
	return p
