#!/bin/bash
# Module: apps — Electron/Chromium app caches (VS Code, Claude, Chrome, Slack…), krisp, GoogleUpdater.

apps_meta() { MOD_TITLE="App caches"; }

apps_scan() {
  [ -d "$AS" ] || return 0
  local d rel root k r tk list kept="" f v newest K GU
  find "$AS" -maxdepth 5 \
    \( -path "$AS/MobileSync" -o -path "$AS/com.apple.*" -o -path "$AS/AddressBook" -o -path "$AS/CallHistoryDB" \
       -o -path "$AS/Knowledge" -o -path "$AS/CloudDocs" -o -path "$AS/FileProvider" \
       -o -path "$AS/Claude/local-agent-mode-sessions" -o -path "$AS/Claude/vm_bundles" \) -prune -o \
    -type d \( -name Cache -o -name "Code Cache" -o -name GPUCache -o -name DawnCache -o -name DawnGraphiteCache \
       -o -name DawnWebGPUCache -o -name GraphiteDawnCache -o -name ShaderCache -o -name GrShaderCache \
       -o -name CacheStorage -o -name ScriptCache -o -name CachedData -o -name CachedExtensionVSIXs \
       -o -name CachedProfilesData -o -name component_crx_cache \) -prune -print 2>/dev/null > "$MC_TMP/apps_dirs"
  : > "$MC_TMP/apps_found"
  while IFS= read -r d; do
    rel="${d#"$AS/"}"; root="${rel%%/*}"
    if app_running "$root"; then
      case " $kept " in *" $root "*) ;; *) kept="$kept $root" ;; esac
      continue
    fi
    k=$(kb "$d"); [ "$k" -lt 1024 ] && continue
    printf '%s\t%s\t%s\n' "$root" "$k" "$d" >> "$MC_TMP/apps_found"
  done < "$MC_TMP/apps_dirs"
  # one safe item per app root, so a single app can be unticked
  while IFS=$'\t' read -r tk r; do
    [ -n "$r" ] || continue
    list=$(mc_listfile)
    awk -F'\t' -v r="$r" '$1==r{print $3}' "$MC_TMP/apps_found" > "$list"
    mc_item safe "$list" "$r caches" "$tk" del_listed_contents "" "@$list"
  done < <(awk -F'\t' '{s[$1]+=$2} END{for(r in s) print s[r]"\t"r}' "$MC_TMP/apps_found" | sort -rn)
  note_kept "$kept"

  K="$AS/krisp"
  if [ -d "$K" ]; then
    if app_running krisp; then note skip "krisp is running — quit it to clean installers/logs/models"
    else
      for f in "$K"/update/*.pkg "$K"/update/*.dmg "$K"/update/*.zip; do
        [ -f "$f" ] && safe_remove "$f" "krisp leftover installer ${f##*/}"
      done
      safe_clear "$K/logs" "krisp logs"
      [ -d "$K/models" ] && pick_path "$K/models" "krisp speech models (transcription; re-downloaded when needed)"
    fi
  fi

  GU="$AS/Google/GoogleUpdater"
  if [ -d "$GU" ]; then
    safe_clear "$GU/crx_cache" "GoogleUpdater download cache"
    newest=$(ls -1 "$GU" 2>/dev/null | grep -E '^[0-9]+\.' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1)
    for v in "$GU"/[0-9]*; do
      [ -d "$v" ] && [ "${v##*/}" != "$newest" ] && safe_remove "$v" "GoogleUpdater old version ${v##*/}"
    done
  fi
  return 0
}

# @standalone-begin
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
  mc_main --only apps "$@"
fi
# @standalone-end
