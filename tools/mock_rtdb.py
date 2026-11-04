#!/usr/bin/env python3
"""Tiny in-memory stand-in for the Firebase Realtime Database REST API (tests only)."""
import json, sys, time, threading, random, string
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

DB = {}
LOCK = threading.Lock()
PUSH_CHARS = "-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz"
_last = [0, ""]


def push_id():
    now = int(time.time() * 1000)
    ts = ""
    n = now
    for _ in range(8):
        ts = PUSH_CHARS[n % 64] + ts
        n //= 64
    if now == _last[0]:
        _last[1] = _last[1][:-1] + PUSH_CHARS[(PUSH_CHARS.index(_last[1][-1]) + 1) % 64]
    else:
        _last[1] = "".join(random.choice(PUSH_CHARS) for _ in range(12))
    _last[0] = now
    return ts + _last[1]


def resolve(v):
    if isinstance(v, dict):
        if v.get(".sv") == "timestamp":
            return int(time.time() * 1000)
        return {k: resolve(x) for k, x in v.items()}
    return v


def parts(path):
    return [p for p in path.strip("/").split("/") if p]


def get(path):
    node = DB
    for p in parts(path):
        if not isinstance(node, dict) or p not in node:
            return None
        node = node[p]
    return node


def put(path, val):
    ps = parts(path)
    if not ps:
        DB.clear()
        if isinstance(val, dict):
            DB.update(val)
        return
    node = DB
    for p in ps[:-1]:
        if not isinstance(node.get(p), dict):
            node[p] = {}
        node = node[p]
    if val is None:
        node.pop(ps[-1], None)
    else:
        node[ps[-1]] = val
    prune(DB)


def prune(n):
    if isinstance(n, dict):
        for k in list(n.keys()):
            prune(n[k])
            if n[k] == {} or n[k] is None:
                del n[k]


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _send(self, obj, code=200):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def _body(self):
        n = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(n) or b"null") if n else None

    def _path(self):
        u = urlparse(self.path)
        return u.path[:-5] if u.path.endswith(".json") else u.path, parse_qs(u.query)

    def do_GET(self):
        path, q = self._path()
        with LOCK:
            v = get(path)
            if isinstance(v, dict):
                if q.get("shallow") == ["true"]:
                    v = {k: True for k in v}
                if "orderBy" in q:
                    items = sorted(v.items())
                    if "startAt" in q:
                        s = json.loads(q["startAt"][0])
                        items = [i for i in items if i[0] >= s]
                    if "limitToLast" in q:
                        items = items[-int(q["limitToLast"][0]):]
                    v = dict(items)
            self._send(v)

    def do_PUT(self):
        path, _ = self._path()
        val = resolve(self._body())
        with LOCK:
            put(path, val)
        self._send(val)

    def do_PATCH(self):
        path, _ = self._path()
        val = resolve(self._body()) or {}
        with LOCK:
            for k, x in val.items():
                put(path.rstrip("/") + "/" + k, x)
        self._send(val)

    def do_POST(self):
        path, _ = self._path()
        val = resolve(self._body())
        k = push_id()
        with LOCK:
            put(path.rstrip("/") + "/" + k, val)
        self._send({"name": k})

    def do_DELETE(self):
        path, _ = self._path()
        with LOCK:
            put(path, None)
        self._send(None)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
