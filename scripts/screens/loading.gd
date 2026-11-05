extends Control
## Match loading screen. Gameplay itself arrives in the next build.

const UI = preload("res://scripts/ui/ui.gd")

var main
var data := {}
var bg_dim := 0.9
var show_top := false
var prog := 0.0
var t := 0.0
var done := false
var _tip := 0
var _tip_t := 0.0
const MAP_PATH := "res://assets/models/map/la.glb"
var _real := 0.0
var video_over := true
const TIPS := [
"Find work, earn money and shape your own story.",
"Use E near a car to enter it and explore the city.",
"Press M to open the city map and set a GPS destination.",
"The city changes with the time of day and the weather.",
"Your home, job and finances are the foundation of your life.",
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip = randi() % TIPS.size()
	ResourceLoader.load_threaded_request(MAP_PATH)
	var p := UI.paint(self, _paint, Rect2(0, 0, 0, 0), true)
	Game.lay(p, [0, 0, 1, 1], [0, 0, 0, 0])
	Game.stop_music()
	var bar := UI.paint(self, _paint_bar, Rect2(0, 0, 0, 0), true)
	Game.lay(bar, [0, 1, 1, 1], [0, -40, 0, 0])


func _process(delta: float) -> void:
	t += delta
	_tip_t += delta
	if _tip_t > 4.0:
		_tip_t = 0.0
		_tip = (_tip + 1) % TIPS.size()
	if not done:
		var arr := []
		var st := ResourceLoader.load_threaded_get_status(MAP_PATH, arr)
		if arr.size() > 0:
			_real = float(arr[0])
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_real = 1.0
		elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_real = 1.0
		prog = minf(prog + delta * 0.6, maxf(_real, minf(prog + delta * 0.08, 0.9)))
		if prog >= 0.999 and _real >= 1.0:
			if video_over:
				if st == ResourceLoader.THREAD_LOAD_LOADED:
					ResourceLoader.load_threaded_get(MAP_PATH)
				_finish()


func _finish() -> void:
	done = true
	Game.play_sfx("go")
	get_tree().change_scene_to_file("res://scenes/city.tscn")


func _finish_old() -> void:
	done = true
	Game.play_sfx("go")
	var b := UI.button(self, "RETURN TO LOBBY", "back", 32, Rect2(0, 0, 0, 0), func(): main.go("menu"))
	b.set("centered", true)
	Game.lay(b, [0.5, 0, 0.5, 0], [-220, 860, 220, 940])
	b.modulate.a = 0.0
	create_tween().tween_property(b, "modulate:a", 1.0, 0.4)
	Game.quiet_focus(b)


func _paint_bar(c: Control) -> void:
	if done:
		return
	var w := c.size.x
	c.draw_rect(Rect2(0, c.size.y - 4, w, 4), Color(1, 1, 1, 0.12))
	c.draw_rect(Rect2(0, c.size.y - 4, w * prog, 4), Game.C_CYAN)
	var txt := "LOADING CITY  %d%%" % int(prog * 100.0) if prog < 0.999 else "READY"
	Game.dtext(c, txt, Vector2(40, c.size.y - 14), 18, Color(1, 1, 1, 0.7), Game.font_tag)


func _paint(c: Control) -> void:
	var cx := c.size.x * 0.5
	Game.dtext(c, "VORN CITY", Vector2(cx, 420), 120, Color.WHITE, Game.font_wide, HORIZONTAL_ALIGNMENT_CENTER)
	Game.dtext(c, "REAL LIFE ROLEPLAY  •  CITY CENTER  •  ONLINE WORLD", Vector2(cx, 474), 22, Game.C_DIM, Game.font_tag, HORIZONTAL_ALIGNMENT_CENTER)
	var tt := "CITIZEN  •  " + str(Game.player.get("job", "UNEMPLOYED")).to_upper()
	var tw := Game.font_tag.get_string_size(tt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	c.draw_rect(Rect2(cx - tw * 0.5 - 24, 520, tw + 48, 46), Color(Game.C_CYAN, 0.2))
	c.draw_rect(Rect2(cx - tw * 0.5 - 24, 520, tw + 48, 46), Color(Game.C_CYAN, 0.8), false, 1.5)
	Game.dtext(c, tt, Vector2(cx, 552), 24, Color.WHITE, Game.font_tag, HORIZONTAL_ALIGNMENT_CENTER)
	if not done:
		var bw := 900.0
		var bx := cx - bw * 0.5
		c.draw_rect(Rect2(bx, 880, bw, 6), Color(1, 1, 1, 0.1))
		c.draw_rect(Rect2(bx, 880, bw * prog, 6), Game.C_CYAN)
		Game.dtext(c, "LOADING CITY" + ".".repeat(int(t * 2.0) % 4), Vector2(bx, 866), 18, Game.C_DIM, Game.font_tag)
		Game.dtext(c, "%d%%" % int(prog * 100.0), Vector2(bx + bw, 866), 20, Color.WHITE, Game.font_bold, HORIZONTAL_ALIGNMENT_RIGHT)
		Game.dtext(c, "TIP:  " + TIPS[_tip], Vector2(cx, 930), 20, Color(1, 1, 1, 0.55), Game.font_med, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		Game.dtext(c, "LOBBY BUILD COMPLETE", Vector2(cx, 700), 40, Game.C_CYAN, Game.font_wide, HORIZONTAL_ALIGNMENT_CENTER)
		Game.dtext(c, "Your life in Vorn City starts in the Downtown district.", Vector2(cx, 748), 24, Game.C_TEXT, Game.font_med, HORIZONTAL_ALIGNMENT_CENTER)


func on_back() -> void:
	if done:
		main.go("menu")
