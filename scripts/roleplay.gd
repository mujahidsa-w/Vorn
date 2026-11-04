extends Node
## Vorn City RP state: jobs, companies, salaries, shifts, bank and citizen needs.

signal changed
signal notification(text: String)

const COMPANIES := [
	{"id": "cityhall", "name": "Vorn City Hall", "sector": "Government", "color": Color(0.25, 0.75, 1.0)},
	{"id": "metro", "name": "Vorn Metro Authority", "sector": "Government", "color": Color(0.35, 0.85, 0.95)},
	{"id": "hospital", "name": "Vorn General Hospital", "sector": "Government", "color": Color(0.4, 1.0, 0.65)},
	{"id": "swift", "name": "SwiftDrop Logistics", "sector": "Private", "color": Color(1.0, 0.72, 0.25)},
	{"id": "royal", "name": "Royal Motors", "sector": "Private", "color": Color(0.95, 0.4, 0.65)},
	{"id": "harbor", "name": "Harborline Group", "sector": "Private", "color": Color(0.75, 0.55, 1.0)},
]

const JOBS := [
	{"id": "unemployed", "name": "Unemployed", "company": "", "company_name": "Independent", "sector": "None", "salary": 0, "rank": "Citizen", "description": "Look for an opportunity in Vorn City."},
	{"id": "city_clerk", "name": "City Hall Clerk", "company": "cityhall", "company_name": "Vorn City Hall", "sector": "Government", "salary": 380, "rank": "Junior Clerk", "description": "Serve citizens and process city requests."},
	{"id": "metro_operator", "name": "Metro Operator", "company": "metro", "company_name": "Vorn Metro Authority", "sector": "Government", "salary": 430, "rank": "Transit Operator", "description": "Keep public transport moving across the city."},
	{"id": "paramedic", "name": "Paramedic", "company": "hospital", "company_name": "Vorn General Hospital", "sector": "Government", "salary": 520, "rank": "Field Medic", "description": "Respond to emergencies and help residents."},
	{"id": "courier", "name": "Courier", "company": "swift", "company_name": "SwiftDrop Logistics", "sector": "Private", "salary": 280, "rank": "Delivery Rider", "description": "Deliver packages on time throughout Downtown."},
	{"id": "taxi_driver", "name": "Taxi Driver", "company": "swift", "company_name": "SwiftDrop Logistics", "sector": "Private", "salary": 340, "rank": "Driver", "description": "Drive citizens safely to their destinations."},
	{"id": "mechanic", "name": "Auto Mechanic", "company": "royal", "company_name": "Royal Motors", "sector": "Private", "salary": 430, "rank": "Workshop Technician", "description": "Repair and maintain the city's vehicles."},
	{"id": "sales_agent", "name": "Vehicle Sales Agent", "company": "royal", "company_name": "Royal Motors", "sector": "Private", "salary": 470, "rank": "Sales Associate", "description": "Help citizens choose their next vehicle."},
	{"id": "port_worker", "name": "Port Worker", "company": "harbor", "company_name": "Harborline Group", "sector": "Private", "salary": 410, "rank": "Dock Associate", "description": "Coordinate cargo and deliveries at the port."},
]

var job_id := "unemployed"
var bank_balance := 2500
var shift_active := false
var shift_seconds := 0.0
var needs := {"hunger": 82.0, "thirst": 76.0, "energy": 91.0}
var _need_clock := 0.0
var _pay_clock := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sync_from_game()

func _process(delta: float) -> void:
	_need_clock += delta
	_pay_clock += delta
	if shift_active:
		shift_seconds += delta
	if _need_clock >= 45.0:
		_need_clock = 0.0
		needs["hunger"] = maxf(float(needs.hunger) - 1.5, 0.0)
		needs["thirst"] = maxf(float(needs.thirst) - 2.0, 0.0)
		needs["energy"] = maxf(float(needs.energy) - 0.8, 0.0)
		_sync_to_game()
	if _pay_clock >= 300.0:
		_pay_clock = 0.0
		var salary: int = int(current_job().get("salary", 0))
		if Administration.sector_id != "" and Administration.salary > 0:
			salary = Administration.salary
		if salary > 0 and shift_active:
			bank_balance += salary
			notification.emit("Salary received: $%d" % salary)
			_sync_to_game()

func _sync_from_game() -> void:
	var p: Dictionary = Game.player
	job_id = str(p.get("job_id", "unemployed"))
	bank_balance = int(p.get("bank", 2500))
	var saved: Dictionary = p.get("needs", {})
	for key in needs:
		needs[key] = float(saved.get(key, needs[key]))
	_sync_to_game(false)

func _sync_to_game(save := true) -> void:
	Game.player["job_id"] = job_id
	Game.player["job"] = str(current_job().get("name", "Unemployed"))
	Game.player["company"] = str(current_job().get("company_name", "Independent"))
	Game.player["sector"] = str(current_job().get("sector", "None"))
	Game.player["rank"] = str(current_job().get("rank", "Citizen"))
	Game.player["bank"] = bank_balance
	Game.player["needs"] = needs.duplicate()
	changed.emit()
	if save:
		Game.save_data()

func current_job() -> Dictionary:
	for job in JOBS:
		if str(job.id) == job_id:
			return job
	return JOBS[0]

func company_for(id: String) -> Dictionary:
	for company in COMPANIES:
		if str(company.id) == id:
			return company
	return {}

func jobs_for_sector(sector: String) -> Array:
	return JOBS.filter(func(job): return str(job.sector) == sector)

func apply_for_job(id: String) -> bool:
	for job in JOBS:
		if str(job.id) == id:
			job_id = id
			shift_active = false
			shift_seconds = 0.0
			_sync_to_game()
			notification.emit("Hired as %s at %s" % [job.name, job.company_name])
			return true
	return false

func set_job(id: String) -> bool:
	return apply_for_job(id)

func start_shift() -> void:
	if job_id == "unemployed":
		notification.emit("Choose a job before starting a shift")
		return
	shift_active = true
	shift_seconds = 0.0
	notification.emit("Shift started: %s" % current_job().name)

func end_shift() -> void:
	shift_active = false
	notification.emit("Shift ended")

func deposit(amount: int) -> bool:
	if amount <= 0 or int(Game.player.get("coins", 0)) < amount:
		return false
	Game.player["coins"] = int(Game.player.coins) - amount
	bank_balance += amount
	_sync_to_game()
	notification.emit("Deposited $%d" % amount)
	return true

func withdraw(amount: int) -> bool:
	if amount <= 0 or bank_balance < amount:
		return false
	bank_balance -= amount
	Game.player["coins"] = int(Game.player.coins) + amount
	_sync_to_game()
	notification.emit("Withdrew $%d" % amount)
	return true

func rest(amount := 18.0) -> void:
	needs["energy"] = minf(float(needs.energy) + amount, 100.0)
	_sync_to_game()

func eat(amount := 22.0) -> void:
	needs["hunger"] = minf(float(needs.hunger) + amount, 100.0)
	_sync_to_game()

func drink(amount := 24.0) -> void:
	needs["thirst"] = minf(float(needs.thirst) + amount, 100.0)
	_sync_to_game()
