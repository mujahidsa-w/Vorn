class_name Player
extends Actor
## Игрок: ввод, камера, оружие и руки от первого лица (отдельный вид поверх мира), слежение за бойцами после гибели.

var head: Node3D
var cam: Camera3D
var vm: ViewModel
var vm_cam: Camera3D
var svp: SubViewport
var layer: CanvasLayer
var ui_block := false
var shake_amp := 0.0
var look_acc := Vector2.ZERO
var spect: Actor
var spect_t := 0.0
var orbit := 0.0
var fov_cur := 90.0
var bob_ph := 0.0
var land_dip := 0.0
var cam_mode := ""                # "" — normal; "free" — the game places the camera (plane); "sky" — no weapon in hands (fall, parachute)

func init_player() -> void:
	head = Node3D.new()
	head.name = "Head"
	add_child(head)
	head.top_level = true
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.cull_mask = 0xFFFFF & ~2
	cam.near = 0.05
	cam.far = 400.0
	cam.fov = float(G.settings["fov"])
	head.add_child(cam)
	cam.current = true
	layer = CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var cont := SubViewportContainer.new()
	cont.stretch = true
	cont.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(cont)
	svp = SubViewport.new()
	svp.transparent_bg = true
	var q := int(G.settings["quality"])
	if G.mobile:
		svp.msaa_3d = Viewport.MSAA_2X if q >= 1 else Viewport.MSAA_DISABLED
	else:
		svp.msaa_3d = Viewport.MSAA_4X if q >= 1 else Viewport.MSAA_2X
	svp.handle_input_locally = false
	svp.audio_listener_enable_3d = false
	cont.add_child(svp)
	vm_cam = Camera3D.new()
	vm_cam.cull_mask = 2
	vm_cam.near = 0.01
	vm_cam.far = 5.0
	vm_cam.fov = float(G.settings["viewmodel_fov"])
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	# своё нейтральное небо для отражений на металле (фон остаётся прозрачным), общий свет — тёплый серый
	var vsky := Sky.new()
	var vsm := ProceduralSkyMaterial.new()
	vsm.sky_top_color = Color(0.50, 0.54, 0.60)
	vsm.sky_horizon_color = Color(0.86, 0.83, 0.78)
	vsm.ground_horizon_color = Color(0.62, 0.56, 0.48)
	vsm.ground_bottom_color = Color(0.30, 0.27, 0.23)
	vsm.sun_angle_max = 0.0
	vsky.sky_material = vsm
	env.sky = vsky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.80, 0.78, 0.74)
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	vm_cam.environment = env
	svp.add_child(vm_cam)
	# свой свет для рук и оружия (только слой 2): ключевой сверху-слева и заполняющий справа
	for cfg in [[Vector3(-38, 28, 0), 1.9, Color(1.0, 0.96, 0.9)], [Vector3(-8, -70, 0), 0.85, Color(0.8, 0.88, 1.0)]]:
		var dl := DirectionalLight3D.new()
		dl.light_cull_mask = 2
		dl.shadow_enabled = false
		dl.rotation_degrees = cfg[0]
		dl.light_energy = cfg[1]
		dl.light_color = cfg[2]
		vm_cam.add_child(dl)
	vm = ViewModel.new()
	vm.name = "ViewModel"
	vm_cam.add_child(vm)
	vm.setup(self)
	weapon_changed.connect(func(w): vm.set_weapon(w); Sfx.play("draw", -10.0))
	# a weapon given before the view existed (battle royale starts with the knife already in hand)
	if cur != "":
		vm.set_weapon(cur)
	shot.connect(func(w):
		vm.on_shot()
		# короткая встряска камеры по силе отдачи
		var rec: Array = DB.W.get(w, {}).get("rec", [0.0])
		if DB.W.get(w, {}).has("rec"):
			shake(0.05 + 0.04 * float(rec[0])))
	reload_started.connect(func(w, t): vm.on_reload(w, t))
	died.connect(func(): vm.visible = false)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look((e as InputEventMouseMotion).relative, 0.0022 * float(G.settings["sens"]))

func look(rel: Vector2, k: float) -> void:
	## Turns the view; shared by the mouse and the touch screen (k = radians per unit of motion).
	if vm and vm.sight:
		k *= lerpf(1.0, float(DB.SIGHTS[vm.sight.kind]["sens"]), vm.ads_e)
	if alive and not game.auto:
		view_yaw = wrapf(view_yaw - rel.x * k, -PI, PI)
		view_pitch = clampf(view_pitch - rel.y * k, -1.5, 1.5)
		look_acc += rel * k
	elif not alive:
		orbit -= rel.x * k

func aim_on_enemy() -> bool:
	## True while the crosshair rests on a visible enemy (the touch controls slow the camera a little then).
	if not alive:
		return false
	var o := eye()
	var fwd := aim_dir()
	for a in game.actors:
		var e2 := a as Actor
		if not e2.alive or not game.hostile(e2, self):
			continue
		var to: Vector3 = e2.global_position + Vector3(0, 1.1, 0) - o
		var d := to.length()
		if d < 60.0 and fwd.angle_to(to) < 0.045 + 0.45 / maxf(d, 1.0) and game.world.los(o, e2.global_position + Vector3(0, 1.25, 0)):
			return true
	return false

