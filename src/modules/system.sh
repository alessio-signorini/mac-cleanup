#!/bin/bash
# Module: system — sudo-level caches, crash reports, rotated logs, Time Machine local snapshots.
# Opt-in: runs only with --system (or when named explicitly).

system_meta() { MOD_TITLE="System-level (sudo)"; MOD_OPTIN=1; }

system_clear() {   # system_clear PATH LABEL — safe item, contents removed via sudo
  local k
  sudo test -d "$1" || return 0
  k=$(sudo du -skx "$1" 2>/dev/null | awk '{print $1+0}')
  [ "${k:-0}" -lt 1024 ] && return 0
  safe_cmd "$1" "$2" system_del_contents "$k"
}

system_scan() {
  local s l
  if ! sudo -v; then note warn "sudo authentication failed — system module skipped"; return 0; fi
  system_clear /Library/Caches "/Library/Caches"
  system_clear /Library/Logs/DiagnosticReports "system crash reports"
  system_clear /Library/Developer/CoreSimulator/Caches "simulator dyld caches (system)"
  safe_cmd rotated "rotated system logs older than 7d (/private/var/log/*.gz)" system_del_rotated 0 "-"
  s=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c 'com.apple')
  if [ "${s:-0}" -gt 0 ]; then
    while IFS= read -r l; do note report "$l"; done < <(tmutil listlocalsnapshots / 2>/dev/null)
    note info "com.apple.os.update-* snapshots belong to Software Update and clear after the update/reboot."
    mc_group "Time Machine local snapshots"
    pick_item thin "thin Time Machine local snapshots ($s found)" 0 system_thin_snapshots "-"
  fi
  return 0
}

system_del_contents() {
  case "$1" in /Library/Caches|/Library/Logs/DiagnosticReports|/Library/Developer/CoreSimulator/Caches) ;; *) return 1 ;; esac
  sudo find "$1" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
  return 0
}
system_del_rotated()    { sudo find /private/var/log -name '*.gz' -mtime +7 -delete; }
system_thin_snapshots() { sudo tmutil thinlocalsnapshots / 999999999999 4; }

# @standalone-begin
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
  mc_main --only system "$@"
fi
# @standalone-end
