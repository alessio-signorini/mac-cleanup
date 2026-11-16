#!/bin/bash
# Module: editors — VS Code and forks: logs, superseded extensions, workspace storage.

editors_meta() { MOD_TITLE="Editors (VS Code, Cursor…)"; }

# Prints "kind|path" for a workspaceStorage entry.
editors_ws_target() {
  local j="$1/workspace.json" uri p="" kind="" hex dec
  [ -f "$j" ] || return 1
  uri=$(sed -nE 's/.*"(folder|workspace)"[[:space:]]*:[[:space:]]*"([^"]*)".*/\2/p' "$j" | head -1)
  case "$uri" in
    file://*) p=$(urldecode "${uri#file://}") ;;
    vscode-remote://dev-container+*)
      hex="${uri#vscode-remote://dev-container+}"; hex="${hex%%/*}"
      dec=$(printf '%s' "$hex" | xxd -r -p 2>/dev/null)
      p=$(printf '%s' "$dec" | sed -nE 's/.*"hostPath"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p')
      [ -z "$p" ] && p="$dec"; kind="devcontainer: " ;;
    *) return 1 ;;
  esac
  [ -n "$p" ] || return 1
  printf '%s|%s' "$kind" "$p"
}

editors_scan() {
  local spec app rest dot base edir json valid e n ws w t kind p db k gs
  for spec in "Code|.vscode" "Code - Insiders|.vscode-insiders" "Cursor|.cursor" "Windsurf|.windsurf" "VSCodium|.vscode-oss"; do
    app="${spec%%|*}"; dot="${spec#*|}"
    base="$AS/$app"; edir="$H/$dot/extensions"
    [ -d "$base" ] || [ -d "$edir" ] || continue
    mc_group "$app"
    if app_running "$app"; then
      note skip "$app is running — quit it to clean logs and old extension versions"
    else
      safe_clear "$base/logs" "$app logs"
      json="$edir/extensions.json"
      if [ -f "$json" ]; then
        valid=$(grep -oE '"relativeLocation"[[:space:]]*:[[:space:]]*"[^"]*"' "$json" | sed -E 's/.*"([^"]*)"$/\1/')
        if [ -n "$valid" ]; then
          for e in "$edir"/*/; do
            e="${e%/}"; n="${e##*/}"
            printf '%s\n' "$valid" | grep -qxF "$n" && continue
            safe_remove "$e" "$app superseded extension: $n"
          done
        fi
      fi
    fi
    ws="$base/User/workspaceStorage"
    if [ -d "$ws" ]; then
      note info "$app workspace storage $(hsz "$ws") (per-folder state incl. Copilot/Claude chat history)"
      : > "$MC_TMP/editors_orphan"; : > "$MC_TMP/editors_idle"
      for w in "$ws"/*/; do
        w="${w%/}"
        t=$(editors_ws_target "$w") || continue
        kind="${t%%|*}"; p="${t#*|}"
        if [ ! -e "$p" ]; then
          printf '%s\t%s\n' "$w" "${kind}$(pretty "$p")  (folder gone)" >> "$MC_TMP/editors_orphan"
        else
          db="$w/state.vscdb"
          [ -f "$db" ] && [ -n "$(find "$db" -mtime +"$DAYS" 2>/dev/null)" ] || continue
          printf '%s\t%s\n' "$w" "${kind}$(pretty "$p")  (last opened $(stat -f '%Sm' -t '%Y-%m-%d' "$db" 2>/dev/null))" >> "$MC_TMP/editors_idle"
        fi
      done
      mc_group "$app — orphaned workspaces (folder no longer exists)"
      while IFS=$'\t' read -r w n; do pick_path "$w" "$n"; done < "$MC_TMP/editors_orphan"
      mc_group "$app — idle > ${DAYS}d, > 10MB (reopening starts with fresh state/chat)"
      while IFS=$'\t' read -r w n; do
        k=$(kb "$w"); [ "$k" -ge 10240 ] && pick_path "$w" "$n" "$k"
      done < "$MC_TMP/editors_idle"
    fi
    gs="$base/User/globalStorage"
    if [ -d "$gs" ]; then
      note report "$app largest extension data (globalStorage):"
      report_top "$gs" 5
    fi
    [ -d "$base/User/History" ] && note report "$(printf '%8s  %s Local History (file snapshots)' "$(hsz "$base/User/History")" "$app")"
  done
  return 0
}

# @standalone-begin
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
  mc_main --only editors "$@"
fi
# @standalone-end
