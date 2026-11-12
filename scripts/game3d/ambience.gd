extends Node
## City soundscape driven by time of day and weather: distant traffic, wind, rain,
## birds by day, crickets at night.

var world
var players := {}
var bus_idx := -1
var _lp: AudioEffectLowPassFilter
var _inside := 0.0


func _ready() -> void:
	# the lobby's rain loop is replaced by weather-driven rain here
	if Game.get("_rain") and Game._rain.playing:
		Game._rain.stop()
	bus_idx = AudioServer.get_bus_index("Ambience")
	if bus_idx < 0:
		AudioServer.add_bus()
		bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_idx, "Ambience")
		AudioServer.set_bus_send(bus_idx, "SFX")
		_lp = AudioEffectLowPassFilter.new()
		_lp.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(bus_idx, _lp)
	else:
		_lp = AudioServer.get_bus_effect(bus_idx, 0)
	for n in ["amb_city", "amb_wind", "rain", "amb_birds", "amb_night"]:
		var p := AudioStreamPlayer.new()
		p.stream = Game._looped("res://assets/audio/%s.wav" % n)
		p.bus = "Ambience"
		p.volume_db = -60.0
		add_child(p)
		p.play(randf() * 4.0)
		players[n] = p


func _vol(n: String, target_db: float, delta: float) -> void:
	var p: AudioStreamPlayer = players[n]
	p.volume_db = lerpf(p.volume_db, target_db, 1.0 - exp(-delta * 1.5))


func _process(delta: float) -> void:
	var sky = world.sky if world else null
	if sky == null:
		return
	var cam: Camera3D = world.current_camera()
	var inside: bool = false
	_inside = move_toward(_inside, 1.0 if inside else 0.0, delta * 2.0)
	_lp.cutoff_hz = lerpf(20000.0, 700.0, _inside)
	var day: float = 1.0 - sky.night
	var quiet := -8.0 * _inside
	_vol("amb_city", lerpf(-19.0, -15.0, day) + quiet, delta)
	_vol("amb_wind", lerpf(-40.0, -14.0, clampf((sky.wind - 0.25) / 0.6, 0.0, 1.0)) + quiet, delta)
	_vol("rain", (lerpf(-50.0, -7.0, clampf(sky.rain, 0.0, 1.0)) if sky.rain > 0.02 else -60.0) + quiet, delta)
	var calm: float = clampf(1.0 - sky.rain * 2.0 - sky.wind * 0.3, 0.0, 1.0)
	_vol("amb_birds", (lerpf(-60.0, -17.0, day * calm) if day * calm > 0.05 else -60.0) + quiet, delta)
	_vol("amb_night", (lerpf(-60.0, -21.0, sky.night * calm) if sky.night * calm > 0.05 else -60.0) + quiet, delta)
