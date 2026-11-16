#!/bin/bash
# Module: gimp — temp/swap files and profiles of older GIMP versions.

gimp_meta() { MOD_TITLE="GIMP"; }

gimp_running() {
  app_running GIMP && return 0
  [ -n "${MC_RUNNING_OVERRIDE+x}" ] && return 1
  pgrep -fi '/GIMP[^/]*\.app/' >/dev/null 2>&1
}

gimp_scan() {
  local G="$AS/GIMP" g s vers latest v
  [ -d "$G" ] || return 0
  if gimp_running; then note skip "GIMP is running — quit it to clean"; return 0; fi
  for g in "$G"/*/; do
    [ -d "$g" ] || continue; g="${g%/}"
    safe_clear "$g/tmp" "GIMP ${g##*/} temp"
    for s in "$g"/gimpswap.*; do [ -f "$s" ] && safe_remove "$s" "GIMP swap ${s##*/}"; done
  done
  vers=$(ls -1 "$G" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+' | sort -t. -k1,1n -k2,2n)
  latest=$(printf '%s\n' "$vers" | tail -1)
  mc_group "Profiles of older GIMP versions (settings, brushes, plug-ins)"
  for v in $vers; do
    [ "$v" = "$latest" ] && continue
    pick_path "$G/$v" "GIMP $v profile"
  done
  return 0
}

# @standalone-begin
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
  mc_main --only gimp "$@"
fi
# @standalone-end
