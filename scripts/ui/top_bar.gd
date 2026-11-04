extends Control
## Player profile panel (top-right): avatar, name, level, XP, coins, gems, friends.

const Icons = preload("res://scripts/ui/icons.gd")

var avatar: Texture2D = preload("res://assets/img/avatar.png")
var t := 0.0
var _coins := 0.0
var _gems := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Game.lay(self, [1, 0, 1, 0], [-610, 22, -28, 140])
	_coins = float(Game.player.coins)
	_gems = float(Game.player.gems)


func _process(delta: float) -> void:
	t += delta
	_coins = lerpf(_coins, float(Game.player.coins), 1.0 - exp(-delta * 6.0))
	_gems = lerpf(_gems, float(Game.player.gems), 1.0 - exp(-delta * 6.0))
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.03, 0.05, 0.09, 0.84))
	draw_rect(r, Color(1, 1, 1, 0.1), false, 1.0)
	draw_rect(Rect2(0, 0, size.x, 2), Color(Game.C_CYAN, 0.55))
	var av := Rect2(12, 12, 94, 94)
	draw_texture_rect(avatar, av, false)
	draw_rect(Rect2(12, 86, 94, 20), Color(0, 0, 0, 0.65))
	draw_circle(Vector2(24, 96), 4.5, Color(Game.C_GREEN, 0.7 + 0.3 * sin(t * 4.0)))
	Game.dtext(self, "ONLINE", Vector2(33, 102), 14, Color(1, 1, 1, 0.9), Game.font_bold)
	draw_rect(av, Color(1, 1, 1, 0.18), false, 1.0)

	Game.dtext(self, str(Game.player.name), Vector2(126, 48), 30, Color.WHITE, Game.font_wide)
	Game.dtext(self, "LEVEL %d" % int(Game.player.level), Vector2(126, 78), 17, Game.C_DIM, Game.font_tag)
	draw_rect(Rect2(126, 88, 170, 5), Color(1, 1, 1, 0.12))
	draw_rect(Rect2(126, 88, 170 * float(Game.player.xp), 5), Game.C_CYAN)

	draw_line(Vector2(318, 18), Vector2(318, size.y - 18), Color(1, 1, 1, 0.1), 1.0)
	Icons.draw(self, "coin", Vector2(346, 40), 22, Color.WHITE)
	Game.dtext(self, Game.fmt(int(round(_coins))), Vector2(366, 49), 25, Color.WHITE, Game.font_semi)
	Icons.draw(self, "gem", Vector2(346, 80), 22, Color.WHITE)
	Game.dtext(self, Game.fmt(int(round(_gems))), Vector2(366, 89), 25, Color.WHITE, Game.font_semi)

	draw_line(Vector2(484, 18), Vector2(484, size.y - 18), Color(1, 1, 1, 0.1), 1.0)
	Icons.draw(self, "friends", Vector2(516, 58), 34, Color(1, 1, 1, 0.85))
	Game.dtext(self, "3", Vector2(544, 68), 26, Color.WHITE, Game.font_semi)
