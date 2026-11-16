extends Node
## Online play: accounts, the waiting room and the battle servers (AURUM MOBILE).
##
## One script, three roles:
##   master  (--server): keeps the accounts and their profiles, logs players in, gathers the waiting room and, when
##            its countdown runs out, starts a battle process for it on the next free port;
##   battle  (--battle): one battle royale on its own port. The players of the room come in with one-time tickets,
##            every seat left empty is a bot, and the process ends with the battle;
##   client  (the game): logs in, keeps the profile on the master, joins the waiting room, plays the battle on its
##            port and comes back to the master afterwards.
## Two ways to connect, chosen by the server address:
##   - an IP or host name: ENet over UDP, encrypted with DTLS (the master makes its key on the first start);
##     ports PORT .. PORT + BATTLE_PORTS must be open (VPS, home PC);
##   - a web address (wss://..., https://..., or a *.hf.space name): WebSocket over HTTPS on one port. The master is at
##     <address>/m and battle N at <address>/b/N; a web server in front (server/hf/nginx.conf) routes the paths. This is
##     the free Hugging Face Spaces set-up (server/hf), where only one web port is open.
## The password never leaves the phone: the client sends a hash of it, and the master keeps a salted PBKDF2 of that hash.
##
## Running a server:  godot --headless --path <project> -- --server [--data <dir>] [--ws --bind 127.0.0.1]

signal changed                        # client: connection, login or waiting-room state changed
signal message(text: String)          # client: a notice for the lobby

const PROTOCOL := 1
const DEFAULT_HOST := "127.0.0.1"     # the address of the AURUM MOBILE server (also editable in the account panel)
const PORT := 24600                   # the master; battles use PORT + 1 .. PORT + BATTLE_PORTS
const BATTLE_PORTS := 40
const ROOM_MAX := 29                  # real players in one battle (the battle's own fighter and the bots make 30)
const COUNTDOWN := 30.0               # the waiting room: seconds from the first player to the start
const COUNTDOWN_FULL := 4.0           # ... once the room is full
const READY_WAIT := 35.0              # battle: how long the players of the room have to load in
const PBKDF2_ROUNDS := 6000
const NAME_RE := "^[A-Za-z0-9_\\x{0600}-\\x{06FF}]{3,16}$"

# ================================================================== client
enum C { OFF, CONNECTING, ON }
var cstate := C.OFF
var link := ""                        # "master" or "battle": where the open connection goes
var logged_in := false
var account := ""
var queued := false
var room := {}                        # the master's waiting-room report: state, n, t, online, battles
var playing := false                  # an online battle is running (the battle royale scene is its client)
var battle := {}                      # host, port, ticket
var friends: Array = []               # [{name, state: "online" / "battle" / "off"}]
var found: Array = []                 # search results (names)
var _pending := {}                    # a login waiting for the connection
var _retry := -1.0                    # seconds to the next reconnect to the master
var _sync_t := -1.0                   # profile upload pending (debounced)

# ================================================================== servers
var role := ""                        # "", "master" or "battle"
var data_dir := ""
var _key: CryptoKey
var _cert: X509Certificate
# master
var accounts := {}                    # key (name in lower case) -> {name, salt, hash, tokens, profile, created}
var token_of := {}                    # token -> key
var by_peer := {}                     # peer -> key
var hello_ok := {}                    # peer -> true once the protocol matches
var queue: Array = []                 # [{peer, outfit}]
var count_t := -1.0
var countdown := COUNTDOWN
var max_battles := BATTLE_PORTS       # --max_battles: how many battles the machine can hold (~400 MB each)
var battles := {}                     # port -> {pid, group, t, sent}
var _dirty := false
var _save_t := 0.0
var _room_t := 0.0
var _fails := {}                      # peer -> [count, first failure msec]
var _made := {}                       # peer -> accounts made on this connection
# battle
var tickets := {}                     # ticket -> {name, outfit, used}
var battle_port := 0
var _end_t := -1.0
var _wait_t := -1.0
var _life_t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_lost)
	multiplayer.peer_disconnected.connect(_on_peer_gone)

# ------------------------------------------------------------------ client: connection
func host_addr() -> String:
	var h := String(G.settings.get("server", "")).strip_edges()
	return h if h != "" else default_host()

