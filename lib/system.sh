#!/opt/homebrew/bin/bash
# cmd_system — investigate what macOS lumps into "System Data" and "macOS"
#              in Storage settings, and explain the gap vs clmac scan.

cmd_system() {
  local show_help=0
  while (( $# > 0 )); do
    case "$1" in
      -h|--help) show_help=1 ;;
      *) log_warn "system: ignoring unknown arg: $1" ;;
    esac
    shift
  done

  if [[ $show_help -eq 1 ]]; then
    _system_help
    return 0
  fi

  printf '\n%s%sclmac system%s — what macOS hides in "System Data"\n' "$C_BOLD" "$C_BLUE" "$C_RESET"
  printf '%s%s%s\n\n' "$C_DIM" "$(printf '%.0s─' {1..60})" "$C_RESET"

  _system_disk_gap
  printf '\n'
  _system_snapshots
  printf '\n'
  _system_ios_backups
  printf '\n'
  _system_vm
  printf '\n'
  _system_apps
  printf '\n'
  printf '%s%sNext steps%s\n' "$C_BOLD" "$C_BLUE" "$C_RESET"
  printf '  clmac clean apfs-snapshots  %s# reclaim snapshot space%s\n' "$C_DIM" "$C_RESET"
  printf '  clmac clean ios-backups     %s# remove local device backups%s\n' "$C_DIM" "$C_RESET"
  printf '  clmac orphans               %s# find leftover app data%s\n\n' "$C_DIM" "$C_RESET"
}

_system_disk_gap() {
  printf '%s%sDisk%s\n' "$C_BOLD" "$C_BLUE" "$C_RESET"

  local apfs cap_bytes used_bytes free_bytes
  apfs=$(diskutil apfs list 2>/dev/null)
  cap_bytes=$(awk  '/Size \(Capacity Ceiling\)/ { print $5; exit }' <<< "$apfs")
  used_bytes=$(awk '/Capacity In Use By Volumes/ { print $7; exit }' <<< "$apfs")
  free_bytes=$(awk '/Capacity Not Allocated/     { print $5; exit }' <<< "$apfs")

  if [[ -n "$used_bytes" ]]; then
    printf '  %-16s %s\n' "Capacity:"  "$(human_size_c "$cap_bytes")"
    printf '  %-16s %s\n' "Used:"      "$(human_size_c "$used_bytes")"
    printf '  %-16s %s\n' "Free:"      "$(human_size_c "$free_bytes")"
  else
    df -h / | awk 'NR==2 { printf "  Root: %s used of %s\n", $3, $2 }'
  fi

  printf '\n  %sWhy clmac scan shows less than macOS Storage:%s\n' "$C_DIM" "$C_RESET"
  printf '  %s• clmac scan only sees paths inside $HOME — not the system volume%s\n' "$C_DIM" "$C_RESET"
  printf '  %s• "macOS" in Storage = OS, frameworks, runtime (~43G on a fresh install)%s\n' "$C_DIM" "$C_RESET"
  printf '  %s• "System Data" = APFS snapshots + swap + iOS backups + other (see below)%s\n' "$C_DIM" "$C_RESET"
  printf '  %s• /Applications is counted separately by macOS but not by clmac scan%s\n' "$C_DIM" "$C_RESET"
}

