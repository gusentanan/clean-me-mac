#!/opt/homebrew/bin/bash
# cmd_orphans — find leftover app data with no matching installed app.

# Locations to scan and how to resolve each entry's bundle ID.
# Each scanner echoes lines: "<bundle_id_or_-> \t <path>"
_scan_app_support() {
  local base="$HOME/Library/Application Support"
  [[ -d "$base" ]] || return 0
  local entry name
  for entry in "$base"/*; do
    [[ -e "$entry" ]] || continue
    name=$(basename "$entry")
    # Bundle-id-shaped folder name?
    if [[ "$name" == *.*.* || "$name" == *.* ]]; then
      printf '%s\t%s\n' "$name" "$entry"
    else
      # Try known-apps mapping.
      local id
      id=$(known_app_bundle_id "$name")
      [[ -n "$id" ]] && printf '%s\t%s\n' "$id" "$entry" || printf -- '-\t%s\n' "$entry"
    fi
  done
}

_scan_caches() {
  local base="$HOME/Library/Caches"
  [[ -d "$base" ]] || return 0
  local entry name
  for entry in "$base"/*; do
    [[ -e "$entry" ]] || continue
    name=$(basename "$entry")
    if [[ "$name" == *.*.* || "$name" == *.* ]]; then
      printf '%s\t%s\n' "$name" "$entry"
    else
      local id
      id=$(known_app_bundle_id "$name")
      [[ -n "$id" ]] && printf '%s\t%s\n' "$id" "$entry" || printf -- '-\t%s\n' "$entry"
    fi
  done
}

_scan_containers() {
  local base="$HOME/Library/Containers"
  [[ -d "$base" ]] || return 0
  local entry id name
  for entry in "$base"/*; do
    [[ -d "$entry" ]] || continue
    id=$(bundle_id_for_container "$entry") || id=""
    if [[ -z "$id" ]]; then
      # Folder name might be a bundle ID directly.
      name=$(basename "$entry")
      [[ "$name" == *.*.* || "$name" == *.* ]] && id=$name
    fi
    [[ -n "$id" ]] && printf '%s\t%s\n' "$id" "$entry" || printf -- '-\t%s\n' "$entry"
  done
}

_scan_preferences() {
  local base="$HOME/Library/Preferences"
  [[ -d "$base" ]] || return 0
  local entry name id
  for entry in "$base"/*.plist; do
    [[ -f "$entry" ]] || continue
    name=$(basename "$entry" .plist)
    # Most are bundle-id-shaped.
    if [[ "$name" == *.* ]]; then
      printf '%s\t%s\n' "$name" "$entry"
    fi
  done
}

_scan_logs() {
  local base="$HOME/Library/Logs"
  [[ -d "$base" ]] || return 0
  local entry name id
  for entry in "$base"/*; do
    [[ -e "$entry" ]] || continue
    name=$(basename "$entry")
    if [[ "$name" == *.*.* || "$name" == *.* ]]; then
      printf '%s\t%s\n' "$name" "$entry"
    else
      id=$(known_app_bundle_id "$name")
      [[ -n "$id" ]] && printf '%s\t%s\n' "$id" "$entry" || printf -- '-\t%s\n' "$entry"
    fi
  done
}

_scan_saved_state() {
  local base="$HOME/Library/Saved Application State"
  [[ -d "$base" ]] || return 0
  local entry name
  for entry in "$base"/*.savedState; do
    [[ -d "$entry" ]] || continue
    name=$(basename "$entry" .savedState)
    if [[ "$name" == *.* ]]; then
      printf '%s\t%s\n' "$name" "$entry"
    fi
  done
}

_scan_http_storages() {
  local base="$HOME/Library/HTTPStorages"
  [[ -d "$base" ]] || return 0
  local entry name
  for entry in "$base"/*; do
    [[ -e "$entry" ]] || continue
    name=$(basename "$entry")
    # Strip trailing ".binarycookies" etc.
    name=${name%.binarycookies}
    if [[ "$name" == *.*.* || "$name" == *.* ]]; then
      printf '%s\t%s\n' "$name" "$entry"
    fi
  done
}

# Combined scan of all locations.
_scan_all() {
  _scan_containers
  _scan_app_support
  _scan_caches
  _scan_preferences
  _scan_logs
  _scan_saved_state
  _scan_http_storages
}

cmd_orphans() {
  local count_only=0
  while (( $# > 0 )); do
    case "$1" in
      --count-only) count_only=1 ;;
      -h|--help)    _orphans_help; return 0 ;;
      -*) log_warn "orphans: ignoring unknown flag: $1" ;;
    esac
    shift
  done

  log_info "Scanning installed apps..."
  get_installed_bundle_ids_cached > /dev/null

  log_info "Scanning Library subfolders for orphans..."

  # Build list of orphans: lines "<bytes>\t<id>\t<path>"
  local rows=""
  local line id path
  while IFS=$'\t' read -r id path; do
    [[ -z "$path" ]] && continue
    # Unknown bundle ID → still record if it lives in a tracked dir; useful for review.
    if [[ "$id" == "-" ]]; then
      continue
    fi
    is_apple_bundle "$id" && continue
    if is_installed_bundle "$id"; then
      continue
    fi
    local sz
    sz=$(dir_size "$path")
    # Filter out trivially small entries (< 1MB).
    (( sz < 1024 * 1024 )) && continue
    rows+="${sz}"$'\t'"${id}"$'\t'"${path}"$'\n'
  done < <(_scan_all)

  # Sort desc by size.
  rows=$(printf '%s' "$rows" | sort -t$'\t' -k1 -nr)

  if [[ "$count_only" -eq 1 ]]; then
    local n total=0
    n=$(printf '%s' "$rows" | grep -c '^' || true)
    while IFS=$'\t' read -r sz _ _; do
      [[ -z "$sz" ]] && continue
      total=$(( total + sz ))
    done <<< "$rows"
    printf '%d orphans, %s reclaimable\n' "$n" "$(human_size "$total")"
    return 0
  fi

  if [[ -z "$rows" ]]; then
    log_info "No orphans found. Nice and tidy."
    return 0
  fi

  if [[ "$CMM_JSON" -eq 1 ]]; then
    _orphans_json "$rows"
    return 0
  fi

  # Show table + interactive picker.
  _orphans_table "$rows"

  # Build picker lines.
  local -a picker_items=()
  while IFS=$'\t' read -r sz id path; do
    [[ -z "$path" ]] && continue
    picker_items+=("$(printf '%10s  %-40s  %s' "$(human_size "$sz")" "$id" "${path/#$HOME/\~}")")
  done <<< "$rows"

  local chosen
  chosen=$(printf '%s\n' "${picker_items[@]}" | select_multi "Pick orphans to delete (Tab multi-select, Enter confirm)")
  [[ -z "$chosen" ]] && { log_info "Nothing selected."; return 0; }

  # Delete chosen paths.
  local total_freed=0 line path_only expanded sz
  while IFS= read -r line; do
    # Path is the last "column" — but paths may contain spaces. Use awk to take 3rd field onwards.
    path_only=$(awk '{ for (i=3; i<=NF; i++) printf "%s%s", $i, (i==NF?"":" ") }' <<< "$line")
    expanded=${path_only/#\~/$HOME}
    [[ -e "$expanded" ]] || continue
    sz=$(dir_size "$expanded")
    _orphan_safe_delete "$expanded"
    total_freed=$(( total_freed + sz ))
  done <<< "$chosen"

  printf '\n%sFreed: %s%s\n' "$C_GREEN" "$(human_size "$total_freed")" "$C_RESET"
}

# Container roots are protected; delete only Data/Bottles inside them.
_orphan_safe_delete() {
  local p=$1
  if [[ "$p" == "$HOME/Library/Containers/"* ]]; then
    local sub
    for sub in "$p"/Data "$p"/Bottles; do
      [[ -e "$sub" ]] && safe_rm "$sub"
    done
    return 0
  fi
  safe_rm "$p"
}

_orphans_table() {
  local rows=$1
  printf '\n%s%sOrphans%s (no matching installed app):\n\n' "$C_BOLD" "$C_RED" "$C_RESET"
  printf '%s%10s  %-40s  %s%s\n' "$C_BOLD" "SIZE" "BUNDLE ID" "PATH" "$C_RESET"
  printf '%s%s%s\n' "$C_DIM" "$(printf '%.0s-' {1..100})" "$C_RESET"
  while IFS=$'\t' read -r sz id path; do
    [[ -z "$path" ]] && continue
    printf '%10s  %-40s  %s\n' "$(human_size "$sz")" "$id" "${path/#$HOME/\~}"
  done <<< "$rows"
  echo
}

_orphans_json() {
  local rows=$1
  printf '%s' "$rows" \
  | jq -R -s '
      split("\n")
      | map(select(length > 0) | split("\t") | { bytes: (.[0] | tonumber), bundle_id: .[1], path: .[2] })
      | { orphans: ., total_bytes: (map(.bytes) | add // 0) }
    '
}

_orphans_help() {
  cat <<EOF
${C_BOLD}clmac orphans${C_RESET}

  Scans ~/Library/{Application Support,Caches,Containers,Preferences,Logs,
  Saved Application State,HTTPStorages} for data belonging to apps that
  are no longer installed.

OPTIONS
  --count-only   Print only a summary line (used by 'doctor')
  --dry-run      (global) Preview deletions only
EOF
}
