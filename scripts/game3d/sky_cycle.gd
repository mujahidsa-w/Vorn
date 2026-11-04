extends Node3D
## Day / night cycle and weather for the city.
## Owns the WorldEnvironment, the sky shader and the sun/moon light, and drives
## everything that depends on time or weather: street lamps, wet roads, fog, rain.
## Time and weather come from the real clock, so every player online sees the same sky.

const DAY_MINUTES := 48.0          # one full in-game day = 48 real minutes (like GTA)
const WEATHER_BLOCK := 420.0       # weather can change every 7 minutes

var world
var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var Q := 1

var hour := 22.0
var forced_hour := -1.0            # test hook
var night := 1.0                   # 0 = full day, 1 = full night
var sun_elev := -0.5               # sin of sun elevation

# weather state (current values ease toward targets)
var clouds := 0.25
var rain := 0.0
var fog := 0.0
var wet := 0.0
var wind := 0.3
var _t_clouds := 0.25
var _t_rain := 0.0
var _t_fog := 0.0
var forced_weather := -1           # test hook: 1 clear, 2 rain, 3 fog
var weather_name := "CLEAR"

var lamps: Array = []              # OmniLight3D street lights
var lamp_mats: Array = []          # emissive bulb materials
var wet_mats: Array = []           # [{mat, col}] road / pavement materials
var foliage_mats: Array = []       # wind-swayed foliage shader materials
var _sky_t := 0.0
var _cloud_off := Vector2.ZERO
var _lamps_on := -1
var flash := 0.0                   # lightning flash
var _next_bolt := 8.0


func _ready() -> void:
	Q = clampi(int(Game.settings.quality), 0, 2)
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://assets/fx/sky.gdshader")
	var nt := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.012
	fn.fractal_octaves = 5
	nt.noise = fn
	nt.seamless = true
	nt.width = 512
	nt.height = 512
	nt.generate_mipmaps = true
	sky_mat.set_shader_parameter("noise_tex", nt)
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_REALTIME if Q >= 2 else Sky.PROCESS_MODE_AUTOMATIC
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = Q > 0
	env.glow_intensity = 0.8
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.fog_sky_affect = 0.55
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.05
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = Q > 0
	sun.directional_shadow_max_distance = [40.0, 60.0, 100.0][Q]
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if Q < 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_blur = 1.5
	sun.shadow_bias = 0.06
	add_child(sun)
	_update_time(0.0)
	_update_weather(10.0)
	_apply(true)


func set_hour(h: float) -> void:
	forced_hour = h
	_update_time(0.0)
	_apply(true)


func set_weather(w: int) -> void:
	forced_weather = w
	_update_weather(1000.0)
	wet = 1.0 if w == 2 else 0.0
	_apply(true)


func refresh() -> void:
	_lamps_on = -1
	_apply(true)


func is_night() -> bool:
	return night > 0.5


# ---------------------------------------------------------------- time
func _clock() -> float:
	return Time.get_unix_time_from_system()


func _update_time(_delta: float) -> void:
	var mode := int(Game.settings.get("time_mode", 0))
	if forced_hour >= 0.0:
		hour = forced_hour
	elif mode == 1:
		hour = 13.0
	elif mode == 2:
		hour = 17.85
	elif mode == 3:
		hour = 23.0
	else:
		hour = fmod(_clock() / (DAY_MINUTES * 60.0 / 24.0) + 3.0, 24.0)
	# sun rises around 6:15, is highest at 12:15 and sets around 18:15
	sun_elev = sin((hour - 6.25) / 24.0 * TAU) * 0.92
	night = 1.0 - smoothstep(-0.1, 0.12, sun_elev)


# ---------------------------------------------------------------- weather
func _hash(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898 + 78.233) * 43758.5453, 1.0)


