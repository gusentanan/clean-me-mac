#!/opt/homebrew/bin/bash
# Interactive selection UI. Draws with the hand-rolled raw-terminal picker
# in lib/tui.sh when a real terminal is available, falls back to a
# pure-bash numbered menu otherwise (no tty attached at all — CI, a
# detached session, etc).
source "$CMM_LIB/tui.sh"

# _ui_interactive — true if there's a real terminal to draw the picker on.
# select_multi/select_menu are always invoked as `items | select_multi ...`
# (every call site in this repo does this — see the items=$(cat) below),
# which means fd 0 and fd 1 are bound to pipe/command-substitution
# plumbing at the point this runs, NOT the terminal. stderr (fd 2) is the
# one fd that's still connected straight through — same test the spinner
# in common.sh already relies on — so that's what has to be checked, not
# -t 0 / -t 1.
_ui_interactive() {
  [[ -t 2 ]] && { : </dev/tty; } 2>/dev/null
}

# select_multi
# Reads items from stdin (one per line) and writes selected items to stdout.
# Args:
#   $1 = prompt header (shown above the picker)
select_multi() {
  local header=${1:-"Select items (Space to toggle, Enter to confirm)"}
  local items
  items=$(cat)
  [[ -z "$items" ]] && return 0

  if _ui_interactive; then
    tui_select_multi "$header" "$items"
  else
    _select_multi_fallback "$header" "$items"
  fi
}

# Pure-bash numbered menu fallback.
_select_multi_fallback() {
  local header=$1 items=$2
  local -a arr
  mapfile -t arr <<< "$items"
  local n=${#arr[@]} i

  printf '%s\n' "$header" >&2
  printf '%s\n' "$(printf '%.0s-' {1..60})" >&2
  for (( i=0; i<n; i++ )); do
    printf '  %2d. %s\n' "$((i+1))" "${arr[i]}" >&2
  done
  printf '%s\n' "$(printf '%.0s-' {1..60})" >&2
  printf 'Enter numbers (e.g. 1,3,5 or 1-3 or "all"), blank to cancel: ' >&2

  # select_multi is always invoked as the right side of a pipe
  # (`items | select_multi`), so fd 0 is bound to that internal data
  # pipe, not the terminal — read from /dev/tty directly, same as
  # common.sh's confirm().
  local reply
  read -r reply </dev/tty
  [[ -z "$reply" ]] && return 0

  if [[ "$reply" == "all" ]]; then
    printf '%s\n' "${arr[@]}"
    return 0
  fi

  # Parse comma-separated list with optional ranges.
  local -a picks
  local part
  IFS=',' read -ra parts <<< "$reply"
  for part in "${parts[@]}"; do
    part=${part// /}
    if [[ "$part" =~ ^[0-9]+-[0-9]+$ ]]; then
      local lo=${part%-*} hi=${part#*-}
      for (( i=lo; i<=hi; i++ )); do picks+=("$i"); done
    elif [[ "$part" =~ ^[0-9]+$ ]]; then
      picks+=("$part")
    fi
  done

  for i in "${picks[@]}"; do
    if (( i >= 1 && i <= n )); then
      printf '%s\n' "${arr[i-1]}"
    fi
  done
}

# select_menu <header> <footer> [border_label]
# Reads TSV rows "<display>\t<payload>" from stdin. Unlike select_one/
# select_multi (which parse the chosen line back apart via whitespace
# tokens), select_menu returns the payload column verbatim — safe for
# payloads containing spaces or ANSI color codes (e.g. explore's colored
# bar rows, or filenames with spaces).
#
# Prints the chosen row's payload on stdout. Sets CMM_MENU_QUIT=1 and
# returns 130 if the user quit (q / Ctrl-C) rather than just cancelling
# this one level (blank/Esc, return 1).
#
# border_label is accepted for call-site compatibility with the old
# fzf-box-label signature but unused — there's no box to label anymore.
select_menu() {
  local header=$1 footer=$2 label=${3:-" clmac "}
  local items
  items=$(cat)
  [[ -z "$items" ]] && return 1

  if _ui_interactive; then
    tui_select_menu "$header" "$footer" "$label" "$items"
  else
    _select_menu_fallback "$header" "$footer" "$items"
  fi
}

# Pure-bash numbered menu fallback for select_menu.
_select_menu_fallback() {
  local header=$1 footer=$2 items=$3
  local -a arr
  mapfile -t arr <<< "$items"
  local n=${#arr[@]} i

  printf '%s\n' "$header" >&2
  printf '%s\n' "$(printf '%.0s-' {1..60})" >&2
  for (( i=0; i<n; i++ )); do
    printf '  %2d. %s\n' "$((i+1))" "${arr[i]%%$'\t'*}" >&2
  done
  printf '%s\n' "$(printf '%.0s-' {1..60})" >&2
  printf '%s\n' "$footer" >&2
  printf 'Enter number, "q" to quit, blank to go back: ' >&2

  # See _select_multi_fallback: fd 0 here is the internal rows pipe, not
  # the terminal — read from /dev/tty directly.
  local reply
  read -r reply </dev/tty
  if [[ "$reply" == [qQ] ]]; then
    CMM_MENU_QUIT=1
    return 130
  fi
  [[ -z "$reply" ]] && return 1
  if [[ "$reply" =~ ^[0-9]+$ ]] && (( reply >= 1 && reply <= n )); then
    printf '%s\n' "${arr[reply-1]##*$'\t'}"
    return 0
  fi
  return 1
}
