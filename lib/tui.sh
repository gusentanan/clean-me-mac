#!/opt/homebrew/bin/bash
# Raw-terminal picker engine — replaces fzf. No box borders, ▶ pointer,
# ☐/☑ checkboxes, paginated arrow/vim navigation, mole-style.
#
# Hand-rolled from the functional description of tw93/mole's UI (CSI arrow
# decoding, terminal-height pagination, tput smcup/rmcup alt-screen), not
# ported from mole's source — mole is GPLv3 and this project isn't, so this
# file is an independent implementation of standard, ubiquitous
# terminal-picker techniques (the same ones gum, lazygit, etc. use).
#
# Calling convention: tui_select_menu/tui_select_multi are always invoked at
# the end of an `items | select_menu ...` pipe (see lib/ui.sh), which forks
# a subshell per pipeline stage — so a trap set in here never clobbers the
# caller's own `trap ... EXIT INT TERM` (common.sh, clmac). That's a
# structural property of always being pipe-invoked, not something enforced
# by this file; the trap-chain in _tui_arm_traps below is defense-in-depth
# for the (currently nonexistent) case of a herestring/redirection caller
# that wouldn't fork a subshell.

# ---------------------------------------------------------------------------
# Terminal primitives
# ---------------------------------------------------------------------------

tui_hide_cursor() { printf '\033[?25l' >&2; }
tui_show_cursor() { printf '\033[?25h' >&2; }

# tui_clear_screen — home cursor, clear the visible viewport (\033[2J), AND
# clear scrollback (\033[3J, xterm's "erase saved lines" extension). Many
# terminals (iTerm2, Terminal.app, VS Code, most VTE-based ones) keep their
# own scroll history *inside* the alternate screen buffer too — \033[2J
# alone only wipes what's currently visible, so a long report's overflow
# stays reachable by scrolling up even though nothing left alt-screen.
# \033[3J is what `clear`/`tput clear` emit on modern terminfo databases
# for exactly this reason; unsupported terminals just ignore it.
tui_clear_screen() { printf '\033[H\033[2J\033[3J' >&2; }

# tui_enter_alt/tui_leave_alt are gated on CMM_TUI_ALT_ACTIVE rather than
# calling tput smcup/rmcup unconditionally on every picker invocation.
# Without this, `clmac` (the interactive menu) would enter/leave the
# alternate screen once per action: each report command (scan/doctor/
# system) prints its plain-text output to the PRIMARY screen between two alt-screen
# picker frames, which pollutes real scrollback — the "past command
# results" a user scrolling up in their terminal would see are exactly
# that leaked primary-screen output. cmd_menu instead enters alt-screen
# once for the whole session (see menu.sh) and every report command's
# plain printf output lands inside that same alternate buffer, which
# leaves zero scrollback residue once the session ends and the terminal
# is restored — the same reason vim/htop/less use alt-screen at all.
#
# Direct one-shot use (`clmac scan` from a normal shell prompt, no menu)
# never sets the flag, so tui_select_menu/tui_select_multi still toggle
# alt-screen per call exactly as before — you want a report you ran
# directly to stay in your scrollback.
CMM_TUI_ALT_ACTIVE=0
tui_enter_alt() {
  (( CMM_TUI_ALT_ACTIVE )) && return 0
  command -v tput >/dev/null 2>&1 && tput smcup >&2 2>/dev/null
  CMM_TUI_ALT_ACTIVE=1
  tui_clear_screen
  return 0
}
tui_leave_alt() {
  (( CMM_TUI_ALT_ACTIVE )) || return 0
  command -v tput >/dev/null 2>&1 && tput rmcup >&2 2>/dev/null
  CMM_TUI_ALT_ACTIVE=0
  return 0
}

TUI_SAVED_STTY=""
tui_raw_on() {
  TUI_SAVED_STTY=$(stty -g </dev/tty 2>/dev/null) || TUI_SAVED_STTY=""
  # -isig: Ctrl-C arrives as byte 0x03 for read_key to decode itself,
  # rather than as a real SIGINT racing a blocking `read` — same model
  # fzf uses. Keeps quit-handling deterministic without relying on
  # signal-delivery timing.
  stty -echo -icanon -isig time 0 min 1 </dev/tty 2>/dev/null || true
}
tui_raw_off() {
  if [[ -n "$TUI_SAVED_STTY" ]]; then
    stty "$TUI_SAVED_STTY" </dev/tty 2>/dev/null || stty sane </dev/tty 2>/dev/null || true
  else
    stty sane </dev/tty 2>/dev/null || true
  fi
}

