extends Node
## Online account (Firebase Auth over REST).
## Google sign-in: the game serves a tiny page on http://localhost:<port>, opens it in the
## player's browser, the page signs in with Google through the Firebase JS SDK and posts the
## tokens back to the game. Guest sign-in uses Firebase anonymous auth.

signal signed_in
signal auth_failed(msg: String)
signal signed_out
signal friends_changed

const Rtdb = preload("res://scripts/net/rtdb.gd")

const API_KEY := "AIzaSyBithXc9Zl3DYNldAOi20AupBAGnjMAQao"
const AUTH_DOMAIN := "ms-company-e7166.firebaseapp.com"
const PROJECT_ID := "ms-company-e7166"
const DB_URL := "https://ms-company-e7166-default-rtdb.europe-west1.firebasedatabase.app"
const APP_ID := "1:400730863326:web:c32de5f96692532112744f"
const SENDER_ID := "400730863326"
const AUTH_PATH := "user://auth.cfg"
const PORTS := [53682, 53683, 53684, 53685]

var uid := ""
var id_token := ""
var refresh_token := ""
var token_expiry := 0.0
var display_name := ""
var email := ""
var photo := ""
var guest := true

var db                      # Rtdb client
var mock := false           # local test database (--mockdb=URL --uid=NAME)
var server_offset := 0.0    # server time - local time (ms)
var friend_code := ""
var friends: Array = []     # [{uid, name, online, status}]
var requests: Array = []    # [{uid, name}]
var match_id := ""          # current online match (set by the lobby)
var join_target := ""       # a friend's lobby to join (set by the friends screen)
var last_error := ""        # last auth error (shown to the player)
var match_team := ""
var comp_mode := false     # competitive rounds (buy, live, end, first to 8) instead of the default match
var _hb_t := 0.0
var _fr_t := 0.0
var _presence_started := false

var _server: TCPServer
var _port := 0
var _clients: Array = []
var _wait_t := 0.0


var offline_mode := false    # playing solo without an account / internet


func is_signed_in() -> bool:
	return uid != "" and refresh_token != ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	db = Rtdb.new()
	add_child(db)
	var url := DB_URL
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mockdb="):
			url = a.substr(9)
			mock = true
	db.setup(url, func() -> String: return "" if mock else id_token)
	if mock:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--uid="):
				uid = a.substr(6)
		if uid == "":
			uid = "test%d" % (randi() % 10000)
		refresh_token = "mock"
		display_name = uid.to_upper()
		guest = true
		Game.player.name = display_name
		_start_presence.call_deferred()
		return
	_load()
	signed_in.connect(_start_presence)
	if Game.reset_pending:
		_fresh_start.call_deferred()
	elif is_signed_in():
		_resume_presence.call_deferred()


## One-time fresh start: removes this account's friends and requests from the server, then signs out
## so the player signs in again and chooses a name.
func _fresh_start() -> void:
	if is_signed_in() and await resume():
		var r: Array = await db.call_async("misc", HTTPClient.METHOD_GET, "friends/" + uid)
		if r[0] is Dictionary:
			for fid in (r[0] as Dictionary).keys():
				await db.call_async("misc", HTTPClient.METHOD_DELETE, "friends/%s/%s" % [str(fid), uid])
		await db.call_async("misc", HTTPClient.METHOD_DELETE, "friends/" + uid)
		await db.call_async("misc", HTTPClient.METHOD_DELETE, "requests/" + uid)
	if is_signed_in():
		sign_out()
	Game.reset_pending = false
	Game.player.reset_v3 = true
	Game.save_data()


func _resume_presence() -> void:
	if await resume():
		_start_presence()


func now_ms() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + server_offset


## Presence: profile, friend code, online flag + heartbeat.
func _start_presence() -> void:
	if not is_signed_in():
		return
	_presence_started = true
	friend_code = uid.md5_text().left(6).to_upper()
	db.request("misc", HTTPClient.METHOD_PUT, "codes/" + friend_code, uid)
	var t0 := Time.get_unix_time_from_system() * 1000.0
	var r: Array = await db.call_async("misc", HTTPClient.METHOD_PATCH, "users/" + uid,
		{"name": display_name, "code": friend_code, "online": true, "status": "lobby", "ts": {".sv": "timestamp"}})
	if r[1] and r[0] is Dictionary and r[0].has("ts"):
		server_offset = float(r[0].ts) - (t0 + Time.get_unix_time_from_system() * 1000.0) * 0.5
	refresh_friends()


