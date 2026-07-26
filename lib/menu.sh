#!/opt/homebrew/bin/bash
# cmd_menu — top-level interactive launcher. Shown when clmac is run with
# no subcommand in a terminal. Loops back to the menu after each action
# until the user quits.

_menu_items() {
  cat <<'EOF'
scan|Categorized disk usage breakdown ($HOME)
explore|Browse disk usage interactively (bar-chart drill-down)
system|Explain the "System Data" gap
orphans|Find & remove leftover app data
clean|Run a known-safe cleanup preset
doctor|One-screen health summary
EOF
}

cmd_menu() {
  local header="clmac — macOS cleanup"
  local footer="↑↓ Navigate | ⏎ Select | Q Quit"

  while true; do
    local rows="" name desc chosen
    while IFS='|' read -r name desc; do
      [[ -z "$name" ]] && continue
      rows+="$(printf '%-10s %s' "$name" "$desc")"$'\t'"${name}"$'\n'
    done < <(_menu_items)

    # NOTE: chosen=$(...) runs select_menu in a subshell, so a variable it
    # sets (CMM_MENU_QUIT) would NOT propagate back here — only the exit
    # code survives the command-substitution boundary. Key off $? instead.
    local rc
    chosen=$(printf '%s' "$rows" | select_menu "$header" "$footer" " clmac ")
    rc=$?
    (( rc == 130 )) && return 0
    [[ -z "$chosen" ]] && return 0

    case "$chosen" in
      scan)    source "$CMM_LIB/scan.sh";    cmd_scan ;;
      explore) source "$CMM_LIB/explore.sh"; cmd_explore ;;
      system)  source "$CMM_LIB/system.sh";  cmd_system ;;
      orphans) source "$CMM_LIB/orphans.sh"; cmd_orphans ;;
      clean)   source "$CMM_LIB/clean.sh";   cmd_clean ;;
      doctor)  source "$CMM_LIB/doctor.sh";  cmd_doctor ;;
    esac
  done
}