static func default_host() -> String:
	## the build's server (res://server.json, written by the build workflows from the GAME_SERVER variable)
	if FileAccess.file_exists("res://server.json"):
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://server.json"))
		if d is Dictionary and String(d.get("host", "")).strip_edges() != "":
			return String(d["host"]).strip_edges()
	return DEFAULT_HOST

func set_server(addr: String) -> void:
	addr = addr.strip_edges()
	if addr == "" or addr == default_host():
		G.settings.erase("server")
	else:
		G.settings["server"] = addr
	G.save_settings()

func has_token() -> bool:
	return String(G.settings.get("token", "")) != ""

func resume() -> void:
	## back in the lobby: reconnect to the master (the saved token logs in again)
	if role != "" or playing or Network.online:
		return
	if logged_in and cstate == C.ON and link == "master":
		return
	if has_token() or not _pending.is_empty():
		_open(host_addr(), PORT, "master")

static func is_web(addr: String) -> bool:
	addr = addr.strip_edges().to_lower()
	return addr.begins_with("ws://") or addr.begins_with("wss://") or addr.begins_with("http://") or addr.begins_with("https://") \
		or addr.trim_suffix("/").ends_with(".hf.space")

static func web_base(addr: String) -> String:
	## wss://host (https -> wss, http -> ws, a bare name -> wss), no trailing slash
	addr = addr.strip_edges().trim_suffix("/")
	if addr.begins_with("https://"):
		addr = "wss://" + addr.substr(8)
	elif addr.begins_with("http://"):
		addr = "ws://" + addr.substr(7)
	elif not (addr.begins_with("ws://") or addr.begins_with("wss://")):
		addr = "wss://" + addr
	return addr

func _open(addr: String, port: int, to: String) -> void:
	_close()
	var peer: MultiplayerPeer
	var err := OK
	if is_web(addr):
		var url := web_base(addr) + ("/m" if to == "master" else "/b/%d" % port)
		var wp := WebSocketMultiplayerPeer.new()
		err = wp.create_client(url, TLSOptions.client() if url.begins_with("wss://") else null)
		peer = wp
	else:
		var ep := ENetMultiplayerPeer.new()
		err = ep.create_client(addr, port)
		if err == OK:
			ep.host.dtls_client_setup(addr, TLSOptions.client_unsafe())
		peer = ep
	if err != OK:
		message.emit("تعذّر الاتصال بالخادم (%s)" % error_string(err))
		return
	multiplayer.multiplayer_peer = peer
	cstate = C.CONNECTING
	link = to
	changed.emit()

func release() -> void:
	## a private LAN room takes the connection over
	if cstate != C.OFF:
		_close()
		logged_in = false
		queued = false
		changed.emit()

func _close() -> void:
	if cstate != C.OFF and multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	cstate = C.OFF
	link = ""

func _on_connected() -> void:
	if role != "" or cstate != C.CONNECTING:
		return
	cstate = C.ON
	if link == "battle":
		G.start_match()          # the battle royale scene says hello with the ticket (BRNet.hello)
		return
	rpc_id(1, "m_hello", PROTOCOL, G.VERSION)
	if not _pending.is_empty():
		_send_pending()
	elif has_token():
		rpc_id(1, "m_resume", String(G.settings["token"]))
	changed.emit()

func _on_failed() -> void:
	if role != "" or cstate == C.OFF:
		return
	var was := link
	cstate = C.OFF
	link = ""
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if was == "battle":
		playing = false
		message.emit("تعذّر الدخول إلى المعركة")
		G.to_menu()
	else:
		_pending = {}
		message.emit("الخادم لا يرد — تحقق من الإنترنت أو عنوان الخادم")
		_retry = 15.0 if has_token() else -1.0
	changed.emit()

func _on_lost() -> void:
	if role != "" or cstate == C.OFF:
		return
	var was := link
	cstate = C.OFF
	link = ""
	logged_in = false
	queued = false
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if was == "battle":
		var still := playing
		playing = false
		var sc := get_tree().current_scene
		if still and sc and sc.get("result") != null and (sc.get("result") as Dictionary).is_empty():
			message.emit("انقطع الاتصال بالمعركة")
			G.to_menu()
	else:
		message.emit("انقطع الاتصال بالخادم")
		_retry = 5.0
	changed.emit()

