#!/bin/sh
set -e

if [ -z "$TUNNEL_TOKEN" ]; then
  echo "ERROR: TUNNEL_TOKEN is not set" >&2
  exit 1
fi

term() {
  echo "[start.sh] shutting down"
  kill -TERM "$CF_PID" 2>/dev/null || true
  kill -TERM "$VW_PID" 2>/dev/null || true
  wait "$CF_PID" "$VW_PID" 2>/dev/null || true
}
trap term TERM INT

echo "[start.sh] launching cloudflared tunnel"
cloudflared tunnel --no-autoupdate run --token "$TUNNEL_TOKEN" &
CF_PID=$!

echo "[start.sh] launching vaultwarden"
/start.sh &
VW_PID=$!

# Poll until either child dies, then shut everything down.
while kill -0 "$CF_PID" 2>/dev/null && kill -0 "$VW_PID" 2>/dev/null; do
  sleep 5
done

echo "[start.sh] a child exited; terminating siblings"
term
