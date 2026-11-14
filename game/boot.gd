extends Node
## Entry point. A normal start runs: studio logo -> credits -> loading screen (real loading) -> lobby.
## Test switches jump straight to the needed scene.

const WARM := ["res://assets/maps/kasbah.glb", "res://assets/models/chars/anims.scn", "res://assets/models/chars/ct_1.scn",
	"res://assets/models/chars/ct_2.scn", "res://assets/models/chars/t_1.scn", "res://assets/models/chars/t_2.scn",
	"res://assets/brand/game_logo.png", "res://assets/brand/emblem.png"]

func _ready() -> void:
	await get_tree().process_frame
	if G.mobile:
		# give the screen a few frames so the safe area (notch) is known before anything is laid out
		for i in 4:
			await get_tree().process_frame
		G.fit_screen()
	if G.args.has("match"):
		G.start_match()
	elif G.args.has("test"):
		get_tree().change_scene_to_file("res://tools/test_%s.tscn" % G.args["test"])
	else:
		var quick := G.args.has("nosplash") or G.args.has("loop") or G.args.has("panel") or (G.shots_dir != "" and not G.args.has("intro"))
		if not quick:
			await _start_up()
		G.to_menu()

func _start_up() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var intro := Intro.new()
	layer.add_child(intro)
	if G.shots_dir != "":
		_shot_later("intro_1_studio", 0.9)
	await intro.studio()
	if G.shots_dir != "":
		_shot_later("intro_2_credits", 1.6)
	await intro.credits()
	intro.queue_free()
	var ls := LoadingScreen.new()
	layer.add_child(ls)
	if G.shots_dir != "":
		_shot_later("intro_3_loading", 2.2)
	await ls.run(WARM)

func _shot_later(n: String, delay: float) -> void:
	## development screenshots of the start-up screens (only with --shots and --intro)
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	await G.shot(n)
