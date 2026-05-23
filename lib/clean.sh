#!/opt/homebrew/bin/bash
# cmd_clean — run known-safe cleanup presets.

# Source a preset file in a subshell-safe way. The preset must set
# PRESET_NAME, PRESET_DESC, PRESET_SAFE and one of:
#   - PRESET_PATHS (array)              standard path-removal preset
#   - PRESET_COMMAND (string)           runs a shell command
#   - PRESET_SCAN=true + PRESET_SCAN_* dynamic scan preset
#
# Glob patterns in PRESET_PATHS (e.g. `AndroidStudio*`) are expanded
# at load time using find, which handles spaces and missing parents.
#
# Sourcing into the caller's scope — clear vars first to avoid leaks.
_load_preset() {
  local file=$1
  unset PRESET_NAME PRESET_DESC PRESET_SAFE PRESET_COMMAND
  unset PRESET_SCAN PRESET_SCAN_NAME PRESET_EMPTY_NOT_REMOVE PRESET_SCAN_MIN_AGE_DAYS
  PRESET_PATHS=()
  PRESET_SCAN_ROOTS=()
  # shellcheck disable=SC1090
  source "$file"
  _expand_preset_globs
}

# Expand any glob-like entries in PRESET_PATHS in-place.
_expand_preset_globs() {
  (( ${#PRESET_PATHS[@]} == 0 )) && return 0
  local -a out=() globbed
  local p parent base
  for p in "${PRESET_PATHS[@]}"; do
    if [[ "$p" == *[\*\?\[]* ]]; then
      parent=$(dirname "$p")
      base=$(basename "$p")
      [[ -d "$parent" ]] || continue
      globbed=()
      while IFS= read -r -d '' m; do
        globbed+=("$m")
      done < <(find "$parent" -maxdepth 1 -name "$base" -print0 2>/dev/null)
      out+=("${globbed[@]}")
    else
      out+=("$p")
    fi
  done
  PRESET_PATHS=("${out[@]}")
}

# List preset files (just the filenames without .sh).
_list_preset_files() {
  local f
  for f in "$CMM_PRESETS"/*.sh; do
    [[ -f "$f" ]] || continue
    echo "$f"
  done | sort
}

# Find a preset file by name; echoes the path or returns 1.
_find_preset() {
  local name=$1
  local f="$CMM_PRESETS/${name}.sh"
  if [[ -f "$f" ]]; then echo "$f"; return 0; fi
  return 1
}

# Echo current size of a preset (in bytes).
_preset_current_size() {
  if [[ -n "${PRESET_COMMAND:-}" ]]; then
    echo 0
    return
  fi
  if [[ "${PRESET_SCAN:-false}" == "true" ]]; then
    local total=0 root
    for root in "${PRESET_SCAN_ROOTS[@]}"; do
      [[ -d "$root" ]] || continue
      # Sum sizes of matching dirs.
      while IFS= read -r -d '' d; do
        local s
        s=$(dir_size "$d")
        total=$(( total + s ))
      done < <(find "$root" -type d -name "$PRESET_SCAN_NAME" -prune -print0 2>/dev/null)
    done
    echo "$total"
    return
  fi
  dir_size_sum "${PRESET_PATHS[@]}"
}

cmd_clean() {
  local list=0 all_safe=0 want=""
  while (( $# > 0 )); do
    case "$1" in
      --list)     list=1 ;;
      --all-safe) all_safe=1 ;;
      -h|--help)
        _clean_help
        return 0
        ;;
      -*) log_warn "clean: ignoring unknown flag: $1" ;;
      *)  want=$1 ;;
    esac
    shift
  done

  if [[ "$list" -eq 1 ]]; then
    _clean_list
    return 0
  fi

  if [[ "$all_safe" -eq 1 ]]; then
    _clean_all_safe
    return 0
  fi

  if [[ -n "$want" ]]; then
    local f
    if ! f=$(_find_preset "$want"); then
      log_error "Unknown preset: $want"
      log_info "Run 'clmac clean --list' to see available presets."
      return 2
    fi
    _load_preset "$f"
    _run_preset
    return $?
  fi

  # Interactive picker.
  _clean_interactive
}

_clean_help() {
  cat <<EOF
${C_BOLD}clmac clean${C_RESET} [preset]

  Run a known-safe cleanup. With no preset, opens an interactive picker.

OPTIONS
  --list         Show all presets with current size
  --all-safe     Run every preset tagged SAFE=true (caches that regenerate)

EXAMPLES
  clmac clean --list
  clmac clean huggingface
  clmac clean --all-safe --dry-run
EOF
}

_clean_list() {
  printf '\n%s%-22s %10s %-6s  %s%s\n' "$C_BOLD" "PRESET" "SIZE" "SAFE" "DESCRIPTION" "$C_RESET"
  printf '%s%s%s\n' "$C_DIM" "$(printf '%.0s-' {1..90})" "$C_RESET"
  spinner_start
  local out
  out=$(
    local f safe_label sz
    while IFS= read -r f; do
      _load_preset "$f"
      sz=$(_preset_current_size)
      if [[ "${PRESET_SAFE:-false}" == "true" ]]; then
        safe_label="${C_GREEN}yes${C_RESET}"
      else
        safe_label="${C_YELLOW}care${C_RESET}"
      fi
      printf '%s%-22s%s %s %b   %s%s%s\n' \
        "$C_CYAN" "$PRESET_NAME" "$C_RESET" \
        "$(human_size_padded "$sz" 10)" \
        "$safe_label" \
        "$C_DIM" "$PRESET_DESC" "$C_RESET"
    done < <(_list_preset_files)
  )
  spinner_stop
  printf '%s\n' "$out"
}

_clean_interactive() {
  spinner_start
  local f
  local -a items=()
  while IFS= read -r f; do
    _load_preset "$f"
    local sz safe
    sz=$(_preset_current_size)
    if [[ "${PRESET_SAFE:-false}" == "true" ]]; then safe="safe"; else safe="care"; fi
    items+=("$(printf '%-22s %10s  [%s]  %s' "$PRESET_NAME" "$(human_size "$sz")" "$safe" "$PRESET_DESC")")
  done < <(_list_preset_files)
  spinner_stop

  local chosen
  chosen=$(printf '%s\n' "${items[@]}" | select_multi "Pick preset(s) to clean (Tab multi-select, Enter confirm)")
  [[ -z "$chosen" ]] && { log_info "Nothing selected."; return 0; }

  # Extract preset name (first column).
  while IFS= read -r line; do
    local name=${line%% *}
    local pf
    if pf=$(_find_preset "$name"); then
      _load_preset "$pf"
      _run_preset
    fi
  done <<< "$chosen"
}

_clean_all_safe() {
  local f
  while IFS= read -r f; do
    _load_preset "$f"
    [[ "${PRESET_SAFE:-false}" == "true" ]] || continue
    _run_preset
  done < <(_list_preset_files)
}

# Run the currently loaded preset.
_run_preset() {
  local before sz path
  before=$(_preset_current_size)
  local before_h
  before_h=$(human_size "$before")

  printf '\n%s%s%s — %s (%s)\n' "$C_BOLD" "$PRESET_NAME" "$C_RESET" "$PRESET_DESC" "$before_h"

  # Command-style preset.
  if [[ -n "${PRESET_COMMAND:-}" ]]; then
    if [[ "$CMM_DRY_RUN" -eq 1 ]]; then
      printf '%s[dry-run]%s would run: %s\n' "$C_DIM" "$C_RESET" "$PRESET_COMMAND"
      return 0
    fi
    if ! confirm "Run '$PRESET_COMMAND'?"; then
      log_info "Skipped."
      return 0
    fi
    eval "$PRESET_COMMAND"
    return $?
  fi

  # Scan-style preset (e.g., node-modules).
  if [[ "${PRESET_SCAN:-false}" == "true" ]]; then
    _run_scan_preset
    return $?
  fi

  # Standard path-removal preset.
  local nonexistent=1
  for path in "${PRESET_PATHS[@]}"; do
    [[ -e "$path" ]] && nonexistent=0
  done
  if (( nonexistent )); then
    log_info "  Nothing to clean (paths absent)."
    return 0
  fi

  for path in "${PRESET_PATHS[@]}"; do
    [[ -e "$path" ]] || continue
    sz=$(dir_size "$path")
    printf '  %s  (%s)\n' "${path/#$HOME/\~}" "$(human_size "$sz")"
  done

  if ! confirm "Delete these paths?"; then
    log_info "Skipped."
    return 0
  fi

  for path in "${PRESET_PATHS[@]}"; do
    if [[ "${PRESET_EMPTY_NOT_REMOVE:-false}" == "true" ]]; then
      _empty_dir "$path"
    else
      safe_rm "$path"
    fi
  done

  local after after_h freed
  after=$(_preset_current_size)
  after_h=$(human_size "$after")
  freed=$(( before - after ))
  printf '  %s%sFreed:%s %s%s%s\n' \
    "$C_BOLD" "$C_GREEN" "$C_RESET" \
    "$C_GREEN" "$(human_size "$freed")" "$C_RESET"
}

# Empty all entries inside a directory without removing the directory itself.
_empty_dir() {
  local d=$1
  [[ -d "$d" ]] || return 0
  if [[ "$CMM_DRY_RUN" -eq 1 ]]; then
    printf '%s[dry-run]%s would empty %s\n' "$C_DIM" "$C_RESET" "$d"
    return 0
  fi
  # Glob hidden + visible entries safely.
  shopt -s dotglob nullglob
  local entry
  for entry in "$d"/*; do
    rm -rf -- "$entry"
  done
  shopt -u dotglob nullglob
}

_run_scan_preset() {
  local root d
  local -a found=()
  for root in "${PRESET_SCAN_ROOTS[@]}"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r -d '' d; do
      # Skip if modified within the min-age window.
      if [[ -n "${PRESET_SCAN_MIN_AGE_DAYS:-}" ]]; then
        if find "$d" -maxdepth 0 -mtime -"${PRESET_SCAN_MIN_AGE_DAYS}" -print -quit | grep -q .; then
          continue
        fi
      fi
      found+=("$d")
    done < <(find "$root" -type d -name "$PRESET_SCAN_NAME" -prune -print0 2>/dev/null)
  done

  if (( ${#found[@]} == 0 )); then
    log_info "  No $PRESET_SCAN_NAME directories found (older than ${PRESET_SCAN_MIN_AGE_DAYS:-0} days)."
    return 0
  fi

  # Build labelled lines for picker: "<size>\t<path>"
  local -a labelled=()
  local sz
  for d in "${found[@]}"; do
    sz=$(dir_size "$d")
    labelled+=("$(printf '%10s  %s' "$(human_size "$sz")" "${d/#$HOME/\~}")")
  done

  local chosen
  chosen=$(printf '%s\n' "${labelled[@]}" | select_multi "Pick $PRESET_SCAN_NAME dirs to remove")
  [[ -z "$chosen" ]] && { log_info "Nothing selected."; return 0; }

  local line path expanded
  while IFS= read -r line; do
    # Strip the size column (first ~10 chars + 2 spaces).
    path=$(awk '{ for (i=2; i<=NF; i++) printf "%s%s", $i, (i==NF?"":" ") }' <<< "$line")
    expanded=${path/#\~/$HOME}
    safe_rm "$expanded"
  done <<< "$chosen"
}
