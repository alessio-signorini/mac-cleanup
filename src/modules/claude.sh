#!/bin/bash
# Module: claude — Claude desktop app + Claude Code.

claude_meta() { MOD_TITLE="Claude (desktop + Code)"; }

claude_scan() {
  local vdir active newest v n sub d k CL claude_up=false s ts la vm
  vdir="$H/.local/share/claude/versions"
  if [ -d "$vdir" ]; then
    active=$(readlink "$H/.local/bin/claude" 2>/dev/null); active="${active##*/}"
    newest=$(ls -t "$vdir" 2>/dev/null | head -1)
    for v in "$vdir"/*; do
      [ -e "$v" ] || continue
      n="${v##*/}"
      [ "$n" = "$active" ] || [ "$n" = "$newest" ] && continue
      safe_remove "$v" "Claude Code old binary $n"
    done
  fi
  safe_clear "$H/.claude/debug" "Claude Code debug logs"
  safe_clear "$H/.claude/shell-snapshots" "Claude Code shell snapshots"

  mc_group "Claude Code history older than ${DAYS}d (used by claude --resume)"
  for sub in projects file-history todos; do
    d="$H/.claude/$sub"; [ -d "$d" ] || continue
    n=$(find "$d" -type f -mtime +"$DAYS" 2>/dev/null | wc -l | tr -d ' ')
    [ "$n" -gt 0 ] || continue
    k=$(find "$d" -type f -mtime +"$DAYS" -exec du -k {} + 2>/dev/null | awk '{s+=$1} END{print s+0}')
    pick_item "$d" "~/.claude/$sub: $n files older than ${DAYS}d" "$k" del_older_than_days
  done

  CL="$AS/Claude"
  [ -d "$CL" ] || return 0
  app_running Claude && claude_up=true
  mc_group "Claude desktop ($(hsz "$CL"))"
  for sub in claude-code claude-code-vm; do
    d="$CL/$sub"; [ -d "$d" ] || continue
    newest=$(ls -t "$d" 2>/dev/null | head -1)
    for v in "$d"/*; do
      [ -e "$v" ] || continue
      [ "${v##*/}" = "$newest" ] && continue
      safe_remove "$v" "bundled $sub ${v##*/} (superseded)"
    done
  done

  mc_group "Cowork sessions idle > ${DAYS}d (removes their files/history in the app)"
  while IFS= read -r s; do
    case "$MC_SELF" in "$s"/*) continue ;; esac     # never the session holding this script
    [ -n "$(find "$s" -type f -mtime -"$DAYS" -print 2>/dev/null | head -1)" ] && continue
    ts=$(find "$s" -type f -exec stat -f '%m' {} + 2>/dev/null | sort -n | tail -1)
    la="?"; [ -n "$ts" ] && la=$(date -r "$ts" '+%Y-%m-%d' 2>/dev/null)
    k=$(kb "$s"); [ "$k" -ge 1024 ] || continue
    pick_path "$s" "Cowork session ${s##*/}  (last active $la)" "$k"
  done < <(find "$CL/local-agent-mode-sessions" -mindepth 3 -maxdepth 3 -type d -name 'local_*' 2>/dev/null)

  vm="$CL/vm_bundles"
  if [ -d "$vm" ]; then
    if $claude_up; then
      note skip "Cowork VM image $(hsz "$vm") — quit Claude to reset it"
    else
      mc_group "Cowork VM — only worth deleting if you rarely use Cowork"
      pick_path "$vm" "Cowork VM image (re-downloads ~1.2GB, rebuilds to ~10GB on next Cowork task)"
    fi
  fi
  $claude_up && note skip "Claude is running — its $(hsz "$CL/Cache") cache is cleared only when Claude is quit"
  return 0
}

# @standalone-begin
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
  mc_main --only claude "$@"
fi
# @standalone-end