func status_text() -> String:
	if playing:
		return "في معركة أونلاين"
	if logged_in:
		return "أونلاين · %s" % account
	if cstate == C.CONNECTING:
		return "جارٍ الاتصال بالخادم..."
	return "أوفلاين — سجّل الدخول للعب أونلاين"

# ------------------------------------------------------------------ client: account
static func pass_hash(name: String, password: String) -> String:
	## what leaves the phone instead of the password
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(("%s|%s|%s" % ["aurum-mobile", name.strip_edges().to_lower(), password]).to_utf8_buffer())
	return h.finish().hex_encode()

static func name_ok(name: String) -> bool:
	var re := RegEx.new()
	re.compile(NAME_RE)
	return re.search(name.strip_edges()) != null

func login(name: String, password: String, create := false) -> void:
	name = name.strip_edges()
	if not name_ok(name):
		message.emit("الاسم من 3 إلى 16 حرفاً: حروف عربية أو إنجليزية وأرقام و _")
		return
	if password.length() < 6:
		message.emit("كلمة المرور 6 أحرف على الأقل")
		return
	_pending = {"create": create, "name": name, "ph": pass_hash(name, password)}
	if cstate == C.ON and link == "master":
		_send_pending()
	else:
		_open(host_addr(), PORT, "master")

func _send_pending() -> void:
	var p := _pending
	_pending = {}
	if p.get("create", false):
		rpc_id(1, "m_register", p["name"], p["ph"], G.profile)
	else:
		rpc_id(1, "m_login", p["name"], p["ph"])

func logout() -> void:
	if logged_in and cstate == C.ON and link == "master":
		rpc_id(1, "m_logout", String(G.settings.get("token", "")))
	G.settings["token"] = ""
	G.save_settings()
	logged_in = false
	queued = false
	_close()
	changed.emit()

func profile_saved() -> void:
	## G.save_profile: the master gets the profile a moment later (or at the next login)
	if role != "" or not has_token():
		return
	G.settings["profile_dirty"] = true
	_sync_t = 1.5

func _push_profile() -> void:
	if logged_in and cstate == C.ON and link == "master":
		rpc_id(1, "m_save", G.profile)
		G.settings["profile_dirty"] = false
		G.save_settings()

@rpc("authority", "call_remote", "reliable")
func c_welcome(token: String, name: String, profile: Dictionary, info: Dictionary) -> void:
	var same := String(G.settings.get("account", "")) == name
	logged_in = true
	account = name
	room = info
	G.settings["token"] = token
	G.settings["account"] = name
	G.settings["name"] = name
	if same and G.settings.get("profile_dirty", false):
		_push_profile()                       # this phone played since the last upload
	elif not profile.is_empty():
		for k in profile:
			G.profile[k] = profile[k]
		var f := FileAccess.open(G.SAVE, FileAccess.WRITE) if not G.args.has("nosave") else null
		if f:
			f.store_string(JSON.stringify(G.profile, "\t"))
	else:
		_push_profile()
	G.settings["profile_dirty"] = false
	G.save_settings()
	ask_friends.call_deferred()
	G.log_line("online: welcome %s (profile %s)" % [name, "uploaded" if (same and G.settings.get("profile_dirty", false)) else "from the server"])
	message.emit("أهلاً %s — أنت متصل" % name)
	changed.emit()

@rpc("authority", "call_remote", "reliable")
func c_denied(msg: String, drop_token: bool) -> void:
	if drop_token:
		G.settings["token"] = ""
		G.save_settings()
	message.emit(msg)
	changed.emit()

@rpc("authority", "call_remote", "reliable")
func c_room(info: Dictionary) -> void:
	room = info
	changed.emit()

@rpc("authority", "call_remote", "reliable")
func c_notice(msg: String) -> void:
	message.emit(msg)

# ------------------------------------------------------------------ client: friends
func ask_friends() -> void:
	if logged_in and cstate == C.ON and link == "master":
		rpc_id(1, "m_friends")

