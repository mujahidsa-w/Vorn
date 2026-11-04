extends Node
## Vorn City justice layer: detention, bail, charges and court cases.

signal changed
signal notification(text: String)

var detained := false
var detainee_name := ""
var charges: Array = []
var jail_seconds := 0.0
var bail_amount := 0
var case_status := "No active case"
var court_cases: Array = []
var release_reason := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sync_from_game()

func _process(delta: float) -> void:
	if not detained:
		return
	jail_seconds = maxf(jail_seconds - delta, 0.0)
	if jail_seconds <= 0.0:
		release("Sentence completed")
	else:
		_sync(false)

func _sync_from_game() -> void:
	detained = bool(Game.player.get("detained", false))
	detainee_name = str(Game.player.get("detainee_name", Game.player.get("name", "CITIZEN")))
	charges = Game.player.get("charges", []).duplicate(true)
	jail_seconds = float(Game.player.get("jail_seconds", 0.0))
	bail_amount = int(Game.player.get("bail_amount", 0))
	case_status = str(Game.player.get("case_status", "No active case"))
	court_cases = Game.player.get("court_cases", []).duplicate(true)
	release_reason = str(Game.player.get("release_reason", ""))

func detain_current_player(new_charges: Array, sentence_seconds: float, bail: int, officer := "Police Officer") -> bool:
	if detained:
		notification.emit("Citizen is already detained")
		return false
	detained = true
	detainee_name = str(Game.player.get("name", "CITIZEN"))
	charges = new_charges.duplicate(true)
	jail_seconds = maxf(sentence_seconds, 60.0)
	bail_amount = maxi(bail, 0)
	case_status = "Awaiting hearing"
	release_reason = ""
	court_cases.append({"defendant": detainee_name, "charges": charges.duplicate(true), "officer": officer, "status": case_status, "bail": bail_amount, "time": Time.get_datetime_string_from_system()})
	_record("DETENTION", "Arrested by " + officer)
	_sync()
	notification.emit("You were detained: " + ", ".join(charges))
	return true

func pay_bail() -> bool:
	if not detained:
		notification.emit("No active detention")
		return true
	if bail_amount <= 0:
		return false
	if int(Game.player.get("bank", 0)) < bail_amount:
		notification.emit("Insufficient bank balance for bail")
		return false
	Game.player["bank"] = int(Game.player.get("bank", 0)) - bail_amount
	release("Bail paid")
	return true

func request_hearing() -> bool:
	if not detained:
		return false
	case_status = "Hearing requested"
	_record("HEARING", "Defendant requested a court hearing")
	_sync()
	notification.emit("Court hearing requested")
	return true

func resolve_case(verdict: String, sentence_seconds := 0.0) -> bool:
	if not detained:
		return false
	case_status = verdict
	if verdict == "GUILTY" and sentence_seconds > 0.0:
		jail_seconds = sentence_seconds
		_sync()
		return true
	if verdict == "NOT GUILTY":
		release("Court verdict: Not Guilty")
		return true
	return false

func release(reason: String) -> void:
	detained = false
	jail_seconds = 0.0
	bail_amount = 0
	case_status = "Closed"
	release_reason = reason
	_record("RELEASE", reason)
	_sync()
	notification.emit("Released: " + reason)

func time_left_text() -> String:
	var total := maxi(int(jail_seconds), 0)
	return "%02d:%02d" % [total / 60, total % 60]

func _record(action: String, detail: String) -> void:
	court_cases.append({"action": action, "detail": detail, "time": Time.get_datetime_string_from_system()})
	if court_cases.size() > 100:
		court_cases.pop_front()

func _sync(save := true) -> void:
	Game.player["detained"] = detained
	Game.player["detainee_name"] = detainee_name
	Game.player["charges"] = charges.duplicate(true)
	Game.player["jail_seconds"] = jail_seconds
	Game.player["bail_amount"] = bail_amount
	Game.player["case_status"] = case_status
	Game.player["court_cases"] = court_cases.duplicate(true)
	Game.player["release_reason"] = release_reason
	changed.emit()
	if save:
		Game.save_data()
