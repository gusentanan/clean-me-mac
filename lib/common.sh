#!/opt/homebrew/bin/bash
# Common helpers: colors, logging, size formatting, confirmation, env checks.

# Global flags set by entrypoint.
: "${CMM_DRY_RUN:=0}"
: "${CMM_YES:=0}"
: "${CMM_VERBOSE:=0}"
: "${CMM_JSON:=0}"

# Colors (disabled when stdout is not a tty or NO_COLOR is set).
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_DIM=$'\033[2m'
  C_BOLD=$'\033[1m'
  C_RESET=$'\033[0m'
else
  C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_DIM='' C_BOLD='' C_RESET=''
fi

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

# Confirm prompt. Honors --yes (CMM_YES=1). Returns 0 if yes, 1 if no.
confirm() {
  local msg=${1:-"Proceed?"}
  if [[ "$CMM_YES" -eq 1 ]]; then
    log_debug "auto-confirmed: $msg"
    return 0
  fi
  local reply
  printf '%s%s%s [y/N] ' "$C_BOLD" "$msg" "$C_RESET" >&2
  read -r reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# Safe delete. Honors --dry-run. Refuses to touch dangerous paths.
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
  if [[ "$CMM_DRY_RUN" -eq 1 ]]; then
    printf '%s[dry-run]%s would remove %s\n' "$C_DIM" "$C_RESET" "$path" >&2
    return 0
  fi
  rm -rf -- "$path"
}
