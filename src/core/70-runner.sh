#!/bin/bash
# shellcheck disable=SC2034
# Phases: scan → report (dry-run) | review + apply → summary.

MODS=()             # active modules, in order
MD_TITLE=(); MD_OPTIN=(); MD_REPORT=()
MD_STATE=()         # "", applied, skipped, empty
MD_FREED=(); MD_OKN=(); MD_FAILN=()
TOTAL_FREED=0
START_FREE=0

mod_meta() {   # loads MOD_TITLE MOD_OPTIN MOD_REPORT for module $1
  MOD_TITLE="$1"; MOD_OPTIN=0; MOD_REPORT=0
  declare -F "${1}_meta" >/dev/null && "${1}_meta"
}

mod_idx() {  # index of module $1 in MODS
  local i
  for ((i=0; i<${#MODS[@]}; i++)); do [ "${MODS[$i]}" = "$1" ] && { echo "$i"; return; }; done
  echo -1
}

in_list() { [[ ",$2," == *",$1,"* ]]; }

resolve_modules() {
  local m
  MODS=(); MD_TITLE=(); MD_OPTIN=(); MD_REPORT=()
  for m in $MC_ALL_MODULES; do
    declare -F "${m}_scan" >/dev/null || continue
    [ -n "$SKIP" ] && in_list "$m" "$SKIP" && continue
    mod_meta "$m"
    if [ -n "$ONLY" ]; then in_list "$m" "$ONLY" || continue
    elif [ "$MOD_OPTIN" = 1 ]; then in_list "$m" "$EXTRA" || continue
    fi
    MODS+=("$m"); MD_TITLE+=("$MOD_TITLE"); MD_OPTIN+=("$MOD_OPTIN"); MD_REPORT+=("$MOD_REPORT")
    MD_STATE+=(""); MD_FREED+=(0); MD_OKN+=(0); MD_FAILN+=(0)
  done
}

disk_banner() {
  local d r
  d=$(df -h "$H" 2>/dev/null | awk 'NR==2{printf "%s used of %s, %s free (%s)", $3, $2, $4, $5}')
  printf '%s%s %s%s — Disk: %s\n' "$BOLD" "$MC_NAME" "$MC_VERSION" "$RST" "$d"
  $APPLY || printf '%sDRY-RUN%s — nothing will be deleted. Re-run with --apply.\n' "$YLW$BOLD" "$RST"
  r=$(running_app_names)
  [ -n "$r" ] && printf '%s! running now (their caches will be skipped): %s%s\n' "$YLW" "$r" "$RST"
  return 0
}

# scan_all [report]. Default: every module, except that report modules are deferred when
# applying (they describe disk usage, so they're measured after deleting). "report": only those.
scan_all() {
  local i k=0 n idx=()
  for ((i=0; i<${#MODS[@]}; i++)); do
    if [ "${1:-}" = report ]; then [ "${MD_REPORT[$i]}" = 1 ] || continue
    elif $APPLY && [ "${MD_REPORT[$i]}" = 1 ]; then continue; fi
    idx+=("$i")
  done
  n=${#idx[@]}
  for i in "${idx[@]}"; do
    k=$((k + 1))
    MOD_CUR="${MODS[$i]}"; GRP_CUR=""
    GRP_SEQ=$((GRP_SEQ + 1))
    progress "$(printf 'Scanning %2d/%d  %s…' "$k" "$n" "${MD_TITLE[$i]}")"
    "${MOD_CUR}_scan"
  done
  progress_done
  MOD_CUR=""
}

# ------------------------------------------------------------------ dry-run report
print_notes() {   # print_notes MODULE [kinds-regex]
  local i n=${#NT_MOD[@]}
  for ((i=0; i<n; i++)); do
    [ "${NT_MOD[$i]}" = "$1" ] || continue
    [ -n "${2:-}" ] && ! [[ "${NT_KIND[$i]}" =~ $2 ]] && continue
    case "${NT_KIND[$i]}" in
      warn)   warn "${NT_TEXT[$i]}" ;;
      skip)   skip "${NT_TEXT[$i]}" ;;
      tip)    printf '  %s→ %s%s\n' "$CYN" "${NT_TEXT[$i]}" "$RST" ;;
      report) printf '  %s%s%s\n' "$DIM" "${NT_TEXT[$i]}" "$RST" ;;
      *)      info "${NT_TEXT[$i]}" ;;
    esac
  done
}

sizes_text() {   # "safe X · review Y"
  local s="-" p="-"
  [ "$1" -gt 0 ] && s=$(hkb "$1")
  [ "$2" -gt 0 ] && p=$(hkb "$2")
  printf 'safe %s · review %s' "$s" "$p"
}

report_module() {
  local m="$1" title="$2" i g="" tc
  mod_sums "$m"
  [ "$MS_N" -eq 0 ] && ! mod_has_notes "$m" && return 0
  printf "\n%s== %s ==%s  %s%s%s\n" "$BOLD$CYN" "$title" "$RST" "$DIM" "$(sizes_text "$MS_SAFE" "$MS_PICK")" "$RST"
  mod_items "$m"
  for i in "${ORD[@]}"; do
    if [ "${IT_GRP[$i]}" != "$g" ]; then
      g="${IT_GRP[$i]}"; [ -n "$g" ] && printf '  %s%s%s\n' "$BOLD" "$g" "$RST"
    fi
    tc="$GRN"; [ "${IT_TIER[$i]}" = pick ] && tc="$YLW"
    printf '    %s%-4s%s %8s  %s\n' "$tc" "${IT_TIER[$i]}" "$RST" "$(item_size "$i")" "${IT_LABEL[$i]}"
  done
  print_notes "$m"
}

overview_table() {
  local i m ts=0 tp=0 s p empty=""
  hdr "OVERVIEW"
  printf '  %s%s %10s %10s%s\n' "$DIM" "$(padr MODULE 30)" "SAFE" "REVIEW" "$RST"
  for ((i=0; i<${#MODS[@]}; i++)); do
    m="${MODS[$i]}"; [ "${MD_REPORT[$i]}" = 1 ] && continue
    mod_sums "$m"
    if [ "$MS_N" -eq 0 ]; then empty="$empty, ${MD_TITLE[$i]}"; continue; fi
    s="-"; p="-"
    [ "$MS_SAFE" -gt 0 ] && s=$(hkb "$MS_SAFE")
    [ "$MS_PICK" -gt 0 ] && p=$(hkb "$MS_PICK")
    printf '  %s %10s %10s\n' "$(padr "${MD_TITLE[$i]}" 30)" "$s" "$p"
    ts=$((ts + MS_SAFE)); tp=$((tp + MS_PICK))
  done
  printf '  %s%s %10s %10s%s\n' "$BOLD" "$(padr TOTAL 30)" "$(hkb "$ts")" "$(hkb "$tp")" "$RST"
  [ -n "$empty" ] && printf '  %snothing to clean: %s%s\n' "$DIM" "${empty#, }" "$RST"
  OV_SAFE=$ts; OV_PICK=$tp
}

print_report_modules() {
  local i
  for ((i=0; i<${#MODS[@]}; i++)); do
    [ "${MD_REPORT[$i]}" = 1 ] || continue
    mod_has_notes "${MODS[$i]}" || continue
    hdr "${MD_TITLE[$i]}"
    print_notes "${MODS[$i]}"
  done
}

# ------------------------------------------------------------------ apply
RV_MOD=""; RV_ROW=()   # module last shown in the item picker; RV_ROW[item] = picker row

# Live apply in the item picker that was just confirmed: rows turn busy → gone/FAIL in place,
# the footer shows a progress bar, the count, freed so far and the current item.
ap_foot() {   # ap_foot K TOT FREED_KB LABEL
  local w=24 fill
  fill=$(( $1 * w / $2 ))
  printf -v PK_FOOT1 '%sDeleting%s [%s%*s] %d/%d · freed %s' "$BOLD" "$RST" \
    "$(printf '%*s' "$fill" '' | tr ' ' '#')" $((w - fill)) '' "$1" "$2" "$(hkb "$3")"
  PK_FOOT2="$4"
}

apply_module() {   # apply_module INDEX  (applies items with IT_SEL=1)
  local mi="$1" m="${MODS[$1]}" i before after freed k=0 tot=0 res live=false row
  mod_items "$m"
  for i in "${ORD[@]}"; do [ "${IT_SEL[$i]}" = 1 ] && tot=$((tot + 1)); done
  $TUI_HOLD && [ "$RV_MOD" = "$m" ] && { live=true; PK_APPLYING=true; }
  for i in "${ORD[@]}"; do
    [ "${IT_SEL[$i]}" = 1 ] || continue
    $MC_INTERRUPTED && break
    k=$((k + 1))
    if $live; then
      row="${RV_ROW[$i]}"; PK_ST[row]=run; PK_CUR=$row
      ap_foot $((k - 1)) "$tot" "${MD_FREED[$mi]}" "${IT_LABEL[$i]}"; pk_draw
    else progress "$(printf '  applying %d/%d  %s…' "$k" "$tot" "${IT_LABEL[$i]:0:60}")"; fi
    before="${IT_KB[$i]}"
    [ -n "${IT_MEAS[$i]}" ] && before=$(kb_meas "${IT_MEAS[$i]}")
    if "${IT_ACT[$i]}" "${IT_ID[$i]}" >> "$MC_TMP/actions.log" 2>&1; then
      res=ok
      if [ -n "${IT_MEAS[$i]}" ]; then
        after=$(kb_meas "${IT_MEAS[$i]}"); freed=$((before - after)); [ "$freed" -lt 0 ] && freed=0
      else freed="${IT_KB[$i]}"; fi
      MD_OKN[mi]=$((MD_OKN[mi] + 1))
    else
      res=fail; freed=0
      MD_FAILN[mi]=$((MD_FAILN[mi] + 1))
    fi
    IT_RES[i]=$res
    $live && PK_ST[row]=$res
    MD_FREED[mi]=$((MD_FREED[mi] + freed)); TOTAL_FREED=$((TOTAL_FREED + freed))
    mc_log "$m  $res  $(hkb "$freed")  ${IT_LABEL[$i]}  [${IT_ID[$i]}]"
    if $VERBOSE; then
      progress_done
      if [ "$res" = ok ]; then emit "$(printf '      %s✔%s %8s  %s' "$GRN" "$RST" "$(hkb "$freed")" "${IT_LABEL[$i]}")"
      else emit "$(printf '      %s✘%s %8s  %s' "$RED" "$RST" "" "${IT_LABEL[$i]}")"; fi
    fi
  done
  progress_done
  if $live; then
    ap_foot "$k" "$tot" "${MD_FREED[$mi]}" "done"; pk_draw
    sleep 1   # let the finished list register before the next screen
    PK_APPLYING=false
  fi
  MD_STATE[mi]=applied
}

result_line() {   # one line per module after apply/skip
  local mi="$1" t extra=""
  t=$(padr "${MD_TITLE[$1]}" 28)
  mod_sums "${MODS[$mi]}"
  case "${MD_STATE[$mi]}" in
    applied)
      if [ "${MD_OKN[$mi]}" -eq 0 ] && [ "${MD_FAILN[$mi]}" -eq 0 ]; then
        printf '  %s–%s %s nothing selected\n' "$DIM" "$RST" "$t"; return
      fi
      [ "${MD_FAILN[$mi]}" -gt 0 ] && extra=" · ${RED}${MD_FAILN[$mi]} failed${RST}"
      printf '  %s✔%s %s freed %s%s%s  (%d item(s))%s\n' "$GRN" "$RST" "$t" "$BOLD" "$(hkb "${MD_FREED[$mi]}")" "$RST" \
        "${MD_OKN[$mi]}" "$extra" ;;
    skipped)
      printf '  %s–%s %s skipped  %s(%s)%s\n' "$DIM" "$RST" "$t" "$DIM" "$(sizes_text "$MS_SAFE" "$MS_PICK")" "$RST" ;;
    *)
      printf '  %s·%s %s nothing to clean\n' "$DIM" "$RST" "$t" ;;
  esac
  $VERBOSE && print_notes "${MODS[$mi]}"
  return 0
}

# Review module $1 (index) with the picker; returns 0 if confirmed.
review_module() {
  local mi="$1" m="${MODS[$1]}" i g="" j=0
  local rowmap=()
  RV_MOD=""; RV_ROW=()
  mod_items "$m"; mod_sums "$m"
  pk_reset
  PK_TITLE="${MD_TITLE[$mi]}"
  PK_SUB="$(sizes_text "$MS_SAFE" "$MS_PICK")"
  PK_CONFIRM=true
  for ((i=0; i<${#NT_MOD[@]}; i++)); do
    [ "${NT_MOD[$i]}" = "$m" ] && pk_note "${NT_KIND[$i]}" "${NT_TEXT[$i]}"
  done
  for i in "${ORD[@]}"; do
    if [ "${IT_GRP[$i]}" != "$g" ]; then
      g="${IT_GRP[$i]}"
      if [ -n "$g" ]; then pk_header "$g"; rowmap+=(-1); fi
    fi
    pk_row "${IT_LABEL[$i]}" "$(item_size "$i")" "${IT_KB[$i]}" "${IT_SEL[$i]}" "${IT_TIER[$i]}"
    rowmap+=("$i")
  done
  picker || return 1
  for ((j=0; j<${#rowmap[@]}; j++)); do
    i=${rowmap[$j]}
    [ "$i" -ge 0 ] && { IT_SEL[i]=${PK_SEL[$j]}; RV_ROW[i]=$j; }
  done
  RV_MOD="$m"
  return 0
}

# Module picker (TUI only). Sets MD_STATE=skipped for unticked modules. Returns 1 on quit.
choose_modules() {
  local i n=0
  local map=()
  pk_reset
  PK_TITLE="Choose modules to review"
  PK_SUB="(space toggles, enter continues)"
  PK_QUIT_LABEL="quit"
  for ((i=0; i<${#MODS[@]}; i++)); do
    [ "${MD_REPORT[$i]}" = 1 ] && continue
    mod_sums "${MODS[$i]}"
    [ "$MS_N" -gt 0 ] || continue
    pk_row "$(fit "${MD_TITLE[$i]}" 30) $(sizes_text "$MS_SAFE" "$MS_PICK")" \
      "$(hkb $((MS_SAFE + MS_PICK)))" $((MS_SAFE + MS_PICK)) 1 ""
    map+=("$i"); n=$((n + 1))
  done
  [ "$n" -gt 0 ] || return 0
  picker || return 1
  for ((i=0; i<${#map[@]}; i++)); do
    [ "${PK_SEL[$i]}" = 1 ] || MD_STATE[${map[$i]}]=skipped
  done
  return 0
}

run_apply() {
  local i quit=false empty="" nsel j
  hdr "RESULTS"
  if ! $ASSUME_YES && $TUI; then
    # One alternate-screen session for the whole review+apply; results print when it ends.
    TUI_HOLD=true
    tui_enter
    choose_modules || quit=true
  fi
  for ((i=0; i<${#MODS[@]}; i++)); do
    [ "${MD_REPORT[$i]}" = 1 ] && continue
    $MC_INTERRUPTED && break
    mod_sums "${MODS[$i]}"
    if [ "$MS_N" -eq 0 ]; then
      MD_STATE[i]=empty
      if mod_has_kind "${MODS[$i]}" warn; then
        emit "$(result_line "$i"; $VERBOSE || print_notes "${MODS[$i]}" '^warn$')"
      else empty="$empty, ${MD_TITLE[$i]}"; fi
      continue
    fi
    if $quit; then MD_STATE[i]=skipped; emit "$(result_line "$i")"; continue; fi
    if [ "${MD_STATE[$i]}" = skipped ]; then emit "$(result_line "$i")"; continue; fi
    if ! $ASSUME_YES; then
      if ! review_module "$i"; then MD_STATE[i]=skipped; emit "$(result_line "$i")"; continue; fi
    fi
    mod_items "${MODS[$i]}"; nsel=0
    for j in "${ORD[@]}"; do [ "${IT_SEL[$j]}" = 1 ] && nsel=$((nsel + 1)); done
    if [ "$nsel" -eq 0 ]; then MD_STATE[i]=skipped; emit "$(result_line "$i")"; continue; fi
    apply_module "$i"
    emit "$(result_line "$i")"
  done
  tui_release
  [ -n "$empty" ] && ! $QUIET && printf '  %s· nothing to clean: %s%s\n' "$DIM" "${empty#, }" "$RST"
  return 0
}

# Ends the apply-phase alternate-screen session and prints the buffered result lines.
tui_release() {
  TUI_HOLD=false
  tui_leave
  emit_flush
}

summary() {
  local end delta
  hdr "SUMMARY"
  if $APPLY; then
    end=$(free_kb); delta=$(( ${end:-0} - ${START_FREE:-0} ))
    local sign="+"; [ "$delta" -lt 0 ] && { sign="-"; delta=$((-delta)); }
    printf '  %sfreed ≈ %s%s   (free space change: %s%s; APFS may take a minute to report)\n' \
      "$GRN$BOLD" "$(hkb "$TOTAL_FREED")" "$RST" "$sign" "$(hkb "$delta")"
    mc_log "run complete: freed≈$(hkb "$TOTAL_FREED") df-delta=$sign$(hkb "$delta")"
  else
    printf '  %ssafe tier ≈ %s%s   review lists up to ≈ %s\n' "$YLW$BOLD" "$(hkb "${OV_SAFE:-0}")" "$RST" "$(hkb "${OV_PICK:-0}")"
    info "Re-run with --apply to review and delete (or --apply --yes for the safe tier only)."
  fi
  df -h "$H" 2>/dev/null | awk 'NR==2{printf "  free now: %s (%s used)\n", $4, $5}'
  $APPLY && info "history: $(pretty "$LOG_FILE")"
  return 0
}

mc_on_interrupt() {
  MC_INTERRUPTED=true
  tui_release
  progress_done
  printf '\n%sinterrupted%s\n' "$YLW" "$RST"
  case "${MC_PHASE:-}" in apply|report) summary ;; esac
  exit 130
}

mc_cleanup() { tui_leave; [ -n "$MC_TMP" ] && rm -rf "$MC_TMP"; }

mc_run() {
  START_FREE=$(free_kb)
  disk_banner
  MC_PHASE=scan
  scan_all
  if ! $APPLY; then
    local i
    if ! $QUIET; then
      for ((i=0; i<${#MODS[@]}; i++)); do
        [ "${MD_REPORT[$i]}" = 1 ] && continue
        report_module "${MODS[$i]}" "${MD_TITLE[$i]}"
      done
    fi
    overview_table
    $QUIET || print_report_modules
    summary
    return 0
  fi
  mc_log "run start: $MC_VERSION modules=${MODS[*]} yes=$ASSUME_YES days=$DAYS media-days=$MEDIA_DAYS"
  MC_PHASE=apply
  run_apply
  MC_PHASE=report
  if ! $QUIET && want_report; then
    scan_all report
    print_report_modules
  fi
  summary
}

# After applying: run report modules if named explicitly (--only/positional), or if the user
# answers y to a 10s prompt. Never in non-interactive runs (they'd only add waiting).
want_report() {
  local i titles="" m
  for ((i=0; i<${#MODS[@]}; i++)); do
    [ "${MD_REPORT[$i]}" = 1 ] || continue
    m="${MODS[$i]}"
    [ -n "$ONLY" ] && in_list "$m" "$ONLY" && return 0
    titles="$titles, ${MD_TITLE[$i]}"
  done
  [ -n "$titles" ] || return 1
  [ -t 0 ] && $IS_TTY && [ -r /dev/tty ] || return 1
  ask_timed "Scan \"${titles#, }\" now? (takes a while)" 10
}

ask_timed() {   # ask_timed QUESTION SECONDS — 0 only if the user presses y before the timeout
  local s="$2" k=""
  while [ "$s" -gt 0 ]; do
    printf '\r\033[K  %s?%s %s [y/N] %s%ds%s ' "$YLW" "$RST" "$1" "$DIM" "$s" "$RST" > /dev/tty
    IFS= read -rsn1 -t 1 k < /dev/tty && break
    s=$((s - 1))
  done
  printf '\r\033[K' > /dev/tty
  case "$k" in y|Y) return 0 ;; esac
  return 1
}
