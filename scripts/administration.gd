extends Node
## Online RP administration foundation: sectors, ranks, salaries and audit records.
## The authoritative backend can replace these local persistence calls later.

signal changed
signal notification(text: String)

const SECTORS := [
	{"id": "police", "name": "Vorn City Police", "salary": 430, "color": Color(0.3, 0.55, 1.0)},
	{"id": "ems", "name": "Vorn Medical Services", "salary": 450, "color": Color(0.3, 1.0, 0.65)},
	{"id": "traffic", "name": "Traffic Authority", "salary": 390, "color": Color(1.0, 0.72, 0.25)},
	{"id": "government", "name": "City Government", "salary": 400, "color": Color(0.25, 0.85, 1.0)},
	{"id": "business", "name": "Private Business", "salary": 360, "color": Color(0.9, 0.45, 0.75)},
	{"id": "gang", "name": "Gang Operations", "salary": 300, "color": Color(1.0, 0.3, 0.45)},
]

const RANKS := {
	"police": ["Cadet", "Officer", "Sergeant", "Lieutenant", "Captain", "Chief"],
	"ems": ["Trainee", "Paramedic", "Senior Medic", "Supervisor", "Director"],
	"traffic": ["Trainee", "Officer", "Senior Officer", "Supervisor", "Director"],
	"government": ["Clerk", "Specialist", "Supervisor", "Manager", "Director"],
	"business": ["Trainee", "Employee", "Senior Employee", "Supervisor", "Manager"],
	"gang": ["Recruit", "Member", "Enforcer", "Lieutenant", "Underboss", "Leader"],
}

var sector_id := ""
var rank := "Citizen"
var salary := 0
var is_admin := false
var pending_requests: Array = []
var audit_log: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sync_from_game()

func _sync_from_game() -> void:
	sector_id = str(Game.player.get("sector_id", ""))
	rank = str(Game.player.get("sector_rank", "Citizen"))
	salary = int(Game.player.get("sector_salary", 0))
	is_admin = bool(Game.player.get("is_sector_admin", false))
	pending_requests = Game.player.get("sector_requests", []).duplicate(true)
	audit_log = Game.player.get("admin_audit", []).duplicate(true)

func sector_by_id(id: String) -> Dictionary:
	for sector in SECTORS:
		if str(sector.id) == id:
			return sector
	return {}

func ranks_for(id: String) -> Array:
	return RANKS.get(id, [])

func request_membership(id: String) -> bool:
	if sector_by_id(id).is_empty():
		return false
	for request in pending_requests:
		if str(request.sector) == id and str(request.status) == "pending":
			notification.emit("Request already pending")
			return false
	pending_requests.append({"player": str(Game.player.get("name", "CITIZEN")), "sector": id, "status": "pending", "time": Time.get_datetime_string_from_system()})
	_record("APPLICATION", "Applied to " + str(sector_by_id(id).name))
	notification.emit("Application sent to " + str(sector_by_id(id).name))
	return true

func approve_self_request(id: String) -> bool:
	if not is_admin:
		notification.emit("Only sector administrators can approve members")
		return false
	var names: Array = ranks_for(id)
	if names.is_empty():
		return false
	sector_id = id
	rank = str(names[0])
	salary = int(sector_by_id(id).salary)
	_record("APPROVE", "Joined " + str(sector_by_id(id).name) + " as " + rank)
	_sync(true)
	notification.emit("Sector membership approved")
	return true

func set_rank(player_name: String, new_rank: String) -> bool:
	if not is_admin or not ranks_for(sector_id).has(new_rank):
		notification.emit("Insufficient administration permissions")
		return false
	_record("PROMOTE", "%s → %s" % [player_name, new_rank])
	if player_name == str(Game.player.get("name", "CITIZEN")):
		rank = new_rank
		salary = int(sector_by_id(sector_id).salary) + ranks_for(sector_id).find(new_rank) * 55
	_sync(true)
	return true

func leave_sector() -> void:
	_record("LEAVE", "Left current sector")
	sector_id = ""
	rank = "Citizen"
	salary = 0
	_sync(true)
	notification.emit("You left the sector")

func _record(action: String, detail: String) -> void:
	audit_log.append({"action": action, "detail": detail, "actor": str(Game.player.get("name", "CITIZEN")), "time": Time.get_datetime_string_from_system()})
	if audit_log.size() > 100:
		audit_log.pop_front()

func _sync(save := true) -> void:
	Game.player["sector_id"] = sector_id
	Game.player["sector_rank"] = rank
	Game.player["sector_salary"] = salary
	Game.player["is_sector_admin"] = is_admin
	Game.player["sector_requests"] = pending_requests.duplicate(true)
	Game.player["admin_audit"] = audit_log.duplicate(true)
	changed.emit()
	if save:
		Game.save_data()
