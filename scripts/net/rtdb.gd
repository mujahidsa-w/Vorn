extends Node
## Minimal Firebase Realtime Database REST client with persistent (keep-alive)
## connections. Each lane is one HTTP connection that runs its requests in order,
## so position updates, polling and events don't block each other.

var base_url := ""          # https://xxx.firebasedatabase.app  (or http://127.0.0.1:port for tests)
var token_fn: Callable      # returns the current auth token ("" = none)
var lanes := {}


class Lane:
	var host := ""
	var port := 443
	var tls := true
	var client := HTTPClient.new()
	var queue: Array = []
	var cur = null
	var body := PackedByteArray()
	var connecting := false
	var fail_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup(url: String, tokf: Callable) -> void:
	base_url = url.trim_suffix("/")
	token_fn = tokf
	for l in lanes.values():
		(l.client as HTTPClient).close()
	lanes.clear()


func _lane(name: String) -> Lane:
	if lanes.has(name):
		return lanes[name]
	var l := Lane.new()
	var u := base_url
	l.tls = u.begins_with("https://")
	u = u.replace("https://", "").replace("http://", "")
	var hp := u.split(":")
	l.host = hp[0]
	l.port = int(hp[1]) if hp.size() > 1 else (443 if l.tls else 80)
	lanes[name] = l
	return l


## Queue a request. cb(result_variant, ok: bool) is called when it completes.
## If `replace_key` is set, a still-queued request with the same key is replaced
## (used for position updates: only the newest one matters).
func request(lane: String, method: int, path: String, body = null, cb := Callable(), query := "", replace_key := "") -> void:
	var l := _lane(lane)
	var r := {"m": method, "p": path, "b": body, "cb": cb, "q": query, "k": replace_key}
	if replace_key != "":
		for i in l.queue.size():
			if l.queue[i].k == replace_key:
				l.queue[i] = r
				return
	l.queue.append(r)


func pending(lane: String) -> int:
	if not lanes.has(lane):
		return 0
	var l: Lane = lanes[lane]
	return l.queue.size() + (1 if l.cur != null else 0)


## Awaitable helper: var res = await db.call_async("misc", HTTPClient.METHOD_GET, "users/x")
signal _done(id, res, ok)
var _next_id := 0


func call_async(lane: String, method: int, path: String, body = null, query := "") -> Array:
	_next_id += 1
	var id := _next_id
	request(lane, method, path, body, func(res, ok): _done.emit(id, res, ok), query)
	while true:
		var a: Array = await _done
		if a[0] == id:
			return [a[1], a[2]]
	return [null, false]


func _url(r: Dictionary) -> String:
	var tok: String = token_fn.call() if token_fn.is_valid() else ""
	var q := "?"
	if tok != "":
		q += "auth=" + tok.uri_encode() + "&"
	if r.q != "":
		q += r.q
	return "/" + str(r.p).trim_prefix("/") + ".json" + q.trim_suffix("&").trim_suffix("?")


func _process(delta: float) -> void:
	for l in lanes.values():
		_tick(l, delta)


func _finish(l: Lane, res, ok: bool) -> void:
	var r = l.cur
	l.cur = null
	l.body = PackedByteArray()
	if r != null and (r.cb as Callable).is_valid():
		(r.cb as Callable).call(res, ok)


func _tick(l: Lane, delta: float) -> void:
	var c := l.client
	if l.fail_t > 0.0:
		l.fail_t -= delta
		return
	c.poll()
	var st := c.get_status()
	match st:
		HTTPClient.STATUS_DISCONNECTED, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			if l.cur != null and c.has_response() and st == HTTPClient.STATUS_DISCONNECTED:
				# server closed the connection after answering
				var txt0 := l.body.get_string_from_utf8()
				var code0 := c.get_response_code()
				_finish(l, JSON.parse_string(txt0) if txt0 != "" else null, code0 >= 200 and code0 < 300)
			if l.cur != null:
				# connection dropped mid-request: retry it once on a fresh connection
				var r = l.cur
				l.cur = null
				if not r.get("retried", false):
					r["retried"] = true
					l.queue.push_front(r)
				elif (r.cb as Callable).is_valid():
					(r.cb as Callable).call(null, false)
			if l.queue.is_empty():
				return
			if st != HTTPClient.STATUS_DISCONNECTED:
				c.close()
				l.fail_t = 1.0
				return
			var opts: TLSOptions = TLSOptions.client() if l.tls else null
			if c.connect_to_host(l.host, l.port, opts) != OK:
				l.fail_t = 1.0
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING:
			pass
		HTTPClient.STATUS_CONNECTED:
			if l.cur != null:
				# response finished
				var txt := l.body.get_string_from_utf8()
				var code := c.get_response_code()
				var parsed = JSON.parse_string(txt) if txt != "" else null
				_finish(l, parsed, code >= 200 and code < 300)
			if l.queue.is_empty():
				return
			var r: Dictionary = l.queue.pop_front()
			var headers := PackedStringArray(["Content-Type: application/json", "Connection: keep-alive"])
			var payload := "" if r.b == null else JSON.stringify(r.b)
			if c.request(r.m, _url(r), headers, payload) != OK:
				if (r.cb as Callable).is_valid():
					(r.cb as Callable).call(null, false)
				c.close()
				return
			l.cur = r
			l.body = PackedByteArray()
		HTTPClient.STATUS_REQUESTING:
			pass
		HTTPClient.STATUS_BODY:
			var chunk := c.read_response_body_chunk()
			if chunk.size() > 0:
				l.body.append_array(chunk)
