"""Accounts backup for the Hugging Face Space: a private dataset <owner>/aurum-data keeps accounts.json.
   python3 sync.py restore <data dir>   (at start)
   python3 sync.py save <data dir>      (every minute, only when it changed)
Needs the Space secret HF_TOKEN (a token with write access); DATASET overrides the dataset name."""
import hashlib, os, shutil, sys

token = os.environ.get("HF_TOKEN", "").strip()
if not token:
    sys.exit(0)
from huggingface_hub import HfApi, hf_hub_download

mode, data = sys.argv[1], sys.argv[2]
api = HfApi(token=token)
repo = os.environ.get("DATASET", "").strip() or api.whoami()["name"] + "/aurum-data"
path = os.path.join(data, "accounts.json")
mark = path + ".saved"

if mode == "restore":
    api.create_repo(repo, repo_type="dataset", private=True, exist_ok=True)
    try:
        shutil.copy(hf_hub_download(repo, "accounts.json", repo_type="dataset", token=token), path)
        print("[sync] accounts restored from", repo)
    except Exception as e:  # first start: nothing saved yet
        print("[sync] no saved accounts yet:", type(e).__name__)
    if os.path.exists(path):
        with open(mark, "w") as f:
            f.write(hashlib.sha256(open(path, "rb").read()).hexdigest())
elif mode == "save":
    if not os.path.exists(path):
        sys.exit(0)
    digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
    if os.path.exists(mark) and open(mark).read() == digest:
        sys.exit(0)
    api.upload_file(path_or_fileobj=path, path_in_repo="accounts.json", repo_id=repo, repo_type="dataset",
                    commit_message="accounts")
    with open(mark, "w") as f:
        f.write(digest)
    print("[sync] accounts saved to", repo)
