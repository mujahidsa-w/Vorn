extends Control
## Shop: featured bundle + daily items, using in-game coins & gems.

const UI = preload("res://scripts/ui/ui.gd")
const ItemCell = preload("res://scripts/ui/item_cell.gd")
const Icons = preload("res://scripts/ui/icons.gd")

var main
var data := {}
var bg_dim := 0.65
var show_top := true

const ITEMS := [
	{"id": "shop/gold_cruiser", "name": "Golden Police Cruiser", "rarity": "Legendary", "price": 2000, "currency": "gems", "icon": "car"},
	{"id": "shop/diamond_mask", "name": "Diamond Mask", "rarity": "Epic", "price": 900, "currency": "gems", "icon": "mask"},
	{"id": "shop/neon_getaway", "name": "Neon Getaway Car", "rarity": "Epic", "price": 15000, "currency": "coins", "icon": "car"},
	{"id": "shop/xp_boost", "name": "XP Booster x2", "rarity": "Rare", "price": 2500, "currency": "coins", "icon": "bolt"},
	{"id": "shop/tiger_bag", "name": "Tiger Loot Bag", "rarity": "Rare", "price": 3000, "currency": "coins", "icon": "bag"},
	{"id": "daily", "name": "Daily Reward", "rarity": "Common", "price": 0, "currency": "coins", "icon": "gift"},
]
const BUNDLE := {"id": "shop/midnight_bundle", "price": 1200, "currency": "gems"}

var cells: Array = []
var bundle_btn: Button
var t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.back_button(self, on_back)
	UI.header(self, "SHOP", "DAILY DEALS  •  NEW ITEMS EVERY 24 HOURS")
	UI.paint(self, _draw_bundle, Rect2(50, 236, 620, 790), true)
	bundle_btn = UI.button(self, "", "gem", 30, Rect2(82, 916, 556, 70), _buy_bundle, Game.C_CYAN)
	bundle_btn.set("primary", true)
	bundle_btn.set("centered", true)
	for i in ITEMS.size():
		var c := ItemCell.new()
		UI.rect(c, 700 + (i % 3) * 384, 236 + int(i / 3.0) * 396, 368, 380)
		c.item = ITEMS[i]
		c.pressed.connect(_buy.bind(i))
		add_child(c)
		cells.append(c)
	var timer := UI.paint(self, _draw_timer, Rect2(0, 0, 0, 0), true)
	Game.lay(timer, [1, 0, 1, 0], [-640, 156, -50, 196])
	_refresh()
	Game.quiet_focus(cells[0])


func _process(delta: float) -> void:
	t += delta


func _today() -> String:
	return Time.get_date_string_from_system()


func _refresh() -> void:
	for i in ITEMS.size():
		var it: Dictionary = ITEMS[i]
		var c = cells[i]
		if it.id == "daily":
			c.state = "owned" if Game.player.daily_claimed == _today() else ""
			c.item = it.duplicate()
			c.item.name = "Daily Reward  +500" if c.state == "" else "Claimed — come back tomorrow"
		else:
			c.state = "owned" if Game.player.owned.has(it.id) else ""
	var owned_b: bool = Game.player.owned.has(BUNDLE.id)
	bundle_btn.set("caption", "OWNED" if owned_b else "BUY  " + Game.fmt(BUNDLE.price))
	bundle_btn.set("icon_kind", "check" if owned_b else "gem")


func _buy(i: int) -> void:
	var it: Dictionary = ITEMS[i]
	var c = cells[i]
	if c.state != "":
		return
	if it.id == "daily":
		Game.player.daily_claimed = _today()
		Game.earn("coins", 500)
		main.toast("+500 coins claimed!", Game.C_GOLD)
	else:
		if not Game.spend(it.currency, it.price):
			main.toast("Not enough %s" % it.currency, Game.C_RED)
			Game.play_sfx("back")
			return
		Game.player.owned.append(it.id)
		Game.save_data()
		main.toast("Purchased %s" % it.name, Game.C_GOLD)
	Game.play_sfx("ready")
	c.flash()
	_refresh()


func _buy_bundle() -> void:
	if Game.player.owned.has(BUNDLE.id):
		return
	if not Game.spend(BUNDLE.currency, BUNDLE.price):
		main.toast("Not enough gems", Game.C_RED)
		Game.play_sfx("back")
		return
	Game.player.owned.append(BUNDLE.id)
	Game.save_data()
	main.toast("Midnight Heist Bundle unlocked!", Game.C_GOLD)
	Game.play_sfx("ready")
	_refresh()


func _draw_timer(c: Control) -> void:
	var now := Time.get_time_dict_from_system()
	var left := 86400 - (int(now.hour) * 3600 + int(now.minute) * 60 + int(now.second))
	var s := "REFRESHES IN  %02d:%02d:%02d" % [left / 3600, (left / 60) % 60, left % 60]
	Game.dtext(c, s, Vector2(c.size.x, 28), 20, Game.C_DIM, Game.font_tag, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_bundle(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	var tex: Texture2D = preload("res://assets/img/robber_art.jpg")
	var ts := tex.get_size()
	var z := maxf(r.size.x / ts.x, r.size.y / ts.y)
	var src := Rect2(Vector2((ts.x - r.size.x / z) * 0.5, 0), r.size / z)
	c.draw_texture_rect_region(tex, r, src)
	var d0 := Color(0.01, 0.015, 0.03, 0.1)
	var d1 := Color(0.01, 0.015, 0.03, 0.97)
	c.draw_polygon(PackedVector2Array([Vector2(0, r.size.y * 0.3), Vector2(r.size.x, r.size.y * 0.3), r.size, Vector2(0, r.size.y)]), PackedColorArray([d0, d0, d1, d1]))
	var gold := Game.C_GOLD
	c.draw_rect(r, Color(gold, 0.5 + 0.2 * sin(t * 2.0)), false, 2.0)
	c.draw_rect(Rect2(24, 24, 150, 34), gold)
	Game.dtext(c, "FEATURED", Vector2(99, 48), 18, Color(0.05, 0.04, 0.0), Game.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	Game.dtext(c, "LEGENDARY BUNDLE", Vector2(32, 420), 18, gold, Game.font_tag)
	Game.dtext(c, "MIDNIGHT HEIST", Vector2(28, 490), 70, Color.WHITE, Game.font_wide)
	var items := ["Midnight Hoodie + Mask", "Smoke-trail Getaway Car", "Golden Loot Bag", "+20% Loot XP for 7 days"]
	for i in items.size():
		Icons.draw(c, "check", Vector2(44, 534 + i * 32), 16, gold)
		Game.dtext(c, items[i], Vector2(64, 541 + i * 32), 21, Game.C_TEXT)


func on_back() -> void:
	Game.play_sfx("back")
	main.go("menu")
