#!/opt/homebrew/bin/bash
# Common helpers: colors, logging, size formatting, confirmation, env checks.

# Global flags set by entrypoint.
: "${CMM_DRY_RUN:=0}"
: "${CMM_YES:=0}"
: "${CMM_VERBOSE:=0}"
: "${CMM_JSON:=0}"
: "${CMM_TRASH:=0}"

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
  C_DIM=$'\033[2m'
  C_BOLD=$'\033[1m'
  C_RESET=$'\033[0m'
else
  C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_MAGENTA='' C_CYAN='' C_DIM='' C_BOLD='' C_RESET=''
fi

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

log_info()  { [[ "$CMM_JSON" -eq 1 ]] && return 0; printf '%s\n' "$*" >&2; }
log_warn()  { printf '%s%s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }
log_error() { printf '%s%s%s\n' "$C_RED"    "$*" "$C_RESET" >&2; }
log_debug() { [[ "$CMM_VERBOSE" -eq 1 ]] && printf '%s[debug] %s%s\n' "$C_DIM" "$*" "$C_RESET" >&2; return 0; }

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
  # `du -sk` outputs "<kb>\t<path>", we convert kb→bytes.
  xargs -0 -n1 -P "$jobs" du -sk 2>/dev/null \
    | awk -v OFS='\t' '{ kb=$1; $1=""; sub(/^\t/,""); printf "%d\t%s\n", kb*1024, $0 }'
}

# Confirm prompt. Honors --yes (CMM_YES=1). Returns 0 if yes, 1 if no.
confirm() {
  local msg=${1:-"Proceed?"}
  if [[ "$CMM_YES" -eq 1 ]]; then
    log_debug "auto-confirmed: $msg"
    return 0
  fi
  local reply
  printf '%s%s%s [y/N] ' "$C_BOLD" "$msg" "$C_RESET" >&2
  read -r reply </dev/tty
  [[ "$reply" =~ ^[Yy]$ ]]
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
      printf '\r  %s%s %s...%s\033[K' "$C_DIM" "${frames[i]}" "$pick" "$C_RESET" >&2
      i=$(( (i + 1) % n ))
      sleep 0.08
    done
  ) &
  CMM_SPINNER_PID=$!
  disown "$CMM_SPINNER_PID" 2>/dev/null || true
}

spinner_stop() {
  [[ -z "${CMM_SPINNER_PID:-}" ]] && return 0
  kill "$CMM_SPINNER_PID" 2>/dev/null
  wait "$CMM_SPINNER_PID" 2>/dev/null
  # Clear line and restore cursor.
  printf '\r\033[K\033[?25h' >&2
  CMM_SPINNER_PID=""
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
      printf '%s[dry-run]%s would trash %s\n' "$C_DIM" "$C_RESET" "$path" >&2
    else
      printf '%s[dry-run]%s would remove %s\n' "$C_DIM" "$C_RESET" "$path" >&2
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
