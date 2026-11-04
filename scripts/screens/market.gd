extends Control
## Vorn Market: vehicle dealership and real-estate office.

const UI = preload("res://scripts/ui/ui.gd")

var main
var data := {}
var bg_dim := 0.72
var show_top := true
var category := "cars"
var list_root: Control
var status := ""
var status_col := Game.C_DIM

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.back_button(self, on_back)
	UI.header(self, "VORN MARKET", "DEALERSHIPS  •  HOUSING  •  OWN YOUR NEXT CHAPTER")
	var cars := UI.button(self, "DEALERSHIP", "car", 22, Rect2(50, 220, 250, 58), _set_category.bind("cars"), Game.C_CYAN)
	cars.set("centered", true)
	var homes := UI.button(self, "HOUSING", "home", 22, Rect2(314, 220, 220, 58), _set_category.bind("homes"), Game.C_GOLD)
	homes.set("centered", true)
	var balance := UI.paint(self, _draw_balance, Rect2(0, 0, 0, 0), true)
	Game.lay(balance, [1, 0, 1, 0], [-520, 220, -50, 292])	
	list_root = Control.new()
	list_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.rect(list_root, 50, 310, 1200, 690)
	add_child(list_root)
	var ownership := UI.paint(self, _draw_ownership, Rect2(0, 0, 0, 0), true)
	Game.lay(ownership, [1, 0, 1, 0], [-620, 340, -50, 640])
	var status_box := UI.paint(self, _draw_status, Rect2(0, 0, 0, 0), true)
	Game.lay(status_box, [1, 0, 1, 0], [-620, 670, -50, 900])
	_build_list()
	Game.quiet_focus(cars)

func _set_category(value: String) -> void:
	category = value
	_build_list()

func _items() -> Array:
	return Commerce.CARS if category == "cars" else Commerce.PROPERTIES

func _build_list() -> void:
	if list_root == null:
		return
	for child in list_root.get_children():
		child.queue_free()
	var y := 0.0
	for item in _items():
		var row := UI.paint(list_root, _draw_item.bind(item), Rect2(0, y, 1200, 130), true)
		var owned := Commerce.owned_cars.has(item.id) if category == "cars" else Commerce.owned_properties.has(item.id)
		var selected: bool = Commerce.current_car == item.id if category == "cars" else Commerce.current_property == item.id
		var cap := "ACTIVE" if selected else ("OWNED" if owned else "BUY")
		var col := Game.C_GREEN if selected else Game.C_CYAN if category == "cars" else Game.C_GOLD
		var b := UI.button(list_root, cap, "check" if owned else "shop", 20, Rect2(980, y + 38, 190, 52), _purchase_or_select.bind(str(item.id)), col)
		b.set("centered", true)
		y += 145.0

func _draw_item(c: Control, item: Dictionary) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	Game.draw_panel(c, r, Game.C_CYAN if category == "cars" else Game.C_GOLD)
	var icon := "CAR" if category == "cars" else "HOME"
	Game.dtext(c, icon, Vector2(26, 39), 17, Game.C_CYAN if category == "cars" else Game.C_GOLD, Game.font_tag)
	Game.dtext(c, str(item.name), Vector2(26, 72), 28, Color.WHITE, Game.font_wide)
	Game.dtext(c, str(item.get("type", "Property")) + "  •  " + str(item.description), Vector2(28, 102), 17, Game.C_TEXT, Game.font_med)
	Game.dtext(c, "$" + Game.fmt(int(item.price)), Vector2(790, 66), 23, Game.C_GOLD, Game.font_semi)
	Game.dtext(c, "BANK PURCHASE", Vector2(790, 94), 14, Game.C_DIM, Game.font_tag)

func _draw_balance(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	Game.draw_panel(c, r, Game.C_CYAN)
	Game.dtext(c, "AVAILABLE BANK FUNDS", Vector2(20, 31), 15, Game.C_DIM, Game.font_tag)
	Game.dtext(c, "$" + Game.fmt(int(Game.player.get("bank", 0))), Vector2(20, 62), 26, Game.C_GOLD, Game.font_wide)

func _draw_ownership(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	Game.draw_panel(c, r, Game.C_CYAN)
	Game.dtext(c, "YOUR GARAGE", Vector2(22, 34), 22, Color.WHITE, Game.font_wide)
	Game.dtext(c, "%d VEHICLES OWNED" % Commerce.owned_cars.size(), Vector2(22, 67), 17, Game.C_CYAN, Game.font_tag)
	Game.dtext(c, "CURRENT: " + str(Commerce.car_by_id(Commerce.current_car).get("name", "None")), Vector2(22, 100), 16, Game.C_TEXT, Game.font_med)
	Game.dtext(c, "YOUR HOMES", Vector2(22, 148), 22, Color.WHITE, Game.font_wide)
	Game.dtext(c, "%d PROPERTIES OWNED" % Commerce.owned_properties.size(), Vector2(22, 181), 17, Game.C_GOLD, Game.font_tag)
	Game.dtext(c, "CURRENT: " + str(Commerce.property_by_id(Commerce.current_property).get("name", "None")), Vector2(22, 214), 16, Game.C_TEXT, Game.font_med)

func _draw_status(c: Control) -> void:
	Game.dtext(c, status, Vector2(4, 28), 18, status_col, Game.font_med)

func _purchase_or_select(id: String) -> void:
	if category == "cars":
		if Commerce.owned_cars.has(id):
			Commerce.select_car(id)
			status = "Active vehicle updated."
			status_col = Game.C_GREEN
		else:
			if Commerce.purchase_car(id):
				status = "Vehicle purchased and added to your garage."
				status_col = Game.C_GREEN
			else:
				status = "Not enough funds in your bank account."
				status_col = Game.C_RED
	else:
		if Commerce.owned_properties.has(id):
			Commerce.select_property(id)
			status = "Current home updated."
			status_col = Game.C_GREEN
		else:
			if Commerce.purchase_property(id):
				status = "Property purchased and added to your portfolio."
				status_col = Game.C_GREEN
			else:
				status = "Not enough funds in your bank account."
				status_col = Game.C_RED
	if status_col == Game.C_GREEN:
		main.toast(status, Game.C_GREEN)
	else:
		main.toast(status, Game.C_RED)
	Game.play_sfx("ready" if status_col == Game.C_GREEN else "back")
	_build_list()

func on_back() -> void:
	Game.play_sfx("back")
	main.go("menu")