func set_status(st: String) -> void:
	if _presence_started:
		db.request("misc", HTTPClient.METHOD_PATCH, "users/" + uid, {"status": st, "online": true, "ts": {".sv": "timestamp"}})


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_cleanly()


func _quit_cleanly() -> void:
	if _presence_started:
		if match_id != "":
			db.request("misc", HTTPClient.METHOD_DELETE, "matches/%s/players/%s" % [match_id, uid])
			db.request("misc", HTTPClient.METHOD_DELETE, "matches/%s/p/%s" % [match_id, uid])
		db.request("misc", HTTPClient.METHOD_PATCH, "users/" + uid, {"online": false, "ts": {".sv": "timestamp"}})
		var t := 0.0
		while db.pending("misc") > 0 and t < 2.0:
			await get_tree().process_frame
			t += get_process_delta_time()
	get_tree().quit()


# ---------------------------------------------------------------- friends (real players)
func refresh_friends() -> void:
	if not _presence_started:
		return
	var r: Array = await db.call_async("misc", HTTPClient.METHOD_GET, "friends/" + uid)
	var ids: Array = (r[0] as Dictionary).keys() if r[0] is Dictionary else []
	var out: Array = []
	for fid in ids:
		var u: Array = await db.call_async("misc", HTTPClient.METHOD_GET, "users/" + str(fid))
		var d: Dictionary = u[0] if u[0] is Dictionary else {}
		var fresh: bool = d.get("online", false) and now_ms() - float(d.get("ts", 0)) < 90000.0
		out.append({"uid": fid, "name": str(d.get("name", "PLAYER")), "online": fresh, "status": str(d.get("status", "")) if fresh else "offline",
			"lobby": str(d.get("lobby", "")) if fresh else ""})
	out.sort_custom(func(a, b): return int(a.online) > int(b.online))
	friends = out
	var rq: Array = await db.call_async("misc", HTTPClient.METHOD_GET, "requests/" + uid)
	requests = []
	if rq[0] is Dictionary:
		for k in rq[0]:
			requests.append({"uid": k, "name": str(rq[0][k])})
	friends_changed.emit()


## the lobby we are waiting in, visible to friends so they can join it ("" when not in one)
func set_lobby(mid: String) -> void:
	if _presence_started:
		db.request("misc", HTTPClient.METHOD_PATCH, "users/" + uid, {"lobby": mid})


func online_friends() -> int:
	var n := 0
	for f in friends:
		if f.online:
			n += 1
	return n


## Returns "" on success or an error message.
func send_friend_request(code: String) -> String:
	code = code.strip_edges().to_upper()
	if code.length() != 6:
		return "Friend codes have 6 characters."
	if code == friend_code:
		return "That's your own code."
	var r: Array = await db.call_async("misc", HTTPClient.METHOD_GET, "codes/" + code)
	if not r[1]:
		return "No connection to the server."
	if r[0] == null:
		return "No player with that code."
	var fid := str(r[0])
	await db.call_async("misc", HTTPClient.METHOD_PUT, "requests/%s/%s" % [fid, uid], display_name)
	return ""


func accept_friend(fid: String) -> void:
	await db.call_async("misc", HTTPClient.METHOD_PUT, "friends/%s/%s" % [uid, fid], true)
	await db.call_async("misc", HTTPClient.METHOD_PUT, "friends/%s/%s" % [fid, uid], true)
	await db.call_async("misc", HTTPClient.METHOD_DELETE, "requests/%s/%s" % [uid, fid])
	refresh_friends()


func decline_friend(fid: String) -> void:
	await db.call_async("misc", HTTPClient.METHOD_DELETE, "requests/%s/%s" % [uid, fid])
	refresh_friends()


func remove_friend(fid: String) -> void:
	await db.call_async("misc", HTTPClient.METHOD_DELETE, "friends/%s/%s" % [uid, fid])
	await db.call_async("misc", HTTPClient.METHOD_DELETE, "friends/%s/%s" % [fid, uid])
	refresh_friends()