func _update_weather(delta: float) -> void:
	var mode := int(Game.settings.get("weather", 0))
	if forced_weather > 0:
		mode = forced_weather
	var kind := 0      # 0 clear, 1 cloudy, 2 rain, 3 fog, 4 storm
	if mode == 0:
		var r := _hash(int(_clock() / WEATHER_BLOCK))
		kind = 0 if r < 0.42 else (1 if r < 0.62 else (2 if r < 0.82 else (3 if r < 0.92 else 4)))
	else:
		kind = [0, 0, 2, 3][mode]
	if not bool(Game.settings.get("rain", true)) and (kind == 2 or kind == 4):
		kind = 1
	match kind:
		0:
			_t_clouds = 0.22; _t_rain = 0.0; _t_fog = 0.0; weather_name = "CLEAR"
		1:
			_t_clouds = 0.65; _t_rain = 0.0; _t_fog = 0.15; weather_name = "CLOUDY"
		2:
			_t_clouds = 0.88; _t_rain = 0.7; _t_fog = 0.3; weather_name = "RAIN"
		3:
			_t_clouds = 0.6; _t_rain = 0.0; _t_fog = 1.0; weather_name = "FOG"
		4:
			_t_clouds = 1.0; _t_rain = 1.0; _t_fog = 0.4; weather_name = "THUNDERSTORM"
	var k := 1.0 - exp(-delta / 25.0)
	clouds = lerpf(clouds, _t_clouds, k)
	rain = lerpf(rain, _t_rain, k)
	fog = lerpf(fog, _t_fog, k)
	# roads get wet in ~20 s of rain and dry over ~2 minutes
	if rain > 0.15:
		wet = minf(1.0, wet + delta / 20.0 * rain)
	else:
		wet = maxf(0.0, wet - delta / 120.0)
	wind = 0.25 + clouds * 0.35 + rain * 0.5
	if kind == 4:
		_next_bolt -= delta
		if _next_bolt <= 0.0:
			_next_bolt = randf_range(9.0, 22.0)
			flash = 1.0
			var dl := randf_range(0.6, 2.8)
			get_tree().create_timer(dl).timeout.connect(func(): Game.play_sfx("thunder", randf_range(0.85, 1.1), -2.0 - dl * 2.0))
	flash = maxf(0.0, flash - delta * 2.6)


# ---------------------------------------------------------------- apply
static func _ramp(stops: Array, x: float) -> Color:
	# stops: [[x, Color], ...] sorted by x
	if x <= stops[0][0]:
		return stops[0][1]
	for i in range(1, stops.size()):
		if x <= stops[i][0]:
			var t: float = (x - stops[i - 1][0]) / (stops[i][0] - stops[i - 1][0])
			return (stops[i - 1][1] as Color).lerp(stops[i][1], t)
	return stops[-1][1]