# tui_term_size — echoes "<rows> <cols>". Hard fallback to 24x80 so a
# picker invoked without a real controlling terminal can't hang or produce
# broken (zero/negative) pagination math.
tui_term_size() {
  local sz
  sz=$(stty size </dev/tty 2>/dev/null)
  if [[ "$sz" =~ ^[0-9]+\ [0-9]+$ ]]; then
    printf '%s\n' "$sz"
  else
    printf '%s %s\n' "${LINES:-24}" "${COLUMNS:-80}"
  fi
}

# tui_visible_width <string> — display width with ANSI SGR sequences
# stripped, so callers can size fixed-width redraws correctly.
tui_visible_width() {
  local stripped
  stripped=$(printf '%s' "$1" | sed -E $'s/\x1b\\[[0-9;]*m//g')
  printf '%s' "${#stripped}"
}

# tui_truncate_visible <string> <max_cols> — truncates by visible width,
# not byte count. Strips embedded ANSI when truncation is needed (a narrow-
# terminal safety valve, not the common path — full-width rows keep colors).
tui_truncate_visible() {
  local s=$1 max=${2:-80} w
  w=$(tui_visible_width "$s")
  if (( w <= max )); then
    printf '%s' "$s"
    return 0
  fi
  local stripped
  stripped=$(printf '%s' "$s" | sed -E $'s/\x1b\\[[0-9;]*m//g')
  local keep=$(( max - 3 ))
  (( keep < 1 )) && keep=1
  printf '%s...' "${stripped:0:keep}"
}

tui_cleanup() {
  tui_raw_off
  tui_show_cursor
  tui_leave_alt
}

# _tui_arm_traps — save the caller's existing EXIT/INT/TERM traps (if any)
# and install a cleanup handler that restores the terminal, then chains to
# whatever was there before. Call _tui_disarm_traps when a picker returns
# normally so the chain doesn't run twice.
_tui_prev_exit=""
_tui_prev_int=""
_tui_prev_term=""
_tui_arm_traps() {
  _tui_prev_exit=$(trap -p EXIT)
  _tui_prev_int=$(trap -p INT)
  _tui_prev_term=$(trap -p TERM)
  trap '_tui_trap_fire' EXIT INT TERM
}
_tui_trap_fire() {
  tui_cleanup
  _tui_disarm_traps
}
_tui_disarm_traps() {
  if [[ -n "$_tui_prev_exit" ]]; then eval "$_tui_prev_exit"; else trap - EXIT; fi
  if [[ -n "$_tui_prev_int" ]]; then eval "$_tui_prev_int"; else trap - INT; fi
  if [[ -n "$_tui_prev_term" ]]; then eval "$_tui_prev_term"; else trap - TERM; fi
}

# ---------------------------------------------------------------------------
# Key decoding
# ---------------------------------------------------------------------------

