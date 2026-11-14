class_name AirSound
extends AudioStreamPlayer
## Generated sound for the jump: the propeller drone inside the plane, the roar of wind in free fall,
## a soft flutter under the parachute, and the howl of the sandstorm.

var mode := ""               # plane, fall, chute, storm, ""
var vol := 0.0
var _pb: AudioStreamGeneratorPlayback
var _rate := 22050.0
var _ph := 0.0
var _am := 0.0
var _lp := 0.0
var _lp2 := 0.0
var _gust := 0.0

func _ready() -> void:
	var g := AudioStreamGenerator.new()
	g.mix_rate = _rate
	g.buffer_length = 0.2
	stream = g
	bus = "SFX"
	volume_db = -4.0
	play()
	_pb = get_stream_playback()

func _process(dt: float) -> void:
	if _pb == null:
		return
	var target: float = {"plane": 0.55, "fall": 0.9, "chute": 0.32, "storm": 0.7}.get(mode, 0.0)
	vol = move_toward(vol, target, dt * 1.2)
	var n := _pb.get_frames_available()
	if vol <= 0.001:
		for i in n:
			_pb.push_frame(Vector2.ZERO)
		return
	var cut := 0.10 if mode == "fall" else (0.035 if mode == "storm" else 0.02)
	var wind := {"plane": 0.35, "fall": 1.6, "chute": 0.9, "storm": 1.4}.get(mode, 0.0) as float
	var engine := 1.0 if mode == "plane" else 0.0
	for i in n:
		_gust += (randf() - 0.5) * 0.0004
		_gust = clampf(_gust * 0.9995, -0.5, 0.5)
		var w := randf() * 2.0 - 1.0
		_lp += (w - _lp) * cut
		_lp2 += (_lp - _lp2) * 0.25
		var s := _lp2 * wind * (1.0 + _gust)
		if engine > 0.0:
			_ph += TAU * 58.0 / _rate
			_am += TAU * 7.5 / _rate
			s += (sin(_ph) * 0.35 + sin(_ph * 2.0) * 0.22 + sin(_ph * 3.0) * 0.12) * (0.75 + 0.25 * sin(_am)) * engine
		_pb.push_frame(Vector2(s, s) * vol)
	if _ph > 1000.0:
		_ph -= TAU * 100.0
	if _am > 1000.0:
		_am -= TAU * 100.0
