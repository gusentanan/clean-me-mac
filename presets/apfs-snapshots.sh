PRESET_NAME="apfs-snapshots"
PRESET_DESC="Delete APFS local Time Machine snapshots (reclaims 'System Data' space)"
PRESET_SAFE=false
# shellcheck disable=SC2016
PRESET_COMMAND='
  mapfile -t _snaps < <(tmutil listlocalsnapshots / 2>/dev/null | grep '^com\.apple\.')
  if (( ${#_snaps[@]} == 0 )); then
    printf "  No local snapshots found.\n"
  else
    printf "  Deleting %d snapshot(s)...\n" "${#_snaps[@]}"
    for _snap in "${_snaps[@]}"; do
      _date="${_snap##*.}"
      if tmutil deletelocalsnapshots "$_date" 2>/dev/null; then
        printf "  deleted %s\n" "$_date"
      elif tmutil deletelocalsnapshots / 2>/dev/null; then
        printf "  deleted all local snapshots on /\n"
        break
      fi
    done
    printf "  Done. Disk free space will update shortly.\n"
  fi
'
