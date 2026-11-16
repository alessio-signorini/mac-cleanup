#!/bin/bash
# Module: orphans — containers left behind by uninstalled apps.

orphans_meta() { MOD_TITLE="Leftovers of uninstalled apps"; }

# Any installed app from the same vendor (first two reverse-DNS parts)?
orphans_vendor_installed() {
  local v
  v=$(printf '%s' "$1" | awk -F. 'NF>=2{print $1"."$2}')
  [ -z "$v" ] && return 0
  grep -qiF "$v." "$MC_TMP/orphans_installed" || grep -qixF "$v" "$MC_TMP/orphans_installed"
}

orphans_scan() {
  local c b g k
  mdfind -attr kMDItemCFBundleIdentifier "kMDItemContentType == 'com.apple.application-bundle'" 2>/dev/null |
    sed -n 's/.*kMDItemCFBundleIdentifier = \(.*\)$/\1/p' | grep -v '(null)' | sort -u > "$MC_TMP/orphans_installed"
  if [ "$(wc -l < "$MC_TMP/orphans_installed" | tr -d ' ')" -lt 20 ]; then
    note skip "Spotlight app index unavailable — skipped (needs Spotlight enabled on the system volume)"
    return 0
  fi
  mc_group "No installed app from the same vendor (e.g. UTM VMs left behind)"
  for c in "$H"/Library/Containers/*/; do
    c="${c%/}"; b="${c##*/}"
    case "$b" in com.apple.*|*" "*) continue ;; esac
    [[ "$b" == *.*.* ]] || continue
    bundle_running "$b" && continue
    orphans_vendor_installed "$b" && continue
    k=$(kb "$c"); [ "$k" -ge 1024 ] || continue
    pick_path "$c" "container  $b" "$k"
  done
  for c in "$H"/Library/"Group Containers"/*/; do
    c="${c%/}"; g="${c##*/}"; g="${g#group.}"
    [[ "$g" =~ ^[A-Z0-9]{10}\.(.+)$ ]] && g="${BASH_REMATCH[1]}"
    case "$g" in com.apple.*|systemgroup.*) continue ;; esac
    [[ "$g" == *.*.* ]] || continue
    group_running "${c##*/}" && continue
    orphans_vendor_installed "$g" && continue
    k=$(kb "$c"); [ "$k" -ge 1024 ] || continue
    pick_path "$c" "group      ${c##*/}" "$k"
  done
  note tip "If a delete fails with 'Operation not permitted', grant your terminal Full Disk Access or drag the folder to Trash in Finder."
  return 0
}

# @standalone-begin
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
  mc_main --only orphans "$@"
fi
# @standalone-end