_system_snapshots() {
  printf '%s%sAPFS Local Snapshots%s' "$C_BOLD" "$C_BLUE" "$C_RESET"

  local -a snaps=()
  while IFS= read -r s; do
    # tmutil on newer macOS emits a "Snapshots for volume group..." header line
    [[ "$s" == com.apple.* ]] && snaps+=("$s")
  done < <(tmutil listlocalsnapshots / 2>/dev/null)

  if (( ${#snaps[@]} == 0 )); then
    printf ' — %snone%s\n' "$C_GREEN" "$C_RESET"
    return
  fi

  printf ' — %s%d snapshot(s)%s %s← often the biggest chunk of "System Data"%s\n' \
    "$C_YELLOW$C_BOLD" "${#snaps[@]}" "$C_RESET" "$C_DIM" "$C_RESET"

  local s
  for s in "${snaps[@]}"; do
    printf '  %s%s%s\n' "$C_DIM" "$s" "$C_RESET"
  done
  printf '  %sclmac clean apfs-snapshots%s  to delete all\n' "$C_CYAN" "$C_RESET"
}

_system_ios_backups() {
  local backup_dir="$HOME/Library/Application Support/MobileSync/Backup"
  printf '%s%siOS / iPad Backups%s' "$C_BOLD" "$C_BLUE" "$C_RESET"

  if [[ ! -d "$backup_dir" ]]; then
    printf ' — %snone%s\n' "$C_GREEN" "$C_RESET"
    return
  fi

  spinner_start "sizing iOS backups"
  local sz
  sz=$(dir_size "$backup_dir")
  spinner_stop

  if (( sz == 0 )); then
    printf ' — %snone%s\n' "$C_GREEN" "$C_RESET"
    return
  fi

  printf ' — %s\n' "$(human_size_c "$sz")"
  local d
  shopt -s nullglob
  for d in "$backup_dir"/*/; do
    [[ -d "$d" ]] || continue
    local bsz
    bsz=$(dir_size "$d")
    printf '  %s  %s%s%s\n' "$(human_size_padded "$bsz" 10)" "$C_DIM" "$(basename "$d")" "$C_RESET"
  done
  shopt -u nullglob
  printf '  %sclmac clean ios-backups%s  to remove (enable iCloud backup first)\n' "$C_CYAN" "$C_RESET"
}

_system_vm() {
  printf '%s%sVirtual Memory / Swap%s' "$C_BOLD" "$C_BLUE" "$C_RESET"
  local vm_dir="/private/var/vm"

  if [[ ! -d "$vm_dir" ]]; then
    printf ' — %snot present%s\n' "$C_GREEN" "$C_RESET"
    return
  fi

  local sz
  sz=$(dir_size "$vm_dir")
  printf ' — %s %s(managed by macOS, not removable while running)%s\n' \
    "$(human_size_c "$sz")" "$C_DIM" "$C_RESET"

  local f
  shopt -s nullglob
  for f in "$vm_dir"/*; do
    [[ -e "$f" ]] || continue
    local fsz
    fsz=$(dir_size "$f")
    printf '  %s  %s%s%s\n' "$(human_size_padded "$fsz" 10)" "$C_DIM" "$(basename "$f")" "$C_RESET"
  done
  shopt -u nullglob
  printf '  %sTip: reduce swap by closing memory-heavy apps or adding more RAM%s\n' "$C_DIM" "$C_RESET"
}

_system_apps() {
  printf '%s%s/Applications%s' "$C_BOLD" "$C_BLUE" "$C_RESET"

  if [[ ! -d /Applications ]]; then
    printf ' — %snot present%s\n' "$C_GREEN" "$C_RESET"
    return
  fi

  spinner_start "sizing /Applications"
  local sz
  sz=$(dir_size /Applications)
  spinner_stop

  printf ' — %s\n' "$(human_size_c "$sz")"
  printf '  %sThis matches the "Applications" entry in macOS Storage settings%s\n' "$C_DIM" "$C_RESET"
  printf '  %sclmac orphans%s  to find leftover data from uninstalled apps\n' "$C_CYAN" "$C_RESET"
}

_system_help() {
  cat <<EOF
${C_BOLD}clmac system${C_RESET} — explain the gap between macOS Storage and clmac scan

  macOS Storage shows "System Data" and "macOS" as separate buckets
  that clmac scan cannot see (they live outside \$HOME). This command
  breaks them down: APFS snapshots, iOS backups, swap, /Applications.

  ${C_BOLD}USAGE${C_RESET}
    clmac system

  ${C_BOLD}SEE ALSO${C_RESET}
    clmac clean apfs-snapshots   delete local Time Machine snapshots
    clmac clean ios-backups      remove local iPhone/iPad backups
    clmac scan                   full \$HOME breakdown
EOF
}
