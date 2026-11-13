extends Node
## Точка входа: обычный запуск -> заставка разработчика -> меню; с ключами проверки -> сразу нужная сцена.

const SPLASH_TIME := 5.0
const WARM := ["res://assets/maps/kasbah.glb", "res://assets/models/chars/anims.scn", "res://assets/models/chars/ct_1.scn",
	"res://assets/models/chars/ct_2.scn", "res://assets/models/chars/t_1.scn", "res://assets/models/chars/t_2.scn"]

func _ready() -> void:
	await get_tree().process_frame
	if G.mobile:
		# give the screen a few frames so the safe area (notch) is known before the menu is laid out
		for i in 4:
			await get_tree().process_frame
		G.fit_screen()
	if G.args.has("match"):
		G.start_match()
	elif G.args.has("test"):
		get_tree().change_scene_to_file("res://tools/test_%s.tscn" % G.args["test"])
	else:
		if not (G.args.has("nosplash") or G.shots_dir != "" or G.args.has("loop") or G.args.has("panel")):
			await _splash()
		G.to_menu()

func _splash() -> void:
	## Developer picture for five seconds; the menu's heavy resources load in the background meanwhile.
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.043, 0.051, 0.066)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var pic := TextureRect.new()
	pic.texture = load("res://assets/ui/developer.png")
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.modulate.a = 0.0
	layer.add_child(pic)
	var asked: Array[String] = []
	for p in WARM:
		if ResourceLoader.exists(p) and ResourceLoader.load_threaded_request(p) == OK:
			asked.append(p)
	var tw := create_tween()
	tw.tween_property(pic, "modulate:a", 1.0, 0.4)
	tw.tween_interval(SPLASH_TIME - 0.9)
	tw.tween_property(pic, "modulate:a", 0.0, 0.5)
	await tw.finished
	for p in asked:
		G.warm.append(ResourceLoader.load_threaded_get(p))
