#!/opt/homebrew/bin/bash
# Common helpers: colors, logging, size formatting, confirmation, env checks.

# Global flags set by entrypoint.
: "${CMM_DRY_RUN:=0}"
: "${CMM_YES:=0}"
: "${CMM_VERBOSE:=0}"
: "${CMM_JSON:=0}"
: "${CMM_TRASH:=0}"
: "${CMM_MENU_QUIT:=0}"

# Operation log location (macOS convention).
CMM_LOG_DIR="$HOME/Library/Logs/clmac"
CMM_LOG_FILE="$CMM_LOG_DIR/operations.log"

# Colors (disabled when stdout is not a tty or NO_COLOR is set).
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_MAGENTA=$'\033[35m'
  C_CYAN=$'\033[36m'
  C_PURPLE=$'\033[0;35m'
  C_PURPLE_BOLD=$'\033[1;35m'
  C_GRAY=$'\033[0;90m'
  C_DIM=$'\033[2m'
  C_BOLD=$'\033[1m'
  C_RESET=$'\033[0m'
else
  C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_MAGENTA='' C_CYAN='' \
    C_PURPLE='' C_PURPLE_BOLD='' C_GRAY='' C_DIM='' C_BOLD='' C_RESET=''
fi

# Icons — plain glyphs, colored at the print site (mole-style: e.g.
# "${C_GREEN}${ICON_SUCCESS}${C_RESET} msg"). Kept uncolored here so a
# single glyph can be reused with different colors in different contexts.
ICON_SUCCESS="✓"
ICON_ERROR="✗"
ICON_WARNING="⚠"
ICON_CONFIRM="◎"
ICON_ARROW="➤"
ICON_LIST="•"
ICON_SUBLIST="↳"
ICON_DRY_RUN="→"
ICON_SOLID="●"
ICON_EMPTY="○"

# Pick a color for a size value (in bytes). Bigger = warmer = more
# interesting cleanup target.
#   >= 5 GB : red+bold
#   >= 1 GB : yellow
#   >= 100M : green
#   <  100M : dim
size_color() {
  local b=${1:-0}
  if   (( b >= 5368709120 )); then printf '%s' "$C_RED$C_BOLD"
  elif (( b >= 1073741824 )); then printf '%s' "$C_YELLOW"
  elif (( b >= 104857600  )); then printf '%s' "$C_GREEN"
  else                              printf '%s' "$C_DIM"
  fi
}

# human_size with size-based coloring applied.
human_size_c() {
  local b=${1:-0}
  printf '%s%s%s' "$(size_color "$b")" "$(human_size "$b")" "$C_RESET"
}

# Right-padded colored size. Colors are applied AROUND the padded text,
# so the visible-width math is correct (ANSI escapes don't count toward
# printf's %*s width).
#   human_size_padded <bytes> [width=10]
human_size_padded() {
  local b=${1:-0} width=${2:-10}
  printf '%s%*s%s' "$(size_color "$b")" "$width" "$(human_size "$b")" "$C_RESET"
}

# render_bar <pct 0-100> [width=20]
# Colored block-style progress bar (█ filled, ░ empty), mole-dashboard style.
# Color ramps green → yellow → red+bold as pct climbs, same thresholds as
# the disk-capacity warning colors used elsewhere (doctor, system).
render_bar() {
  local pct=${1:-0} width=${2:-20}
  local filled rest bar color
  filled=$(awk -v p="$pct" -v w="$width" \
    'BEGIN { f = int((p * w / 100) + 0.5); if (f < 0) f = 0; if (f > w) f = w; print f }')
  rest=$(( width - filled ))
  color="$C_GREEN"
  if awk -v p="$pct" 'BEGIN { exit !(p >= 85) }' </dev/null; then
    color="$C_RED$C_BOLD"
  elif awk -v p="$pct" 'BEGIN { exit !(p >= 60) }' </dev/null; then
    color="$C_YELLOW"
  fi
  bar=""
  (( filled > 0 )) && bar=$(printf '█%.0s' $(seq 1 "$filled"))
  (( rest > 0 )) && bar+=$(printf '░%.0s' $(seq 1 "$rest"))
  printf '%s%s%s' "$color" "$bar" "$C_RESET"
}

# divider_eq/divider_dash [width] — repeated-character rules. divider_eq is
# the mole-style "====...====" completion-summary rule (doctor's header
# divider and clean/orphans' "Freed:" blocks); divider_dash is the lighter
# "----...----" rule used for table separators.
divider_eq()   { local w=${1:-50} i s=""; for (( i=0; i<w; i++ )); do s+="="; done; printf '%s' "$s"; }
divider_dash() { local w=${1:-60} i s=""; for (( i=0; i<w; i++ )); do s+="-"; done; printf '%s' "$s"; }

