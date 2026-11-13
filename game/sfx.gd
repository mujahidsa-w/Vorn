extends Node
## Sfx — звук: шины, набор звуков из assets/sounds (варианты step1..4 собираются в группу "step"),
## 2D и 3D проигрыватели из пула, музыка с плавной сменой, фон окружения.

const DIRS := ["res://assets/sounds", "res://assets/music"]
var lib := {}                      # имя -> Array[AudioStream]
var _p2: Array[AudioStreamPlayer] = []
var _p3: Array[AudioStreamPlayer3D] = []
var _i2 := 0
var _i3 := 0
var _music: Array[AudioStreamPlayer] = []
var _mi := 0
var _amb: AudioStreamPlayer
var music_name := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b in ["Music", "SFX", "UI"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	var lim := AudioEffectLimiter.new()
	AudioServer.add_bus_effect(0, lim)
	for d in DIRS:
		_scan(d)
	for i in 16:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_p2.append(p)
	for i in 28:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 6.0
		p.max_distance = 90.0
		p.attenuation_filter_cutoff_hz = 9000.0
		add_child(p)
		_p3.append(p)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -60.0
		add_child(p)
		_music.append(p)
	_amb = AudioStreamPlayer.new()
	_amb.bus = "SFX"
	add_child(_amb)
	apply_volumes()

func _scan(dir: String) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	var seen := {}
	for f in da.get_files():
		var n := String(f)
		if n.ends_with(".import"):
			n = n.trim_suffix(".import")
		var ext := n.get_extension().to_lower()
		if not (ext in ["wav", "ogg", "mp3", "sample", "oggvorbisstr", "mp3str"]) or seen.has(n):
			continue
		seen[n] = true
		var s = load(dir + "/" + n)
		if s == null:
			continue
		var key := n.get_basename()
		lib[key] = [s]
		var grp := key.rstrip("0123456789").rstrip("_")
		if grp != key:
			if not lib.has("#" + grp):
				lib["#" + grp] = []
			lib["#" + grp].append(s)
	for k in lib.keys():
		if String(k).begins_with("#"):
			var g := String(k).substr(1)
			if not lib.has(g):
				lib[g] = lib[k]

func has(n: String) -> bool:
	return lib.has(n)

func _pick(n: String) -> AudioStream:
	if not lib.has(n):
		return null
	var a: Array = lib[n]
	return a[randi() % a.size()]

func apply_volumes() -> void:
	if AudioServer.get_bus_index("Music") < 0:
		return
	var s: Dictionary = G.settings
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, float(s["vol_master"]))))
	if G.args.has("silent"):
		AudioServer.set_bus_volume_db(0, -80.0)       # проверки без звука: шина считается, но в колонки не слышна
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(0.0001, float(s["vol_music"]))))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(0.0001, float(s["vol_sfx"]))))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("UI"), linear_to_db(maxf(0.0001, float(s["vol_sfx"]))))

func play(n: String, vol_db := 0.0, pitch := 1.0, bus := "SFX") -> void:
	var s := _pick(n)
	if s == null:
		return
	if G.args.has("sndlog"):
		print("SND %d %s" % [Time.get_ticks_msec(), n])
	var p := _p2[_i2]
	_i2 = (_i2 + 1) % _p2.size()
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.bus = bus
	p.play()

func ui(n: String, vol_db := -6.0, pitch := 1.0) -> void:
	play(n, vol_db, pitch, "UI")

func at(n: String, pos: Vector3, vol_db := 0.0, pitch := 1.0, unit := 6.0, max_d := 90.0) -> void:
	var s := _pick(n)
	if s == null:
		return
	var p := _p3[_i3]
	_i3 = (_i3 + 1) % _p3.size()
	p.stream = s
	p.global_position = pos
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.unit_size = unit
	p.max_distance = max_d
	p.play()

func music(n: String, fade := 1.5, vol_db := -4.0) -> void:
	if n == music_name:
		return
	music_name = n
	var old := _music[_mi]
	_mi = 1 - _mi
	var cur := _music[_mi]
	var tw := create_tween().set_parallel(true)
	tw.tween_property(old, "volume_db", -60.0, fade)
	var s := _pick(n) if n != "" else null
	if s:
		if s is AudioStreamOggVorbis:
			s.loop = true
		elif s is AudioStreamMP3:
			s.loop = true
		elif s is AudioStreamWAV:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_end = int(s.get_length() * s.mix_rate)
		cur.stream = s
		cur.volume_db = -60.0
		cur.play()
		tw.tween_property(cur, "volume_db", vol_db, fade)
	tw.chain().tween_callback(old.stop)

func ambient(n: String, vol_db := -14.0) -> void:
	var s := _pick(n) if n != "" else null
	if s == null:
		_amb.stop()
		return
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.get_length() * s.mix_rate)
	elif s is AudioStreamOggVorbis or s is AudioStreamMP3:
		s.loop = true
	_amb.stream = s
	_amb.volume_db = vol_db
	_amb.play()

func stop_all() -> void:
	for p in _p2:
		p.stop()
	for p in _p3:
		p.stop()
	_amb.stop()
