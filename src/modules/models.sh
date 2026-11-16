#!/bin/bash
# Module: models — local LLM models under ~/.omlx.

models_meta() { MOD_TITLE="Local LLM models (~/.omlx)"; }

models_scan() {
  local O="$H/.omlx" c cc m ts la
  [ -d "$O/models" ] || return 0
  safe_clear "$O/cache" ".omlx cache"
  {
    for c in "$O/models"/*/; do
      [ -d "$c" ] || continue; c="${c%/}"
      case "${c##*/}" in models--*) echo "$c"; continue ;; esac
      if ls "$c" 2>/dev/null | grep -qE '\.(safetensors|gguf|bin|npz)$|^config\.json$'; then echo "$c"
      else for cc in "$c"/*/; do [ -d "$cc" ] && echo "${cc%/}"; done; fi
    done
  } > "$MC_TMP/models_list"
  mc_group "Models (last used = newest weight-file access time)"
  while IFS= read -r m; do
    ts=$(find "$m" -type f \( -name '*.safetensors' -o -name '*.gguf' -o -name '*.bin' -o -name '*.npz' \) \
           -exec stat -f '%a' {} + 2>/dev/null | sort -n | tail -1)
    la="never"; [ -n "$ts" ] && la=$(date -r "$ts" '+%Y-%m-%d' 2>/dev/null)
    pick_path "$m" "$(fit "${m#"$O/models/"}" 52) last used $la"
  done < "$MC_TMP/models_list"
  return 0
}

# @standalone-begin
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
  mc_main --only models "$@"
fi
# @standalone-end
