extends Node
## Positional audio helper for footsteps, gunshots and environment cues.

var world
var _streams := {}
var _active: Array[AudioStreamPlayer3D] = []

func _ready() -> void:
	for name in ["shot_pistol", "shot_rifle", "shot_ak", "shot_sniper", "step_concrete_1", "step_concrete_2", "step_concrete_3", "step_tile_1", "step_tile_2", "step_tile_3", "step_grass_1", "step_grass_2", "step_grass_3", "step_wet_1", "step_wet_2", "step_wet_3", "glass", "explosion", "thunder"]:
		var path := "res://assets/audio/%s.wav" % name
		if ResourceLoader.exists(path):
			_streams[name] = load(path)

func play_at(position: Vector3, sound: String, pitch := 1.0, volume_db := 0.0, max_distance := 55.0) -> void:
	if not _streams.has(sound):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _streams[sound]
	p.bus = "SFX"
	p.global_position = position
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.max_distance = max_distance
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.unit_size = 5.0
	add_child(p)
	_active.append(p)
	p.finished.connect(func():
		_active.erase(p)
		p.queue_free()
	)
	p.play()

func play_footstep(position: Vector3, kind: String, running := false) -> void:
	var sound := "step_%s_%d" % [kind, randi_range(1, 3)]
	play_at(position, sound, randf_range(0.92, 1.08), -8.0 if running else -12.0, 22.0)

func play_gunshot(position: Vector3, weapon: String) -> void:
	var sound := weapon if _streams.has(weapon) else "shot_pistol"
	play_at(position, sound, randf_range(0.96, 1.04), -1.0, 180.0)
	# A distant reflection sells the scale of the city without stacking another full shot.
	if world and world.sky and world.sky.night > 0.2:
		play_at(position, sound, randf_range(0.82, 0.9), -17.0, 260.0)
