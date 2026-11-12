extends RefCounted
## Competitive round rules (CS2 style): buy phase, live round, round end, first team to WIN_ROUNDS wins.
## Pure logic: no nodes, so it can be tested headless. The caller feeds it the alive count per team
## and calls tick() every frame.

signal phase_changed(phase: String)
signal round_ended(winner: String)      # "a", "b" or "" for a draw (time ran out with equal alive)
signal match_over(winner: String)

const BUY_TIME := 15.0
const LIVE_TIME := 115.0
const END_TIME := 5.0
const WIN_ROUNDS := 8
const TEAMS := ["a", "b"]

var phase := "buy"
var phase_left := BUY_TIME
var round_no := 1
var score := {"a": 0, "b": 0}
var alive_of: Callable = func(_team: String) -> int: return 0


func start() -> void:
	phase = "buy"
	phase_left = BUY_TIME
	round_no = 1
	score = {"a": 0, "b": 0}
	phase_changed.emit(phase)


func is_over() -> bool:
	return phase == "over"


func tick(delta: float) -> void:
	if phase == "over":
		return
	phase_left -= delta
	if phase == "live":
		var a := int(alive_of.call("a"))
		var b := int(alive_of.call("b"))
		if a == 0 and b == 0:
			_end_round("")
		elif a == 0:
			_end_round("b")
		elif b == 0:
			_end_round("a")
		elif phase_left <= 0.0:
			_end_round("a" if a > b else ("b" if b > a else ""))
		return
	if phase_left > 0.0:
		return
	if phase == "buy":
		_set_phase("live", LIVE_TIME)
	elif phase == "end":
		round_no += 1
		_set_phase("buy", BUY_TIME)


func _end_round(winner: String) -> void:
	if winner != "":
		score[winner] = int(score[winner]) + 1
	round_ended.emit(winner)
	if int(score["a"]) >= WIN_ROUNDS or int(score["b"]) >= WIN_ROUNDS:
		phase = "over"
		phase_left = 0.0
		match_over.emit("a" if int(score["a"]) >= WIN_ROUNDS else "b")
		phase_changed.emit(phase)
		return
	_set_phase("end", END_TIME)


func _set_phase(p: String, t: float) -> void:
	phase = p
	phase_left = t
	phase_changed.emit(p)
