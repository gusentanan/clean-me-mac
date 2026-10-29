#!/opt/homebrew/bin/bash
# Simulator cleanup helpers behind the `simulators`, `simulator-erase` and
# `simulator-runtimes` presets. Sizes come from `simctl`'s own JSON.

_sim_available() {
  if ! xcrun --find simctl >/dev/null 2>&1; then
    log_warn "simctl not found — install Xcode or its command line tools."
    return 1
  fi
}

# One TSV row per device: bytes, udid, state, runtime, name.
_sim_device_rows() {
  xcrun simctl list devices -j 2>/dev/null | jq -r '
    .devices | to_entries[] | .key as $rt
    | .value[]
    | [(.dataPathSize // 0), .udid, .state,
       ($rt | sub("com.apple.CoreSimulator.SimRuntime."; "")), .name]
    | @tsv'
}

# _sim_pick_devices delete|erase
# Interactive picker over simulator devices. Booted devices are skipped
# (simctl cannot erase or delete them). The udid is the last column of each
# line so device names with spaces parse back cleanly.
_sim_pick_devices() {
  local mode=$1
  _sim_available || return 0

  if [[ "$mode" == "delete" ]]; then
    if [[ "$CMM_DRY_RUN" -eq 1 ]]; then
      printf '  %s%s%s would run: xcrun simctl delete unavailable\n' "$C_DIM" "$ICON_DRY_RUN" "$C_RESET"
    else
      xcrun simctl delete unavailable >/dev/null 2>&1 && log_success "removed unavailable simulators"
    fi
  fi

  local -a items=()
  local bytes udid state runtime name
  while IFS=$'\t' read -r bytes udid state runtime name; do
    [[ -z "$udid" ]] && continue
    [[ "$state" == "Booted" ]] && { log_warn "skipping booted simulator: $name ($udid) — shut it down first"; continue; }
    items+=("$(printf '%s  %-9s %s  %s' "$(human_size_padded "$bytes" 10)" "$runtime" "$name" "$udid")")
  done < <(_sim_device_rows | sort -t$'\t' -k1 -nr)

  if (( ${#items[@]} == 0 )); then
    log_info "  No simulators to $mode."
    return 0
  fi

  local chosen
  chosen=$(printf '%s\n' "${items[@]}" | select_multi "Pick simulator(s) to $mode")
  [[ -z "$chosen" ]] && { log_info "Nothing selected."; return 0; }

  local -a udids=()
  local line
  while IFS= read -r line; do udids+=("${line##* }"); done <<< "$chosen"

  confirm "${mode^} ${#udids[@]} simulator(s)?" || { log_info "Skipped."; return 0; }

  local freed=0 sz
  for udid in "${udids[@]}"; do
    sz=$(_sim_device_rows | awk -F'\t' -v u="$udid" '$2 == u { print $1 }')
    if [[ "$CMM_DRY_RUN" -eq 1 ]]; then
      printf '  %s%s%s would %s %s\n' "$C_DIM" "$ICON_DRY_RUN" "$C_RESET" "$mode" "$udid"
      continue
    fi
    if xcrun simctl "$mode" "$udid" >/dev/null 2>&1; then
      freed=$(( freed + ${sz:-0} ))
      log_operation "simctl-$mode" "$udid" "${sz:-0}"
      log_success "$mode $udid ($(human_size "${sz:-0}"))"
    else
      log_error "simctl $mode failed for $udid"
    fi
  done
  [[ "$CMM_DRY_RUN" -eq 1 ]] || printf '%sFreed:%s ~%s\n' "$C_BOLD" "$C_RESET" "$(human_size_c "$freed")"
}

# _sim_pick_runtimes — pick simulator runtime disk images to remove. Each is
# a multi-GB download that Xcode can fetch again; devices that use a removed
# runtime become unavailable (the `simulators` preset cleans those up).
_sim_pick_runtimes() {
  _sim_available || return 0

  local rt_json dev_json
  rt_json=$(xcrun simctl runtime list -j 2>/dev/null)
  dev_json=$(xcrun simctl list devices -j 2>/dev/null)

  local -a items=()
  local bytes label id rtid users
  while IFS=$'\t' read -r bytes label id rtid; do
    [[ -z "$id" ]] && continue
    users=$(jq -r --arg r "$rtid" '.devices[$r] // [] | length' <<< "$dev_json")
    items+=("$(printf '%s  %-14s %s device(s)  %s' "$(human_size_padded "$bytes" 10)" "$label" "$users" "$id")")
  done < <(jq -r '
      to_entries[] | select(.value.deletable == true)
      | [.value.sizeBytes, (.value.runtimeIdentifier | sub("com.apple.CoreSimulator.SimRuntime."; "") | sub("-"; " ") | gsub("-"; ".")),
         .key, .value.runtimeIdentifier] | @tsv' <<< "$rt_json" | sort -t$'\t' -k1 -nr)

  if (( ${#items[@]} == 0 )); then
    log_info "  No removable simulator runtimes."
    return 0
  fi

  local chosen
  chosen=$(printf '%s\n' "${items[@]}" | select_multi "Pick simulator runtime(s) to remove")
  [[ -z "$chosen" ]] && { log_info "Nothing selected."; return 0; }

  local -a ids=()
  local line
  while IFS= read -r line; do ids+=("${line##* }"); done <<< "$chosen"

  confirm "Remove ${#ids[@]} runtime(s)? Devices using them become unavailable." \
    || { log_info "Skipped."; return 0; }

  local sz
  for id in "${ids[@]}"; do
    sz=$(jq -r --arg i "$id" '.[$i].sizeBytes // 0' <<< "$rt_json")
    if [[ "$CMM_DRY_RUN" -eq 1 ]]; then
      printf '  %s%s%s would run: xcrun simctl runtime delete %s\n' "$C_DIM" "$ICON_DRY_RUN" "$C_RESET" "$id"
      continue
    fi
    if xcrun simctl runtime delete "$id" >/dev/null 2>&1; then
      log_operation "simctl-runtime-delete" "$id" "$sz"
      log_success "removed runtime $id ($(human_size "$sz"))"
    else
      log_error "simctl runtime delete failed for $id"
    fi
  done
}
