#!/usr/bin/env bash
# The Space's process: web server on 7860 in front, the game's online server behind it (WebSocket),
# and the accounts backed up to a private dataset of the Space owner (secret HF_TOKEN; without it they live
# only until the Space restarts).
export HOME=/tmp/aurum-home
DATA=/tmp/aurum-data
mkdir -p "$HOME" "$DATA" /tmp/nginx
python3 /game/server/hf/sync.py restore "$DATA" || true
nginx -c /game/server/hf/nginx.conf
( while true; do sleep 60; python3 /game/server/hf/sync.py save "$DATA" || true; done ) &
SYNC=$!
godot --headless --path /game -- --server --ws --bind 127.0.0.1 --data "$DATA" --max_battles "${MAX_BATTLES:-4}" &
GAME=$!
trap 'python3 /game/server/hf/sync.py save "$DATA"; kill $GAME $SYNC 2>/dev/null; exit 0' TERM INT
wait $GAME
python3 /game/server/hf/sync.py save "$DATA" || true
