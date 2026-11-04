extends Control
## Character locker: pick team, category, buy/equip items.

const UI = preload("res://scripts/ui/ui.gd")
const ItemCell = preload("res://scripts/ui/item_cell.gd")

var main
var data := {}
var bg_dim := 0.82
var show_top := true

const CATS := {
	"robbers": [["MASKS", "Mask", "mask"], ["HOODIES", "Hoodie", "customize"], ["PANTS", "Cargos", "pants"], ["SHOES", "Sneakers", "shoe"], ["GLOVES", "Gloves", "glove"]],
	"cops": [["CAPS", "Cap", "cap"], ["VESTS", "Vest", "customize"], ["PANTS", "Pants", "pants"], ["BOOTS", "Boots", "shoe"], ["BADGES", "Badge", "badge"]],
}
const PREFIX := ["Classic", "Street", "Urban", "Shadow", "Neon", "Chrome", "Phantom", "Midnight", "Golden"]
const RARITY_BY_IDX := ["Common", "Common", "Common", "Rare", "Rare", "Rare", "Epic", "Epic", "Legendary"]
const PRICE_BY_IDX := [0, 400, 800, 1500, 2200, 3000, 5000, 7500, 12000]

var team := "robbers"
var cat := 0
var team_btns: Array = []
var cat_btns: Array = []
var cells: Array = []
var art_tex := {"cops": preload("res://assets/img/cop_art.jpg"), "robbers": preload("res://assets/img/robber_art.jpg")}
var t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	team = str(Game.player.team) if str(Game.player.team) != "" else "robbers"
	UI.back_button(self, on_back)
	UI.header(self, "CUSTOMIZE", "BUILD YOUR LOOK  •  ITEMS ARE SAVED TO YOUR PROFILE")
	var tb1 := UI.button(self, "COPS", "", 26, Rect2(1010, 150, 200, 56), _set_team.bind("cops"), Game.C_BLUE)
	var tb2 := UI.button(self, "ROBBERS", "", 26, Rect2(1222, 150, 200, 56), _set_team.bind("robbers"), Game.C_RED)
	tb1.set("centered", true)
	tb2.set("centered", true)
	team_btns = [tb1, tb2]
	for i in 5:
		var b := UI.button(self, "", "", 28, Rect2(50, 236 + i * 76, 300, 64), _set_cat.bind(i))
		cat_btns.append(b)
	UI.paint(self, _draw_char, Rect2(380, 236, 600, 760), true)
	for i in 9:
		var c := ItemCell.new()
		UI.rect(c, 1010 + (i % 3) * 276, 236 + int(i / 3.0) * 216, 260, 200)
		c.pressed.connect(_on_cell.bind(i))
		add_child(c)
		cells.append(c)
	var hint := Game.label("CLICK AN ITEM TO BUY OR EQUIP", 16, Game.font_tag, Color(1, 1, 1, 0.4))
	UI.rect(hint, 1010, 890, 820, 30)
	add_child(hint)
	_rebuild()
	Game.quiet_focus(cat_btns[0])


func _process(delta: float) -> void:
	t += delta


func _item_id(i: int) -> String:
	return "%s/%s/%d" % [team, CATS[team][cat][0], i]


func _item(i: int) -> Dictionary:
	var c: Array = CATS[team][cat]
	return {
		"name": "%s %s" % [PREFIX[i], c[1]],
		"rarity": RARITY_BY_IDX[i],
		"price": PRICE_BY_IDX[i],
		"currency": "coins",
		"icon": c[2],
	}


func _slot_key() -> String:
	return "%s/%s" % [team, CATS[team][cat][0]]


func _rebuild() -> void:
	for i in 5:
		var b = cat_btns[i]
		b.set("caption", CATS[team][i][0])
		b.set("icon_kind", CATS[team][i][2])
		b.set("primary", i == cat)
		b.set("accent", Game.C_BLUE if team == "cops" else Game.C_RED)
	team_btns[0].set("primary", team == "cops")
	team_btns[1].set("primary", team == "robbers")
	var eq = Game.player.equipped.get(_slot_key(), 0)
	for i in 9:
		var c = cells[i]
		c.item = _item(i)
		var id := _item_id(i)
		if int(eq) == i:
			c.state = "equipped"
		elif i == 0 or Game.player.owned.has(id):
			c.state = "owned"
		else:
			c.state = ""


