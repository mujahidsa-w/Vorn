class_name RemoteActor
extends Actor
## Network-controlled representation of another human player.

var target_position := Vector3.ZERO
var target_yaw := 0.0
var target_pitch := 0.0
var target_hp := 100
var target_alive := true
var target_crouch := 0.0
var target_weapon := "knife"

func _ready() -> void:
	set_physics_process(false)
	set_process(true)

func apply_network_state(pos: Vector3, yaw: float, pitch: float, health: int, is_alive: bool, crouch: float, weapon: String) -> void:
	target_position = pos
	target_yaw = yaw
	target_pitch = pitch
	target_hp = health
	target_alive = is_alive
	target_crouch = crouch
	target_weapon = weapon
	if not alive and target_alive:
		spawn_at(pos, yaw, true)
	elif alive and not target_alive:
		alive = false
		_set_hit_enabled(false)
		if body:
			body.die(false, pos)

func _process(dt: float) -> void:
	if not is_inside_tree():
		return
	var k := 1.0 - exp(-18.0 * dt)
	global_position = global_position.lerp(target_position, k)
	view_yaw = lerp_angle(view_yaw, target_yaw, k)
	view_pitch = lerpf(view_pitch, target_pitch, k)
	crouch_t = lerpf(crouch_t, target_crouch, k)
	hp = target_hp
	if cur != target_weapon and DB.W.has(target_weapon):
		if target_weapon != "knife":
			var slot: int = int(DB.W[target_weapon]["slot"])
			inv[slot] = target_weapon
			_fill(target_weapon)
		switch_to(target_weapon, true)
	if body:
		body.position = Vector3.ZERO
		body.rotation.y = view_yaw
