#!/opt/homebrew/bin/bash
# cmd_explore — interactive disk usage browser (bar-chart drill-down).
# View-only: browses and reveals in Finder. Use 'clmac clean' or
# 'clmac orphans' to actually delete something.

_explore_help() {
  cat <<EOF
${C_BOLD}clmac explore${C_RESET}

  Interactive disk usage browser. Starts at a handful of top-level
  locations (Home, App Library, Applications, System Library, Volumes)
  and lets you drill into any directory with Enter.

  View-only — use ${C_CYAN}clmac clean${C_RESET} or ${C_CYAN}clmac orphans${C_RESET} to delete something.
EOF
}

_explore_root_defs() {
  cat <<EOF
Home|$HOME
App Library|$HOME/Library
Applications|/Applications
System Library|/Library
Volumes|/Volumes
EOF
}

cmd_explore() {
  while (( $# > 0 )); do
    case "$1" in
      -h|--help) _explore_help; return 0 ;;
      *) log_warn "explore: ignoring unknown arg: $1" ;;
    esac
    shift
  done

  while true; do
    local chosen rc
    chosen=$(_explore_roots_screen)
    rc=$?
    (( rc == 130 )) && return 0
    [[ -z "$chosen" ]] && return 0

    _explore_dir_screen "$chosen" "${chosen/#$HOME/\~}"
    rc=$?
    (( rc == 130 )) && return 0
    # else: fell back out of a subtree — redraw the roots screen.
  done
}

_explore_roots_screen() {
  local -a labels=() paths=() types=()
  local name path
  while IFS='|' read -r name path; do
    [[ -z "$name" ]] && continue
    [[ -e "$path" ]] || continue
    labels+=("$name")
    paths+=("$path")
    types+=("d")
  done < <(_explore_root_defs)

  _explore_pick "clmac explore" labels paths types 0
}

# _explore_dir_screen <path> <breadcrumb>
# Owns its own redraw loop for one directory level. Recurses into
# subdirectories directly (no path stack needed — "up" just returns to
# the caller's own loop, which still has its own path in scope).
# Returns 130 if the user quit (propagated all the way back to
# cmd_explore); 0 for a normal "popped back up one level".
_explore_dir_screen() {
  local path=$1 breadcrumb=$2
  while true; do
    local -a labels=() paths=() types=()
    local root_dev entry label dev
    root_dev=$(stat -f '%d' / 2>/dev/null)
    while IFS= read -r -d '' entry; do
      # Self-reference guard: /Volumes commonly lists the boot volume
      # itself under its own name — skip it, it's already covered by Home.
      if [[ "$path" == "/Volumes" ]]; then
        dev=$(stat -f '%d' "$entry" 2>/dev/null)
        [[ -n "$dev" && "$dev" == "$root_dev" ]] && continue
      fi
      label=$(basename "$entry")
      labels+=("$label")
      paths+=("$entry")
      if [[ -d "$entry" && ! -L "$entry" ]]; then
        types+=("d")
      else
        types+=("f")
      fi
    done < <(find "$path" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)

    local chosen rc
    chosen=$(_explore_pick "$breadcrumb" labels paths types 1)
    rc=$?
    (( rc == 130 )) && return 130
    [[ -z "$chosen" || "$chosen" == ".." ]] && return 0

    if [[ -d "$chosen" && ! -L "$chosen" ]]; then
      _explore_dir_screen "$chosen" "$breadcrumb/$(basename "$chosen")"
      rc=$?
      (( rc == 130 )) && return 130
      # else: back from a child — loop and redraw this level.
    else
      _explore_reveal_in_finder "$chosen"
    fi
  done
}

# _explore_pick <breadcrumb> <label_arr_name> <path_arr_name> <type_arr_name> <show_up>
# Prints the picked path (or "..") to stdout; all status output goes to
# stderr so it doesn't pollute the captured selection. Sizes directories
# via dir_size_parallel (pending placeholders shown first, then a single
# redraw once every size is in — no live per-row updates, no alt-screen).
# Return code is select_menu's: 0 = picked, 1 = cancelled, 130 = quit.
_explore_pick() {
  local breadcrumb=$1 label_var=$2 path_var=$3 type_var=$4 show_up=$5
  local -n _ep_labels=$label_var
  local -n _ep_paths=$path_var
  local -n _ep_types=$type_var

  printf '\n%s%s%s\n%sScanning...%s\n\n' \
    "$C_BOLD" "$breadcrumb" "$C_RESET" "$C_DIM" "$C_RESET" >&2

  declare -A size_map=()
  local -a dir_paths=()
  local i
  for i in "${!_ep_paths[@]}"; do
    if [[ "${_ep_types[i]}" == d ]]; then
      dir_paths+=("${_ep_paths[i]}")
      printf '  %-32s %s\n' "${_ep_labels[i]}" "${C_DIM}pending..${C_RESET}" >&2
    else
      size_map["${_ep_paths[i]}"]=$(stat -f%z "${_ep_paths[i]}" 2>/dev/null || echo 0)
    fi
  done

  if (( ${#dir_paths[@]} > 0 )); then
    local bytes p
    while IFS=$'\t' read -r bytes p; do
      size_map["$p"]=$bytes
    done < <(printf '%s\0' "${dir_paths[@]}" | dir_size_parallel)
  fi

  local total=0
  for i in "${!_ep_paths[@]}"; do
    total=$(( total + ${size_map[${_ep_paths[i]}]:-0} ))
  done

  {
    for i in "${!_ep_paths[@]}"; do
      local bytes=${size_map[${_ep_paths[i]}]:-0}
      local pct="0.0"
      (( total > 0 )) && pct=$(awk -v b="$bytes" -v t="$total" 'BEGIN { printf "%.1f", (b/t)*100 }')
      local bar icon display
      bar=$(_explore_bar "$bytes" "$total" 20)
      icon="${C_CYAN}➤${C_RESET}"
      [[ "${_ep_types[i]}" == f ]] && icon="${C_DIM}${ICON_LIST}${C_RESET}"
      display=$(printf '%s%s%s %5s%%  %s %-28s %s' \
        "$(size_color "$bytes")" "$bar" "$C_RESET" \
        "$pct" "$icon" "${_ep_labels[i]}" "$(human_size_padded "$bytes" 8)")
      printf '%s\t%s\n' "$display" "${_ep_paths[i]}"
    done
    # `if` (not `(( show_up )) && printf`) so this group's exit status is
    # always 0 when show_up=0 — with pipefail set globally, a false-y
    # `&&` here would otherwise corrupt the pipeline's reported exit code
    # even when select_menu itself succeeds.
    if (( show_up )); then
      printf '  %s%s%s .. (up one level)\t..\n' "$C_DIM" "$ICON_SUBLIST" "$C_RESET"
    fi
  } | select_menu "$breadcrumb" "↑↓ Navigate | ⏎ Open | Q Quit" " clmac explore "
}

_explore_bar() {
  local bytes=$1 total=$2 width=${3:-20}
  local filled=0
  (( total > 0 )) && filled=$(( bytes * width / total ))
  (( filled > width )) && filled=$width
  local bar=""
  (( filled > 0 )) && bar=$(printf '█%.0s' $(seq 1 "$filled"))
  local rest=$(( width - filled ))
  (( rest > 0 )) && bar+=$(printf '░%.0s' $(seq 1 "$rest"))
  printf '%s' "$bar"
}

_explore_reveal_in_finder() {
  local path=$1
  open -R "$path" 2>/dev/null
}