func _set_team(tm: String) -> void:
	team = tm
	cat = 0
	_rebuild()


func _set_cat(i: int) -> void:
	cat = i
	_rebuild()


func _on_cell(i: int) -> void:
	var c = cells[i]
	var it := _item(i)
	if c.state == "equipped":
		return
	if c.state == "":
		if not Game.spend("coins", int(it.price)):
			main.toast("Not enough coins for %s" % it.name, Game.C_RED)
			Game.play_sfx("back")
			return
		Game.player.owned.append(_item_id(i))
		main.toast("Purchased %s" % it.name, Game.C_GOLD)
	Game.player.equipped[_slot_key()] = i
	Game.save_data()
	Game.play_sfx("ready")
	c.flash()
	_rebuild()


func _draw_char(c: Control) -> void:
	var tex: Texture2D = art_tex[team]
	var acc := Game.C_BLUE if team == "cops" else Game.C_RED
	var r := Rect2(Vector2.ZERO, c.size)
	var base := Vector2(c.size.x * 0.5, c.size.y - 70)
	# platform
	for i in 3:
		var rr := 200.0 - i * 40.0
		var pts := PackedVector2Array()
		for k in 49:
			var a := TAU * k / 48.0
			pts.append(base + Vector2(cos(a) * rr, sin(a) * rr * 0.22))
		c.draw_polyline(pts, Color(acc, 0.5 - i * 0.12), 2.0, true)
	var a0 := t * 1.2
	var arc := PackedVector2Array()
	for k in 17:
		var a := a0 + 1.4 * k / 16.0
		arc.append(base + Vector2(cos(a) * 200.0, sin(a) * 44.0))
	c.draw_polyline(arc, acc.lightened(0.3), 4.0, true)
	# character (center crop of art)
	var ts := tex.get_size()
	var src := Rect2(ts.x * 0.18, 0, ts.x * 0.64, ts.y)
	var h := c.size.y - 40.0
	var w := h * src.size.x / src.size.y
	var dst := Rect2(base.x - w * 0.5, base.y - h + 30.0, w, h)
	c.draw_texture_rect_region(tex, dst, src, Color(1, 1, 1, 1))
	# fade edges
	var e0 := Color(0.01, 0.015, 0.035, 0.0)
	var e1 := Color(0.01, 0.015, 0.035, 0.85)
	var ew := 150.0
	c.draw_polygon(PackedVector2Array([dst.position, dst.position + Vector2(ew, 0), Vector2(dst.position.x + ew, dst.end.y), Vector2(dst.position.x, dst.end.y)]), PackedColorArray([e1, e0, e0, e1]))
	c.draw_polygon(PackedVector2Array([Vector2(dst.end.x - ew, dst.position.y), Vector2(dst.end.x, dst.position.y), dst.end, Vector2(dst.end.x - ew, dst.end.y)]), PackedColorArray([e0, e1, e1, e0]))
	c.draw_polygon(PackedVector2Array([dst.position, Vector2(dst.end.x, dst.position.y), Vector2(dst.end.x, dst.position.y + 160), Vector2(dst.position.x, dst.position.y + 160)]), PackedColorArray([e1, e1, e0, e0]))
	var eq = Game.player.equipped.get(_slot_key(), 0)
	var it := _item(int(eq))
	var rc: Color = Game.RARITY[it.rarity]
	c.draw_rect(Rect2(20, r.size.y - 50, r.size.x - 40, 44), Color(0.03, 0.05, 0.09, 0.85))
	Game.dtext(c, "EQUIPPED:", Vector2(36, r.size.y - 21), 16, Game.C_DIM, Game.font_tag)
	Game.dtext(c, "%s  (%s)" % [it.name, it.rarity], Vector2(166, r.size.y - 20), 22, rc, Game.font_bold)


func on_back() -> void:
	Game.play_sfx("back")
	main.go("menu")
