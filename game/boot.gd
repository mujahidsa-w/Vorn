extends Node
## Точка входа: обычный запуск -> меню; с ключами проверки -> сразу нужная сцена.

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
		G.to_menu()
