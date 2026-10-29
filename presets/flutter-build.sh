PRESET_NAME="flutter-build"
PRESET_DESC="Flutter build/ and .dart_tool dirs in project directories (what 'flutter clean' removes)"
PRESET_SCAN=true
PRESET_SCAN_NAMES=("build" ".dart_tool")
# Only match inside real Flutter/Dart projects — "build" alone is far too generic.
PRESET_SCAN_REQUIRE_SIBLING="pubspec.yaml"
PRESET_SCAN_ROOTS=(
  "$HOME/projects"
  "$HOME/Projects"
  "$HOME/Works"
  "$HOME/develop"
)
PRESET_SCAN_MIN_AGE_DAYS=7
PRESET_SAFE=false
