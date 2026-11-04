extends Node
## Vorn City traffic authority: licenses, driving tests, fines and penalty points.

signal changed
signal notification(text: String)

var license_valid := false
var license_level := "None"
var penalty_points := 0
var fines: Array = []
var _speed_clock := 0.0
var _speed_cooldown := 0.0
var _no_license_reported := false

const SPEED_LIMITS := {"Downtown Core": 50.0, "Industrial Zone": 60.0, "Harbor District": 45.0, "Residential Heights": 35.0, "NEUTRAL DISTRICT": 50.0}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	license_valid = bool(Game.player.get("license_valid", false))
	license_level = str(Game.player.get("license_level", "None"))
	penalty_points = int(Game.player.get("penalty_points", 0))
	fines = Game.player.get("traffic_fines", []).duplicate()

func _process(delta: float) -> void:
	if _speed_cooldown > 0.0:
		_speed_cooldown -= delta

func update_vehicle(world, delta: float) -> void:
	if world == null or world.active_car == null:
		_speed_clock = 0.0
		_no_license_reported = false
		return
	if not license_valid and not _no_license_reported:
		_no_license_reported = true
		issue_fine("Driving without a valid license", 500, 3)
	var territory: Dictionary = Gangs.territory_at(world.player.global_position)
	var zone := str(territory.get("name", "NEUTRAL DISTRICT"))
	var limit := float(SPEED_LIMITS.get(zone, 50.0))
	var speed := float(world.active_car.kmh())
	if speed > limit + 12.0:
		_speed_clock += delta
		if _speed_clock >= 3.0 and _speed_cooldown <= 0.0:
			issue_fine("Speeding in %s (%d km/h / limit %d)" % [zone, int(speed), int(limit)], 250, 2)
			_speed_cooldown = 25.0
			_speed_clock = 0.0
	else:
		_speed_clock = maxf(_speed_clock - delta * 2.0, 0.0)

func take_driving_test() -> bool:
	if license_valid:
		notification.emit("Driving license already valid")
		return true
	var cost := 300
	if int(Game.player.get("bank", 0)) < cost:
		notification.emit("You need $%d for the driving test" % cost)
		return false
	Game.player["bank"] = int(Game.player.get("bank", 0)) - cost
	license_valid = true
	license_level = "Class B"
	penalty_points = 0
	_save()
	notification.emit("Driving test passed — Class B license issued")
	return true

func issue_fine(reason: String, amount: int, points: int) -> void:
	fines.append({"reason": reason, "amount": amount, "points": points, "time": Time.get_datetime_string_from_system(), "paid": false})
	penalty_points += points
	_sync()
	notification.emit("Traffic fine: $%d  •  %s" % [amount, reason])

func pay_fines() -> bool:
	var total := 0
	for fine in fines:
		if not bool(fine.get("paid", false)):
			total += int(fine.get("amount", 0))
	if total == 0:
		notification.emit("No unpaid traffic fines")
		return true
	if int(Game.player.get("bank", 0)) < total:
		notification.emit("Insufficient bank balance to pay fines")
		return false
	Game.player["bank"] = int(Game.player.get("bank", 0)) - total
	for fine in fines:
		fine["paid"] = true
	_save()
	notification.emit("Paid traffic fines: $%d" % total)
	return true

func unpaid_total() -> int:
	var total := 0
	for fine in fines:
		if not bool(fine.get("paid", false)):
			total += int(fine.get("amount", 0))
	return total

func _sync() -> void:
	Game.player["license_valid"] = license_valid
	Game.player["license_level"] = license_level
	Game.player["penalty_points"] = penalty_points
	Game.player["traffic_fines"] = fines.duplicate(true)
	changed.emit()
	Game.save_data()

func _save() -> void:
	_sync()
