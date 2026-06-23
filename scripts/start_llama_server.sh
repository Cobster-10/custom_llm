#!/usr/bin/env bash
set -euo pipefail

LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-/content/llama.cpp}"
LLAMA_SERVER_BIN="${LLAMA_SERVER_BIN:-$LLAMA_CPP_DIR/build/bin/llama-server}"

MODEL_REPO="${MODEL_REPO:-HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive}"
MODEL_QUANT="${MODEL_QUANT:-Q8_K_P}"
MODEL_ID="${MODEL_ID:-$MODEL_REPO:$MODEL_QUANT}"

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8080}"
CTX_SIZE="${CTX_SIZE:-131072}"
N_GPU_LAYERS="${N_GPU_LAYERS:-99}"
PARALLEL="${PARALLEL:-1}"
LOG_FILE="${LOG_FILE:-/content/llama-server.log}"
BACKGROUND="${BACKGROUND:-1}"

if [ ! -x "$LLAMA_SERVER_BIN" ]; then
  echo "llama-server was not found at: $LLAMA_SERVER_BIN" >&2
  echo "Run scripts/setup_colab.sh first." >&2
  exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"

cmd=(
  "$LLAMA_SERVER_BIN"
  -hf "$MODEL_ID"
  --host "$HOST"
  --port "$PORT"
  --jinja
  -c "$CTX_SIZE"
  -ngl "$N_GPU_LAYERS"
  --parallel "$PARALLEL"
)

if [ -n "${LLAMA_EXTRA_ARGS:-}" ]; then
  # shellcheck disable=SC2206
  extra_args=( $LLAMA_EXTRA_ARGS )
  cmd+=( "${extra_args[@]}" )
fi

echo "==> Starting llama-server"
echo "Model: $MODEL_ID"
echo "Local API: http://127.0.0.1:$PORT/v1"
echo "Log file: $LOG_FILE"
printf 'Command:'
printf ' %q' "${cmd[@]}"
printf '\n'

if [ "$BACKGROUND" = "1" ]; then
  if pgrep -f "llama-server.*--port $PORT" >/dev/null 2>&1; then
    echo "A llama-server process already appears to be using port $PORT."
  else
    nohup "${cmd[@]}" > "$LOG_FILE" 2>&1 &
    echo $! > /content/llama-server.pid
    echo "PID: $(cat /content/llama-server.pid)"
  fi

  echo "Waiting briefly for the server to bind..."
  sleep 8
  tail -n 80 "$LOG_FILE" || true
else
  exec "${cmd[@]}"
fi