func search(q: String) -> void:
	if logged_in and cstate == C.ON and link == "master" and q.strip_edges().length() >= 1:
		rpc_id(1, "m_search", q.strip_edges())

func add_friend(name: String) -> void:
	if logged_in and cstate == C.ON and link == "master":
		rpc_id(1, "m_add_friend", name)

func remove_friend(name: String) -> void:
	if logged_in and cstate == C.ON and link == "master":
		rpc_id(1, "m_remove_friend", name)

@rpc("authority", "call_remote", "reliable")
func c_friends(list: Array) -> void:
	friends = list
	changed.emit()

@rpc("authority", "call_remote", "reliable")
func c_found(list: Array) -> void:
	found = list
	changed.emit()

# ------------------------------------------------------------------ client: waiting room and battle
func join_queue() -> void:
	if not logged_in:
		return
	queued = true
	rpc_id(1, "m_queue", int(G.settings.get("outfit", 0)), String(G.settings.get("br_map", "island")))
	changed.emit()

func leave_queue() -> void:
	if queued and cstate == C.ON and link == "master":
		rpc_id(1, "m_unqueue")
	queued = false
	changed.emit()

@rpc("authority", "call_remote", "reliable")
func c_go(port: int, ticket: String, map_name: String) -> void:
	## the room's battle is up: leave the master for its port
	queued = false
	playing = true
	battle = {"host": host_addr(), "port": port, "ticket": ticket}
	G.settings["br_map"] = map_name
	var addr := host_addr()
	_open(addr, port, "battle")
	logged_in = false
	changed.emit()

func leave_battle() -> void:
	## the results card's «back to the lobby»: close the battle connection (the lobby reconnects to the master)
	playing = false
	battle = {}
	if link == "battle":
		_close()
	changed.emit()

# ================================================================== master
func start_master() -> void:
	role = "master"
	G.args["nosave"] = "1"
	_data_dir()
	_load_accounts()
	countdown = float(G.args.get("countdown", COUNTDOWN))
	max_battles = clampi(int(G.args.get("max_battles", BATTLE_PORTS)), 1, BATTLE_PORTS)
	var port := int(G.args.get("port", PORT))
	var peer := _server_peer(port, 256)
	if peer == null:
		printerr("[online] cannot open port %d" % port)
		get_tree().quit(1)
		return
	(multiplayer as SceneMultiplayer).server_relay = false      # players never talk to each other directly
	multiplayer.multiplayer_peer = peer
	print("[online] master on %s %d, %d accounts, data %s" % ["WebSocket" if G.args.has("ws") else "UDP", port, accounts.size(), data_dir])

func _server_peer(port: int, max_peers: int) -> MultiplayerPeer:
	## --ws: WebSocket behind the web server (one public port); otherwise ENet + DTLS on UDP
	if G.args.has("ws"):
		var wp := WebSocketMultiplayerPeer.new()
		if wp.create_server(port, String(G.args.get("bind", "*"))) != OK:
			return null
		return wp
	var ep := ENetMultiplayerPeer.new()
	if ep.create_server(port, max_peers) != OK:
		return null
	ep.host.dtls_server_setup(TLSOptions.server(_key, _cert))
	return ep

func _data_dir() -> void:
	data_dir = String(G.args.get("data", OS.get_user_data_dir() + "/server"))
	DirAccess.make_dir_recursive_absolute(data_dir + "/battles")
	var kp := data_dir + "/server.key"
	var cp := data_dir + "/server.crt"
	if FileAccess.file_exists(kp) and FileAccess.file_exists(cp):
		_key = CryptoKey.new()
		_key.load(kp)
		_cert = X509Certificate.new()
		_cert.load(cp)
		return
	var c := Crypto.new()
	_key = c.generate_rsa(2048)
	_cert = c.generate_self_signed_certificate(_key, "CN=aurum-mobile,O=SAQR STUDIOS,C=SA", "20260101000000", "20460101000000")
	_key.save(kp)
	_cert.save(cp)

func _load_accounts() -> void:
	var p := data_dir + "/accounts.json"
	if FileAccess.file_exists(p):
		var d = JSON.parse_string(FileAccess.get_file_as_string(p))
		if d is Dictionary:
			accounts = d
	for k in accounts:
		for t in accounts[k].get("tokens", []):
			token_of[String(t)] = k

