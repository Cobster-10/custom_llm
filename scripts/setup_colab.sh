#!/usr/bin/env bash
set -euo pipefail

LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-/content/llama.cpp}"
CMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}"
BUILD_THREADS="${BUILD_THREADS:-$(nproc)}"

echo "==> Installing system packages"
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
  build-essential \
  cmake \
  curl \
  git \
  ninja-build

echo "==> Installing Python test dependencies"
python3 - <<'PY'
import requests
print(f"requests {requests.__version__}")
PY

echo "==> Fetching llama.cpp"
if [ -d "$LLAMA_CPP_DIR/.git" ]; then
  git -C "$LLAMA_CPP_DIR" pull --ff-only
else
  git clone https://github.com/ggml-org/llama.cpp.git "$LLAMA_CPP_DIR"
fi

echo "==> Building llama-server with CUDA support"
cmake -S "$LLAMA_CPP_DIR" -B "$LLAMA_CPP_DIR/build" \
  -G Ninja \
  -DCMAKE_BUILD_TYPE="$CMAKE_BUILD_TYPE" \
  -DGGML_CUDA=ON \
  -DLLAMA_CURL=ON

cmake --build "$LLAMA_CPP_DIR/build" \
  --target llama-server llama-cli \
  -j "$BUILD_THREADS"

echo "==> Installing cloudflared"
sudo mkdir -p /usr/local/bin
curl -L --fail --retry 3 \
  -o /tmp/cloudflared \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
sudo install -m 0755 /tmp/cloudflared /usr/local/bin/cloudflared

echo "==> Setup complete"
"$LLAMA_CPP_DIR/build/bin/llama-server" --version || true
cloudflared --version || true
