#!/bin/zsh
# DeepSeek Harness server launcher — used by the desktop app and dshctl.
# Idempotent: if the web server is already listening, it just reports "ready".

set -u

HOST="${DSH_WEB_HOST:-127.0.0.1}"
PORT="${DSH_WEB_PORT:-3080}"
URL="http://${HOST}:${PORT}/"
LOG_DIR="$HOME/.dsh/logs"
LOG_FILE="$LOG_DIR/dsh-web.log"
PID_FILE="$LOG_DIR/dsh-web.pid"

mkdir -p "$LOG_DIR"

# A GUI-launched (Finder/Dock) process has a minimal PATH. Restore nvm + homebrew
# so node/pnpm/npx/dsh resolve the same way they do in the user's terminal.
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" >/dev/null 2>&1
[ -d /opt/homebrew/bin ] && export PATH="/opt/homebrew/bin:$PATH"

# Locate dsh: a global install first, then the newest npx cache, then npx.
find_dsh() {
  if command -v dsh >/dev/null 2>&1; then command -v dsh; return; fi
  local bin
  bin=$(ls -td "$HOME"/.npm/_npx/*/node_modules/.bin/dsh 2>/dev/null | head -1)
  if [ -n "$bin" ]; then echo "$bin"; return; fi
  echo "npx"
}

# Health check: any HTTP response means something is listening on the port.
is_up() {
  curl -s -o /dev/null --max-time 2 "$URL" 2>/dev/null
}

if is_up; then
  echo "server already running at $URL"
  exit 0
fi

DSH="$(find_dsh)"

# /api 浏览器信任围栏的额外放行域名（逗号分隔，如 Tailscale 的 xxx.ts.net）
TRUSTED_ARGS=()
if [ -n "${DSH_WEB_TRUSTED_HOSTS:-}" ]; then
  IFS=',' read -rA _trusted <<< "$DSH_WEB_TRUSTED_HOSTS"
  for _h in "${_trusted[@]}"; do
    _h="${_h// /}"
    [ -n "$_h" ] && TRUSTED_ARGS+=(--trusted-host "$_h")
  done
fi

if [ "$DSH" = "npx" ]; then
  nohup npx --yes @deepseek-ai/dsh@0.1.0-rc.6 web --host "$HOST" --port "$PORT" "${TRUSTED_ARGS[@]}" >> "$LOG_FILE" 2>&1 &
else
  nohup "$DSH" web --host "$HOST" --port "$PORT" "${TRUSTED_ARGS[@]}" >> "$LOG_FILE" 2>&1 &
fi
echo $! > "$PID_FILE"
echo "started dsh web (pid $(cat "$PID_FILE")) -> $URL (logs: $LOG_FILE)"

# Wait up to 30s for the server to answer.
for _ in {1..30}; do
  if is_up; then echo "ready: $URL"; exit 0; fi
  sleep 1
done

echo "warning: server did not respond within 30s; check $LOG_FILE"
exit 1
