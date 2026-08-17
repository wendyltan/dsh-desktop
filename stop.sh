#!/bin/zsh
# Stop DSH intentionally and disable the watchdog until the next explicit
# launch. This prevents a manual stop from being mistaken for a crash.

set -u

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" >/dev/null 2>&1
[ -d /opt/homebrew/bin ] && export PATH="/opt/homebrew/bin:$PATH"

GUARDIAN="$HOME/.dsh/guardian/guardian.mjs"
if [ -f "$GUARDIAN" ]; then
  exec node "$GUARDIAN" stop
fi

echo "guardian missing: $GUARDIAN"
exit 1
