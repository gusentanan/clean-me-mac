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

# Per-key color so the six menu entries are distinguishable at a glance
# rather than reading as one undifferentiated block of white text. Keyed
# by the same name used as _menu_items' first column and the picker's
# payload — declared at file scope (not inside a function) since the
# C_* vars are only ever set once, by common.sh, well before menu.sh's
# own functions run.
declare -A _MENU_KEY_COLORS=(
  [scan]="$C_BLUE"
  [explore]="$C_CYAN"
  [system]="$C_MAGENTA"
  [orphans]="$C_RED"
  [clean]="$C_GREEN"
  [doctor]="$C_PURPLE"
)

# Big block-letter "CLMAC" wordmark printed above the menu — same idea as
# omarchy's installer TUI (a large chunky pixel-font logo over the
# form/content). Follows omarchy's specific letterform conventions as
# closely as I can read them off a screenshot (no font source available):
# an open bracket-shaped C, an M with a pointed zigzag valley, an A with
# flared triangular legs, and — the detail that most sets the style apart
# from a generic block font — small flared "feet" where each stroke meets
# the baseline, which C/M/A (and the improvised L, not in "OMARCHY" but
# built to match) all carry at their base.
#
# One static block of text, no animation. Each row prints as its own line
# (no side-by-side column-pairing needed here, unlike the reverted
# left-panel attempt), so there's no risk of the "color state bleeding
# across separately-printed lines" bug that mattered there — still
# wrapping each line in its own color+reset anyway since that's cheap and
# one less thing to get wrong if this ever gets reused elsewhere.
_menu_banner() {
  local -a letter_c=('  █████ ' ' ███████' '███     ' '██      ' '██      ' '██      ' '███     ' ' ███████' '  █████ ')
  local -a letter_l=('██      ' '██      ' '██      ' '██      ' '██      ' '██      ' '██      ' '███     ' '████████')
  local -a letter_m=('██     ██' '███   ███' '████ ████' '██ ███ ██' '██  █  ██' '██     ██' '██     ██' '██     ██' '███   ███')
  local -a letter_a=('  ████  ' ' ██  ██ ' '██    ██' '██    ██' '████████' '██    ██' '██    ██' '██    ██' '███  ███')
  local i
  for i in 0 1 2 3 4 5 6 7 8; do
    printf '%s%s  %s  %s  %s  %s%s\n' \
      "$C_CYAN$C_BOLD" "${letter_c[i]}" "${letter_l[i]}" "${letter_m[i]}" "${letter_a[i]}" "${letter_c[i]}" "$C_RESET"
  done
}

cmd_menu() {
  local header="clmac — macOS cleanup"
  local footer="↑↓ Navigate | ⏎ Select | Q Quit"
  local banner
  banner=$(_menu_banner)

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
      # Pad the plain name to width FIRST, then wrap in color — ANSI
      # codes don't count toward printf's %-Ns width, so coloring before
      # padding would throw the column alignment off (same reasoning as
      # human_size_padded in common.sh).
      local padded_name key_color
      padded_name=$(printf '%-10s' "$name")
      key_color=${_MENU_KEY_COLORS[$name]:-$C_RESET}
      rows+="${key_color}${padded_name}${C_RESET} ${desc}"$'\t'"${name}"$'\n'
    done < <(_menu_items)

    # NOTE: chosen=$(...) runs select_menu in a subshell, so a variable it
    # sets (CMM_MENU_QUIT) would NOT propagate back here — only the exit
    # code survives the command-substitution boundary. Key off $? instead.
    local rc
    chosen=$(printf '%s' "$rows" | select_menu "$header" "$footer" " clmac " "$banner")
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
