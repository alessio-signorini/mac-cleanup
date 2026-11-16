#!/bin/bash
# Module: backups — iOS/iPadOS device backups (Finder/iTunes).

backups_meta() { MOD_TITLE="iOS device backups"; }

backups_scan() {
  local BK="$AS/MobileSync/Backup" PB=/usr/libexec/PlistBuddy b dev last
  [ -d "$BK" ] || return 0
  mc_group "Device backups (Finder > device > Manage Backups shows the same list)"
  for b in "$BK"/*/; do
    [ -d "$b" ] || continue; b="${b%/}"
    dev="?"; last="?"
    if [ -f "$b/Info.plist" ] && [ -x "$PB" ]; then
      dev=$("$PB" -c 'Print :"Device Name"' "$b/Info.plist" 2>/dev/null || echo "?")
      last=$("$PB" -c 'Print :"Last Backup Date"' "$b/Info.plist" 2>/dev/null || echo "?")
    fi
    pick_path "$b" "$(fit "$dev" 24) last backup $last"
  done
  return 0
}

# @standalone-begin
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
  mc_main --only backups "$@"
fi
# @standalone-end