# ---------------------------------------------------------------- persistence
func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(AUTH_PATH) != OK:
		return
	uid = cf.get_value("auth", "uid", "")
	refresh_token = cf.get_value("auth", "refresh", "")
	display_name = cf.get_value("auth", "name", "")
	email = cf.get_value("auth", "email", "")
	photo = cf.get_value("auth", "photo", "")
	guest = cf.get_value("auth", "guest", true)
	if display_name != "":
		Game.player.name = display_name


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("auth", "uid", uid)
	cf.set_value("auth", "refresh", refresh_token)
	cf.set_value("auth", "name", display_name)
	cf.set_value("auth", "email", email)
	cf.set_value("auth", "photo", photo)
	cf.set_value("auth", "guest", guest)
	cf.save(AUTH_PATH)


func sign_out() -> void:
	if _presence_started:
		db.request("misc", HTTPClient.METHOD_PATCH, "users/" + uid, {"online": false})
	_presence_started = false
	friends = []
	requests = []
	uid = ""
	id_token = ""
	refresh_token = ""
	display_name = ""
	email = ""
	photo = ""
	guest = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AUTH_PATH))
	signed_out.emit()


func _set_profile_name(n: String) -> void:
	display_name = n.strip_edges().to_upper().left(16)
	if display_name == "":
		display_name = "GUEST-" + uid.left(4).to_upper()
	Game.player.name = display_name
	Game.save_data()


# ---------------------------------------------------------------- REST helpers
func _post_json(url: String, body: Dictionary, form := false) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 20.0
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/x-www-form-urlencoded" if form else "Content-Type: application/json"])
	var payload := ""
	if form:
		var parts: Array = []
		for k in body:
			parts.append("%s=%s" % [k, str(body[k]).uri_encode()])
		payload = "&".join(parts)
	else:
		payload = JSON.stringify(body)
	var err := http.request(url, headers, HTTPClient.METHOD_POST, payload)
	if err != OK:
		http.queue_free()
		return {"error": {"message": "NETWORK_ERROR"}}
	var res: Array = await http.request_completed
	http.queue_free()
	var txt: String = (res[3] as PackedByteArray).get_string_from_utf8()
	var parsed = JSON.parse_string(txt)
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": {"message": "NO_CONNECTION"}}
	return parsed if parsed is Dictionary else {"error": {"message": "BAD_RESPONSE"}}


## Returns a valid ID token (refreshes it when it is about to expire).
func get_token() -> String:
	if refresh_token == "":
		return ""
	if id_token != "" and Time.get_unix_time_from_system() < token_expiry - 60.0:
		return id_token
	var r := await _post_json("https://securetoken.googleapis.com/v1/token?key=" + API_KEY,
		{"grant_type": "refresh_token", "refresh_token": refresh_token}, true)
	if r.has("error"):
		var e = r.error
		last_error = str(e.get("message", e)) if e is Dictionary else str(e)
		return ""
	last_error = ""
	id_token = str(r.get("id_token", ""))
	refresh_token = str(r.get("refresh_token", refresh_token))
	uid = str(r.get("user_id", uid))
	token_expiry = Time.get_unix_time_from_system() + float(r.get("expires_in", "3600"))
	_save()
	return id_token


## Called at startup: confirms the saved session still works.
func resume() -> bool:
	if not is_signed_in():
		return false
	var t := await get_token()
	return t != ""


# ---------------------------------------------------------------- guest
func sign_in_guest() -> void:
	var r := await _post_json("https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=" + API_KEY, {"returnSecureToken": true})
	if r.has("error"):
		auth_failed.emit(_explain(str(r.error.get("message", ""))))
		return
	uid = str(r.localId)
	id_token = str(r.idToken)
	refresh_token = str(r.refreshToken)
	token_expiry = Time.get_unix_time_from_system() + float(r.get("expiresIn", "3600"))
	guest = true
	email = ""
	photo = ""
	_set_profile_name("")
	_save()
	signed_in.emit()


func _explain(code: String) -> String:
	if code.contains("ADMIN_ONLY_OPERATION") or code.contains("OPERATION_NOT_ALLOWED"):
		return "Guest sign-in is disabled in Firebase (enable Anonymous)."
	if code.contains("NO_CONNECTION") or code.contains("NETWORK"):
		return "No internet connection."
	return "Sign-in failed: " + code


