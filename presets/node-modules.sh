PRESET_NAME="node-modules"
PRESET_DESC="Scan project dirs for node_modules and remove selected"
# Scan-style preset: cmd_clean treats this specially.
PRESET_SCAN=true
PRESET_SCAN_NAME="node_modules"
PRESET_SCAN_ROOTS=(
  "$HOME/projects"
  "$HOME/Projects"
  "$HOME/Works"
  "$HOME/develop"
)
# Exclude dirs touched in the last N days (recently used).
PRESET_SCAN_MIN_AGE_DAYS=7
PRESET_SAFE=false