func _physics_process(dt: float) -> void:
	if not alive:
		tick_weapon(dt)
		return
	if game.auto and has_meta("brain"):
		get_meta("brain").think(dt)
		tick_weapon(dt)
		return
	var block: bool = ui_block or game.state == game.S.OVER
	var wish := Vector2.ZERO
	var jump := false
	var crouch := false
	var walk := false
	if not block:
		wish = Input.get_vector("left", "right", "back", "fwd")
		jump = Input.is_action_just_pressed("jump")
		crouch = Input.is_action_pressed("crouch")
		walk = Input.is_action_pressed("walk")
	if game.frozen():
		wish = Vector2.ZERO
		jump = false
	if game.test_wish != Vector2.ZERO:
		wish = game.test_wish
	move_step(wish, jump, crouch, walk, dt)
	if not block:
		var d := wd()
		var cls: String = d["cls"]
		if cls == "c4":
			game.try_plant(self, Input.is_action_pressed("fire") or Input.is_action_pressed("use"))
		else:
			if plant_t >= 0.0:
				plant_t = -1.0
			var want := Input.is_action_pressed("fire") if d.get("auto", false) else Input.is_action_just_pressed("fire")
			if want:
				try_fire(false)
			if Input.is_action_just_pressed("alt"):
				try_fire(true)
		if Input.is_action_just_pressed("reload"):
			start_reload()
		if Input.is_action_just_pressed("inspect"):
			vm.inspect()
		for i in range(1, 6):
			if Input.is_action_just_pressed("slot%d" % i):
				switch_slot(i)
		if Input.is_action_just_pressed("quick") and owned().has(prev):
			switch_to(prev)
		if Input.is_action_just_pressed("next"):
			cycle(1)
		if Input.is_action_just_pressed("prev"):
			cycle(-1)
		if team == "ct":
			game.try_defuse(self, Input.is_action_pressed("use"))
	tick_weapon(dt)

func on_player_death(killer: Actor) -> void:
	spect = killer if killer and killer.alive and killer != self else null
	spect_t = 0.0
	orbit = view_yaw

func shake(amp: float) -> void:
	shake_amp = maxf(shake_amp, amp)

func _next_spect() -> void:
	var mates: Array = game.alive_of(team)
	if mates.is_empty():
		mates = game.alive_of("ct" if team == "t" else "t")
	if mates.is_empty():
		spect = null
		return
	var i := mates.find(spect)
	spect = mates[(i + 1) % mates.size()]

func _process(dt: float) -> void:
	if cam_mode == "free":
		vm.visible = false
		vm_cam.global_transform = cam.global_transform
		return
	shake_amp = maxf(0.0, shake_amp - dt * 1.6)
	var sh := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake_amp * 0.035
	var want_fov := float(G.settings["fov"])
	if alive:
		if vm.sight:
			want_fov *= lerpf(1.0, float(DB.SIGHTS[vm.sight.kind]["fov_k"]), vm.ads_e)
		var sp := speed_h()
		bob_ph = step_ph
		var bob := -absf(sin(bob_ph)) * 0.012 * clampf(sp / 5.5, 0.0, 1.0) if is_on_floor() else 0.0
		land_dip = lerpf(land_dip, 0.0, 1.0 - exp(-9.0 * dt))
		if landed_v < -4.0:
			land_dip = clampf(landed_v * 0.012, -0.14, 0.0)
			landed_v = 0.0
		head.global_position = eye() + Vector3(0, bob + land_dip, 0)
		var p := view_pitch + deg_to_rad(punch.x) * 0.5
		var y := view_yaw + deg_to_rad(punch.y) * 0.5
		head.global_transform.basis = Basis(Vector3.UP, y) * Basis(Vector3.RIGHT, clampf(p, -1.55, 1.55)) * Basis.from_euler(sh)
		vm.visible = cam_mode != "sky"
		vm.fov_world = cam.fov
		vm.fov_vm = vm_cam.fov
		vm.tick(dt, look_acc)
		look_acc = Vector2.ZERO
	else:
		vm.visible = false
		spect_t += dt
		if spect == null or not is_instance_valid(spect) or (not spect.alive and spect_t > 2.5):
			_next_spect()
			spect_t = 0.0
		if Input.is_action_just_pressed("fire") and not game.auto:
			_next_spect()
		var focus := (spect.global_position + Vector3(0, 1.5, 0)) if spect else global_position + Vector3(0, 1.0, 0)
		if spect and spect.alive:
			orbit = lerp_angle(orbit, spect.view_yaw, 1.0 - exp(-3.0 * dt))
		var back := Basis(Vector3.UP, orbit).z * 2.8 + Vector3(0, 0.7, 0)
		var q := PhysicsRayQueryParameters3D.create(focus, focus + back, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		var cp: Vector3 = focus + back
		if not hit.is_empty():
			cp = (hit["position"] as Vector3) - back.normalized() * 0.25
		head.global_position = head.global_position.lerp(cp, 1.0 - exp(-10.0 * dt))
		head.look_at(focus, Vector3.UP)
	fov_cur = lerpf(fov_cur, want_fov, 1.0 - exp(-30.0 * dt))
	cam.fov = fov_cur
	vm_cam.global_transform = cam.global_transform
