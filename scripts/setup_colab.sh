#!/usr/bin/env bash
set -euo pipefail

LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-/content/llama.cpp}"
CMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}"
BUILD_THREADS="${BUILD_THREADS:-$(nproc)}"

echo "==> Checking built-in Colab tools"
for tool in git cmake curl; do
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

echo "==> Fetching llama.cpp"
if [ -d "$LLAMA_CPP_DIR/.git" ]; then
  git -C "$LLAMA_CPP_DIR" pull --ff-only
else
  git clone https://github.com/ggml-org/llama.cpp.git "$LLAMA_CPP_DIR"
fi

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
