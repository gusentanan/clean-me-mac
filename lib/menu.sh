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

# Mole mascot shown to the left of the top-level menu on a wide-enough
# terminal (see tui_select_menu's art_active check) — a nod to tw93/mole,
# whose interaction design this UI follows (see tui.sh's file header).
# Two frames (blink) cycled every 200ms by tui_select_menu's tick loop.
#
# _menu_art_wrap colors each LINE individually rather than wrapping the
# whole block once: _tui_render_with_art splits a frame apart into
# separate array elements (one per line) and prints each on its own row
# interleaved with unrelated menu content. A single leading color code
# with the reset only at the very end would leave every line after the
# first relying on ANSI state "carrying over" across other printf calls
# in between — fragile and liable to bleed into or get clobbered by the
# menu column's own colors. Each line closing its own color is the only
# way that's safe.
_menu_art_wrap() {
  local line
  while IFS= read -r line; do
    printf '%s%s%s\n' "$C_ORANGE" "$line" "$C_RESET"
  done
}

_menu_art_frame_a() {
  _menu_art_wrap <<'EOF'
    .-""""-.
   /  o  o  \
  |     <    |
   \  '--'  /
    '.____.'
     /|  |\
    ' |  | '
      |  |
    __|  |__
EOF
}

_menu_art_frame_b() {
  _menu_art_wrap <<'EOF'
    .-""""-.
   /  -  -  \
  |     <    |
   \  '--'  /
    '.____.'
     /|  |\
    ' |  | '
      |  |
    __|  |__
EOF
}

cmd_menu() {
  local header="clmac — macOS cleanup"
  local footer="↑↓ Navigate | ⏎ Select | Q Quit"
  local -a CMM_MENU_ART_FRAMES=("$(_menu_art_frame_a)" "$(_menu_art_frame_b)")

  # Own one alt-screen for the entire interactive session instead of
  # letting each picker call open/close its own. Without this, every
  # report command (scan/doctor/system) printed its plain-text output to
  # the PRIMARY screen in the gap between two alt-screen picker frames —
  # invisible while the menu was showing, but still sitting in real
  # terminal scrollback, which is exactly what a user scrolling up would
  # find. Keeping one alt-screen open for the whole session (like
  # vim/htop/less do) means nothing any action prints ever touches
  # scrollback; only the terminal state from before `clmac` was launched
  # comes back when the session ends. tui_select_menu/tui_select_multi's
  # own enter/leave calls become no-ops while this is active (tui.sh).
  tui_enter_alt
  trap 'tui_leave_alt' RETURN

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
    chosen=$(printf '%s' "$rows" | select_menu "$header" "$footer" " clmac " CMM_MENU_ART_FRAMES)
    rc=$?
    (( rc == 130 )) && return 0
    [[ -z "$chosen" ]] && return 0

    # Clear before dispatching so each action starts on a blank frame
    # instead of drawing over whatever the picker last had on screen —
    # tui_clear_screen (not a plain \033[2J) also drops whatever
    # scrollback the terminal kept inside the alt-screen buffer itself,
    # which a visible-viewport-only clear leaves scrollable-into.
    tui_clear_screen

    # scan/system/doctor/orphans/clean print report output; pause for a
    # keypress before looping back so it's actually readable.
    case "$chosen" in
      scan)    source "$CMM_LIB/scan.sh";    cmd_scan;    press_any_key ;;
      explore)
        # explore may exec a separate Go binary (cmd/explore) with its own
        # independent alt-screen lifecycle (tea.WithAltScreen) rather than
        # bash's managed one — its rmcup on exit would desync our
        # CMM_TUI_ALT_ACTIVE flag from the terminal's real state if we
        # left our alt-screen "active" underneath it. Hand it a clean
        # terminal instead and reclaim alt-screen once it's back.
        source "$CMM_LIB/explore.sh"
        tui_leave_alt
        cmd_explore
        tui_enter_alt
        ;;
      system)  source "$CMM_LIB/system.sh";  cmd_system;  press_any_key ;;
      orphans) source "$CMM_LIB/orphans.sh"; cmd_orphans; press_any_key ;;
      clean)   source "$CMM_LIB/clean.sh";   cmd_clean;   press_any_key ;;
      doctor)  source "$CMM_LIB/doctor.sh";  cmd_doctor;  press_any_key ;;
    esac
  done
}
