#!/bin/bash
# install.sh — verify deps and symlink clmac into PATH.
set -eu

SCRIPT_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
TARGET="/opt/homebrew/bin/clmac"

red()    { printf '\033[31m%s\033[0m' "$*"; }
green()  { printf '\033[32m%s\033[0m' "$*"; }
yellow() { printf '\033[33m%s\033[0m' "$*"; }
bold()   { printf '\033[1m%s\033[0m'  "$*"; }

echo
bold "Installing clmac"; echo
echo

# 1. Bash 5 check.
if [[ ! -x /opt/homebrew/bin/bash ]]; then
  red "Bash 5 not found at /opt/homebrew/bin/bash"; echo
  echo "Install it with:"
  bold "  brew install bash"; echo
  exit 1
fi
green "✓"; echo " Bash 5 found ($(/opt/homebrew/bin/bash --version | head -1))"

# 2. jq check.
if ! command -v jq >/dev/null 2>&1; then
  yellow "!"; echo " jq not found — required for --json output."
  echo "  Install with: brew install jq"
else
  green "✓"; echo " jq found"
fi

# 3. Go (optional) — builds the enhanced bar-chart `clmac explore`.
# Without it, explore falls back to a bash implementation automatically.
if command -v go >/dev/null 2>&1; then
  green "✓"; echo " Go found — building clmac explore..."
  if ( cd "$SCRIPT_DIR" && go build -ldflags="-s -w" -o bin/clmac-explore ./cmd/explore ) 2>/dev/null; then
    green "✓"; echo " Built bin/clmac-explore"
  else
    yellow "!"; echo " Go build failed — clmac explore will use its bash fallback"
  fi
else
  yellow "!"; echo " Go not installed (optional — clmac explore will use its bash fallback)"
  echo "  For the bar-chart explorer: brew install go && (cd \"$SCRIPT_DIR\" && make build)"
fi

# 4. Symlink.
if [[ ! -w /opt/homebrew/bin ]]; then
  red "/opt/homebrew/bin is not writable by your user."; echo
  echo "Run with sudo or fix Homebrew ownership."
  exit 1
fi

ln -sf "$SCRIPT_DIR/clmac" "$TARGET"
chmod +x "$SCRIPT_DIR/clmac"

green "✓"; echo " Symlinked $TARGET → $SCRIPT_DIR/clmac"
echo
bold "Try it:"; echo
echo "  clmac doctor"
echo "  clmac scan"
echo "  clmac clean --list"
echo
