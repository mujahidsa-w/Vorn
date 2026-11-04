extends Control
## Main lobby menu (VORN CITY lobby): gold sidebar, logo, city card, big PLAY CTA.

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

	_build_logo()

	# Gold sidebar, same buttons and handlers as before.
	var y := 300.0
	for i in items.size():
		var it: Array = items[i]
		var b := NeonButton.new()
		b.setup(it[0], it[1], 30, Game.C_GOLD)
		b.primary = i == 0
		UI.rect(b, 40, y, 330, 70)
		b.pressed.connect(_on_item.bind(it[2]))
		add_child(b)
		buttons.append(b)
		b.modulate.a = 0.0
		b.position.x = -40.0
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.08 + i * 0.05)
		tw.tween_property(b, "modulate:a", 1.0, 0.3)
		tw.parallel().tween_property(b, "position:x", 40.0, 0.35)
		y += 80.0

	# Right-side city card.
	var card := UI.paint(self, _draw_city_card, Rect2(0, 0, 0, 0))
	Game.lay(card, [1, 0, 1, 0], [-470, 150, -60, 330])

	# Big PLAY CTA (routes to the same flow as PLAY ONLINE).
	var cta := NeonButton.new()
	cta.setup("PLAY NOW", "play", 54, Game.C_GOLD)
	cta.primary = true
	cta.pressed.connect(_on_item.bind("team"))
	Game.lay(cta, [1, 1, 1, 1], [-560, -190, -60, -80])
	add_child(cta)
	buttons.append(cta)

	# Welcome line above the status bar.
	var welcome := Game.label("WELCOME TO VORN CITY", 20, Game.font_tag, Game.C_DIM)
	Game.lay(welcome, [0, 1, 0, 1], [40, -170, 700, -125])
	add_child(welcome)

	# Status bar, moved to bottom-left so it does not overlap the CTA.
	var status := UI.paint(self, _draw_status, Rect2(0, 0, 0, 0), true)
	Game.lay(status, [0, 1, 0, 1], [40, -110, 470, -40])

	var ver := Game.label("v0.8", 14, Game.font_tag, Color(1, 1, 1, 0.3), HORIZONTAL_ALIGNMENT_RIGHT)
	Game.lay(ver, [1, 1, 1, 1], [-430, -32, -30, -8])
	add_child(ver)

	Game.quiet_focus(buttons[0])


func _build_logo() -> void:
	# Text logo placeholder until the real VORN artwork is supplied.
	var logo := Game.label("VORN", 120, Game.font_wide, Game.C_GOLD)
	Game.lay(logo, [0, 0, 0, 0], [40, 30, 640, 170])
	add_child(logo)

	var sub := Game.label("CITY  •  ROLEPLAY  •  SURVIVAL", 22, Game.font_bold, Color.WHITE)
	Game.lay(sub, [0, 0, 0, 0], [44, 180, 700, 215])
	add_child(sub)

	var tagline := Game.label("Live the Real Life...", 30, Game.font_semi, Game.C_TEXT)
	Game.lay(tagline, [0, 0, 0, 0], [44, 215, 700, 255])
	add_child(tagline)

	var line := ColorRect.new()
	line.color = Game.C_GOLD
	UI.rect(line, 44, 272, 90, 3)
	add_child(line)


func _process(delta: float) -> void:
	t += delta


func _draw_city_card(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(r, Color(0.03, 0.05, 0.09, 0.84))
	c.draw_rect(r, Color(Game.C_GOLD, 0.45), false, 1.5)
	c.draw_rect(Rect2(0, 0, 3, r.size.y), Game.C_GOLD)
	Icons.draw(c, "car", Vector2(40, 46), 30, Color(Game.C_GOLD, 0.9))
	Game.dtext(c, "VORN CITY", Vector2(72, 56), 34, Color.WHITE, Game.font_wide)
	Game.dtext(c, "OPEN WORLD  •  10 DISTRICTS", Vector2(40, 100), 20, Game.C_DIM, Game.font_tag)
	Game.dtext(c, "DOWNTOWN  •  HARBOR  •  AIRPORT", Vector2(40, 130), 20, Game.C_TEXT, Game.font_semi)
	c.draw_rect(Rect2(40, 150, r.size.x - 80, 2), Color(1, 1, 1, 0.12))
	Game.dtext(c, "Explore, work, buy property and meet other players.", Vector2(40, 178), 19, Game.C_DIM, Game.font_tag)


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
