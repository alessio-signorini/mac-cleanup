#!/bin/bash
# Module: projects — regenerable build artifacts in projects idle > DAYS.

projects_meta() { MOD_TITLE="Stale project artifacts"; }

projects_scan() {
  local a n p recent k
  local ART=( -name node_modules -o -name .venv -o -name venv -o -name .next -o -name .nuxt -o -name .turbo
              -o -name .svelte-kit -o -name .parcel-cache -o -name .gradle -o -name Pods -o -name DerivedData
              -o -name .terraform -o -name .serverless -o -name .pytest_cache -o -name .mypy_cache
              -o -name .ruff_cache -o -name target )
  {
    find "$H" -maxdepth 7 \( -path "$H/Library" -o -path "$H/.*" -o -path "$H/Movies" -o -path "$H/Music" \
      -o -path "$H/Pictures" -o -path "$H/Applications" -o -name .git \) -prune -o -type d \( "${ART[@]}" \) -prune -print 2>/dev/null
    [ -d "$H/Library/Projects" ] && find "$H/Library/Projects" -maxdepth 6 -name .git -prune -o -type d \( "${ART[@]}" \) -prune -print 2>/dev/null
  } > "$MC_TMP/projects_artifacts"
  mc_group "Artifacts in projects idle > ${DAYS}d, ≥ 10MB (all regenerable)"
  while IFS= read -r a; do
    n="${a##*/}"; p="${a%/*}"
    case "$n" in
      target) [ -f "$p/Cargo.toml" ] || [ -f "$p/pom.xml" ] || continue ;;
      Pods)   [ -f "$p/Podfile" ] || continue ;;
      venv)   [ -f "$a/pyvenv.cfg" ] || continue ;;
    esac
    recent=$(find "$p" -maxdepth 3 \( -name node_modules -o -name .git -o -name "$n" \) -prune -o -type f -mtime -"$DAYS" -print 2>/dev/null | head -1)
    [ -n "$recent" ] && continue
    k=$(kb "$a"); [ "$k" -lt 10240 ] && continue
    pick_path "$a" "$(pretty "$a")" "$k"
  done < "$MC_TMP/projects_artifacts"
  return 0
}

# @standalone-begin
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
  mc_main --only projects "$@"
fi
# @standalone-end
