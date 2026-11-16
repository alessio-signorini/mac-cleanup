#!/bin/bash
# Module: brew — old formula versions, download cache, orphaned dependencies.

brew_meta() { MOD_TITLE="Homebrew"; }

brew_scan() {
  command -v brew >/dev/null 2>&1 || return 0
  local line k orphans
  line=$(brew cleanup --prune=all -n 2>/dev/null | grep -i 'free approximately' | tail -1)
  k=$(parse_size "$(printf '%s' "$line" | sed -nE 's/.*approximately ([0-9.]+[A-Za-z]+).*/\1/p')")
  [ "${k:-0}" -gt 0 ] && safe_cmd cleanup "brew cleanup --prune=all -s (old versions + downloads)" brew_cleanup "$k"
  orphans=$(brew autoremove --dry-run 2>/dev/null | grep -vc '^==>')
  [ "${orphans:-0}" -gt 0 ] && safe_cmd autoremove "brew autoremove ($orphans orphaned dependencies)" brew_autoremove 0 "-"
  return 0
}

brew_cleanup()    { brew cleanup --prune=all -s; }
brew_autoremove() { brew autoremove; }

# @standalone-begin
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
  mc_main --only brew "$@"
fi
# @standalone-end
