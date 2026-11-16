#!/bin/bash
# Module: dev — package manager / build tool caches.

dev_meta() { MOD_TITLE="Dev toolchain caches"; }

# dev_tool NAME CACHE_DIR ACTION — safe item that runs the tool's own clean command.
dev_tool() {
  local name="$1" p="$2" k
  [ -n "$p" ] && [ -d "$p" ] || return 0
  k=$(kb "$p"); [ "$k" -lt 1024 ] && return 0
  safe_cmd "$p" "$name cache  ($(pretty "$p"))" "$3" "$k" "" "$p"
}

dev_has() { command -v "$1" >/dev/null 2>&1; }

dev_scan() {
  local c k mc
  dev_has npm  && dev_tool npm  "$H/.npm/_cacache" dev_clean_npm
  dev_has pnpm && dev_tool pnpm "$(pnpm store path 2>/dev/null)" dev_clean_pnpm
  dev_has yarn && dev_tool yarn "$(yarn cache dir 2>/dev/null)" dev_clean_yarn
  dev_has pip3 && dev_tool pip  "$(pip3 cache dir 2>/dev/null)" dev_clean_pip
  dev_has uv   && dev_tool uv   "$(uv cache dir 2>/dev/null)" dev_clean_uv
  dev_has go   && dev_tool go   "$(go env GOCACHE 2>/dev/null)" dev_clean_go
  dev_has pod  && dev_tool CocoaPods "$H/Library/Caches/CocoaPods" dev_clean_pod
  safe_clear "$H/.bun/install/cache"    "bun cache"
  safe_clear "$H/.cargo/registry/cache" "cargo registry cache"
  safe_clear "$H/.cargo/registry/src"   "cargo registry sources"
  safe_clear "$H/.cargo/git/checkouts"  "cargo git checkouts"
  safe_clear "$H/.gradle/caches"        "Gradle caches"

  mc_group "~/.cache folders (huggingface models, puppeteer/playwright browsers…)"
  for c in "$H/.cache"/*/; do
    [ -d "$c" ] || continue; c="${c%/}"; k=$(kb "$c")
    [ "$k" -ge 10240 ] && pick_path "$c" "$(pretty "$c")" "$k"
  done
  if dev_has go; then
    mc=$(go env GOMODCACHE 2>/dev/null)
    if [ -n "$mc" ] && [ -d "$mc" ]; then
      mc_group "Go module cache (re-downloaded on next build)"
      pick_item "$mc" "Go module cache  ($(pretty "$mc"))" "$(kb "$mc")" dev_del_gomod "" "$mc"
    fi
  fi
  return 0
}

dev_clean_npm()  { npm cache clean --force; }
dev_clean_pnpm() { pnpm store prune; }
dev_clean_yarn() { yarn cache clean; }
dev_clean_pip()  { pip3 cache purge; }
dev_clean_uv()   { uv cache clean; }
dev_clean_go()   { go clean -cache; }
dev_clean_pod()  { pod cache clean --all; }
dev_del_gomod()  { go clean -modcache; }

# @standalone-begin
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
  mc_main --only dev "$@"
fi
# @standalone-end
