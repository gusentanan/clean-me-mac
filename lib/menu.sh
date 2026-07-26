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

# Sunset/reflection ASCII art shown to the left of the top-level menu on
# a wide-enough terminal (see tui_select_menu's art_active check). This is
# a hand-transcription (visual read of a reference screenshot, not an
# OCR/pixel-exact extraction — there's no tool in this environment for
# that) of a density-mapped image-to-ASCII render, so treat it as a close
# approximation rather than a guaranteed exact match; swap
# _MENU_ART_BASE for the original generator's text output directly if
# exactness matters.
#
# The top ~6 rows are the sun/glow disc and stay fixed; rows below that
# are the water-reflection texture, which _menu_art_frame cyclically
# rotates a few characters per frame to read as a shimmer rather than a
# static block — cheap and low-risk since frame B is derived from frame
# A programmatically instead of hand-duplicated (no risk of the two
# drifting out of sync from a transcription slip).
_MENU_ART_BASE=(
'                {{{{{{{{{{{{{'
'              ~{}}{{}}{{}}{{}}{{}}?'
'        1{{{{{{{{{{{{{{{{{{{{{{{{~'
'     )1)1)1)1)1)1)))))))))1)1)1)1)1)1(1'
'    /\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\'
'   ////////////////////////////////////'
'   rjrjrjrjrjrjrjjjjjjjjjjjjjrjrjrjrjrjrjrjrj'
'  nxuunxuunxuunxuunxuuxxuunxuunxnuuxnuuxnuux'
'  vcvcvcvcvcvcvcvcvcvcvcccvcvcvcvcvcvcvcvcvcvc~'
' zzXYzzXYzzXYzzXYzzYYzzYYzzYYzzYXzzYXzzYXzzYXzzY'
'UUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUU'
'UUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUU'
'UUUUUUUUUUUUUUUUUUXYXXYUUUYzvczuuxucvuuzUXYX'
')uvczXUzzzYUUUUUUUUUUUUUUYXYzvccvnvzUXUUUUU'
'xv1[jnuvzzzvcncvzzuvzYUUUUXYXzvzXzvzYzzzYXYXz_'
' ;\|/fxuuuxjtfjxxvvvvvvuxxf//\|tftjxvzYzzz_'
'  :1\//frjrruuuuuuvzzzzzzzzzzvvuuxjrf/'
'  \uvuuvuxrxvvvvuuuvvvvuuuuuuuuuczzUUXYzvvvvur'
'     ]{{{{i      ?{{{{{{\{{{\1'
'     //\{(//|((1{(|/tttt\||{1{1{{}{iI>'
'     i()()(({{{{{1{(((((|///tjt/|(/(\(\)'
'      ?[{{{{['
'       {{{{{{{'
)

# _menu_art_frame <rotate-by> — prints one frame, water rows (index 6+)
# left-rotated by <rotate-by> characters. Each line carries its own
# color+reset rather than the block being wrapped once: _tui_render_with_art
# splits a frame into separate array elements printed on different rows
# interleaved with unrelated menu content, so relying on ANSI state to
# "carry over" between them would be fragile and liable to bleed into the
# menu column's own colors.
_menu_art_frame() {
  local shift=$1 i line len n
  for i in "${!_MENU_ART_BASE[@]}"; do
    line=${_MENU_ART_BASE[i]}
    if (( i >= 6 )); then
      len=${#line}
      if (( len > 0 )); then
        n=$(( shift % len ))
        line="${line:n}${line:0:n}"
      fi
    fi
    printf '%s%s%s\n' "$C_ORANGE" "$line" "$C_RESET"
  done
}

_menu_art_frame_a() { _menu_art_frame 0; }
_menu_art_frame_b() { _menu_art_frame 3; }

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
