#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-8080}"
LOCAL_URL="${LOCAL_URL:-http://127.0.0.1:$PORT}"
LOG_FILE="${CLOUDFLARED_LOG_FILE:-/content/cloudflared.log}"
BACKGROUND="${BACKGROUND:-1}"
CLOUDFLARED_BIN="${CLOUDFLARED_BIN:-/content/cloudflared}"

if [ ! -x "$CLOUDFLARED_BIN" ]; then
  if command -v cloudflared >/dev/null 2>&1; then
    CLOUDFLARED_BIN="$(command -v cloudflared)"
  fi
fi

if [ ! -x "$CLOUDFLARED_BIN" ]; then
  echo "cloudflared is not installed. Run scripts/setup_colab.sh first." >&2
  exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"

echo "==> Starting Cloudflare quick tunnel"
echo "Local target: $LOCAL_URL"
echo "Log file: $LOG_FILE"

if [ "$BACKGROUND" = "1" ]; then
  if pgrep -f "cloudflared tunnel --url $LOCAL_URL" >/dev/null 2>&1; then
    echo "A cloudflared process already appears to be tunneling $LOCAL_URL."
  else
    nohup "$CLOUDFLARED_BIN" tunnel --url "$LOCAL_URL" > "$LOG_FILE" 2>&1 &
    echo $! > /content/cloudflared.pid
    echo "PID: $(cat /content/cloudflared.pid)"
  fi

  echo "Waiting for public URL..."
  for _ in $(seq 1 30); do
    url="$(grep -oE 'https://[-a-zA-Z0-9]+\.trycloudflare\.com' "$LOG_FILE" | head -n 1 || true)"
    if [ -n "$url" ]; then
      echo "Public base URL: $url/v1"
      echo "$url/v1" > /content/openclaw_base_url.txt
      exit 0
    fi
    sleep 1
  done

  echo "Tunnel started, but no public URL was found yet. Recent log:"
  tail -n 80 "$LOG_FILE" || true
  exit 1
else
  exec "$CLOUDFLARED_BIN" tunnel --url "$LOCAL_URL"
fi
