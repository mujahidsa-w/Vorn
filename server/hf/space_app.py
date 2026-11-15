"""AURUM MOBILE online server inside a free Hugging Face Space (Gradio SDK).

The Space's own app.py (server/hf/app.py, the only file the Space needs) clones the game and calls main():
  - Godot is downloaded, the project imported, and the game's online server started behind (WebSocket, --ws);
  - the web port 7860 serves a small status page (Gradio) and passes the players' connections through:
      /m    -> the master (accounts, waiting room)        ws://127.0.0.1:24600
      /b/N  -> battle N (one process per battle)          ws://127.0.0.1:N
  - the accounts are backed up every minute to a private dataset <owner>/aurum-data when the Space has the secret
    HF_TOKEN (a token with write access); without it they last until the Space restarts.
"""
import asyncio
import hashlib
import os
import platform
import shutil
import subprocess
import threading
import time
import urllib.request
import zipfile

GAME = os.environ.get("GAME_DIR", "/tmp/game")
GODOT_VERSION = "4.6.2"
GODOT = os.environ.get("GODOT_BIN", "/tmp/godot/godot")
DATA = os.environ.get("AURUM_DATA", "/tmp/aurum-data")
HOME = "/tmp/aurum-home"
MASTER = 24600
MAX_BATTLES = int(os.environ.get("MAX_BATTLES", "4"))
state = {"phase": "جارٍ التجهيز", "since": time.time(), "restarts": 0, "saved": "-"}


def log(text):
    print("[space]", text, flush=True)


# ------------------------------------------------------------------ the game server
def ensure_godot():
    if os.path.exists(GODOT):
        return
    arch = "arm64" if platform.machine() in ("aarch64", "arm64") else "x86_64"
    url = ("https://github.com/godotengine/godot/releases/download/%s-stable/Godot_v%s-stable_linux.%s.zip"
           % (GODOT_VERSION, GODOT_VERSION, arch))
    folder = os.path.dirname(GODOT)
    os.makedirs(folder, exist_ok=True)
    archive = GODOT + ".zip"
    log("downloading Godot " + GODOT_VERSION)
    urllib.request.urlretrieve(url, archive)
    with zipfile.ZipFile(archive) as z:
        name = z.namelist()[0]
        z.extract(name, folder)
    os.replace(os.path.join(folder, name), GODOT)
    os.chmod(GODOT, 0o755)
    os.remove(archive)


def _hub():
    token = os.environ.get("HF_TOKEN", "").strip()
    if not token:
        return None, None, None
    from huggingface_hub import HfApi
    api = HfApi(token=token)
    repo = os.environ.get("DATASET", "").strip() or api.whoami()["name"] + "/aurum-data"
    return api, repo, token


