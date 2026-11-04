extends Node
## Dev-only: run with `-- --tour <outdir>` to capture screenshots of every screen.

var main
var out := "user://"

func _shot(n: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + n + ".png")
	print("shot ", n)

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func run() -> void:
	await _wait(2.0)
	await _shot("01_menu")
	main.go("team"); await _wait(1.0)
	await _shot("02_team")
	main.go("match"); await _wait(1.0)
	await _shot("03_match_start")
	await _wait(9.0)
	main.current._toggle_ready(); await _wait(2.5)
	await _shot("04_match_countdown")
	main.go("customize"); await _wait(1.0)
	await _shot("05_customize")
	main.go("shop"); await _wait(1.0)
	await _shot("06_shop")
	main.go("friends"); await _wait(1.0)
	await _shot("07_friends")
	main.go("settings"); await _wait(1.0)
	await _shot("08_settings")
	main.current._set_tab(1); await _wait(0.5)
	await _shot("09_settings_audio")
	main.current._set_tab(2); await _wait(0.5)
	await _shot("10_settings_keys")
	main.go("loading", {"team": "cops"}); await _wait(1.5)
	await _shot("11_loading")
	await _wait(5.0)
	await _shot("12_loading_done")
	main.go("menu"); await _wait(1.0)
	main.current.on_back(); await _wait(0.5)
	await _shot("13_exit_confirm")
	get_tree().quit()