# ---------------------------------------------------------------- google (browser)
func sign_in_google() -> void:
	stop_google()
	_server = TCPServer.new()
	_port = 0
	for p in PORTS:
		if _server.listen(p, "127.0.0.1") == OK:
			_port = p
			break
	if _port == 0:
		_server = null
		auth_failed.emit("Could not open the login page (ports busy).")
		return
	_wait_t = 300.0
	OS.shell_open("http://localhost:%d/login" % _port)


func stop_google() -> void:
	for c in _clients:
		(c.peer as StreamPeerTCP).disconnect_from_host()
	_clients.clear()
	if _server:
		_server.stop()
		_server = null


func google_waiting() -> bool:
	return _server != null


func login_url() -> String:
	return "http://localhost:%d/login" % _port


func _process(delta: float) -> void:
	if _presence_started:
		_hb_t -= delta
		if _hb_t <= 0.0:
			_hb_t = 30.0
			db.request("misc", HTTPClient.METHOD_PATCH, "users/" + uid, {"online": true, "ts": {".sv": "timestamp"}}, Callable(), "", "hb")
		_fr_t -= delta
		if _fr_t <= 0.0:
			_fr_t = 20.0
			refresh_friends()
		if not mock and refresh_token != "" and id_token != "" and Time.get_unix_time_from_system() > token_expiry - 120.0:
			token_expiry = Time.get_unix_time_from_system() + 600.0   # avoid re-entry while refreshing
			id_token = ""
			get_token()
	_google_process(delta)


func _google_process(delta: float) -> void:
	if _server == null:
		return
	_wait_t -= delta
	if _wait_t <= 0.0:
		stop_google()
		auth_failed.emit("Login timed out. Try again.")
		return
	while _server and _server.is_connection_available():
		var peer := _server.take_connection()
		_clients.append({"peer": peer, "buf": PackedByteArray(), "t": 10.0})
	for i in range(_clients.size() - 1, -1, -1):
		var c: Dictionary = _clients[i]
		var peer: StreamPeerTCP = c.peer
		peer.poll()
		c.t -= delta
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or c.t <= 0.0:
			_clients.remove_at(i)
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			var got: Array = peer.get_data(n)
			if got[0] == OK:
				c.buf.append_array(got[1])
		if _handle(c):
			peer.disconnect_from_host()
			_clients.remove_at(i)
		if _server == null:
			return


func _respond(peer: StreamPeerTCP, code: String, ctype: String, body: String) -> void:
	var b := body.to_utf8_buffer()
	var head := "HTTP/1.1 %s\r\nContent-Type: %s; charset=utf-8\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" % [code, ctype, b.size()]
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(b)


## Returns true once a full request was answered.
func _handle(c: Dictionary) -> bool:
	var raw: String = (c.buf as PackedByteArray).get_string_from_utf8()
	var sep := raw.find("\r\n\r\n")
	if sep < 0:
		return false
	var head := raw.substr(0, sep)
	var line := head.split("\r\n")[0]
	var parts := line.split(" ")
	if parts.size() < 2:
		return true
	var method := parts[0]
	var path := parts[1]
	var clen := 0
	for h in head.split("\r\n"):
		if h.to_lower().begins_with("content-length:"):
			clen = int(h.substr(15).strip_edges())
	var body_bytes := (c.buf as PackedByteArray).slice(sep + 4)
	if body_bytes.size() < clen:
		return false
	var peer: StreamPeerTCP = c.peer
	if method == "GET" and path.begins_with("/login"):
		_respond(peer, "200 OK", "text/html", _page())
	elif method == "POST" and path.begins_with("/token"):
		var d = JSON.parse_string(body_bytes.get_string_from_utf8())
		if d is Dictionary and d.has("refreshToken") and d.has("uid"):
			_respond(peer, "200 OK", "application/json", "{\"ok\":true}")
			_google_done(d)
		else:
			_respond(peer, "400 Bad Request", "application/json", "{\"ok\":false}")
	else:
		_respond(peer, "404 Not Found", "text/plain", "not found")
	return true


func _google_done(d: Dictionary) -> void:
	uid = str(d.uid)
	id_token = str(d.get("idToken", ""))
	refresh_token = str(d.refreshToken)
	token_expiry = Time.get_unix_time_from_system() + 3300.0
	email = str(d.get("email", ""))
	photo = str(d.get("photo", ""))
	guest = false
	var nm := str(d.get("name", ""))
	if nm == "":
		nm = email.get_slice("@", 0)
	_set_profile_name(nm)
	_save()
	# close the server a moment later so the page receives its reply
	get_tree().create_timer(1.0, true, false, true).timeout.connect(stop_google)
	signed_in.emit()
	# bring the game window back to the front
	DisplayServer.window_move_to_foreground()


