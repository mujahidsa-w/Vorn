# AURUM MOBILE online server — the only file a free Hugging Face Space (Gradio SDK) needs.
# It downloads the game from GitHub on every start (so a restart brings the newest version) and runs it.
import os
import subprocess
import sys

REPO = "https://github.com/mujahidsa-w/Vorn.git"
BRANCH = "claude/game-pubg-animation-ffzj2v"
GAME = os.environ.get("GAME_DIR", "/tmp/game")

if not os.path.isdir(os.path.join(GAME, ".git")):
    subprocess.run(["git", "clone", "--depth", "1", "-b", BRANCH, REPO, GAME], check=True)
subprocess.run([sys.executable, "-m", "pip", "install", "-q", "websockets"], check=False)
sys.path.insert(0, os.path.join(GAME, "server", "hf"))

import space_app  # noqa: E402

space_app.main()
