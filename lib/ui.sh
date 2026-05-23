#!/opt/homebrew/bin/bash
# Interactive selection UI. Uses fzf when available, falls back to numbered menu.

# select_multi
# Reads items from stdin (one per line) and writes selected items to stdout.
# Args:
#   $1 = prompt header (shown above the picker)
select_multi() {
  local header=${1:-"Select items (Tab to multi-select, Enter to confirm)"}
  local items
  items=$(cat)
  [[ -z "$items" ]] && return 0

  if command -v fzf >/dev/null 2>&1; then
    printf '%s\n' "$items" | fzf \
      --multi \
      --header="$header" \
      --height=60% \
      --reverse \
      --border \
      --prompt="> "
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

  local reply
  read -r reply
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

# select_one — pick one item from stdin.
select_one() {
  local header=${1:-"Select one"}
  local items
  items=$(cat)
  [[ -z "$items" ]] && return 0

  if command -v fzf >/dev/null 2>&1; then
    printf '%s\n' "$items" | fzf \
      --header="$header" \
      --height=60% \
      --reverse \
      --border \
      --prompt="> "
  else
    local -a arr
    mapfile -t arr <<< "$items"
    local n=${#arr[@]} i
    printf '%s\n' "$header" >&2
    for (( i=0; i<n; i++ )); do
      printf '  %2d. %s\n' "$((i+1))" "${arr[i]}" >&2
    done
    printf 'Enter number (blank to cancel): ' >&2
    local reply
    read -r reply
    [[ -z "$reply" ]] && return 0
    if [[ "$reply" =~ ^[0-9]+$ ]] && (( reply >= 1 && reply <= n )); then
      printf '%s\n' "${arr[reply-1]}"
    fi
  fi
}