func _page() -> String:
	var cfg := JSON.stringify({"apiKey": API_KEY, "authDomain": AUTH_DOMAIN, "projectId": PROJECT_ID, "appId": APP_ID, "messagingSenderId": SENDER_ID, "databaseURL": DB_URL})
	return """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Vorn City - Sign in</title>
<style>
body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#05080f;
font-family:Segoe UI,Arial,sans-serif;color:#e6edf5}
.card{width:min(420px,92vw);padding:40px 34px;background:#0b111c;border:1px solid #1d2a3c;border-radius:10px;text-align:center}
h1{margin:0 0 6px;font-size:28px;letter-spacing:3px}h1 span{color:#ff4062}h1 b{color:#4080ff}
p{color:#8b9bb0;margin:0 0 28px}
button{display:flex;align-items:center;justify-content:center;gap:12px;width:100%;padding:14px;font-size:17px;
border:0;border-radius:6px;background:#fff;color:#1f1f1f;cursor:pointer;font-weight:600}
button:disabled{opacity:.6;cursor:default}
#msg{margin-top:20px;min-height:24px;color:#8b9bb0}.ok{color:#4cf08a!important}.err{color:#ff6b6b!important}
</style></head><body><div class="card">
<h1><b>V</b>ORN CITY</h1><p>Sign in to live online with real players</p>
<button id="g"><svg width="20" height="20" viewBox="0 0 48 48"><path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3C33.7 32.7 29.2 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.8 1.2 7.9 3.1l5.7-5.7C34 6.1 29.3 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.4-.4-3.5z"/><path fill="#FF3D00" d="M6.3 14.7l6.6 4.8C14.7 15.1 19 12 24 12c3.1 0 5.8 1.2 7.9 3.1l5.7-5.7C34 6.1 29.3 4 24 4 16.3 4 9.7 8.3 6.3 14.7z"/><path fill="#4CAF50" d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-8l-6.5 5C9.5 39.6 16.2 44 24 44z"/><path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.2-2.2 4.2-4.1 5.6l6.2 5.2C37 39.2 44 34 44 24c0-1.3-.1-2.4-.4-3.5z"/></svg>Sign in with Google</button>
<div id="msg"></div></div>
<script src="https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js"></script>
<script src="https://www.gstatic.com/firebasejs/10.12.2/firebase-auth-compat.js"></script>
<script>
const cfg = __CFG__;
const msg = document.getElementById('msg'), btn = document.getElementById('g');
function say(t, c){ msg.textContent = t; msg.className = c || ''; }
firebase.initializeApp(cfg);
const auth = firebase.auth();
auth.setPersistence(firebase.auth.Auth.Persistence.NONE);
async function send(u){
  say('Signing in to the game...');
  const r = await fetch('/token', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({
    uid: u.uid, idToken: await u.getIdToken(), refreshToken: u.refreshToken,
    name: u.displayName || '', email: u.email || '', photo: u.photoURL || ''})});
  if (!r.ok) throw new Error('game did not accept the login');
  say('Done! You can close this tab and go back to the game.', 'ok');
  btn.style.display = 'none';
  setTimeout(() => window.close(), 1500);
}
btn.onclick = async () => {
  btn.disabled = true; say('Opening Google...');
  try {
    const p = new firebase.auth.GoogleAuthProvider();
    p.setCustomParameters({prompt: 'select_account'});
    const res = await auth.signInWithPopup(p);
    await send(res.user);
  } catch (e) {
    btn.disabled = false;
    let t = e && e.code ? e.code : String(e);
    if (t.includes('operation-not-allowed')) t = 'Google sign-in is not enabled in Firebase yet.';
    else if (t.includes('popup-closed')) t = 'Sign-in window was closed. Try again.';
    else if (t.includes('unauthorized-domain')) t = 'localhost is not an authorized domain in Firebase.';
    else if (t.includes('Failed to fetch')) t = 'The game is not running. Open the game and try again.';
    say(t, 'err');
  }
};
</script></body></html>""".replace("__CFG__", cfg)
