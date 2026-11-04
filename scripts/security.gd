extends Node
## Vorn City security layer: weapon licensing, wanted status and gang conflict incidents.

signal changed
signal notification(text: String)

const FACTIONS := ["police", "gangs", "citizen"]
var weapon_license := false
var wanted_level := 0
var wanted_decay := 0.0
var active_incident := ""
var shots_fired := 0
var arrests := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	weapon_license = bool(Game.player.get("weapon_license", false))
	wanted_level = int(Game.player.get("wanted_level", 0))
	shots_fired = int(Game.player.get("shots_fired", 0))

func _process(delta: float) -> void:
	if wanted_level > 0:
		wanted_decay += delta
		if wanted_decay >= 90.0:
			wanted_decay = 0.0
			wanted_level = maxi(wanted_level - 1, 0)
			_sync()

func _sync() -> void:
	Game.player["weapon_license"] = weapon_license
	Game.player["wanted_level"] = wanted_level
	Game.player["shots_fired"] = shots_fired
	changed.emit()
	Game.save_data()

func buy_weapon_license() -> bool:
	if weapon_license:
		notification.emit("Weapon license already active")
		return true
	var cost := 1200
	if int(Game.player.get("bank", 0)) < cost:
		notification.emit("You need $%d in your bank account" % cost)
		return false
	Game.player["bank"] = int(Game.player.get("bank", 0)) - cost
	weapon_license = true
	_sync()
	notification.emit("Weapon license issued")
	return true

func record_player_shot(in_territory := "") -> void:
	shots_fired += 1
	var escalation := 1
	if not weapon_license:
		escalation += 1
	if in_territory != "":
		escalation += 1
	wanted_level = mini(wanted_level + escalation, 5)
	active_incident = "GANG CLASH  •  " + in_territory.to_upper() if Gangs.current_gang != "" and in_territory != "" else "ARMED INCIDENT"
	wanted_decay = 0.0
	_sync()
	notification.emit("Police alert: wanted level %d" % wanted_level)

func record_assault() -> void:
	wanted_level = mini(wanted_level + 1, 5)
	active_incident = "PUBLIC DISTURBANCE"
	wanted_decay = 0.0
	_sync()

func start_clash(territory_id: String) -> void:
	active_incident = "GANG CLASH  •  " + territory_id.to_upper()
	notification.emit(active_incident)
	changed.emit()

func clear_wanted() -> void:
	wanted_level = 0
	active_incident = ""
	wanted_decay = 0.0
	_sync()
	notification.emit("Wanted status cleared")

func wanted_text() -> String:
	return "CLEAR" if wanted_level == 0 else "WANTED  " + "★".repeat(wanted_level)