func _save_accounts() -> void:
	var p := data_dir + "/accounts.json"
	var f := FileAccess.open(p + ".tmp", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(accounts))
	f.close()
	DirAccess.rename_absolute(p + ".tmp", p)
	_dirty = false

static func _pbkdf2(pw: PackedByteArray, salt: PackedByteArray, rounds: int) -> PackedByteArray:
	var c := Crypto.new()
	var u := c.hmac_digest(HashingContext.HASH_SHA256, pw, salt + PackedByteArray([0, 0, 0, 1]))
	var out := u.duplicate()
	for i in rounds - 1:
		u = c.hmac_digest(HashingContext.HASH_SHA256, pw, u)
		for j in 32:
			out[j] = out[j] ^ u[j]
	return out

func _hash(ph: String, salt_hex: String) -> String:
	return _pbkdf2(ph.to_utf8_buffer(), salt_hex.hex_decode(), PBKDF2_ROUNDS).hex_encode()

func _random_hex(n: int) -> String:
	return Crypto.new().generate_random_bytes(n).hex_encode()

func _info() -> Dictionary:
	var t := count_t if count_t >= 0.0 else -1.0
	return {"state": "count" if count_t >= 0.0 else "wait", "n": queue.size(), "t": t, "online": by_peer.size(), "battles": battles.size(), "max": ROOM_MAX}

func _sender_ok() -> int:
	## the peer of the current request, or 0 when it may not talk to the master yet
	if role != "master":
		return 0
	var id := multiplayer.get_remote_sender_id()
	return id if hello_ok.has(id) else 0

func _deny(id: int, msg: String, drop := false) -> void:
	rpc_id(id, "c_denied", msg, drop)

func _too_many(id: int) -> bool:
	var f: Array = _fails.get(id, [0, 0])
	if Time.get_ticks_msec() - int(f[1]) > 60000:
		_fails.erase(id)
		return false
	return int(f[0]) >= 5

func _failed_once(id: int) -> void:
	var f: Array = _fails.get(id, [0, Time.get_ticks_msec()])
	_fails[id] = [int(f[0]) + 1, int(f[1])]

@rpc("any_peer", "call_remote", "reliable")
func m_hello(proto: int, version: String) -> void:
	if role != "master":
		return
	var id := multiplayer.get_remote_sender_id()
	if proto != PROTOCOL:
		_deny(id, "نسخة اللعبة (%s) لا تطابق الخادم — حدّث اللعبة لتلعب أونلاين" % version)
		return
	hello_ok[id] = true

@rpc("any_peer", "call_remote", "reliable")
func m_register(name: String, ph: String, profile: Dictionary) -> void:
	var id := _sender_ok()
	if id == 0:
		return
	name = name.strip_edges()
	var key := name.to_lower()
	if not name_ok(name) or ph.length() != 64:
		_deny(id, "الاسم من 3 إلى 16 حرفاً: حروف عربية أو إنجليزية وأرقام و _")
		return
	if accounts.has(key):
		_deny(id, "الاسم «%s» مستخدم — اختر اسماً آخر" % name)
		return
	if int(_made.get(id, 0)) >= 2:
		_deny(id, "أنشأت حسابات كافية من هذا الاتصال")
		return
	_made[id] = int(_made.get(id, 0)) + 1
	var salt := _random_hex(16)
	accounts[key] = {"name": name, "salt": salt, "hash": _hash(ph, salt), "tokens": [], "profile": _clean(profile), "created": int(Time.get_unix_time_from_system())}
	print("[online] new account %s (%d)" % [name, accounts.size()])
	_welcome(id, key, "")

@rpc("any_peer", "call_remote", "reliable")
func m_login(name: String, ph: String) -> void:
	var id := _sender_ok()
	if id == 0:
		return
	if _too_many(id):
		_deny(id, "محاولات كثيرة — انتظر دقيقة ثم حاول")
		return
	var key := name.strip_edges().to_lower()
	var acc = accounts.get(key, null)
	if acc == null or _hash(ph, String(acc["salt"])) != String(acc["hash"]):
		_failed_once(id)
		_deny(id, "اسم المستخدم أو كلمة المرور غير صحيحة")
		return
	_welcome(id, key, "")

