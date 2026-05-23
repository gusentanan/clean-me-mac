#!/opt/homebrew/bin/bash
# cmd_scan — categorized disk usage report.

# Category definitions. Each is a name and a list of glob patterns / paths.
# Patterns are expanded with bash globbing (nullglob).
_scan_categories() {
  cat <<'EOF'
Dev caches|$HOME/.gradle|$HOME/.dartServer|$HOME/.cache|$HOME/.pub-cache|$HOME/.npm|$HOME/.cocoapods|$HOME/.yarn|$HOME/.pnpm-store|$HOME/Library/pnpm
Xcode|$HOME/Library/Developer/Xcode/DerivedData|$HOME/Library/Developer/Xcode/iOS DeviceSupport|$HOME/Library/Developer/Xcode/Archives|$HOME/Library/Developer/CoreSimulator
Android|$HOME/.android|$HOME/Library/Android
Flutter|$HOME/fvm|$HOME/develop/flutter
Browsers|$HOME/Library/Application Support/Google/Chrome|$HOME/Library/Application Support/Firefox|$HOME/Library/Application Support/com.operasoftware.Opera|$HOME/Library/Application Support/BraveSoftware|$HOME/Library/Caches/Google/Chrome|$HOME/Library/Caches/Firefox|$HOME/Library/Caches/com.operasoftware.Opera|$HOME/Library/Safari
App Containers|$HOME/Library/Containers
App Support (other)|$HOME/Library/Application Support
App Caches (other)|$HOME/Library/Caches
User Projects|$HOME/Works|$HOME/develop|$HOME/projects|$HOME/Projects|$HOME/Documents|$HOME/Downloads|$HOME/Desktop
Trash|$HOME/.Trash
EOF
}

# Paths already counted in other categories (subtract from "other" buckets).
_excluded_app_support=(
  "$HOME/Library/Application Support/Google/Chrome"
  "$HOME/Library/Application Support/Firefox"
  "$HOME/Library/Application Support/com.operasoftware.Opera"
  "$HOME/Library/Application Support/BraveSoftware"
)
_excluded_caches=(
  "$HOME/Library/Caches/Google/Chrome"
  "$HOME/Library/Caches/Firefox"
  "$HOME/Library/Caches/com.operasoftware.Opera"
)

# Size of a directory minus the size of excluded children paths.
_dir_size_minus() {
  local root=$1; shift
  local total exc s
  total=$(dir_size "$root")
  for exc in "$@"; do
    s=$(dir_size "$exc")
    total=$(( total - s ))
  done
  (( total < 0 )) && total=0
  echo "$total"
}

cmd_scan() {
  local show_help=0
  while (( $# > 0 )); do
    case "$1" in
      -h|--help) show_help=1 ;;
      *) log_warn "scan: ignoring unknown arg: $1" ;;
    esac
    shift
  done

  if [[ $show_help -eq 1 ]]; then
    cat <<EOF
${C_BOLD}clmac scan${C_RESET} — categorized disk usage breakdown

  Walks curated locations and reports sizes by intent, not by macOS's
  confusing Storage categories.

Use --json (global) for machine-readable output.
EOF
    return 0
  fi

  # Pre-resolve excluded paths.
  local exc_app_support_args=() exc_cache_args=()
  for p in "${_excluded_app_support[@]}"; do exc_app_support_args+=("$p"); done
  for p in "${_excluded_caches[@]}";     do exc_cache_args+=("$p"); done

  spinner_start

  # Pass 1: collect (category, path, kind) tuples. kind is one of:
  #   normal | minus_app_support | minus_caches
  local -a cats=() paths=() kinds=()
  local cat_name rest_pipe p kind
  while IFS='|' read -r cat_name rest_pipe; do
    [[ -z "$cat_name" || -z "$rest_pipe" ]] && continue
    local -a parts
    IFS='|' read -ra parts <<< "$rest_pipe"
    for p in "${parts[@]}"; do
      [[ -z "$p" ]] && continue
      p=${p//\$HOME/$HOME}
      [[ -e "$p" ]] || continue
      if [[ "$cat_name" == "App Support (other)" && "$p" == "$HOME/Library/Application Support" ]]; then
        kind="minus_app_support"
      elif [[ "$cat_name" == "App Caches (other)" && "$p" == "$HOME/Library/Caches" ]]; then
        kind="minus_caches"
      else
        kind="normal"
      fi
      cats+=("$cat_name")
      paths+=("$p")
      kinds+=("$kind")
    done
  done < <(_scan_categories)

  # Pass 2: parallel size lookup for every unique path.
  # Build a path→bytes map by running dir_size_parallel over all paths.
  declare -A size_map=()
  local line bytes path
  while IFS=$'\t' read -r bytes path; do
    [[ -z "$path" ]] && continue
    size_map["$path"]=$bytes
  done < <(printf '%s\0' "${paths[@]}" | dir_size_parallel)

  # Pass 3: assemble rows. For "minus_*" kinds, subtract excluded sizes.
  local rows="" sz
  for i in "${!paths[@]}"; do
    p=${paths[i]}
    case "${kinds[i]}" in
      minus_app_support)
        sz=$(_dir_size_minus "$p" "${exc_app_support_args[@]}" \
          "$HOME/Library/Application Support/CrossOver")
        ;;
      minus_caches)
        sz=$(_dir_size_minus "$p" "${exc_cache_args[@]}")
        ;;
      *)
        sz=${size_map["$p"]:-0}
        ;;
    esac
    rows+="${cats[i]}"$'\t'"${p}"$'\t'"${sz}"$'\n'
  done
  spinner_stop

  if [[ "$CMM_JSON" -eq 1 ]]; then
    _scan_json "$rows"
  else
    _scan_table "$rows"
  fi
}

