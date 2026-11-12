extends CharacterBody3D
## Another real player in the match, driven by their network state.
## Bullets that hit this body are reported to that player (they apply the damage).

const Rig = preload("res://scripts/game3d/rig.gd")
const W = preload("res://scripts/game3d/weapons.gd")

var net                     # MatchNet
var world
var uid := ""
var pname := "PLAYER"
var team := "a"
var side := "a"              # competitive side (a or b), sent with every state
var rig
var model: Node3D
var weapon_node: Node3D
var weapon_id := ""
var label: Label3D
var hp := 100.0
var dead := false
var stance := 0
var in_car := -1
var last_rx := 0.0          # local time of the last state
var _target := Vector3.ZERO
var _vel := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _aim := false
var _has_state := false
var _shown_vel := Vector3.ZERO
var col_shape: CollisionShape3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	var cs := CollisionShape3D.new()
	col_shape = cs
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	model = Node3D.new()
	model.rotation.y = PI
	add_child(model)
	rig = Rig.new()
	model.add_child(rig)
	rig.setup(team == "cops")
	label = Label3D.new()
	label.text = pname
	label.font = Game.font_bold
	label.font_size = 64
	label.pixel_size = 0.004
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = (Game.C_BLUE if team == "cops" else Game.C_RED).lightened(0.35)
	label.position = Vector3(0, 2.15, 0)
	label.visibility_range_end = 70.0
	add_child(label)


func apply_state(s: Dictionary) -> void:
	side = str(s.get("cs", side))
	last_rx = Time.get_ticks_msec() / 1000.0
	var p := Vector3(float(s.get("x", 0)), float(s.get("y", 0)), float(s.get("z", 0)))
	_vel = Vector3(float(s.get("vx", 0)), 0, float(s.get("vz", 0)))
	_yaw = float(s.get("ry", 0))
	_pitch = float(s.get("pt", 0))
	_aim = bool(s.get("am", false))
	if not _has_state or p.distance_to(global_position) > 12.0:
		global_position = p
		rotation.y = _yaw
	_has_state = true
	_target = p
	stance = int(s.get("st", 0))
	hp = float(s.get("hp", 100))
	var was_dead := dead
	dead = bool(s.get("dead", false))
	if dead and not was_dead:
		rig.death_clip = str(s.get("dc", "death_front"))
	rig.dead = dead
	rig.stance = stance
	in_car = int(s.get("car", -1))
	visible = in_car < 0
	col_shape.disabled = in_car >= 0 or dead
	var w := str(s.get("w", ""))
	if w != weapon_id:
		_equip(w)


func _equip(id: String) -> void:
	weapon_id = id
	if weapon_node:
		weapon_node.queue_free()
		weapon_node = null
	rig.grips = {}
	rig.weapon = null
	if id == "" or not W.DATA.has(id):
		return
	var d: Dictionary = W.DATA[id]
	weapon_node = load(d.path).instantiate()
	model.add_child(weapon_node)
	weapon_node.position = d.pos
	weapon_node.rotation_degrees = d.rot
	rig.weapon = weapon_node
	rig.weapon_id = id
	rig.grips = W.grips_for(id, weapon_node)


func muzzle_pos() -> Vector3:
	if weapon_node == null:
		return global_position + Vector3(0, 1.4, 0)
	return weapon_node.global_transform * W.muzzle_local(weapon_id, weapon_node)


## Local bullets / melee / cars hitting this player: tell them, they apply it.
func take_damage(amount: float, attacker, dir := Vector3.ZERO) -> void:
	if dead or amount <= 0.0 or net == null:
		return
	if attacker == world.player or attacker == null or (attacker is Node and attacker.has_method("exit_car")):
		net.send_hit(uid, amount, dir)
	world.fx.impact(global_position + Vector3(0, 1.2, 0), -dir.normalized() if dir.length() > 0 else Vector3.UP, true)


func push(_v: Vector3) -> void:
	pass


func _physics_process(delta: float) -> void:
	if not _has_state:
		return
	# smooth toward the latest network position, extrapolating a little with velocity
	var age := clampf(Time.get_ticks_msec() / 1000.0 - last_rx, 0.0, 0.25)
	var want := _target + _vel * age
	var prev := global_position
	global_position = global_position.lerp(want, 1.0 - exp(-delta * 12.0))
	_shown_vel = _shown_vel.lerp((global_position - prev) / maxf(delta, 0.001), 1.0 - exp(-delta * 10.0))
	rotation.y = lerp_angle(rotation.y, _yaw, 1.0 - exp(-delta * 14.0))


func _process(delta: float) -> void:
	if not _has_state or not visible:
		return
	var cam: Camera3D = world.current_camera() if world else null
	if cam and cam.global_position.distance_to(global_position) > 90.0:
		return
	var fwd := -global_transform.basis.z
	var vl := Vector2(_shown_vel.dot(global_transform.basis.x), _shown_vel.dot(fwd))
	if vl.length() < 0.12:
		vl = Vector2.ZERO
	rig.aiming = _aim
	var typ: String = W.DATA[weapon_id].type if weapon_id != "" and W.DATA.has(weapon_id) else ""
	if weapon_node and typ != "" and typ not in ["rifle", "rpg"]:
		var d: Dictionary = W.DATA[weapon_id]
		weapon_node.position = d.pos + Vector3(0, rig.position.y, 0)
		weapon_node.rotation_degrees = d.rot
	rig.update(delta, vl, true, typ, 1.0 if typ != "" else 0.0, _pitch)
