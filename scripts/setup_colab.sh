#!/usr/bin/env bash
set -euo pipefail

LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-/content/llama.cpp}"
CMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}"
BUILD_THREADS="${BUILD_THREADS:-$(nproc)}"
LLAMA_CPP_VERSION="${LLAMA_CPP_VERSION:-latest}"

echo "==> Checking built-in Colab tools"
for tool in cmake curl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
done

if command -v ninja >/dev/null 2>&1; then
  CMAKE_GENERATOR="${CMAKE_GENERATOR:-Ninja}"
else
  CMAKE_GENERATOR="${CMAKE_GENERATOR:-Unix Makefiles}"
fi

echo "==> Checking built-in Python packages"
python3 - <<'PY'
import requests
print(f"requests {requests.__version__}")
PY

echo "==> Fetching llama.cpp source archive"
python3 - <<'PY'
import json
import os
import shutil
import tarfile
import urllib.request
from pathlib import Path

target = Path(os.environ.get("LLAMA_CPP_DIR", "/content/llama.cpp"))
version = os.environ.get("LLAMA_CPP_VERSION", "latest")
archive = Path("/content/llama.cpp-src.tar.gz")

if version == "latest":
    with urllib.request.urlopen("https://api.github.com/repos/ggml-org/llama.cpp/releases/latest", timeout=60) as response:
        release = json.load(response)
    tag = release["tag_name"]
else:
    tag = version

url = f"https://github.com/ggml-org/llama.cpp/archive/refs/tags/{tag}.tar.gz"
print(f"Downloading {url}")
urllib.request.urlretrieve(url, archive)

if target.exists():
    shutil.rmtree(target)
target.mkdir(parents=True)

with tarfile.open(archive, "r:gz") as tar:
    root = None
    for member in tar.getmembers():
        parts = member.name.split("/", 1)
        if len(parts) != 2:
            continue
        root = parts[0]
        member.name = parts[1]
        tar.extract(member, path=target)

print(f"Extracted llama.cpp {tag} to {target}")
PY

echo "==> Building llama-server with CUDA support"
cmake -S "$LLAMA_CPP_DIR" -B "$LLAMA_CPP_DIR/build" \
  -G "$CMAKE_GENERATOR" \
  -DCMAKE_BUILD_TYPE="$CMAKE_BUILD_TYPE" \
  -DGGML_CUDA=ON \
  -DLLAMA_CURL=ON \
  -DLLAMA_BUILD_UI=OFF \
  -DLLAMA_USE_PREBUILT_UI=ON

cmake --build "$LLAMA_CPP_DIR/build" \
  --target llama-server llama-cli \
  -j "$BUILD_THREADS"

echo "==> Downloading cloudflared"
curl -L --fail --retry 3 \
  -o /content/cloudflared \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x /content/cloudflared

echo "==> Setup complete"
"$LLAMA_CPP_DIR/build/bin/llama-server" --version || true
/content/cloudflared --version || true