# read_key [fd] [timeout]
# Decodes one keypress into a symbolic name: UP DOWN LEFT RIGHT ENTER SPACE
# BACKSPACE QUIT TOP BOTTOM TICK CHAR:<c> OTHER.
#
# With no fd argument, opens /dev/tty for the read — the pickers below
# always run at the end of an `items | tui_select_*` pipe, so fd 0 is
# bound to already-consumed pipe data, not the terminal (same reasoning as
# the pure-bash fallbacks in lib/ui.sh, which read from /dev/tty directly
# for the same reason). Pass an explicit fd number (e.g. `read_key 0`) to
# feed scripted byte sequences for testing.
#
# With a timeout given, a wait that expires with no key pressed returns
# TICK rather than QUIT (`read -t` exits >128 on a real timeout vs. 1 on
# genuine EOF/closed-fd, so the two are distinguishable) — this is what
# lets a picker redraw on a timer (e.g. to animate something) without
# treating "no input yet" as if the user asked to quit.
read_key() {
  local fd=${1:-} timeout=${2:-} opened=0
  if [[ -z "$fd" ]]; then
    exec {fd}</dev/tty || { printf 'QUIT\n'; return 0; }
    opened=1
  fi

  local key rc
  if [[ -n "$timeout" ]]; then
    IFS= read -r -s -n 1 -t "$timeout" -u "$fd" key
  else
    IFS= read -r -s -n 1 -u "$fd" key
  fi
  rc=$?
  if (( rc > 128 )); then
    (( opened )) && exec {fd}<&-
    printf 'TICK\n'
    return 0
  fi
  if (( rc != 0 )); then
    (( opened )) && exec {fd}<&-
    printf 'QUIT\n'
    return 0
  fi

  # `read -n 1` on a newline consumes it as the line terminator and leaves
  # $key empty rather than $'\n' — this is how Enter actually arrives.
  if [[ -z "$key" ]]; then
    (( opened )) && exec {fd}<&-
    printf 'ENTER\n'
    return 0
  fi

  local out
  case "$key" in
    $'\n' | $'\r') out=ENTER ;;
    ' ') out=SPACE ;;
    q | Q) out=QUIT ;;
    $'\x03') out=QUIT ;;
    $'\x7f' | $'\x08') out=BACKSPACE ;;
    j | J) out=DOWN ;;
    k | K) out=UP ;;
    h | H) out=LEFT ;;
    l | L) out=RIGHT ;;
    G) out=BOTTOM ;;
    g)
      local rest
      if IFS= read -r -s -n 1 -t 0.3 -u "$fd" rest 2>/dev/null && [[ "$rest" == g ]]; then
        out=TOP
      else
        out=OTHER
      fi
      ;;
    $'\x1b')
      # CSI sequences arrive as a burst (terminal-generated, not
      # human-paced), unlike the "gg" double-tap above — a short timeout
      # is enough to disambiguate a bare Escape from the start of one.
      local rest rest2
      if IFS= read -r -s -n 1 -t 0.05 -u "$fd" rest 2>/dev/null && [[ "$rest" == '[' ]]; then
        if IFS= read -r -s -n 1 -t 0.05 -u "$fd" rest2 2>/dev/null; then
          case "$rest2" in
            A) out=UP ;;
            B) out=DOWN ;;
            C) out=RIGHT ;;
            D) out=LEFT ;;
            *) out=OTHER ;;
          esac
        else
          out=OTHER
        fi
      else
        out=QUIT # bare Escape cancels, same as fzf
      fi
      ;;
    *) out="CHAR:$key" ;;
  esac

  (( opened )) && exec {fd}<&-
  printf '%s\n' "$out"
}

