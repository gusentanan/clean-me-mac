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
  printf '\n%sDisk%s\n' "$C_BOLD" "$C_RESET"
  # Pull APFS data volume stats.
  local line capacity used
  line=$(diskutil apfs list 2>/dev/null \
    | awk '/Capacity Ceiling/ { ceil=$NF; gsub("[()]","",ceil) } /Capacity In Use By Volumes/ { used=$NF; gsub("[()]","",used) } END { printf "%s %s", ceil, used }')

  if [[ -n "$line" ]]; then
    echo "  Container:    $(diskutil apfs list 2>/dev/null | awk '/Size \(Capacity Ceiling\)/ {print $5, $6; exit}')"
    echo "  In use:       $(diskutil apfs list 2>/dev/null | awk '/Capacity In Use By Volumes/ {print $7, $8; exit}')"
    echo "  Not allocated:$(diskutil apfs list 2>/dev/null | awk '/Capacity Not Allocated/ {print $5, $6; exit}')"
  else
    df -h / | awk 'NR==2 { printf "  Root: %s used of %s (%s)\n", $3, $2, $5 }'
  fi
}

_doctor_top_home() {
  printf '\n%sTop 10 dirs in $HOME (excluding Library):%s\n' "$C_BOLD" "$C_RESET"
  local d sz
  {
    # Visible top-level dirs.
    for d in "$HOME"/*; do
      [[ -d "$d" ]] || continue
      [[ "$(basename "$d")" == "Library" ]] && continue
      sz=$(dir_size "$d")
      printf '%d\t%s\n' "$sz" "$d"
    done
    # Hidden top-level dirs.
    for d in "$HOME"/.*; do
      [[ -d "$d" ]] || continue
      local n
      n=$(basename "$d")
      [[ "$n" == "." || "$n" == ".." ]] && continue
      sz=$(dir_size "$d")
      printf '%d\t%s\n' "$sz" "$d"
    done
  } | sort -t$'\t' -k1 -nr | head -10 \
    | while IFS=$'\t' read -r sz path; do
        printf '  %10s  %s\n' "$(human_size "$sz")" "${path/#$HOME/\~}"
      done
}

_doctor_orphans() {
  printf '\n%sOrphans:%s ' "$C_BOLD" "$C_RESET"
  # Source orphans lazily.
  source "$CMM_LIB/orphans.sh"
  CMM_JSON=0 cmd_orphans --count-only
}

_doctor_top_presets() {
  printf '\n%sTop 5 cleanable presets (current size):%s\n' "$C_BOLD" "$C_RESET"
  source "$CMM_LIB/clean.sh"

  local f sz line
  local rows=""
  while IFS= read -r f; do
    _load_preset "$f"
    sz=$(_preset_current_size)
    rows+="${sz}"$'\t'"${PRESET_NAME}"$'\t'"${PRESET_DESC}"$'\n'
  done < <(_list_preset_files)

  printf '%s' "$rows" | sort -t$'\t' -k1 -nr | head -5 \
    | while IFS=$'\t' read -r sz name desc; do
        [[ -z "$name" ]] && continue
        printf '  %10s  %-22s %s\n' "$(human_size "$sz")" "$name" "$desc"
      done
}

_doctor_help() {
  cat <<EOF
${C_BOLD}clmac doctor${C_RESET}

  One-shot health screen combining disk usage, top dirs in \$HOME,
  orphan count, and the largest cleanable presets.
EOF
}
