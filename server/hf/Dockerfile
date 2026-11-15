# AURUM MOBILE online server on a free Hugging Face Space (Docker, CPU basic).
# This is the only file the Space needs: create a Docker Space, add this file as "Dockerfile", and the Space builds
# the server from the game's GitHub repository. Settings -> "Factory rebuild" picks up a newer version of the game.
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
 && git clone --depth 1 -b claude/game-pubg-animation-ffzj2v https://github.com/mujahidsa-w/Vorn.git /game \
 && bash /game/server/hf/build.sh
USER 1000
EXPOSE 7860
CMD ["bash", "/game/server/hf/start.sh"]
