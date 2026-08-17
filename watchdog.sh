#!/bin/zsh
# launchd entrypoint for the external DSH guardian.
set -u
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" >/dev/null 2>&1
[ -d /opt/homebrew/bin ] && export PATH="/opt/homebrew/bin:$PATH"
exec node "$HOME/.dsh/guardian/guardian.mjs" watchdog --json
