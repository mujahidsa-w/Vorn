extends Node
## Vorn City RP gangs and territories: identity, reputation and influence.

signal changed
signal notification(text: String)

const GANGS := [
	{"id": "night_owls", "name": "Night Owls", "motto": "Own the night.", "color": Color(0.72, 0.38, 1.0)},
	{"id": "iron_line", "name": "Iron Line", "motto": "Earn your place.", "color": Color(0.95, 0.55, 0.22)},
	{"id": "harbor_kings", "name": "Harbor Kings", "motto": "From the port to the skyline.", "color": Color(0.25, 0.78, 1.0)},
]

const TERRITORIES := [
	{"id": "downtown", "name": "Downtown Core", "description": "The commercial heart of Vorn City.", "base": "night_owls"},
	{"id": "industrial", "name": "Industrial Zone", "description": "Warehouses, workshops and night shifts.", "base": "iron_line"},
	{"id": "harbor", "name": "Harbor District", "description": "The port, freight routes and waterfront.", "base": "harbor_kings"},
	{"id": "residential", "name": "Residential Heights", "description": "Quiet streets and growing families.", "base": "neutral"},
]

var current_gang := ""
var reputation := 0
var influence := {"downtown": 40, "industrial": 40, "harbor": 40, "residential": 0}
var territory_centers := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sync_from_game()

func _sync_from_game() -> void:
	var p: Dictionary = Game.player
	current_gang = str(p.get("gang_id", ""))
	reputation = int(p.get("gang_reputation", 0))
	var saved: Dictionary = p.get("territory_influence", {})
	for territory in TERRITORIES:
		var id := str(territory.id)
		influence[id] = int(saved.get(id, influence.get(id, 0)))
	_sync_to_game(false)

func _sync_to_game(save := true) -> void:
	Game.player["gang_id"] = current_gang
	Game.player["gang_reputation"] = reputation
	Game.player["territory_influence"] = influence.duplicate()
	changed.emit()
	if save:
		Game.save_data()

func configure_world(world) -> void:
	var origin: Vector3 = world.spawn_xf.origin
	var forward: Vector3 = -world.spawn_xf.basis.z.normalized()
	var side: Vector3 = world.spawn_xf.basis.x.normalized()
	territory_centers = {
		"downtown": origin + forward * 20.0,
		"industrial": origin + forward * 20.0 + side * 55.0,
		"harbor": origin + forward * 20.0 - side * 55.0,
		"residential": origin - forward * 55.0,
	}

func gang_by_id(id: String) -> Dictionary:
	for gang in GANGS:
		if str(gang.id) == id:
			return gang
	return {}

func territory_by_id(id: String) -> Dictionary:
	for territory in TERRITORIES:
		if str(territory.id) == id:
			return territory
	return {}

func territory_at(pos: Vector3) -> Dictionary:
	var best := {}
	var distance := 999999.0
	for id in territory_centers:
		var d: float = pos.distance_to(territory_centers[id])
		if d < distance and d < 75.0:
			distance = d
			best = territory_by_id(str(id)).duplicate()
	if not best.is_empty():
		best["influence"] = int(influence.get(best.id, 0))
		best["controller"] = controller_for(str(best.id))
	return best

func controller_for(territory_id: String) -> String:
	var territory := territory_by_id(territory_id)
	var owner := str(territory.get("base", "neutral"))
	var best := int(influence.get(territory_id, 0))
	for gang in GANGS:
		var key := territory_id + ":" + str(gang.id)
		var value := int(Game.player.get("gang_influence", {}).get(key, 0))
		if value > best:
			best = value
			owner = str(gang.id)
	return owner

func join_gang(id: String) -> bool:
	var gang := gang_by_id(id)
	if gang.is_empty():
		return false
	current_gang = id
	reputation = max(reputation, 10)
	_sync_to_game()
	notification.emit("You joined %s" % gang.name)
	return true

func leave_gang() -> void:
	current_gang = ""
	reputation = 0
	_sync_to_game()
	notification.emit("You left your gang")

func contribute(territory_id: String) -> bool:
	if current_gang == "":
		notification.emit("Join a gang before contributing influence")
		return false
	if not territory_by_id(territory_id).is_empty():
		var key := territory_id + ":" + current_gang
		var values: Dictionary = Game.player.get("gang_influence", {})
		values[key] = int(values.get(key, 0)) + 10
		Game.player["gang_influence"] = values
		reputation += 5
		_sync_to_game()
		notification.emit("Influence increased in %s" % territory_by_id(territory_id).name)
		return true
	return false
