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

# 3. fzf check (optional).
if ! command -v fzf >/dev/null 2>&1; then
  yellow "!"; echo " fzf not installed (optional — numbered menu will be used)"
  echo "  For better UX: brew install fzf"
else
  green "✓"; echo " fzf found"
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
