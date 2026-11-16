#!/bin/bash
# Module: report — where else is space going (read-only; printed at the end).

report_meta() { MOD_TITLE="Where else is space going"; MOD_REPORT=1; }

report_scan() {
  local d k p
  for d in "$AS" "$H/Library/Containers" "$H/Library/Group Containers"; do
    [ -d "$d" ] || continue
    note info "${BOLD}$(pretty "$d")${RST}"
    report_top "$d" 6
  done
  note info "${BOLD}Files > 1GB in home${RST} (excluding colima, omlx, iOS backups, iCloud Drive)"
  while read -r k p; do
    note report "$(printf '%8s  %s' "$(hkb "$k")" "$(pretty "$p")")"
  done < <(find "$H" -xdev \( -path "$H/.colima" -o -path "$H/.omlx" -o -path "$AS/MobileSync" \
             -o -path "$H/Library/Mobile Documents" \) -prune -o -type f -size +1G -print0 2>/dev/null |
           xargs -0 du -k 2>/dev/null | sort -rn | head -15)
  return 0
}

# @standalone-begin
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
  mc_main --only report "$@"
fi
# @standalone-end
