#!/bin/zsh
# DeepSeek Harness guarded launcher. All production starts pass through the
# external guardian so a broken profile/plugin is rejected before port 3080 is
# touched, and a failed boot can recover or fall back to safe mode.

set -u

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" >/dev/null 2>&1
[ -d /opt/homebrew/bin ] && export PATH="/opt/homebrew/bin:$PATH"

GUARDIAN="$HOME/.dsh/guardian/guardian.mjs"
if [ ! -f "$GUARDIAN" ]; then
  echo "guardian missing: $GUARDIAN"
  exit 1
fi

exec node "$GUARDIAN" start