@rpc("any_peer", "call_remote", "reliable")
func m_resume(token: String) -> void:
	var id := _sender_ok()
	if id == 0:
		return
	var key = token_of.get(token, null)
	if key == null or not accounts.has(key):
		_deny(id, "انتهت الجلسة — سجّل الدخول من جديد", true)
		return
	_welcome(id, String(key), token)

func _welcome(id: int, key: String, token: String) -> void:
	var acc: Dictionary = accounts[key]
	# one connection per account: an older one (another phone, a dropped link) is closed
	for p in by_peer.keys():
		if by_peer[p] == key and p != id:
			rpc_id(p, "c_denied", "تم تسجيل الدخول بحسابك من جهاز آخر", false)
			_drop_peer(p)
			multiplayer.multiplayer_peer.disconnect_peer(p)
	if token == "":
		token = _random_hex(24)
		var tl: Array = acc.get("tokens", [])
		tl.append(token)
		while tl.size() > 6:
			token_of.erase(String(tl.pop_front()))
		acc["tokens"] = tl
		token_of[token] = key
		_dirty = true
	by_peer[id] = key
	rpc_id(id, "c_welcome", token, String(acc["name"]), acc.get("profile", {}), _info())

@rpc("any_peer", "call_remote", "reliable")
func m_logout(token: String) -> void:
	var id := _sender_ok()
	if id == 0 or not by_peer.has(id):
		return
	var key: String = by_peer[id]
	var tl: Array = accounts[key].get("tokens", [])
	tl.erase(token)
	token_of.erase(token)
	_dirty = true
	_drop_peer(id)

@rpc("any_peer", "call_remote", "reliable")
func m_save(profile: Dictionary) -> void:
	var id := _sender_ok()
	if id == 0 or not by_peer.has(id):
		return
	accounts[by_peer[id]]["profile"] = _clean(profile)
	_dirty = true

func _clean(p: Dictionary) -> Dictionary:
	## a profile as the master keeps it: known keys only, sane sizes
	var out := {}
	for k in ["credits", "cases", "matches", "wins", "kills", "uid"]:
		if p.has(k) and (typeof(p[k]) == TYPE_INT or typeof(p[k]) == TYPE_FLOAT):
			out[k] = clampi(int(p[k]), 0, 2000000000)
	if p.get("inv", null) is Array:
		var inv: Array = []
		for s in p["inv"]:
			if typeof(s) == TYPE_STRING and String(s).length() < 40 and inv.size() < 400:
				inv.append(String(s))
		out["inv"] = inv
	if p.get("equip", null) is Dictionary and JSON.stringify(p["equip"]).length() < 4000:
		out["equip"] = p["equip"]
	return out

func _state_of(key: String) -> String:
	for p in by_peer:
		if by_peer[p] == key:
			return "online"
	for port in battles:
		if key in battles[port].get("keys", []):
			return "battle"
	return "off"

func _send_friends(id: int) -> void:
	var key: String = by_peer[id]
	var out: Array = []
	for f in accounts[key].get("friends", []):
		if accounts.has(f):
			out.append({"name": String(accounts[f]["name"]), "state": _state_of(f)})
	rpc_id(id, "c_friends", out)

@rpc("any_peer", "call_remote", "reliable")
func m_friends() -> void:
	var id := _sender_ok()
	if id != 0 and by_peer.has(id):
		_send_friends(id)

@rpc("any_peer", "call_remote", "reliable")
func m_search(q: String) -> void:
	var id := _sender_ok()
	if id == 0 or not by_peer.has(id):
		return
	q = q.to_lower().substr(0, 16)
	var out: Array = []
	for k in accounts:
		if String(k).contains(q) and k != by_peer[id]:
			out.append(String(accounts[k]["name"]))
			if out.size() >= 20:
				break
	rpc_id(id, "c_found", out)

@rpc("any_peer", "call_remote", "reliable")
func m_add_friend(name: String) -> void:
	var id := _sender_ok()
	if id == 0 or not by_peer.has(id):
		return
	var me: String = by_peer[id]
	var k := name.strip_edges().to_lower()
	if not accounts.has(k) or k == me:
		return
	var fl: Array = accounts[me].get("friends", [])
	if not k in fl and fl.size() < 200:
		fl.append(k)
		accounts[me]["friends"] = fl
		_dirty = true
	_send_friends(id)

