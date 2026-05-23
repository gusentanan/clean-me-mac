#!/opt/homebrew/bin/bash
# App / bundle ID resolution helpers.

# Echo bundle ID for an .app bundle (e.g., /Applications/Foo.app).
bundle_id_for_app() {
  local app=$1
  local plist="$app/Contents/Info.plist"
  [[ -f "$plist" ]] || return 1
  plutil -extract CFBundleIdentifier raw -o - "$plist" 2>/dev/null
}

# Echo bundle ID for a sandboxed container directory.
# Container metadata lives in .com.apple.containermanagerd.metadata.plist
bundle_id_for_container() {
  local container=$1
  local meta="$container/.com.apple.containermanagerd.metadata.plist"
  [[ -f "$meta" ]] || return 1
  plutil -extract MCMMetadataIdentifier raw -o - "$meta" 2>/dev/null
}

# True if a bundle ID is Apple-managed (should never be considered an orphan).
is_apple_bundle() {
  local id=$1
  [[ "$id" == com.apple.* ]] || \
  [[ "$id" == group.com.apple.* ]] || \
  [[ "$id" == apple.* ]]
}

# Print one bundle ID per line for every .app bundle found in the
# standard application locations. Deduplicated, sorted.
list_installed_bundle_ids() {
  local -a roots=(
    "/Applications"
    "$HOME/Applications"
    "/System/Applications"
    "/System/Applications/Utilities"
    "/Applications/Utilities"
    "/System/Library/CoreServices/Applications"
  )
  local root app id
  {
    for root in "${roots[@]}"; do
      [[ -d "$root" ]] || continue
      # Up to 3 levels deep to catch nested .app inside .app (rare) or subfolders.
      while IFS= read -r app; do
        id=$(bundle_id_for_app "$app") || continue
        [[ -n "$id" ]] && printf '%s\n' "$id"
      done < <(find "$root" -maxdepth 3 -name "*.app" -type d 2>/dev/null)
    done
  } | sort -u
}

# Cache of installed bundle IDs for the lifetime of a single command.
# Use this instead of calling list_installed_bundle_ids repeatedly.
CMM_INSTALLED_IDS_FILE=""
get_installed_bundle_ids_cached() {
  if [[ -z "$CMM_INSTALLED_IDS_FILE" || ! -f "$CMM_INSTALLED_IDS_FILE" ]]; then
    CMM_INSTALLED_IDS_FILE=$(mktemp -t cmm-ids.XXXXXX)
    list_installed_bundle_ids > "$CMM_INSTALLED_IDS_FILE"
  fi
  cat "$CMM_INSTALLED_IDS_FILE"
}

# True if a bundle ID matches any installed app.
is_installed_bundle() {
  local id=$1
  [[ -z "$id" ]] && return 1
  get_installed_bundle_ids_cached | grep -Fxq "$id"
}

# Best-effort: given a Library entry path like "Application Support/CrossOver",
# try to map a non-bundle-id folder name to a known app. Returns the bundle ID
# if known, or echoes nothing.
# Mapping is also extensible via ~/.config/clmac/known-apps.txt
# Format per line: <folder-name>	<bundle-id>
declare -A CMM_KNOWN_APPS=(
  ["CrossOver"]="com.codeweavers.CrossOver"
  ["Whisky"]="com.isaacmarovitz.Whisky"
  ["Steam"]="com.valvesoftware.steam"
  ["Spotify"]="com.spotify.client"
  ["Slack"]="com.tinyspeck.slackmacgap"
  ["Discord"]="com.hnc.Discord"
  ["zoom.us"]="us.zoom.xos"
  ["Code"]="com.microsoft.VSCode"
  ["Code - Insiders"]="com.microsoft.VSCodeInsiders"
  ["Cursor"]="com.todesktop.230313mzl4w4u92"
  ["JetBrains"]="com.jetbrains.toolbox"
  ["Postman"]="com.postmanlabs.mac"
  ["obsidian"]="md.obsidian"
  ["TMetric Desktop"]="com.devart.TMetric"
  ["Insomnia"]="com.insomnia.app"
)

# Load user-defined mappings (overrides built-ins).
_load_user_known_apps() {
  local f="$HOME/.config/clmac/known-apps.txt"
  [[ -f "$f" ]] || return 0
  local name id
  while IFS=$'\t' read -r name id; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    CMM_KNOWN_APPS["$name"]="$id"
  done < "$f"
}
_load_user_known_apps

# Map a folder name to a bundle ID. Echo nothing if unknown.
known_app_bundle_id() {
  local name=$1
  printf '%s' "${CMM_KNOWN_APPS[$name]:-}"
}