def _digest(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


_last_saved = {"digest": ""}


def restore_accounts():
    try:
        api, repo, token = _hub()
        if api is None:
            log("no HF_TOKEN secret: accounts are kept until the Space restarts")
            return
        from huggingface_hub import hf_hub_download
        api.create_repo(repo, repo_type="dataset", private=True, exist_ok=True)
        path = os.path.join(DATA, "accounts.json")
        try:
            shutil.copy(hf_hub_download(repo, "accounts.json", repo_type="dataset", token=token), path)
            _last_saved["digest"] = _digest(path)
            log("accounts restored from " + repo)
        except Exception as e:
            log("no saved accounts yet (%s)" % type(e).__name__)
    except Exception as e:
        log("accounts restore failed: %s" % e)


def save_accounts():
    try:
        path = os.path.join(DATA, "accounts.json")
        if not os.path.exists(path):
            return
        digest = _digest(path)
        if digest == _last_saved["digest"]:
            return
        api, repo, _ = _hub()
        if api is None:
            return
        api.upload_file(path_or_fileobj=path, path_in_repo="accounts.json", repo_id=repo, repo_type="dataset",
                        commit_message="accounts")
        _last_saved["digest"] = digest
        state["saved"] = time.strftime("%H:%M UTC", time.gmtime())
        log("accounts saved to " + repo)
    except Exception as e:
        log("accounts save failed: %s" % e)


def run_server():
    os.makedirs(DATA, exist_ok=True)
    os.makedirs(HOME, exist_ok=True)
    env = dict(os.environ, HOME=HOME)
    try:
        ensure_godot()
        state["phase"] = "جارٍ تجهيز ملفات اللعبة (دقيقة أو دقيقتان)"
        subprocess.run([GODOT, "--headless", "--path", GAME, "--import"], env=env, timeout=1800,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as e:
        state["phase"] = "تعذّر التجهيز: %s" % e
        log(state["phase"])
        return
    restore_accounts()
    while True:
        state["phase"] = "الخادم يعمل ✓"
        state["since"] = time.time()
        proc = subprocess.Popen([GODOT, "--headless", "--path", GAME, "--", "--server", "--ws", "--bind", "127.0.0.1",
                                 "--data", DATA, "--max_battles", str(MAX_BATTLES)], env=env)
        tick = 0
        while proc.poll() is None:
            time.sleep(1)
            tick += 1
            if tick % 60 == 0:
                save_accounts()
        save_accounts()
        state["restarts"] += 1
        state["phase"] = "إعادة تشغيل الخادم..."
        log("server stopped (%s), restarting" % proc.returncode)
        time.sleep(3)


# ------------------------------------------------------------------ the players' connections
async def _pipe(ws, port):
    import websockets
    await ws.accept()
    try:
        async with websockets.connect("ws://127.0.0.1:%d" % port, max_size=None, ping_interval=None,
                                      open_timeout=10) as up:
            async def from_player():
                while True:
                    m = await ws.receive()
                    if m["type"] == "websocket.disconnect":
                        return
                    data = m.get("bytes")
                    if data is None:
                        data = m.get("text")
                    if data is not None:
                        await up.send(data)

            async def to_player():
                async for msg in up:
                    if isinstance(msg, (bytes, bytearray)):
                        await ws.send_bytes(bytes(msg))
                    else:
                        await ws.send_text(msg)

            tasks = [asyncio.create_task(from_player()), asyncio.create_task(to_player())]
            _, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            for t in pending:
                t.cancel()
    except Exception:
        pass
    finally:
        try:
            await ws.close()
        except Exception:
            pass


async def ws_master(ws):
    await _pipe(ws, MASTER)


async def ws_battle(ws):
    port = int(ws.path_params.get("port", 0))
    if MASTER < port <= MASTER + 40:
        await _pipe(ws, port)
    else:
        await ws.close()


# ------------------------------------------------------------------ status page
def status_text():
    up = int(time.time() - state["since"])
    battles = 0
    folder = os.path.join(DATA, "battles")
    if os.path.isdir(folder):
        battles = len([f for f in os.listdir(folder) if f.endswith(".ready")])
    return ("## %s\n\nمدة التشغيل: %d دقيقة · المعارك الجارية: %d · آخر حفظ للحسابات: %s\n\n"
            "عنوان الخادم في اللعبة: **%s**"
            % (state["phase"], up // 60, battles, state["saved"], os.environ.get("SPACE_HOST", "اسم-الـ-Space.hf.space")))


def main():
    import gradio as gr
    from starlette.routing import WebSocketRoute

    try:  # ZeroGPU hardware wants one GPU function declared; the server never uses it
        import spaces

        @spaces.GPU
        def _unused():
            return 0
    except Exception:
        pass

    threading.Thread(target=run_server, daemon=True).start()
    with gr.Blocks(title="AURUM MOBILE") as demo:
        gr.Markdown("# 🦅 AURUM MOBILE — خادم اللعب أونلاين")
        status = gr.Markdown(status_text())
        gr.Button("تحديث").click(status_text, outputs=status)
        demo.load(status_text, outputs=status)
    app, _, _ = demo.launch(server_name="0.0.0.0", server_port=int(os.environ.get("PORT", "7860")),
                            prevent_thread_lock=True)
    # the players' WebSocket paths go before Gradio's own routes
    app.router.routes.insert(0, WebSocketRoute("/m", ws_master))
    app.router.routes.insert(0, WebSocketRoute("/b/{port:int}", ws_battle))
    log("web port ready")
    while True:
        time.sleep(3600)
