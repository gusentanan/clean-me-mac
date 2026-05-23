#!/opt/homebrew/bin/bash
# cmd_doctor — one-screen health summary.

cmd_doctor() {
  while (( $# > 0 )); do
    case "$1" in
      -h|--help) _doctor_help; return 0 ;;
      *) ;;
    esac
    shift
  done

  printf '\n%s%sclmac doctor%s\n' "$C_BOLD" "$C_BLUE" "$C_RESET"
  printf '%s%s%s\n' "$C_DIM" "$(printf '%.0s=' {1..50})" "$C_RESET"

  _doctor_disk
  _doctor_top_home
  _doctor_orphans
  _doctor_top_presets

  printf '\n%sTip:%s clmac scan       — full breakdown\n' "$C_DIM" "$C_RESET"
  printf '%s    %s clmac orphans    — review leftover app data\n' "$C_DIM" "$C_RESET"
  printf '%s    %s clmac clean      — interactive preset cleanup\n\n' "$C_DIM" "$C_RESET"
}

_doctor_disk() {
  printf '\n%s%sDisk%s\n' "$C_BOLD" "$C_BLUE" "$C_RESET"

  # Parse APFS container stats — first container only (boot disk).
  local apfs cap used free pct
  apfs=$(diskutil apfs list 2>/dev/null)
  cap=$(awk  '/Size \(Capacity Ceiling\)/ { print $5; exit }'        <<< "$apfs")
  used=$(awk '/Capacity In Use By Volumes/ { print $7; exit }'       <<< "$apfs")
  free=$(awk '/Capacity Not Allocated/      { print $5; exit }'      <<< "$apfs")

  if [[ -n "$cap" && -n "$used" ]]; then
    pct=$(awk -v u="$used" -v c="$cap" 'BEGIN { printf "%.0f", (u/c)*100 }')
    local pct_color="$C_GREEN"
    (( pct >= 70 )) && pct_color="$C_YELLOW"
    (( pct >= 85 )) && pct_color="$C_RED$C_BOLD"
    printf '  %-14s %s\n'      "Capacity:"     "$(human_size_c "$cap")"
    printf '  %-14s %s  %s(%s%%)%s\n' "In use:"  "$(human_size_c "$used")" "$pct_color" "$pct" "$C_RESET"
    printf '  %-14s %s\n'      "Free:"         "$(human_size_c "$free")"
  else
    df -h / | awk 'NR==2 { printf "  Root: %s used of %s (%s)\n", $3, $2, $5 }'
  fi
}

_doctor_top_home() {
  printf '\n%s%sTop 10 dirs in $HOME%s %s(excluding Library)%s\n' \
    "$C_BOLD" "$C_BLUE" "$C_RESET" "$C_DIM" "$C_RESET"
  spinner_start
  local out
  out=$(
    # Collect candidate paths (visible + hidden), excluding Library.
    local -a paths=()
    local d n
    for d in "$HOME"/*; do
      [[ -d "$d" ]] || continue
      [[ "$(basename "$d")" == "Library" ]] && continue
      paths+=("$d")
    done
    for d in "$HOME"/.*; do
      [[ -d "$d" ]] || continue
      n=$(basename "$d")
      [[ "$n" == "." || "$n" == ".." ]] && continue
      paths+=("$d")
    done

    # Parallel size lookup, sort desc, take top 10.
    printf '%s\0' "${paths[@]}" \
      | dir_size_parallel \
      | sort -t$'\t' -k1 -nr | head -10 \
      | while IFS=$'\t' read -r sz path; do
          printf '  %s  %s\n' "$(human_size_padded "$sz" 10)" "${path/#$HOME/\~}"
        done
  )
  spinner_stop
  printf '%s\n' "$out"
}

_doctor_orphans() {
  printf '\n%s%sOrphans:%s ' "$C_BOLD" "$C_BLUE" "$C_RESET"
  source "$CMM_LIB/orphans.sh"
  spinner_start
  local out
  out=$(cmd_orphans --count-only 2>/dev/null)
  spinner_stop
  # Colorize: highlight the numeric count and reclaimable size.
  # Format: "N orphans, SIZE reclaimable"
  if [[ "$out" =~ ^([0-9]+)\ orphans,\ (.+)\ reclaimable$ ]]; then
    local n=${BASH_REMATCH[1]} sz=${BASH_REMATCH[2]}
    local n_color="$C_GREEN"
    (( n > 0 )) && n_color="$C_YELLOW$C_BOLD"
    printf '%s%s%s orphans, %s%s%s reclaimable\n' \
      "$n_color" "$n" "$C_RESET" "$C_YELLOW$C_BOLD" "$sz" "$C_RESET"
  else
    printf '%s\n' "$out"
  fi
}

_doctor_top_presets() {
  printf '\n%s%sTop 5 cleanable presets%s %s(current size)%s\n' \
    "$C_BOLD" "$C_BLUE" "$C_RESET" "$C_DIM" "$C_RESET"
  source "$CMM_LIB/clean.sh"
  spinner_start
  local out
  out=$(
    local f sz rows=""
    while IFS= read -r f; do
      _load_preset "$f"
      sz=$(_preset_current_size)
      rows+="${sz}"$'\t'"${PRESET_NAME}"$'\t'"${PRESET_DESC}"$'\n'
    done < <(_list_preset_files)
    printf '%s' "$rows" | sort -t$'\t' -k1 -nr | head -5 \
      | while IFS=$'\t' read -r sz name desc; do
          [[ -z "$name" ]] && continue
          printf '  %s  %s%-22s%s %s%s%s\n' \
            "$(human_size_padded "$sz" 10)" \
            "$C_CYAN" "$name" "$C_RESET" \
            "$C_DIM" "$desc" "$C_RESET"
        done
  )
  spinner_stop
  printf '%s\n' "$out"
}

_doctor_help() {
  cat <<EOF
${C_BOLD}clmac doctor${C_RESET}

  One-shot health screen combining disk usage, top dirs in \$HOME,
  orphan count, and the largest cleanable presets.
EOF
}
