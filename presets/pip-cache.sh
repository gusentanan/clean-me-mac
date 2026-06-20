PRESET_NAME="pip-cache"
PRESET_DESC="Python pip download cache (safe to remove, re-downloads on next pip install)"
PRESET_SAFE=true
PRESET_PATHS=(
  "$HOME/Library/Caches/pip"
  "$HOME/.cache/pip"
)
