class_name Bot
extends Actor
## Боец под управлением Brain.

func _physics_process(dt: float) -> void:
	if alive and has_meta("brain"):
		(get_meta("brain") as Brain).think(dt)
	tick_weapon(dt)
