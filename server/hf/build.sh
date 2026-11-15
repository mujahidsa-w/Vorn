#!/usr/bin/env bash
# Image build for the Hugging Face Space (runs as root once): Godot, the web server, the account backup tool.
set -euo pipefail
GODOT_VERSION=4.6.2
export DEBIAN_FRONTEND=noninteractive
apt-get install -y --no-install-recommends curl unzip libfontconfig1 nginx-light python3 python3-pip >/dev/null
pip3 install --no-cache-dir --break-system-packages -q huggingface_hub
ARCH=$(uname -m | sed 's/aarch64/arm64/')
curl -fsSL --retry 3 -o /tmp/godot.zip \
  "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.${ARCH}.zip"
unzip -q /tmp/godot.zip -d /tmp/godot
install -m 755 "/tmp/godot/Godot_v${GODOT_VERSION}-stable_linux.${ARCH}" /usr/local/bin/godot
rm -rf /tmp/godot /tmp/godot.zip /var/lib/apt/lists/*
# import the project once, so the server starts at once
HOME=/tmp/import-home godot --headless --path /game --import >/dev/null 2>&1 || true
chmod -R a+rwX /game
