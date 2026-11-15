class_name NetPuppet
extends RemoteActor
## A fighter driven over the network in the online battle royale: on clients every fighter but their own (bots and
## other players, from the host's snapshots); on the host the other players (from their own reports).
## It follows the reported pose smoothly and keeps its hit boxes where the body is.

var target_prone := 0.0
var target_lean := 0.0
var target_armor := 0
var target_helmet := false
var net_idx := -1
var peer := 0                 # network peer that plays it, 0 for a bot
var host_side := false        # on the host: life and death stay with the host, only the pose comes from the peer

func apply_pose(pos: Vector3, yaw: float, pitch: float, crouch: float, prone_v: float, lean_v: float, weapon: String) -> void:
	target_position = pos
	target_yaw = yaw
	target_pitch = pitch
	target_crouch = crouch
	target_prone = prone_v
	target_lean = lean_v
	target_weapon = weapon

func _process(dt: float) -> void:
	if not is_inside_tree():
		return
	var k := 1.0 - exp(-16.0 * dt)
	if vehicle == null:
		if global_position.distance_to(target_position) > 25.0:
			global_position = target_position
		else:
			global_position = global_position.lerp(target_position, k)
	view_yaw = lerp_angle(view_yaw, target_yaw, k)
	view_pitch = lerpf(view_pitch, target_pitch, k)
	crouch_t = lerpf(crouch_t, target_crouch, k)
	prone_t = lerpf(prone_t, target_prone, k)
	prone = target_prone > 0.5
	lean = lerpf(lean, target_lean, k)
	if not host_side:
		hp = target_hp
		armor = target_armor
		helmet = target_helmet
	if cur != target_weapon and DB.W.has(target_weapon):
		if target_weapon != "knife" and not host_side:
			var slot: int = int(DB.W[target_weapon]["slot"])
			inv[slot] = target_weapon
			_fill(target_weapon)
		if owned().has(target_weapon):
			switch_to(target_weapon, true)
	if alive:
		_apply_crouch()
	if host_side:
		tick_weapon(dt)

## a client learns from the host that this fighter is down
func net_die() -> void:
	if not alive:
		return
	alive = false
	_set_hit_enabled(false)
	if body:
		body.die(false, global_position + Vector3(0, 0, 1))
