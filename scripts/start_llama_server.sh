#!/usr/bin/env bash
set -euo pipefail

RUNTIME_DIR="${RUNTIME_DIR:-$HOME/custom_llm_runtime}"
LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-$RUNTIME_DIR/llama.cpp}"
LLAMA_SERVER_BIN="${LLAMA_SERVER_BIN:-$LLAMA_CPP_DIR/build/bin/llama-server}"

MODEL_REPO="${MODEL_REPO:-HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive}"
MODEL_QUANT="${MODEL_QUANT:-Q8_K_P}"
MODEL_ID="${MODEL_ID:-$MODEL_REPO:$MODEL_QUANT}"

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8080}"
CTX_SIZE="${CTX_SIZE:-131072}"
N_GPU_LAYERS="${N_GPU_LAYERS:-99}"
PARALLEL="${PARALLEL:-1}"
LOG_FILE="${LOG_FILE:-$RUNTIME_DIR/llama-server.log}"
PID_FILE="${PID_FILE:-$RUNTIME_DIR/llama-server.pid}"
BACKGROUND="${BACKGROUND:-1}"
RESTART_SERVER="${RESTART_SERVER:-1}"

if [ ! -x "$LLAMA_SERVER_BIN" ]; then
  echo "llama-server was not found at: $LLAMA_SERVER_BIN" >&2
  echo "Run scripts/setup_colab.sh first." >&2
  exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$PID_FILE")"

stop_existing_server() {
  echo "==> Stopping any existing process on port $PORT"

  if [ -f "$PID_FILE" ]; then
    old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "$old_pid" ] && kill -0 "$old_pid" >/dev/null 2>&1; then
      kill "$old_pid" >/dev/null 2>&1 || true
      sleep 3
      kill -9 "$old_pid" >/dev/null 2>&1 || true
    fi
    rm -f "$PID_FILE"
  fi

  if command -v fuser >/dev/null 2>&1; then
    fuser -k "${PORT}/tcp" >/dev/null 2>&1 || true
  fi

  pkill -f "llama-server.*(--port| )${PORT}" >/dev/null 2>&1 || true
  sleep 2
}

cmd=(
  "$LLAMA_SERVER_BIN"
  -hf "$MODEL_ID"
  --alias "$MODEL_ID"
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
  if [ "$RESTART_SERVER" = "1" ]; then
    stop_existing_server
  elif pgrep -f "llama-server.*(--port| )${PORT}" >/dev/null 2>&1; then
    echo "A llama-server process already appears to be using port $PORT."
    echo "Set RESTART_SERVER=1 to force a clean restart."
    exit 0
  fi

  if [ -f "$LOG_FILE" ]; then
    mv "$LOG_FILE" "${LOG_FILE}.$(date +%Y%m%d-%H%M%S).old" || true
  fi

  nohup "${cmd[@]}" > "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  echo "PID: $(cat "$PID_FILE")"

  echo "Waiting briefly for the server to bind..."
  sleep 8
  echo "Process status:"
  ps -p "$(cat "$PID_FILE")" -o pid,etime,pcpu,pmem,args || true
  echo "Recent log:"
  tail -n 80 "$LOG_FILE" || true
else
  exec "${cmd[@]}"
fi