_scan_table() {
  local rows=$1
  # Compute category totals.
  printf '\n%s%sclmac scan%s — disk usage by category\n\n' "$C_BOLD" "$C_BLUE" "$C_RESET"

  # Totals per category
  printf '%s%-22s %12s%s\n' "$C_BOLD" "CATEGORY" "SIZE" "$C_RESET"
  printf '%s%s%s\n' "$C_DIM" "$(printf '%.0s-' {1..40})" "$C_RESET"

  # Sort categories by their total size desc. Guard against empty keys
  # (a trailing newline in $rows can produce a phantom "" key in awk).
  local totals
  totals=$(awk -F'\t' 'NF >= 3 && $1 != "" { totals[$1] += $3 }
                       END { for (k in totals) printf "%s\t%d\n", k, totals[k] }' <<< "$rows" \
    | sort -t$'\t' -k2 -nr)

  local grand=0 cat bytes
  while IFS=$'\t' read -r cat bytes; do
    [[ -z "$cat" || "$bytes" == "" ]] && continue
    printf '%-22s %s\n' "$cat" "$(human_size_padded "$bytes" 12)"
    grand=$(( grand + bytes ))
  done <<< "$totals"
  printf '%s%s%s\n' "$C_DIM" "$(printf '%.0s-' {1..40})" "$C_RESET"
  printf '%s%-22s %s%s\n\n' \
    "$C_BOLD" "TOTAL" \
    "$(printf '%s%12s%s' "$C_BOLD$C_MAGENTA" "$(human_size "$grand")" "$C_RESET")" \
    "$C_RESET"

  # Detail listing, sorted by bytes desc within each category.
  printf '%s%sTop items%s\n\n' "$C_BOLD" "$C_BLUE" "$C_RESET"
  printf '%s%-22s %12s  %s%s\n' "$C_BOLD" "CATEGORY" "SIZE" "PATH" "$C_RESET"
  printf '%s%s%s\n' "$C_DIM" "$(printf '%.0s-' {1..90})" "$C_RESET"

  # Detail rows. awk filter avoids the same phantom-empty-row problem.
  awk -F'\t' 'NF >= 3 && $1 != "" { print }' <<< "$rows" \
  | sort -t$'\t' -k3 -nr \
  | while IFS=$'\t' read -r cat path bytes; do
      [[ -z "$cat" || -z "$bytes" ]] && continue
      # Skip rows under 10 MB in table view to reduce noise.
      if (( bytes < 10 * 1024 * 1024 )); then continue; fi
      local short=${path/#$HOME/\~}
      printf '%-22s %s  %s%s%s\n' \
        "$cat" "$(human_size_padded "$bytes" 12)" \
        "$C_DIM" "$short" "$C_RESET"
    done
  echo
}

_scan_json() {
  local rows=$1
  # Build JSON via jq.
  printf '%s' "$rows" \
    | awk -F'\t' 'NF==3 { printf "%s\t%s\t%s\n", $1, $2, $3 }' \
    | jq -R -s '
        split("\n")
        | map(select(length > 0) | split("\t") | { category: .[0], path: .[1], bytes: (.[2] | tonumber) })
        | { items: ., total_bytes: (map(.bytes) | add) }
      '
}