log_info()    { [[ "$CMM_JSON" -eq 1 ]] && return 0; printf '%s\n' "$*" >&2; }
log_success() { [[ "$CMM_JSON" -eq 1 ]] && return 0; printf '  %s%s%s %s\n' "$C_GREEN" "$ICON_SUCCESS" "$C_RESET" "$*" >&2; }
log_warn()    { printf '%s%s %s%s\n' "$C_YELLOW" "$ICON_WARNING" "$*" "$C_RESET" >&2; }
log_error()   { printf '%s%s %s%s\n' "$C_RED" "$ICON_ERROR" "$*" "$C_RESET" >&2; }
log_debug()   { [[ "$CMM_VERBOSE" -eq 1 ]] && printf '%s[debug] %s%s\n' "$C_DIM" "$*" "$C_RESET" >&2; return 0; }

require_bash5() {
  if (( BASH_VERSINFO[0] < 5 )); then
    log_error "clmac requires Bash 5+. Current: $BASH_VERSION"
    log_error "Install with: brew install bash"
    exit 1
  fi
}

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    log_error "clmac only supports macOS."
    exit 1
  fi
}

# Convert bytes (integer) to a human-readable string like "1.2G".
human_size() {
  local bytes=${1:-0}
  awk -v b="$bytes" 'BEGIN {
    split("B K M G T P", u, " ");
    i = 1;
    while (b >= 1024 && i < 6) { b /= 1024; i++ }
    if (i == 1) printf "%d%s", b, u[i];
    else        printf "%.1f%s", b, u[i];
  }'
}

# Return size in bytes for a path. 0 if path does not exist.
dir_size() {
  local path=$1
  [[ -e "$path" ]] || { echo 0; return; }
  # `du -sk` returns kilobytes (POSIX). Multiply by 1024.
  local kb
  kb=$(du -sk "$path" 2>/dev/null | awk '{print $1}')
  echo $(( ${kb:-0} * 1024 ))
}

# Sum sizes across multiple paths.
dir_size_sum() {
  local total=0 p sz
  for p in "$@"; do
    sz=$(dir_size "$p")
    total=$(( total + sz ))
  done
  echo "$total"
}

# Parallel size lookup. Reads NUL-terminated paths from stdin, writes
# "<bytes>\t<path>" lines on stdout. Uses up to N concurrent `du`s
# (defaults to CPU count, capped at 12 to avoid I/O thrash).
#
# Usage:
#   printf '%s\0' "${paths[@]}" | dir_size_parallel
dir_size_parallel() {
  local jobs=${CMM_PARALLEL_JOBS:-$(/usr/sbin/sysctl -n hw.ncpu 2>/dev/null || echo 4)}
  (( jobs > 12 )) && jobs=12
  # `du -sk` outputs "<kb>\t<path>", we convert kb→bytes. Split on tab
  # only (not default whitespace) so paths containing spaces survive.
  xargs -0 -n1 -P "$jobs" du -sk 2>/dev/null \
    | awk -F'\t' -v OFS='\t' '{ printf "%d\t%s\n", $1*1024, $2 }'
}

# Confirm prompt. Honors --yes (CMM_YES=1). Returns 0 if yes, 1 if no.
confirm() {
  local msg=${1:-"Proceed?"}
  if [[ "$CMM_YES" -eq 1 ]]; then
    log_debug "auto-confirmed: $msg"
    return 0
  fi
  local reply
  printf '%s%s%s %s%s%s %s[y/N]%s ' \
    "$C_PURPLE_BOLD" "$ICON_CONFIRM" "$C_RESET" "$C_BOLD" "$msg" "$C_RESET" "$C_DIM" "$C_RESET" >&2
  read -r reply </dev/tty
  [[ "$reply" =~ ^[Yy]$ ]]
}

# press_any_key — blocks until a keypress, then clears its own prompt line.
# Use before returning to an alt-screen picker (cmd_menu's loop) after
# printing report/summary output on the main screen: entering alt-screen
# again immediately hides whatever was just printed, so callers that loop
# back into a picker after a non-interactive action need this pause or the
# user never gets to read the result. No-op when there's no real terminal
# (matches the interactivity check in ui.sh) or when --yes/--json is set.
press_any_key() {
  [[ "$CMM_YES" -eq 1 || "$CMM_JSON" -eq 1 ]] && return 0
  [[ -t 2 ]] || return 0
  { : </dev/tty; } 2>/dev/null || return 0
  printf '\n%sPress any key to continue…%s' "$C_DIM" "$C_RESET" >&2
  read -r -s -n 1 _ </dev/tty 2>/dev/null
  printf '\r\033[K' >&2
}

# ---------------------------------------------------------------------------
# Spinner — tongue-in-cheek loading indicator for slow operations.
# Suppressed when stderr is not a tty, when --json is set, or --verbose
# (debug logs would clash with the spinner line).
# ---------------------------------------------------------------------------

