#!/bin/bash
# Module: report — where else is space going (read-only; printed at the end).

report_meta() { MOD_TITLE="Where else is space going"; MOD_REPORT=1; }

# Sizes exclude what the modules above already listed and the user kept (unselected,
# skipped, or not applied): the point is to show space nobody has looked at yet.
report_scan() {
  local d k p cov="$MC_TMP/report_covered"
  plan_covered "$cov"
  for d in "$AS" "$H/Library/Containers" "$H/Library/Group Containers"; do
    [ -d "$d" ] || continue
    note info "${BOLD}$(pretty "$d")${RST}"
    report_top_uncovered "$d" 6 "$cov"
  done
  note info "${BOLD}Files > 1GB in home${RST} (excluding colima, omlx, iOS backups, iCloud Drive)"
  while IFS=$'\t' read -r k p; do
    note report "$(printf '%8s  %s' "$(hkb "$k")" "$(pretty "$p")")"
  done < <(find "$H" -xdev \( -path "$H/.colima" -o -path "$H/.omlx" -o -path "$AS/MobileSync" \
             -o -path "$H/Library/Mobile Documents" \) -prune -o -type f -size +1G -print0 2>/dev/null |
           xargs -0 du -k 2>/dev/null | report_uncovered "$cov" | awk -F'\t' '$2 == 0 {print $1 "\t" $3}' |
           sort -rn | head -15)
  [ -s "$cov" ] && note info "${DIM}Sizes leave out what the cleanup modules already listed and you kept.${RST}"
  return 0
}

# stdin "KB<TAB>path" → stdout "uncoveredKB<TAB>coveredKB<TAB>path"
report_uncovered() {
  awk -F'\t' -v cov="$1" '
    BEGIN { while ((getline l < cov) > 0) { split(l, a, "\t"); m++; ck[m] = a[1]; cp[m] = a[2] } }
    { c = 0
      for (j = 1; j <= m; j++)
        if (cp[j] == $2 || index(cp[j], $2 "/") == 1 || index($2, cp[j] "/") == 1) c += ck[j]
      if (c > $1) c = $1
      print ($1 - c) "\t" c "\t" $2 }'
}

# Top N children of DIR by size not already covered by the plan (hides those under 10MB).
report_top_uncovered() {
  local dir="$1" n="$2" u c p extra
  while IFS=$'\t' read -r u c p; do
    extra=""; [ "$c" -gt 0 ] && extra="  ${DIM}(+$(hkb "$c") listed above)${RST}"
    note report "$(printf '%8s  %s%s' "$(hkb "$u")" "$(pretty "$p")" "$extra")"
  done < <(du -skx "$dir"/* "$dir"/.[!.]* 2>/dev/null | report_uncovered "$3" |
           awk -F'\t' '$1 >= 10240' | sort -t$'\t' -k1,1rn | head -"$n")
}

# @standalone-begin
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
  mc_main --only report "$@"
fi
# @standalone-end