func _apply(force := false) -> void:
	var e := sun_elev
	var over := clampf(clouds * 1.15 - 0.25, 0.0, 1.0)       # overcast amount
	var top := _ramp([[-0.25, Color(0.03, 0.035, 0.07)], [-0.05, Color(0.035, 0.05, 0.12)], [0.05, Color(0.13, 0.2, 0.42)], [0.3, Color(0.2, 0.42, 0.82)], [1.0, Color(0.16, 0.36, 0.78)]], e)
	var hor := _ramp([[-0.25, Color(0.2, 0.15, 0.15)], [-0.05, Color(0.28, 0.17, 0.2)], [0.04, Color(0.98, 0.5, 0.26)], [0.22, Color(0.78, 0.78, 0.82)], [1.0, Color(0.66, 0.79, 0.93)]], e)
	var grey := Color(0.5, 0.53, 0.57).lerp(Color(0.62, 0.5, 0.42), night * 0.7) * clampf(0.4 + (1.0 - night) * 0.6, 0.05, 1.0)
	top = top.lerp(grey * 0.85, over * 0.85)
	hor = hor.lerp(grey, over * 0.8)
	var sun_dir := _sun_dir()
	sky_mat.set_shader_parameter("top_col", top)
	sky_mat.set_shader_parameter("hor_col", hor)
	sky_mat.set_shader_parameter("ground_col", hor * 0.35)
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("moon_dir", -sun_dir.rotated(Vector3.UP, 0.6).normalized() * Vector3(1, 0.0, 1) + Vector3(0, 0.55, 0))
	sky_mat.set_shader_parameter("sun_col", _ramp([[-0.05, Color(1.0, 0.35, 0.12)], [0.15, Color(1.0, 0.7, 0.4)], [0.5, Color(1.0, 0.95, 0.85)]], e))
	sky_mat.set_shader_parameter("night", night)
	sky_mat.set_shader_parameter("clouds", clouds)
	sky_mat.set_shader_parameter("cloud_light", clampf(0.32 + (1.0 - night) * 0.66 + flash * 0.8, 0.0, 1.4))
	sky_mat.set_shader_parameter("cloud_off", _cloud_off)
	# sun or moon light
	var day_k := 1.0 - night
	var sun_vis := clampf(1.0 - over * 0.75, 0.15, 1.0)
	if e > -0.02:
		sun.look_at_from_position(Vector3.ZERO, -sun_dir, Vector3.UP if absf(sun_dir.y) < 0.99 else Vector3.FORWARD)
		sun.light_color = _ramp([[0.0, Color(1.0, 0.45, 0.2)], [0.18, Color(1.0, 0.78, 0.55)], [0.5, Color(1.0, 0.96, 0.9)]], e)
		sun.light_energy = clampf(e * 6.0, 0.0, 1.0) * 0.98 * sun_vis
		sun.shadow_opacity = clampf(0.85 * sun_vis, 0.2, 0.85)
	else:
		var md := Vector3(0.35, 0.75, -0.55).normalized()
		sun.look_at_from_position(Vector3.ZERO, -md, Vector3.UP)
		sun.light_color = Color(0.55, 0.65, 1.0)
		sun.light_energy = 0.19 * clampf(1.0 - over * 0.6, 0.3, 1.0)
		sun.shadow_opacity = 0.5
	sun.light_energy += flash * 2.5
	# ambient + fog
	var amb := Color(0.32, 0.38, 0.6).lerp(Color(0.62, 0.66, 0.74), day_k).lerp(Color(0.55, 0.57, 0.6), over * day_k * 0.6)
	env.ambient_light_color = amb
	env.ambient_light_energy = lerpf(0.24, 0.5, day_k) * lerpf(1.0, 1.15, over) + flash * 1.5
	env.tonemap_exposure = lerpf(1.1, 0.74, day_k)
	env.tonemap_white = lerpf(4.0, 6.0, day_k)
	env.fog_light_color = hor.lerp(Color(0.6, 0.62, 0.65) * (0.15 + day_k * 0.75), clampf(fog + rain * 0.5, 0.0, 1.0))
	var base_fog: float = lerpf([0.0065, 0.0045, 0.0035][Q], 0.0016, day_k)
	env.fog_density = base_fog + fog * 0.022 + rain * 0.004
	env.glow_intensity = lerpf(0.9, 0.35, day_k)
	# street lamps switch on at dusk
	var on := 1 if night > 0.35 or (fog > 0.6 and night > 0.1) else 0
	if on != _lamps_on or force:
		_lamps_on = on
		for l in lamps:
			if is_instance_valid(l) and not l.get_meta("broken", false):
				l.visible = on == 1
		for m in lamp_mats:
			m.emission_energy_multiplier = 4.0 if on == 1 else 0.0
			m.albedo_color = Color(1.0, 0.8, 0.5) if on == 1 else Color(0.55, 0.55, 0.52)
	# wet roads: darker and glossy, reflecting the sky and lights
	for w in wet_mats:
		var m: StandardMaterial3D = w.mat
		m.roughness = lerpf(0.82, 0.14, wet)
		m.metallic_specular = lerpf(0.45, 0.9, wet)
		m.albedo_color = (w.col as Color) * lerpf(1.0, 0.62, wet)
	for fm in foliage_mats:
		fm.set_shader_parameter("wind", wind)


func _sun_dir() -> Vector3:
	# direction toward the sun: east (+X) in the morning, west in the evening
	var az := (hour - 12.25) / 12.0 * PI
	var el := asin(clampf(sun_elev, -1.0, 1.0))
	return Vector3(-sin(az) * cos(el), sin(el), -cos(az) * cos(el) * 0.6 - 0.25).normalized()


func _process(delta: float) -> void:
	_update_time(delta)
	_update_weather(delta)
	_cloud_off += Vector2(0.0032, 0.0011) * delta * (0.6 + wind)
	_sky_t += delta
	var period := 0.05 if flash > 0.0 else (0.25 if Q >= 2 else 0.5)
	if _sky_t >= period:
		_sky_t = 0.0
		_apply()
	if world and world.rain:
		var dp: ParticleProcessMaterial = world.rain.process_material
		world.rain.amount_ratio = clampf(rain, 0.0, 1.0)
		dp.direction = Vector3(0.12 + wind * 0.25, -1, 0.05)
