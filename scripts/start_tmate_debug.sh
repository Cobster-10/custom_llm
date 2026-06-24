#!/usr/bin/env bash
set -euo pipefail

TMATE_DIR="${TMATE_DIR:-/content/tmate-debug}"
TMATE_BIN="${TMATE_BIN:-$TMATE_DIR/tmate}"

mkdir -p "$TMATE_DIR"

if [ ! -x "$TMATE_BIN" ]; then
  echo "==> Downloading tmate static binary"
  python3 - <<'PY'
import json
import os
import re
import tarfile
import urllib.request
from pathlib import Path

tmate_dir = Path(os.environ.get("TMATE_DIR", "/content/tmate-debug"))
archive = tmate_dir / "tmate.tar.xz"

with urllib.request.urlopen("https://api.github.com/repos/tmate-io/tmate/releases/latest", timeout=60) as response:
    release = json.load(response)

asset_url = None
for asset in release.get("assets", []):
    name = asset.get("name", "")
    if re.search(r"linux.*amd64.*\.tar\.xz$", name):
        asset_url = asset["browser_download_url"]
        break

if not asset_url:
    raise SystemExit("Could not find a linux amd64 tmate release asset.")

print(f"Downloading {asset_url}")
urllib.request.urlretrieve(asset_url, archive)

with tarfile.open(archive, "r:xz") as tar:
    members = tar.getmembers()
    wanted = [m for m in members if m.name.endswith("/tmate")]
    if not wanted:
        raise SystemExit("Archive did not contain a tmate binary.")
    member = wanted[0]
    member.name = "tmate"
    tar.extract(member, path=tmate_dir)

tmate = tmate_dir / "tmate"
tmate.chmod(0o755)
print(f"Installed {tmate}")
PY
fi

echo "==> Starting tmate debug session"
echo "This shell is temporary. Stop it with Ctrl+C in Colab when done."
echo
"$TMATE_BIN" -F
