#!/bin/zsh
# DeepSeek Harness server stopper — kills the server launched by launch.sh.

set -u

LOG_DIR="$HOME/.dsh/logs"
PID_FILE="$LOG_DIR/dsh-web.pid"
PORT="${DSH_WEB_PORT:-3080}"

stopped=0

if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE" 2>/dev/null)
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null
    echo "stopped dsh web (pid $PID)"
    stopped=1
  fi
  rm -f "$PID_FILE"
fi

# Fallback: any dsh-web process still listening on the port.
if command -v lsof >/dev/null 2>&1; then
  lsof -ti tcp:"$PORT" -sTCP:LISTEN 2>/dev/null | while read -r p; do
    if ps -p "$p" -o command= 2>/dev/null | grep -q "dsh web"; then
      kill "$p" 2>/dev/null
      echo "stopped dsh web (pid $p, via lsof)"
      stopped=1
    fi
  done
fi

if [ "$stopped" = "0" ]; then
  echo "no dsh web server found on port $PORT"
fi