# _tui_render_with_art <gap> <art_width> <content_lines_var> <art_lines_var>
# Prints "<art line, padded to art_width><gap spaces><content line>" for
# every row up to the taller of the two inputs, blank-padding whichever
# side runs out first. Factored out of tui_select_menu's draw loop (used
# for the top-level menu's mascot) specifically so this line-pairing math
# — the part most likely to have an off-by-one — can be unit-tested with
# piped-in arrays instead of needing a real terminal to eyeball.
_tui_render_with_art() {
  local gap=$1 art_width=$2 content_var=$3 art_var=$4
  local -n _tra_content=$content_var
  local -n _tra_art=$art_var
  local n_content=${#_tra_content[@]} n_art=${#_tra_art[@]}
  local max=$n_content
  (( n_art > max )) && max=$n_art
  local i gap_str
  gap_str=$(printf '%*s' "$gap" '')
  for (( i = 0; i < max; i++ )); do
    local art_line=${_tra_art[i]:-} art_w fill
    art_w=$(tui_visible_width "$art_line")
    fill=$(( art_width - art_w ))
    (( fill < 0 )) && fill=0
    printf '%s%*s%s%s\n' "$art_line" "$fill" '' "$gap_str" "${_tra_content[i]:-}" >&2
  done
}

# ---------------------------------------------------------------------------
# Pickers
# ---------------------------------------------------------------------------

# _tui_divider <text> [max=60] — a ═ rule sized to the text, mole-style.
_tui_divider() {
  local text=$1 max=${2:-60} w
  w=$(tui_visible_width "$text")
  (( w > max )) && w=$max
  (( w < 8 )) && w=8
  printf '%s' "$(printf '═%.0s' $(seq 1 "$w"))"
}

# tui_select_menu <header> <footer> <label> <items>
# <items> is already-read `display\tpayload` TSV, one per line (label is
# accepted for call-site compatibility with the old fzf-border-label
# signature but unused — there's no box to label anymore).
# Prints the chosen payload on stdout. Sets CMM_MENU_QUIT=1 and returns 130
# on quit (q / Esc / Ctrl-C); returns 1 on an empty item list.
# tui_select_menu <header> <footer> <label> <items> [art_frames_var]
# art_frames_var, if given, names an array whose elements are complete
# multi-line ASCII-art frames (one element per animation frame) drawn to
# the left of the list, cycled on a timer. Only menu.sh's top-level menu
# passes this — every other caller (clean/orphans pickers) is unaffected,
# and it's skipped automatically on a terminal too narrow to fit both
# columns.
tui_select_menu() {
  local header=$1 footer=$2 _label=${3:-} items=$4 art_var=${5:-}
  local -a tui_labels=() tui_payloads=()
  local disp payload
  while IFS=$'\t' read -r disp payload; do
    [[ -z "$disp" && -z "$payload" ]] && continue
    tui_labels+=("$disp")
    tui_payloads+=("$payload")
  done <<< "$items"
  local n=${#tui_labels[@]}
  (( n == 0 )) && return 1

  local rows cols page_size cursor=0 top=0
  read -r rows cols < <(tui_term_size)
  page_size=$(( rows - 6 ))
  (( page_size < 1 )) && page_size=1
  (( page_size > n )) && page_size=$n

  # Art setup: only enabled when a frames array was passed AND the
  # terminal is wide enough for both columns plus a gap. art_width is the
  # widest line across ALL frames (not just the current one) so the
  # content column doesn't shift left/right as frames cycle.
  local -a art_frames=()
  [[ -n "$art_var" ]] && { local -n _tsm_frames_ref=$art_var; art_frames=("${_tsm_frames_ref[@]}"); }
  local art_gap=3 art_width=0 art_frame_idx=0
  if (( ${#art_frames[@]} > 0 )); then
    local -a _probe_lines
    local frame al w
    for frame in "${art_frames[@]}"; do
      mapfile -t _probe_lines <<< "$frame"
      for al in "${_probe_lines[@]}"; do
        w=$(tui_visible_width "$al")
        (( w > art_width )) && art_width=$w
      done
    done
  fi
  local art_active=0
  (( ${#art_frames[@]} > 0 && cols >= art_width + art_gap + 60 )) && art_active=1
  local tick_timeout=""
  (( art_active )) && tick_timeout=0.2

  _tui_arm_traps
  tui_enter_alt; tui_raw_on; tui_hide_cursor
  tui_clear_screen

  local rc=130 result=""
  while true; do
    (( cursor < top )) && top=$cursor
    (( cursor >= top + page_size )) && top=$(( cursor - page_size + 1 ))

    local -a content_lines=()
    content_lines+=("$(printf '%s%s%s' "$C_BOLD" "$header" "$C_RESET")")
    content_lines+=("$(printf '%s%s%s' "$C_DIM" "$(_tui_divider "$header" "$cols")" "$C_RESET")")
    content_lines+=("")

    local i last=$(( top + page_size - 1 ))
    (( last >= n )) && last=$(( n - 1 ))
    for (( i = top; i <= last; i++ )); do
      if (( i == cursor )); then
        content_lines+=("$(printf '%s▶%s %s' "$C_CYAN$C_BOLD" "$C_RESET" "${tui_labels[i]}")")
      else
        content_lines+=("$(printf '  %s' "${tui_labels[i]}")")
      fi
    done

    content_lines+=("")
    content_lines+=("$(printf '%s%s%s' "$C_DIM" "$footer" "$C_RESET")")

    printf '\033[H\033[J' >&2
    if (( art_active )); then
      local -a art_lines
      mapfile -t art_lines <<< "${art_frames[art_frame_idx]}"
      _tui_render_with_art "$art_gap" "$art_width" content_lines art_lines
    else
      local line
      for line in "${content_lines[@]}"; do
        printf '  %s\n' "$line" >&2
      done
    fi

    local key
    key=$(read_key "" "$tick_timeout")
    case "$key" in
      TICK) (( art_active )) && art_frame_idx=$(( (art_frame_idx + 1) % ${#art_frames[@]} )) ;;
      UP) (( cursor > 0 )) && cursor=$(( cursor - 1 )) ;;
      DOWN) (( cursor < n - 1 )) && cursor=$(( cursor + 1 )) ;;
      TOP) cursor=0 ;;
      BOTTOM) cursor=$(( n - 1 )) ;;
      ENTER) result=${tui_payloads[cursor]}; rc=0; break ;;
      QUIT) CMM_MENU_QUIT=1; rc=130; break ;;
      *) ;;
    esac
  done

  tui_cleanup
  _tui_disarm_traps
  (( rc == 0 )) && printf '%s\n' "$result"
  return $rc
}

# tui_select_multi <header> <items>
# <items> is already-read plain lines, one per line — emitted verbatim for
# selected rows (callers reconstruct fields with awk; the line text must
# not be truncated or re-serialized). Prints selected lines on stdout, one
# per line; empty output means cancelled. If Enter is pressed with nothing
# checked, the row under the cursor is treated as selected (matches fzf's
# default when nothing is marked).
tui_select_multi() {
  local header=$1 items=$2
  local -a tui_lines=()
  mapfile -t tui_lines <<< "$items"
  local n=${#tui_lines[@]}
  while (( n > 0 )) && [[ -z "${tui_lines[n-1]}" ]]; do
    unset 'tui_lines[n-1]'
    tui_lines=("${tui_lines[@]}")
    n=${#tui_lines[@]}
  done
  (( n == 0 )) && return 0

  local -a tui_checked=()
  local i
  for (( i = 0; i < n; i++ )); do tui_checked[i]=0; done

  local rows cols page_size cursor=0 top=0
  read -r rows cols < <(tui_term_size)
  page_size=$(( rows - 6 ))
  (( page_size < 1 )) && page_size=1
  (( page_size > n )) && page_size=$n

  _tui_arm_traps
  tui_enter_alt; tui_raw_on; tui_hide_cursor
  tui_clear_screen

  local rc=1
  while true; do
    (( cursor < top )) && top=$cursor
    (( cursor >= top + page_size )) && top=$(( cursor - page_size + 1 ))

    printf '\033[H\033[J' >&2
    printf '  %s%s%s\n' "$C_BOLD" "$header" "$C_RESET" >&2
    printf '  %s%s%s\n\n' "$C_DIM" "$(_tui_divider "$header" "$cols")" "$C_RESET" >&2

    local last=$(( top + page_size - 1 ))
    (( last >= n )) && last=$(( n - 1 ))
    for (( i = top; i <= last; i++ )); do
      local box='☐'
      (( tui_checked[i] )) && box='☑'
      if (( i == cursor )); then
        printf '  %s▶%s %s%s%s %s\n' "$C_CYAN$C_BOLD" "$C_RESET" "$C_GREEN" "$box" "$C_RESET" "${tui_lines[i]}" >&2
      else
        printf '    %s%s%s %s\n' "$C_DIM" "$box" "$C_RESET" "${tui_lines[i]}" >&2
      fi
    done

    printf '\n  %s↑↓ Navigate | Space Toggle | Enter Confirm | Q Quit%s\n' "$C_DIM" "$C_RESET" >&2

    local key
    key=$(read_key)
    case "$key" in
      UP) (( cursor > 0 )) && cursor=$(( cursor - 1 )) ;;
      DOWN) (( cursor < n - 1 )) && cursor=$(( cursor + 1 )) ;;
      TOP) cursor=0 ;;
      BOTTOM) cursor=$(( n - 1 )) ;;
      SPACE) (( tui_checked[cursor] = tui_checked[cursor] ? 0 : 1 )) ;;
      ENTER) rc=0; break ;;
      QUIT) rc=1; break ;;
      *) ;;
    esac
  done

  tui_cleanup
  _tui_disarm_traps

  if (( rc == 0 )); then
    local any=0
    for (( i = 0; i < n; i++ )); do
      if (( tui_checked[i] )); then
        printf '%s\n' "${tui_lines[i]}"
        any=1
      fi
    done
    (( any == 0 )) && printf '%s\n' "${tui_lines[cursor]}"
  fi
  return 0
}
