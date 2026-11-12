extends CanvasLayer
## Buy menu for the buy phase (open with B, or the BUY button on touch screens).
## Items are real: buying takes the money and gives the weapon / armor right away.

const W = preload("res://scripts/game3d/weapons.gd")
const ITEMS := [
	{"id": "m4", "name": "M4 CARBINE", "price": 3100, "kind": "rifle", "info": "30 RDS  ·  AUTO  ·  RIFLE"},
	{"id": "kevlar", "name": "KEVLAR VEST", "price": 650, "kind": "armor", "info": "100 ARMOR"},
]

var mode                      # comp_mode (money, phase, player)
var open := false
var root: Control
var cards: Array = []
var money_lbl: Label
var hint_lbl: Label


func _ready() -> void:
	layer = 11     # above the touch controls
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: toggle())
	root.add_child(dim)
	var title := Game.label("BUY", 46, Game.font_wide, Color.WHITE)
	title.position = Vector2(160, 150)
	root.add_child(title)
	money_lbl = Game.label("$0", 40, Game.font_wide, Color(0.45, 1.0, 0.55))
	money_lbl.position = Vector2(330, 152)
	root.add_child(money_lbl)
	hint_lbl = Game.label("", 18, Game.font_bold, Game.C_DIM)
	hint_lbl.position = Vector2(162, 214)
	root.add_child(hint_lbl)
	for i in ITEMS.size():
		var it: Dictionary = ITEMS[i]
		var b := Button.new()
		b.position = Vector2(160 + i * 440, 270)
		b.size = Vector2(410, 300)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_buy.bind(i))
		var n := StyleBoxFlat.new()
		n.bg_color = Color(0.04, 0.06, 0.09, 0.92)
		n.border_color = Color(1, 1, 1, 0.18)
		n.set_border_width_all(2)
		n.set_corner_radius_all(10)
		var h := n.duplicate()
		h.border_color = Color(1.0, 0.78, 0.25, 0.9)
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", h)
		b.add_theme_stylebox_override("pressed", h)
		b.add_theme_stylebox_override("disabled", n)
		root.add_child(b)
		var art := Control.new()
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.position = Vector2(20, 20)
		art.size = Vector2(370, 170)
		art.draw.connect(_draw_art.bind(art, str(it.kind)))
		b.add_child(art)
		var nm := Game.label(str(it.name), 28, Game.font_wide, Color.WHITE)
		nm.position = Vector2(24, 196)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(nm)
		var inf := Game.label(str(it.info), 16, Game.font_bold, Game.C_DIM)
		inf.position = Vector2(26, 236)
		inf.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(inf)
		var pr := Game.label("$%d" % int(it.price), 30, Game.font_wide, Color(0.45, 1.0, 0.55))
		pr.position = Vector2(290, 196)
		pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(pr)
		cards.append({"btn": b, "price": pr, "item": it})


func toggle() -> void:
	set_open(not open)


func set_open(on: bool) -> void:
	if on and not mode.can_buy():
		return
	open = on
	root.visible = on
	if not Game.touch:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	_refresh()


func _owned(it: Dictionary) -> bool:
	var pl = mode.world.player
	if it.kind == "armor":
		return pl.armor >= 100.0
	return pl.inventory.has(it.id)


func _buy(i: int) -> void:
	var it: Dictionary = ITEMS[i]
	if not mode.can_buy() or _owned(it) or mode.money < int(it.price):
		Game.play_sfx("click", 0.6, -6.0)
		return
	mode.money -= int(it.price)
	var pl = mode.world.player
	if it.kind == "armor":
		pl.armor = 100.0
	else:
		pl.give_weapon(it.id)
		pl.equip(it.id)
	Game.play_sfx("pickup")
	_refresh()


func _refresh() -> void:
	if mode == null:
		return
	money_lbl.text = "$%d" % int(mode.money)
	hint_lbl.text = "BUY TIME %ds   ·   B / TAP OUTSIDE TO CLOSE" % int(ceil(mode.rules.phase_left))
	for c in cards:
		var it: Dictionary = c.item
		var owned := _owned(it)
		var afford: bool = mode.money >= int(it.price)
		c.price.text = "OWNED" if owned else "$%d" % int(it.price)
		c.price.add_theme_color_override("font_color", Game.C_DIM if owned else (Color(0.45, 1.0, 0.55) if afford else Color(1.0, 0.35, 0.3)))
		c.btn.modulate = Color(1, 1, 1, 0.55 if (owned or not afford) else 1.0)


func _process(_d: float) -> void:
	if open:
		if not mode.can_buy():
			set_open(false)
		else:
			_refresh()


## touch screens: taps on a card buy it, taps outside close the menu
func _input(e: InputEvent) -> void:
	if not open or not (e is InputEventScreenTouch) or not e.pressed:
		return
	get_viewport().set_input_as_handled()
	for i in cards.size():
		var b: Button = cards[i].btn
		if Rect2(b.global_position, b.size).has_point(e.position):
			_buy(i)
			return
	set_open(false)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_B:
		toggle()
		get_viewport().set_input_as_handled()


## simple line art per item kind (no image files)
func _draw_art(c: Control, kind: String) -> void:
	var col := Color(1, 1, 1, 0.85)
	var o := Vector2(30, 40)
	if kind == "rifle":
		var pts := [
			[Vector2(0, 40), Vector2(70, 40)], [Vector2(70, 30), Vector2(250, 30)], [Vector2(250, 30), Vector2(320, 34)],
			[Vector2(70, 30), Vector2(70, 60)], [Vector2(70, 60), Vector2(180, 60)], [Vector2(0, 40), Vector2(0, 70)],
			[Vector2(0, 70), Vector2(60, 64)], [Vector2(150, 60), Vector2(140, 115)], [Vector2(140, 115), Vector2(160, 118)],
			[Vector2(160, 118), Vector2(168, 60)], [Vector2(110, 60), Vector2(100, 95)], [Vector2(100, 95), Vector2(116, 98)],
			[Vector2(116, 98), Vector2(122, 60)], [Vector2(120, 30), Vector2(120, 14)], [Vector2(120, 14), Vector2(200, 14)],
			[Vector2(200, 14), Vector2(200, 30)],
		]
		for seg in pts:
			c.draw_line(o + seg[0], o + seg[1], col, 4.0, true)
	else:
		var v := PackedVector2Array([Vector2(110, 0), Vector2(200, 0), Vector2(230, 40), Vector2(215, 140), Vector2(155, 160), Vector2(95, 140), Vector2(80, 40)])
		for i in v.size():
			c.draw_line(o + v[i], o + v[(i + 1) % v.size()], col, 4.0, true)
		c.draw_line(o + Vector2(155, 20), o + Vector2(155, 140), Color(col, 0.5), 3.0)
