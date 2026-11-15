#!/usr/bin/env bash
# AURUM MOBILE online server: one-command install on a fresh Ubuntu machine (x86_64 or ARM64, e.g. Oracle Cloud free).
#   curl -fsSL https://raw.githubusercontent.com/mujahidsa-w/Vorn/claude/game-pubg-animation-ffzj2v/server/setup_ubuntu.sh | sudo bash
# Run it again later to update the server to the latest version of the game.
set -euo pipefail
REPO="${REPO:-https://github.com/mujahidsa-w/Vorn.git}"
BRANCH="${BRANCH:-claude/game-pubg-animation-ffzj2v}"
GODOT_VERSION=4.6.2
DIR=/opt/aurum
DATA=/var/lib/aurum

export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q git curl unzip ca-certificates libfontconfig1 iptables-persistent >/dev/null

# the game (only what the server needs is used, but the whole project is small enough)
if [ -d "$DIR/.git" ]; then
  git -C "$DIR" fetch -q --depth 1 origin "$BRANCH"
  git -C "$DIR" reset -q --hard FETCH_HEAD
else
  git clone -q --depth 1 --branch "$BRANCH" "$REPO" "$DIR"
fi

# Godot for this processor
case "$(uname -m)" in
  aarch64|arm64) GARCH=arm64 ;;
  *) GARCH=x86_64 ;;
esac
if [ ! -x /usr/local/bin/godot ] || ! /usr/local/bin/godot --version 2>/dev/null | grep -q "^${GODOT_VERSION}"; then
  curl -fsSL --retry 3 -o /tmp/godot.zip \
    "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.${GARCH}.zip"
  unzip -q -o /tmp/godot.zip -d /tmp/godot
  install -m 755 /tmp/godot/Godot_v${GODOT_VERSION}-stable_linux.${GARCH} /usr/local/bin/godot
  rm -rf /tmp/godot /tmp/godot.zip
fi

id aurum >/dev/null 2>&1 || useradd --system --home "$DATA" --shell /usr/sbin/nologin aurum
mkdir -p "$DATA"
chown -R aurum:aurum "$DATA" "$DIR"
sudo -u aurum HOME="$DATA" godot --headless --path "$DIR" --import >/dev/null 2>&1 || true

# small machines (1 GB): add swap; battles at ~400 MB each
MEM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
if [ "$MEM_MB" -lt 3000 ] && [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap -q /swapfile && swapon /swapfile
  echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi
MAX_BATTLES=$(( (MEM_MB - 250) / 420 ))
[ "$MAX_BATTLES" -lt 1 ] && MAX_BATTLES=1
[ "$MAX_BATTLES" -gt 40 ] && MAX_BATTLES=40

cat > /etc/systemd/system/aurum.service <<UNIT
[Unit]
Description=AURUM MOBILE online server
After=network-online.target
Wants=network-online.target

[Service]
User=aurum
Environment=HOME=$DATA
ExecStart=/usr/local/bin/godot --headless --path $DIR -- --server --data $DATA --max_battles $MAX_BATTLES
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

# the game's UDP ports (Ubuntu images on Oracle Cloud reject everything not listed)
iptables -C INPUT -p udp --dport 24600:24640 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p udp --dport 24600:24640 -j ACCEPT
netfilter-persistent save >/dev/null 2>&1 || true

systemctl daemon-reload
systemctl enable aurum >/dev/null 2>&1
systemctl restart aurum
sleep 4
systemctl --no-pager --lines 5 status aurum || true
IP=$(curl -fsS --max-time 5 https://api.ipify.org || hostname -I | awk '{print $1}')
echo
echo "AURUM MOBILE server is running. Address for the game: $IP  (UDP 24600-24640, up to $MAX_BATTLES battles at once)"