CMM_SPINNER_MSGS=(
  "lollygagging"
  "ruminating"
  "marinating"
  "pondering"
  "shuffling bytes"
  "counting bits"
  "snooping disks"
  "noodling"
  "trundling"
  "spelunking dirs"
  "rummaging around"
  "hemming and hawing"
)

CMM_SPINNER_PID=""

# spinner_start [message-override]
spinner_start() {
  CMM_SPINNER_PID=""
  if [[ ! -t 2 || "$CMM_JSON" -eq 1 || "$CMM_VERBOSE" -eq 1 ]]; then
    return 0
  fi
  local pick
  if [[ -n "${1:-}" ]]; then
    pick=$1
  else
    pick=${CMM_SPINNER_MSGS[$((RANDOM % ${#CMM_SPINNER_MSGS[@]}))]}
  fi
  local -a frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  (
    local n=${#frames[@]} i=0
    # Hide cursor.
    printf '\033[?25l' >&2
    while :; do
      printf '\r  %s%s%s %s%s...%s\033[K' "$C_CYAN" "${frames[i]}" "$C_RESET" "$C_DIM" "$pick" "$C_RESET" >&2
      i=$(( (i + 1) % n ))
      sleep 0.08
    done
  ) &
  CMM_SPINNER_PID=$!
  disown "$CMM_SPINNER_PID" 2>/dev/null || true
}

# spinner_stop [completion-message]
# With no argument: clears the spinner line silently (caller prints its own
# output next, e.g. a table). With an argument: clears the spinner line and
# replaces it with a "✓ message" line, mole-style real-time completion
# feedback.
spinner_stop() {
  local done_msg=${1:-}
  if [[ -n "${CMM_SPINNER_PID:-}" ]]; then
    kill "$CMM_SPINNER_PID" 2>/dev/null
    wait "$CMM_SPINNER_PID" 2>/dev/null
    # Clear line and restore cursor.
    printf '\r\033[K\033[?25h' >&2
    CMM_SPINNER_PID=""
  fi
  [[ -n "$done_msg" ]] && log_success "$done_msg"
  return 0
}

# Run a command with a spinner. The command's stdout is captured and
# replayed AFTER the spinner is cleared, so it never overwrites the
# spinner line.
#   with_spinner "msg" some_function arg1 arg2
with_spinner() {
  local msg=$1; shift
  if [[ ! -t 2 || "$CMM_JSON" -eq 1 || "$CMM_VERBOSE" -eq 1 ]]; then
    "$@"
    return $?
  fi
  spinner_start "$msg"
  local out rc
  out=$("$@")
  rc=$?
  spinner_stop
  [[ -n "$out" ]] && printf '%s\n' "$out"
  return $rc
}

# Ensure the spinner is killed on script exit or interrupt.
trap 'spinner_stop' EXIT INT TERM

# Append one line to the operation log. Format:
#   ISO-8601 TIMESTAMP \t ACTION \t BYTES \t PATH
log_operation() {
  local action=$1 path=$2 bytes=${3:-0}
  mkdir -p "$CMM_LOG_DIR" 2>/dev/null || return 0
  printf '%s\t%s\t%d\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$action" "$bytes" "$path" \
    >> "$CMM_LOG_FILE"
}

# Move a path to the Finder Trash via AppleScript. Recoverable from the Trash.
trash_path() {
  local path=$1
  [[ -e "$path" ]] || return 0
  # Resolve to an absolute POSIX path.
  local abs
  abs=$(/usr/bin/python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$path" 2>/dev/null) \
    || abs=$path
  /usr/bin/osascript -e "tell application \"Finder\" to delete POSIX file \"$abs\"" >/dev/null 2>&1
}

# Safe delete. Honors --dry-run and --trash. Refuses dangerous paths.
# Logs every successful action to $CMM_LOG_FILE.
safe_rm() {
  local path=$1
  if [[ -z "$path" || "$path" == "/" || "$path" == "$HOME" ]]; then
    log_error "safe_rm refused path: '$path'"
    return 1
  fi
  if [[ ! -e "$path" ]]; then
    log_debug "skip (missing): $path"
    return 0
  fi

  local sz
  sz=$(dir_size "$path")

  if [[ "$CMM_DRY_RUN" -eq 1 ]]; then
    if [[ "$CMM_TRASH" -eq 1 ]]; then
      printf '  %s%s%s would trash %s\n' "$C_DIM" "$ICON_DRY_RUN" "$C_RESET" "$path" >&2
    else
      printf '  %s%s%s would remove %s\n' "$C_DIM" "$ICON_DRY_RUN" "$C_RESET" "$path" >&2
    fi
    return 0
  fi

  if [[ "$CMM_TRASH" -eq 1 ]]; then
    if trash_path "$path"; then
      log_operation "trash" "$path" "$sz"
      return 0
    fi
    log_warn "trash failed for $path; falling back to rm"
  fi

  if rm -rf -- "$path"; then
    log_operation "rm" "$path" "$sz"
    return 0
  fi
  return 1
}
