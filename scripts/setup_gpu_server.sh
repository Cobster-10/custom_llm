#!/usr/bin/env bash
set -euo pipefail

RUNTIME_DIR="${RUNTIME_DIR:-$HOME/custom_llm_runtime}"
LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-$RUNTIME_DIR/llama.cpp}"
CMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}"
CMAKE_CUDA_ARCHITECTURES="${CMAKE_CUDA_ARCHITECTURES:-80}"
BUILD_THREADS="${BUILD_THREADS:-$(nproc)}"
LLAMA_CPP_VERSION="${LLAMA_CPP_VERSION:-latest}"
INSTALL_SYSTEM_PACKAGES="${INSTALL_SYSTEM_PACKAGES:-1}"
export RUNTIME_DIR LLAMA_CPP_DIR LLAMA_CPP_VERSION

mkdir -p "$RUNTIME_DIR"

maybe_install_system_packages() {
  missing=()
  for tool in cmake curl python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing+=("$tool")
    fi
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    return
  fi

  if [ "$INSTALL_SYSTEM_PACKAGES" != "1" ]; then
    printf 'Missing required tools:'
    printf ' %s' "${missing[@]}"
    printf '\n'
    echo "Set INSTALL_SYSTEM_PACKAGES=1 on a normal GPU VM to install them with apt." >&2
    exit 1
  fi

  if ! command -v sudo >/dev/null 2>&1 || ! command -v apt-get >/dev/null 2>&1; then
    printf 'Missing required tools:'
    printf ' %s' "${missing[@]}"
    printf '\n'
    echo "Automatic apt install is unavailable on this system." >&2
    exit 1
  fi

  echo "==> Installing system build tools"
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    git \
    libssl-dev \
    ninja-build \
    pkg-config \
    python3
}

maybe_install_system_packages

echo "==> Checking Python HTTP client"
python3 - <<'PY'
try:
    import requests
except ImportError:
    print("requests is not installed. Install it only if the tests fail to import requests.")
else:
    print(f"requests {requests.__version__}")
PY

if command -v ninja >/dev/null 2>&1; then
  CMAKE_GENERATOR="${CMAKE_GENERATOR:-Ninja}"
else
  CMAKE_GENERATOR="${CMAKE_GENERATOR:-Unix Makefiles}"
fi

echo "==> Fetching llama.cpp source archive"
python3 - <<'PY'
import json
import os
import shutil
import tarfile
import urllib.request
from pathlib import Path

runtime_dir = Path(os.environ.get("RUNTIME_DIR", str(Path.home() / "custom_llm_runtime")))
target = Path(os.environ.get("LLAMA_CPP_DIR", str(runtime_dir / "llama.cpp")))
version = os.environ.get("LLAMA_CPP_VERSION", "latest")
archive = runtime_dir / "llama.cpp-src.tar.gz"

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
    for member in tar.getmembers():
        parts = member.name.split("/", 1)
        if len(parts) != 2:
            continue
        member.name = parts[1]
        tar.extract(member, path=target)

print(f"Extracted llama.cpp {tag} to {target}")
PY

echo "==> Building llama-server with CUDA support"
cmake -S "$LLAMA_CPP_DIR" -B "$LLAMA_CPP_DIR/build" \
  -G "$CMAKE_GENERATOR" \
  -DCMAKE_BUILD_TYPE="$CMAKE_BUILD_TYPE" \
  -DCMAKE_CUDA_ARCHITECTURES="$CMAKE_CUDA_ARCHITECTURES" \
  -DGGML_CUDA=ON \
  -DLLAMA_CURL=ON \
  -DLLAMA_OPENSSL=ON \
  -DLLAMA_BUILD_UI=OFF \
  -DLLAMA_USE_PREBUILT_UI=ON

cmake --build "$LLAMA_CPP_DIR/build" \
  --target llama-server llama-cli \
  -j "$BUILD_THREADS"

echo "==> Downloading cloudflared"
curl -L --fail --retry 3 \
  -o "$RUNTIME_DIR/cloudflared" \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x "$RUNTIME_DIR/cloudflared"

echo "==> Setup complete"
"$LLAMA_CPP_DIR/build/bin/llama-server" --version || true
"$RUNTIME_DIR/cloudflared" --version || true
