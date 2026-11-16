#!/bin/bash
# Module: runtimes — old rbenv/pyenv/nvm versions and rust toolchains.

runtimes_meta() { MOD_TITLE="Language runtime versions"; }

# runtimes_vm LABEL DIR CURRENT — every version dir except the current one.
# Keeps n == cur, or n starting with "cur." (nvm alias "v20" keeps v20.x.y).
runtimes_vm() {
  local label="$1" dir="$2" cur="$3" v n
  [ -d "$dir" ] && [ -n "$cur" ] || return 0
  mc_group "$label versions (keeping $cur; projects pinned to removed versions need a reinstall)"
  for v in "$dir"/*/; do
    [ -d "$v" ] || continue; v="${v%/}"; n="${v##*/}"
    [ "$n" = "$cur" ] && continue
    case "$n" in "$cur".*) continue ;; esac
    pick_path "$v" "$label $n"
  done
}

runtimes_scan() {
  local def cur t
  command -v rbenv >/dev/null 2>&1 && runtimes_vm ruby "$H/.rbenv/versions" "$(rbenv global 2>/dev/null)"
  command -v pyenv >/dev/null 2>&1 && runtimes_vm python "$H/.pyenv/versions" "$(pyenv global 2>/dev/null | head -1)"
  if [ -d "$H/.nvm/versions/node" ]; then
    def=$(cat "$H/.nvm/alias/default" 2>/dev/null)
    case "$def" in [0-9]*) cur="v$def" ;; v[0-9]*) cur="$def" ;; *) cur=$(node -v 2>/dev/null) ;; esac
    runtimes_vm node "$H/.nvm/versions/node" "$cur"
  fi
  if command -v rustup >/dev/null 2>&1; then
    mc_group "Rust toolchains (non-default)"
    while IFS= read -r t; do
      case "$t" in *"(default)"*|*"(active"*|"") continue ;; esac
      t="${t%% *}"
      pick_item "$t" "rust toolchain $t" "$(kb "$H/.rustup/toolchains/$t")" runtimes_del_rust "" "$H/.rustup/toolchains/$t"
    done < <(rustup toolchain list 2>/dev/null)
  fi
  return 0
}

runtimes_del_rust() { rustup toolchain uninstall "$1"; }

# @standalone-begin
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
  mc_main --only runtimes "$@"
fi
# @standalone-end
