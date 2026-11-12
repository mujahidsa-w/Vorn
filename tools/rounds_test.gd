extends SceneTree
## Headless check of the round rules. Run: godot --headless --script res://tools/rounds_test.gd

const Rules = preload("res://scripts/game3d/comp_rounds.gd")


func _init() -> void:
	var fails := 0
	var r = Rules.new()
	var alive := {"a": 5, "b": 5}
	r.alive_of = func(t: String) -> int: return alive[t]
	r.start()

	# buy -> live after BUY_TIME
	r.tick(Rules.BUY_TIME + 0.01)
	if r.phase != "live":
		print("FAIL buy->live, phase=", r.phase); fails += 1

	# team b wiped -> a wins the round, goes to end phase
	alive["b"] = 0
	r.tick(0.1)
	if r.phase != "end" or int(r.score["a"]) != 1 or int(r.score["b"]) != 0:
		print("FAIL wipe, phase=", r.phase, " score=", r.score); fails += 1

	# end -> next buy, round counter advances
	r.tick(Rules.END_TIME + 0.01)
	if r.phase != "buy" or r.round_no != 2:
		print("FAIL end->buy, phase=", r.phase, " round=", r.round_no); fails += 1

	# time runs out with more alive on b -> b wins
	alive["a"] = 2
	alive["b"] = 3
	r.tick(Rules.BUY_TIME + 0.01)
	r.tick(Rules.LIVE_TIME + 0.01)
	if int(r.score["b"]) != 1:
		print("FAIL timeout winner, score=", r.score); fails += 1

	# equal alive at timeout -> draw, no point
	r.tick(Rules.END_TIME + 0.01)
	alive["a"] = 1
	alive["b"] = 1
	r.tick(Rules.BUY_TIME + 0.01)
	r.tick(Rules.LIVE_TIME + 0.01)
	if int(r.score["a"]) != 1 or int(r.score["b"]) != 1:
		print("FAIL draw, score=", r.score); fails += 1

	# first to WIN_ROUNDS ends the match
	r.score = {"a": Rules.WIN_ROUNDS - 1, "b": 0}
	r.phase = "live"
	r.phase_left = 10.0
	alive["a"] = 3
	alive["b"] = 0
	r.tick(0.1)
	if not r.is_over() or r.score["a"] != Rules.WIN_ROUNDS:
		print("FAIL match over, phase=", r.phase, " score=", r.score); fails += 1

	print("ROUNDS TEST ", "OK" if fails == 0 else "FAILED (%d)" % fails)
	quit(1 if fails > 0 else 0)