@rpc("any_peer", "call_remote", "reliable")
func m_remove_friend(name: String) -> void:
	var id := _sender_ok()
	if id == 0 or not by_peer.has(id):
		return
	var fl: Array = accounts[by_peer[id]].get("friends", [])
	fl.erase(name.strip_edges().to_lower())
	_dirty = true
	_send_friends(id)

@rpc("any_peer", "call_remote", "reliable")
func m_queue(outfit: int, _map_name: String) -> void:
	var id := _sender_ok()
	if id == 0 or not by_peer.has(id):
		return
	for q in queue:
		if q["peer"] == id:
			return
	queue.append({"peer": id, "outfit": clampi(outfit, 0, 7)})
	if count_t < 0.0:
		count_t = countdown
	if queue.size() >= ROOM_MAX:
		count_t = minf(count_t, COUNTDOWN_FULL)
	_push_room()

@rpc("any_peer", "call_remote", "reliable")
func m_unqueue() -> void:
	var id := _sender_ok()
	if id == 0:
		return
	_unqueue(id)
	_push_room()

func _unqueue(id: int) -> void:
	for i in range(queue.size() - 1, -1, -1):
		if queue[i]["peer"] == id:
			queue.remove_at(i)
	if queue.is_empty():
		count_t = -1.0

func _drop_peer(id: int) -> void:
	_unqueue(id)
	by_peer.erase(id)

func _on_peer_gone(id: int) -> void:
	if role == "master":
		_drop_peer(id)
		hello_ok.erase(id)
		_fails.erase(id)
		_made.erase(id)

func _push_room() -> void:
	var info := _info()
	for q in queue:
		rpc_id(q["peer"], "c_room", info)

func _process(dt: float) -> void:
	match role:
		"master":
			_master_tick(dt)
		"battle":
			_battle_tick(dt)
		_:
			_client_tick(dt)

func _client_tick(dt: float) -> void:
	if _retry >= 0.0:
		_retry -= dt
		if _retry < 0.0 and cstate == C.OFF and not playing:
			resume()
	if _sync_t >= 0.0:
		_sync_t -= dt
		if _sync_t < 0.0:
			_push_profile()

func _master_tick(dt: float) -> void:
	if count_t >= 0.0:
		count_t -= dt
		if count_t <= 0.0:
			count_t = -1.0
			_launch()
	_room_t += dt
	if _room_t >= 1.0:
		_room_t = 0.0
		_push_room()
	for port in battles.keys():
		var b: Dictionary = battles[port]
		b["t"] = float(b["t"]) + dt
		if not OS.is_process_running(int(b["pid"])):
			print("[online] battle on %d ended" % port)
			if not b["sent"]:
				for q in b["group"]:
					if by_peer.has(q["peer"]):
						rpc_id(q["peer"], "c_notice", "تعذّر تشغيل المعركة — حاول مرة أخرى")
			battles.erase(port)
			continue
		if not b["sent"] and FileAccess.file_exists("%s/battles/%d.ready" % [data_dir, port]):
			b["sent"] = true
			for q in b["group"]:
				if by_peer.has(q["peer"]):
					rpc_id(q["peer"], "c_go", int(port), String(q["ticket"]), String(b["map"]))
		elif not b["sent"] and float(b["t"]) > 90.0:
			OS.kill(int(b["pid"]))
	_save_t += dt
	if _dirty and _save_t > 3.0:
		_save_t = 0.0
		_save_accounts()

