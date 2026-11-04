extends Node
## Vorn Market: dealerships, homes and property ownership.

signal changed
signal notification(text: String)

const CARS := [
	{"id": "city_sedan", "name": "Vorn City Sedan", "type": "Sedan", "price": 18000, "description": "Reliable daily driver for city life.", "model": "mustang69"},
	{"id": "royal_sport", "name": "Royal Sport GT", "type": "Sports", "price": 48000, "description": "High-performance coupe for Downtown nights.", "model": "mustang_gt"},
	{"id": "vorn_rtr", "name": "Vorn RTR", "type": "Performance", "price": 72000, "description": "Premium performance car with a bold profile.", "model": "mustang_rtr"},
]

const PROPERTIES := [
	{"id": "starter_apartment", "name": "Downtown Starter Apartment", "type": "Apartment", "price": 15000, "description": "A compact home close to work and city services."},
	{"id": "residential_house", "name": "Palm Avenue House", "type": "House", "price": 95000, "description": "A quiet residential home with room to grow."},
	{"id": "downtown_condo", "name": "Vorn Downtown Condo", "type": "Luxury Condo", "price": 180000, "description": "Modern skyline living in the heart of Downtown."},
	{"id": "city_penthouse", "name": "Skyline Penthouse", "type": "Penthouse", "price": 420000, "description": "The ultimate Vorn City address with a panoramic view."},
]

var owned_cars: Array = []
var owned_properties: Array = []
var current_car := ""
var current_property := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sync_from_game()

func _sync_from_game() -> void:
	var p: Dictionary = Game.player
	owned_cars = p.get("owned_cars", []).duplicate()
	owned_properties = p.get("owned_properties", []).duplicate()
	current_car = str(p.get("current_car", owned_cars[0] if owned_cars.size() > 0 else ""))
	current_property = str(p.get("current_property", p.get("home_id", "")))
	_sync_to_game(false)

func _sync_to_game(save := true) -> void:
	Game.player["owned_cars"] = owned_cars.duplicate()
	Game.player["owned_properties"] = owned_properties.duplicate()
	Game.player["current_car"] = current_car
	Game.player["current_property"] = current_property
	var property := property_by_id(current_property)
	Game.player["home"] = str(property.get("name", "No property owned"))
	changed.emit()
	if save:
		Game.save_data()

func car_by_id(id: String) -> Dictionary:
	for car in CARS:
		if str(car.id) == id:
			return car
	return {}

func property_by_id(id: String) -> Dictionary:
	for property in PROPERTIES:
		if str(property.id) == id:
			return property
	return {}

func purchase_car(id: String) -> bool:
	var car := car_by_id(id)
	if car.is_empty() or owned_cars.has(id):
		return false
	if not _pay_from_bank(int(car.price)):
		notification.emit("Not enough money for %s" % car.name)
		return false
	owned_cars.append(id)
	if current_car == "":
		current_car = id
	_sync_to_game()
	notification.emit("Car purchased: %s" % car.name)
	return true

func purchase_property(id: String) -> bool:
	var property := property_by_id(id)
	if property.is_empty() or owned_properties.has(id):
		return false
	if not _pay_from_bank(int(property.price)):
		notification.emit("Not enough money for %s" % property.name)
		return false
	owned_properties.append(id)
	if current_property == "":
		current_property = id
	_sync_to_game()
	notification.emit("Property purchased: %s" % property.name)
	return true

func _pay_from_bank(amount: int) -> bool:
	if amount <= 0 or int(Game.player.get("bank", 0)) < amount:
		return false
	Game.player["bank"] = int(Game.player.get("bank", 0)) - amount
	return true

func select_car(id: String) -> bool:
	if not owned_cars.has(id):
		return false
	current_car = id
	_sync_to_game()
	notification.emit("Active vehicle: %s" % car_by_id(id).get("name", id))
	return true

func select_property(id: String) -> bool:
	if not owned_properties.has(id):
		return false
	current_property = id
	_sync_to_game()
	notification.emit("Current home: %s" % property_by_id(id).get("name", id))
	return true
