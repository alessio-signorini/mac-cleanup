#!/bin/bash
# shellcheck disable=SC2034
# The plan: items (deletable candidates) and notes, filled by module scans.
# See docs/BUILD.md §5 for the contract.

IT_MOD=(); IT_TIER=(); IT_ID=(); IT_LABEL=(); IT_KB=(); IT_SZ=(); IT_ACT=()
IT_MEAS=(); IT_GRP=(); IT_GSEQ=(); IT_SEL=(); IT_RES=()
NT_MOD=(); NT_KIND=(); NT_TEXT=()

MOD_CUR=""      # module currently scanning
GRP_CUR=""      # current group heading
GRP_SEQ=0       # current group sequence number
LIST_SEQ=0

mc_group() { GRP_CUR="$1"; GRP_SEQ=$((GRP_SEQ + 1)); }

# mc_item TIER ID LABEL KB ACTION [SZ] [MEAS]
mc_item() {
  local kbv="${4:-0}"
  case "$kbv" in ''|*[!0-9]*) kbv=0 ;; esac
  IT_MOD+=("$MOD_CUR"); IT_TIER+=("$1"); IT_ID+=("$2"); IT_LABEL+=("$3"); IT_KB+=("$kbv")
  IT_ACT+=("${5:-del_path}"); IT_SZ+=("${6:-}"); IT_MEAS+=("${7:-}")
  IT_GRP+=("$GRP_CUR"); IT_GSEQ+=("$GRP_SEQ"); IT_RES+=("")
  if [ "$1" = safe ]; then IT_SEL+=(1); else IT_SEL+=(0); fi
}

safe_clear() {   # delete contents of a dir
  local p="$1" k
  [ -d "$p" ] || return 0
  k=$(kb "$p"); [ "$k" -lt "${3:-1024}" ] && return 0
  mc_item safe "$p" "$2" "$k" del_contents "" "$p"
}

safe_remove() {  # remove a path entirely
  [ -e "$1" ] || return 0
  mc_item safe "$1" "$2" "$(kb "$1")" del_path "" "$1"
}

# Aggregated item: every child of DIR except those whose app is running.
safe_clear_children() {
  local dir="$1" label="$2" c n k tot=0 kept="" list
  [ -d "$dir" ] || return 0
  mc_listfile; list="$LIST_FILE"
  for c in "$dir"/* "$dir"/.[!.]*; do
    [ -e "$c" ] || continue
    n="${c##*/}"
    if app_running "$n"; then kept="$kept $n"; continue; fi
    k=$(kb "$c"); tot=$((tot + k)); printf '%s\n' "$c" >> "$list"
  done
  [ "$tot" -ge 1024 ] && mc_item safe "$list" "$label" "$tot" del_listed "" "@$list"
  [ -n "$kept" ] && note_kept "$kept"
  return 0
}

safe_cmd() { mc_item safe "$1" "$2" "${4:-0}" "$3" "${5:-}" "${6:-}"; }

pick_path() {
  local k="${3:-}"
  [ -e "$1" ] || return 0
  [ -z "$k" ] && k=$(kb "$1")
  mc_item pick "$1" "$2" "$k" "${4:-del_path}" "" "$1"
}

pick_item() { mc_item pick "$1" "$2" "$3" "$4" "${5:-}" "${6:-}"; }

note() { NT_MOD+=("$MOD_CUR"); NT_KIND+=("$1"); NT_TEXT+=("$2"); }

# note_kept "a b c …" — one short skip note for things kept because their app is running.
note_kept() {
  local list="$1" n shown
  [ -n "${list// /}" ] || return 0
  n=$(printf '%s\n' $list | wc -l | tr -d ' ')
  shown=$(printf '%s\n' $list | head -6 | tr '\n' ' ')
  [ "$n" -gt 6 ] && shown="${shown}… +$((n - 6)) more"
  note skip "kept $n (app running): ${shown% }"
}

report_top() {
  local dir="$1" n="${2:-8}" k p
  [ -d "$dir" ] || return 0
  while read -r k p; do
    note report "$(printf '%8s  %s' "$(hkb "$k")" "$(pretty "$p")")"
  done < <(du -skx "$dir"/* "$dir"/.[!.]* 2>/dev/null | sort -rn | head -"$n")
}

# Sets LIST_FILE to a new, empty list file. Never call it as $(mc_listfile): the counter
# would only advance in the subshell and every item would share (and overwrite) one file.
mc_listfile() {
  LIST_SEQ=$((LIST_SEQ + 1))
  LIST_FILE="$MC_TMP/list.$LIST_SEQ"
  : > "$LIST_FILE"
}

# ---- queries used by the runner

# Fills ORD with the item indexes of module $1 in display order:
# groups in order of appearance, items by size (desc) within a group.
ORD=()
mod_items() {
  local m="$1" i n=${#IT_MOD[@]} _g _k
  ORD=()
  while read -r _g _k i; do
    [ -n "$i" ] && ORD+=("$i")
  done < <(for ((i=0; i<n; i++)); do
             [ "${IT_MOD[$i]}" = "$m" ] && printf '%s %s %s\n' "${IT_GSEQ[$i]}" "${IT_KB[$i]}" "$i"
           done | sort -k1,1n -k2,2rn -k3,3n)
}

# Sets MS_SAFE MS_PICK (KB) and MS_N (item count) for module $1
mod_sums() {
  local m="$1" i n=${#IT_MOD[@]}
  MS_SAFE=0; MS_PICK=0; MS_N=0
  for ((i=0; i<n; i++)); do
    [ "${IT_MOD[$i]}" = "$m" ] || continue
    MS_N=$((MS_N + 1))
    if [ "${IT_TIER[$i]}" = safe ]; then MS_SAFE=$((MS_SAFE + IT_KB[i])); else MS_PICK=$((MS_PICK + IT_KB[i])); fi
  done
}

mod_has_notes() {
  local i n=${#NT_MOD[@]}
  for ((i=0; i<n; i++)); do [ "${NT_MOD[$i]}" = "$1" ] && return 0; done
  return 1
}

mod_has_kind() {   # mod_has_kind MODULE KIND
  local i n=${#NT_MOD[@]}
  for ((i=0; i<n; i++)); do [ "${NT_MOD[$i]}" = "$1" ] && [ "${NT_KIND[$i]}" = "$2" ] && return 0; done
  return 1
}

item_size() {   # display size of item $1
  if [ -n "${IT_SZ[$1]}" ]; then printf '%s' "${IT_SZ[$1]}"
  elif [ "${IT_KB[$1]}" -gt 0 ]; then hkb "${IT_KB[$1]}"
  else printf -- "-"; fi
}

# Writes "KB<TAB>path" for every item still on disk (not applied successfully) to file $1:
# space the modules already listed and the user kept. List items (@file) use their first path.
plan_covered() {
  local i n=${#IT_MOD[@]} p
  : > "$1"
  for ((i=0; i<n; i++)); do
    [ "${IT_RES[$i]}" = ok ] && continue
    [ "${IT_KB[$i]}" -gt 0 ] || continue
    p="${IT_MEAS[$i]}"; [ -n "$p" ] || p="${IT_ID[$i]}"
    case "$p" in @*) [ -f "${p#@}" ] || continue; p=$(head -1 "${p#@}") ;; esac
    case "$p" in /*) printf '%s\t%s\n' "${IT_KB[$i]}" "${p%/}" >> "$1" ;; esac
  done
  return 0
}
