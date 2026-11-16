#!/bin/bash
# Module: caches — user caches, logs, Trash, sandboxed app caches. Reference module.

caches_meta() { MOD_TITLE="Caches & logs"; }

caches_scan() {
  local c b g kept=""
  safe_clear_children "$H/Library/Caches" "~/Library/Caches"
  safe_clear "$H/Library/Logs" "~/Library/Logs"
  safe_clear "$H/Library/Containers/com.apple.mail/Data/Library/Mail Downloads" "Mail attachment downloads"
  safe_clear "$H/Library/iTunes/iPhone Software Updates" "iPhone firmware (.ipsw)"
  safe_clear "$H/Library/iTunes/iPad Software Updates" "iPad firmware (.ipsw)"
  safe_clear "$H/.Trash" "Trash"
  for c in "$H"/Library/Containers/*/Data/Library/Caches; do
    [ -d "$c" ] || continue
    b="${c#"$H/Library/Containers/"}"; b="${b%%/*}"
    if bundle_running "$b"; then kept="$kept $b"; continue; fi
    safe_clear "$c" "sandboxed app cache: $b"
  done
  for c in "$H"/Library/"Group Containers"/*/Library/Caches; do
    [ -d "$c" ] || continue
    g="${c#"$H/Library/Group Containers/"}"; g="${g%%/*}"
    if group_running "$g"; then kept="$kept $g"; continue; fi
    safe_clear "$c" "group container cache: $g"
  done
  note_kept "$kept"
  command -v qlmanage >/dev/null 2>&1 && safe_cmd qlmanage "reset QuickLook thumbnail cache" caches_ql_reset 0 "-"
  return 0
}

caches_ql_reset() { qlmanage -r cache >/dev/null 2>&1; }

# @standalone-begin
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
  mc_main --only caches "$@"
fi
# @standalone-end
