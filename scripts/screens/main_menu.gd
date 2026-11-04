extends Control
## Main lobby menu.

const UI = preload("res://scripts/ui/ui.gd")
const NeonButton = preload("res://scripts/ui/neon_button.gd")
const Icons = preload("res://scripts/ui/icons.gd")

var main
var data := {}
var bg_dim := 0.0
var show_top := true
var buttons: Array = []
var t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var items := [
		["PLAY ONLINE", "play", "team"],
		["PLAY OFFLINE", "play", "offline"],
		["CUSTOMIZE", "customize", "customize"],
		["SHOP", "shop", "shop"],
		["FRIENDS", "friends", "friends"],
		["SETTINGS", "settings", "settings"],
		["EXIT", "exit", "exit"],
	]
	var y := 214.0
	for i in items.size():
		var it: Array = items[i]
		var b := NeonButton.new()
		b.setup(it[0], it[1], 40)
		b.primary = i == 0
		UI.rect(b, 50, y, 450, 80)
		b.pressed.connect(_on_item.bind(it[2]))
		add_child(b)
		buttons.append(b)
		b.modulate.a = 0.0
		b.position.x = -40.0
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.08 + i * 0.05)
		tw.tween_property(b, "modulate:a", 1.0, 0.3)
		tw.parallel().tween_property(b, "position:x", 50.0, 0.35)
		y += 92.0

	var tag := Game.label("TWO SIDES\nONE CITY\nYOUR STORY", 20, Game.font_tag, Game.C_DIM)
	tag.add_theme_constant_override("line_spacing", 2)
	UI.rect(tag, 66, 62, 400, 90)
	add_child(tag)
	var line := ColorRect.new()
	line.color = Game.C_CYAN
	UI.rect(line, 68, 158, 48, 3)
	add_child(line)

	var line2 := ColorRect.new()
	line2.color = Game.C_CYAN
	UI.rect(line2, 68, 922, 48, 3)
	add_child(line2)
	var tag2 := Game.label("LAW KEEPS ORDER\nCHAOS KEEPS THINGS INTERESTING", 18, Game.font_tag, Game.C_DIM)
	UI.rect(tag2, 66, 940, 700, 70)
	add_child(tag2)

	var status := UI.paint(self, _draw_status, Rect2(0, 0, 0, 0), true)
	Game.lay(status, [1, 1, 1, 1], [-430, -110, -28, -40])

	var ver := Game.label("v0.8", 14, Game.font_tag, Color(1, 1, 1, 0.3), HORIZONTAL_ALIGNMENT_RIGHT)
	Game.lay(ver, [1, 1, 1, 1], [-430, -32, -30, -8])
	add_child(ver)

	Game.quiet_focus(buttons[0])


func _process(delta: float) -> void:
	t += delta


func _draw_status(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(r, Color(0.03, 0.05, 0.09, 0.84))
	c.draw_rect(r, Color(1, 1, 1, 0.1), false, 1.0)
	Icons.draw(c, "friends", Vector2(32, r.size.y * 0.5), 26, Color(1, 1, 1, 0.85))
	Game.dtext(c, "%d FRIENDS ONLINE" % Online.online_friends(), Vector2(58, r.size.y * 0.5 + 7), 19, Color.WHITE, Game.font_semi)
	c.draw_line(Vector2(240, 16), Vector2(240, r.size.y - 16), Color(1, 1, 1, 0.12), 1.0)
	var on: bool = Online.is_signed_in()
	c.draw_circle(Vector2(268, r.size.y * 0.5), 6, Color(Game.C_GREEN if on else Game.C_RED, 0.7 + 0.3 * sin(t * 4.0)))
	Game.dtext(c, ("ONLINE  •  " + Online.friend_code) if on else "OFFLINE", Vector2(284, r.size.y * 0.5 + 7), 19, Color.WHITE, Game.font_semi)


func _on_item(target: String) -> void:
	if target == "exit":
		on_back()
		return
	if target == "team" and not Online.is_signed_in():
		main.toast("SIGN IN TO PLAY ONLINE", Game.C_CYAN)
		main.go("login")
		return
	if target == "offline":
		main.go("team", {"offline": true})
		return
	main.go(target)


func on_back() -> void:
	main.confirm("EXIT GAME?", "Leave the city and close the game?", "EXIT", func(): Online._quit_cleanly())
