# AURUM MOBILE online server: accounts, the waiting room and the battles (one process per battle).
#   docker build -f server/Dockerfile -t aurum-server .
#   docker run -d --name aurum --restart unless-stopped -p 24600-24640:24600-24640/udp -v aurum-data:/data aurum-server
FROM ubuntu:24.04
ARG GODOT_VERSION=4.6.2
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
 && rm -rf /var/lib/apt/lists/* \
 && ARCH=$(uname -m | sed 's/aarch64/arm64/') \
 && curl -fL --retry 3 -o /tmp/godot.zip \
    "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.${ARCH}.zip" \
 && unzip -q /tmp/godot.zip -d /tmp \
 && mv "/tmp/Godot_v${GODOT_VERSION}-stable_linux.${ARCH}" /usr/local/bin/godot \
 && rm /tmp/godot.zip
WORKDIR /game
COPY . /game
# import once at build time so the server starts at once
RUN godot --headless --path /game --import || true
EXPOSE 24600-24640/udp
VOLUME /data
CMD ["godot", "--headless", "--path", "/game", "--", "--server", "--data", "/data"]
