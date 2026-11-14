extends Node
## ENet session and lightweight player-state replication for VORN.

signal session_ready
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal state_received(peer_id: int, pos: Vector3, yaw: float, pitch: float, hp: int, alive: bool, crouch: float, weapon: String)
signal connection_failed(reason: String)

const DEFAULT_PORT := 24567
const MAX_CLIENTS := 10
var online := false
var is_host := false
var local_peer_id := 1
var player_name := "Player"
var server_address := "127.0.0.1"
var _send_acc := 0.0
var match_ref: Node = null

func host(port: int = DEFAULT_PORT) -> Error:
	close_session()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS - 1)
	if err != OK:
		connection_failed.emit("تعذر إنشاء الغرفة: %s" % error_string(err))
		return err
	multiplayer.multiplayer_peer = peer
	online = true
	is_host = true
	local_peer_id = 1
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	session_ready.emit()
	return OK

func join(address: String, port: int = DEFAULT_PORT) -> Error:
	close_session()
	server_address = address.strip_edges()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(server_address, port)
	if err != OK:
		connection_failed.emit("تعذر الاتصال: %s" % error_string(err))
		return err
	multiplayer.multiplayer_peer = peer
	online = true
	is_host = false
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_disconnected)
	return OK

func close_session() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	online = false
	is_host = false
	_send_acc = 0.0

func _on_connected() -> void:
	local_peer_id = multiplayer.get_unique_id()
	session_ready.emit()

func _on_failed() -> void:
	connection_failed.emit("فشل الاتصال بالخادم. تحقق من العنوان والمنفذ.")
	close_session()

func _on_disconnected() -> void:
	connection_failed.emit("انقطع الاتصال بالخادم.")
	close_session()

func _on_peer_connected(id: int) -> void:
	peer_joined.emit(id)
	if is_host:
		var ids: Array[int] = [1]
		for peer_id in multiplayer.get_peers():
			ids.append(int(peer_id))
		rpc_id(id, "client_sync_roster", ids)
		rpc("client_peer_joined", id)

func _on_peer_disconnected(id: int) -> void:
	peer_left.emit(id)

func peer_team(peer_id: int) -> String:
	var ids: Array[int] = [1]
	for id in multiplayer.get_peers():
		ids.append(int(id))
	ids.sort()
	var idx := ids.find(peer_id)
	var first := "ct" # ثابت على كل الأجهزة حتى لا تختلف الفرق باختلاف إعدادات كل لاعب
	return first if idx % 2 == 0 else ("t" if first == "ct" else "ct")

func peer_slot(peer_id: int) -> int:
	var ids: Array[int] = [1]
	for id in multiplayer.get_peers():
		ids.append(int(id))
	ids.sort()
	var team := peer_team(peer_id)
	var slot := 0
	for i in range(ids.find(peer_id)):
		if peer_team(ids[i]) == team:
			slot += 1
	return slot

func send_player_state(actor: Actor, dt: float) -> void:
	if not online or not is_instance_valid(actor):
		return
	_send_acc += dt
	if _send_acc < 0.05:
		return
	_send_acc = 0.0
	var data := [actor.global_position, actor.view_yaw, actor.view_pitch, actor.crouch_t, actor.cur]
	if is_host:
		client_apply_state(1, data[0], data[1], data[2], actor.hp, actor.alive, data[3], data[4])
		rpc("client_apply_state", 1, data[0], data[1], data[2], actor.hp, actor.alive, data[3], data[4])
	else:
		rpc_id(1, "server_receive_state", data[0], data[1], data[2], data[3], data[4])

@rpc("any_peer", "call_remote", "unreliable_ordered")
func server_receive_state(pos: Vector3, yaw: float, pitch: float, crouch: float, weapon: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1 or not is_instance_valid(match_ref):
		return
	var actor = match_ref.get_node_or_null("Peer_%d" % sender)
	if actor == null or not actor.alive:
		return
	# الصحة والموت لا يقبلهما الخادم من العميل مطلقاً.
	actor.global_position = pos
	actor.view_yaw = yaw
	actor.view_pitch = pitch
	actor.crouch_t = clampf(crouch, 0.0, 1.0)
	if DB.W.has(weapon) and (weapon == "knife" or actor.inv.has(int(DB.W[weapon]["slot"]))):
		actor.cur = weapon
	rpc("client_apply_state", sender, actor.global_position, actor.view_yaw, actor.view_pitch, actor.hp, actor.alive, actor.crouch_t, actor.cur)

@rpc("authority", "call_remote", "reliable")
func client_sync_roster(peer_ids: Array) -> void:
	if not is_instance_valid(match_ref):
		return
	for value in peer_ids:
		var id := int(value)
		if id != multiplayer.get_unique_id():
			match_ref._add_network_actor(id)

@rpc("authority", "call_remote", "reliable")
func client_peer_joined(peer_id: int) -> void:
	if is_instance_valid(match_ref):
		match_ref._add_network_actor(peer_id)

func request_shot(origin: Vector3, direction: Vector3, weapon: String) -> void:
	if online and not is_host:
		rpc_id(1, "server_receive_shot", origin, direction, weapon)

@rpc("any_peer", "call_remote", "reliable")
func server_receive_shot(origin: Vector3, direction: Vector3, weapon: String) -> void:
	if not multiplayer.is_server() or not is_instance_valid(match_ref):
		return
	var sender := multiplayer.get_remote_sender_id()
	var shooter = match_ref.get_node_or_null("Peer_%d" % sender)
	if shooter == null or not shooter.alive or shooter.cur != weapon or not DB.W.has(weapon):
		return
	if match_ref.frozen() or shooter.fire_cd > 0.0 or shooter.reload_t > 0.0 or shooter.mag() <= 0:
		return
	if origin.distance_to(shooter.eye()) > 3.0 or direction.length_squared() < 0.8 or direction.length_squared() > 1.2:
		return
	# يخصم الخادم الذخيرة ويضبط مهلة الإطلاق قبل احتساب الإصابة.
	shooter.ammo[weapon][0] -= 1
	shooter.fire_cd = 60.0 / float(DB.W[weapon]["rpm"])
	match_ref.bullet(shooter, shooter.eye(), direction.normalized(), weapon, true)

@rpc("authority", "call_remote", "unreliable_ordered")
func client_apply_state(peer_id: int, pos: Vector3, yaw: float, pitch: float, hp: int, alive: bool, crouch: float, weapon: String) -> void:
	state_received.emit(peer_id, pos, yaw, pitch, hp, alive, crouch, weapon)
