PRESET_NAME="firefox-cache"
PRESET_DESC="Firefox HTTP cache (regenerates as you browse)"
PRESET_PATHS=(
  "$HOME/Library/Caches/Firefox"
  "$HOME/Library/Application Support/Firefox/Profiles/*/cache2"
  "$HOME/Library/Application Support/Firefox/Profiles/*/startupCache"
)
PRESET_SAFE=true