func _launch() -> void:
	## the countdown ran out: the room goes to a battle of its own (the empty seats are bots)
	var group := queue.slice(0, ROOM_MAX)
	queue = queue.slice(ROOM_MAX)
	if not queue.is_empty():
		count_t = countdown
	if group.is_empty():
		return
	var port := 0
	for i in range(1, BATTLE_PORTS + 1):
		if battles.size() >= max_battles:
			break
		if not battles.has(PORT + i):
			port = PORT + i
			break
	if port == 0:
		for q in group:
			rpc_id(q["peer"], "c_notice", "كل الخوادم مشغولة — ستبدأ معركتك بعد قليل")
		queue = group + queue
		count_t = 15.0
		return
	var tk := {}
	for q in group:
		q["ticket"] = _random_hex(16)
		tk[q["ticket"]] = {"name": String(accounts[by_peer[q["peer"]]]["name"]), "outfit": int(q["outfit"])}
	var map_name := "island"
	var f := FileAccess.open("%s/battles/%d.json" % [data_dir, port], FileAccess.WRITE)
	f.store_string(JSON.stringify({"tickets": tk, "map": map_name}))
	f.close()
	DirAccess.remove_absolute("%s/battles/%d.ready" % [data_dir, port])
	var args: PackedStringArray = []
	if not OS.has_feature("template"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--headless", "--", "--battle", "--port", str(port), "--data", data_dir])
	if G.args.has("ws"):
		args.append_array(["--ws", "--bind", String(G.args.get("bind", "*"))])
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		for q in group:
			rpc_id(q["peer"], "c_notice", "تعذّر تشغيل المعركة على الخادم")
		return
	var keys: Array = []
	for q in group:
		keys.append(by_peer.get(q["peer"], ""))
	battles[port] = {"pid": pid, "group": group, "t": 0.0, "sent": false, "map": map_name, "keys": keys}
	print("[online] battle on %d: %d players, pid %d" % [port, group.size(), pid])
	for q in group:
		rpc_id(q["peer"], "c_room", {"state": "launch", "n": group.size(), "t": 0.0, "online": by_peer.size(), "battles": battles.size(), "max": ROOM_MAX})

# ================================================================== battle
func start_battle_server() -> void:
	role = "battle"
	G.args["nosave"] = "1"
	_data_dir()
	battle_port = int(G.args.get("port", PORT + 1))
	var d = JSON.parse_string(FileAccess.get_file_as_string("%s/battles/%d.json" % [data_dir, battle_port]))
	if not (d is Dictionary):
		printerr("[online] battle %d: no room file" % battle_port)
		get_tree().quit(1)
		return
	tickets = d["tickets"]
	G.settings["br_map"] = String(d.get("map", "island"))
	G.settings["outfit"] = randi() % 8
	var peer := _server_peer(battle_port, ROOM_MAX + 2)
	if peer == null:
		printerr("[online] battle cannot open port %d" % battle_port)
		get_tree().quit(1)
		return
	(multiplayer as SceneMultiplayer).server_relay = false
	multiplayer.multiplayer_peer = peer
	print("[online] battle on port %d for %d players" % [battle_port, tickets.size()])
	G.start_match()

func battle_world_ready() -> void:
	## BRMatch built the world: the master may send the players over
	var f := FileAccess.open("%s/battles/%d.ready" % [data_dir, battle_port], FileAccess.WRITE)
	f.store_string("1")
	f.close()
	_wait_t = READY_WAIT

func use_ticket(ticket: String) -> Dictionary:
	var t = tickets.get(ticket, null)
	if t == null or t.get("used", false):
		return {}
	t["used"] = true
	return t

func all_in() -> bool:
	for k in tickets:
		if not tickets[k].get("used", false):
			return false
	return true

func battle_done(after: float) -> void:
	if _end_t < 0.0 or after < _end_t:
		_end_t = after

func _battle_tick(dt: float) -> void:
	_life_t += dt
	if _wait_t >= 0.0:
		_wait_t -= dt
		if _wait_t < 0.0:
			var sc := get_tree().current_scene
			var net = sc.get_node_or_null("Net") if sc else null
			if net and not net.started:
				if net.ready_count() == 0:
					print("[online] battle %d: nobody came" % battle_port)
					battle_done(0.5)
				else:
					net.host_start()
	if _end_t >= 0.0:
		_end_t -= dt
		if _end_t < 0.0:
			_quit_battle()
	if _life_t > 45.0 * 60.0:
		_quit_battle()

func _quit_battle() -> void:
	print("[online] battle %d closing" % battle_port)
	DirAccess.remove_absolute("%s/battles/%d.ready" % [data_dir, battle_port])
	DirAccess.remove_absolute("%s/battles/%d.json" % [data_dir, battle_port])
	get_tree().quit()
