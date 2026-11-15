#!/usr/bin/env bash
# AURUM MOBILE online server on a Linux machine (VPS or home PC), without Docker.
#   ./server/run_server.sh            (from the project folder; keeps running, restarts if it stops)
# Open UDP ports 24600-24640 in the firewall / router. Accounts are kept in ./server_data.
set -u
cd "$(dirname "$0")/.."
GODOT_VERSION=4.6.2
GODOT="${GODOT:-$PWD/.server_bin/godot}"
if [ ! -x "$GODOT" ]; then
  mkdir -p .server_bin
  ARCH=$(uname -m | sed 's/aarch64/arm64/')
  curl -fL --retry 3 -o .server_bin/godot.zip \
    "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.${ARCH}.zip"
  unzip -q -o .server_bin/godot.zip -d .server_bin
  mv ".server_bin/Godot_v${GODOT_VERSION}-stable_linux.${ARCH}" "$GODOT"
  rm .server_bin/godot.zip
fi
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
mkdir -p server_data
while true; do
  "$GODOT" --headless --path . -- --server --data "$PWD/server_data"
  echo "server stopped ($?), restarting in 3 s"
  sleep 3
done
