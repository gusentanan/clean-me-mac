PRESET_NAME="python-venv"
PRESET_DESC="Python virtual environments (venv / .venv) in project directories"
PRESET_SCAN=true
PRESET_SCAN_NAMES=("venv" ".venv")
PRESET_SCAN_ROOTS=(
  "$HOME/projects"
  "$HOME/Projects"
  "$HOME/Works"
  "$HOME/develop"
)
PRESET_SCAN_MIN_AGE_DAYS=14
PRESET_SAFE=false
