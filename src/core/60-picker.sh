#!/bin/bash
# shellcheck disable=SC2034
# Checkbox picker: full-screen TUI (alternate screen) and a numbered text fallback.
#
# Caller fills the PK_* arrays with pk_reset/pk_header/pk_row/pk_note, sets PK_TITLE,
# PK_SUB, PK_CONFIRM, then calls `picker`. Returns 0 = confirmed (PK_SEL updated),
# 1 = skipped/quit.

PK_TYPE=(); PK_TEXT=(); PK_SIZE=(); PK_KB=(); PK_SEL=(); PK_TIER=(); PK_ST=()
PK_NKIND=(); PK_NTEXT=()
PK_TITLE=""; PK_SUB=""; PK_CONFIRM=false; PK_QUIT_LABEL="skip"
PK_CUR=0; PK_TOP=0; PK_ASK=""; PK_HELP=false
# Live apply inside the picker: PK_ST[row] = ""|run|ok|fail, footer lines replace selection/help.
PK_APPLYING=false; PK_FOOT1=""; PK_FOOT2=""
TUI_ON=false; TUI_STTY=""

pk_reset() {
  PK_TYPE=(); PK_TEXT=(); PK_SIZE=(); PK_KB=(); PK_SEL=(); PK_TIER=(); PK_ST=()
  PK_NKIND=(); PK_NTEXT=(); PK_TITLE=""; PK_SUB=""; PK_CONFIRM=false
  PK_QUIT_LABEL="skip"; PK_ASK=""; PK_HELP=false
  PK_APPLYING=false; PK_FOOT1=""; PK_FOOT2=""
}
pk_header() { PK_TYPE+=(h); PK_TEXT+=("$1"); PK_SIZE+=(""); PK_KB+=(0); PK_SEL+=(0); PK_TIER+=(""); PK_ST+=(""); }
pk_row()    { PK_TYPE+=(i); PK_TEXT+=("$1"); PK_SIZE+=("$2"); PK_KB+=("${3:-0}"); PK_SEL+=("${4:-0}"); PK_TIER+=("${5:-}"); PK_ST+=(""); }
pk_note()   { PK_NKIND+=("$1"); PK_NTEXT+=("$2"); }

picker() { if $TUI; then pk_tui; else pk_text; fi; }

# Sets PK_SELN PK_SELKB PK_PICKN PK_PICKKB for the current selection.
pk_sel_summary() {
  local i n=${#PK_TYPE[@]}
  PK_SELN=0; PK_SELKB=0; PK_PICKN=0; PK_PICKKB=0
  for ((i=0; i<n; i++)); do
    [ "${PK_TYPE[$i]}" = i ] && [ "${PK_SEL[$i]}" = 1 ] || continue
    PK_SELN=$((PK_SELN + 1)); PK_SELKB=$((PK_SELKB + PK_KB[i]))
    if [ "${PK_TIER[$i]}" = pick ]; then PK_PICKN=$((PK_PICKN + 1)); PK_PICKKB=$((PK_PICKKB + PK_KB[i])); fi
  done
}

pk_set_all() {
  local i n=${#PK_TYPE[@]}
  for ((i=0; i<n; i++)); do [ "${PK_TYPE[$i]}" = i ] && PK_SEL[i]=$1; done
}

# "1 3 5-7" | "a" -> unique indexes 1..n, one per line
expand_sel() {
  local s n="$2" t
  s=$(printf '%s' "$1" | tr ',' ' ')
  case "$s" in a|A|all|ALL) seq 1 "$n"; return ;; esac
  for t in $s; do
    if [[ "$t" =~ ^([0-9]+)-([0-9]+)$ ]]; then seq "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    elif [[ "$t" =~ ^[0-9]+$ ]]; then echo "$t"; fi
  done | awk -v n="$n" '$1>=1 && $1<=n' | sort -un
}

pk_note_prefix() {
  case "$1" in
    warn) printf '%s! ' "$YLW" ;;
    skip) printf '%s· ' "$DIM" ;;
    tip)  printf '%s→ ' "$CYN" ;;
    report) printf '%s  ' "$DIM" ;;
    *) printf '  ' ;;
  esac
}

# ------------------------------------------------------------------ text fallback
pk_text() {
  local n=${#PK_TYPE[@]} i num=0 line idx r
  local map=()
  printf "\n%s== %s ==%s  %s%s%s\n" "$BOLD$CYN" "$PK_TITLE" "$RST" "$DIM" "$PK_SUB" "$RST"
  for ((i=0; i<${#PK_NTEXT[@]}; i++)); do
    printf '  %s%s%s\n' "$(pk_note_prefix "${PK_NKIND[$i]}")" "${PK_NTEXT[$i]}" "$RST"
  done
  for ((i=0; i<n; i++)); do
    if [ "${PK_TYPE[$i]}" = h ]; then printf '  %s%s%s\n' "$BOLD" "${PK_TEXT[$i]}" "$RST"; continue; fi
    num=$((num + 1)); map+=("$i")
    local box=" "; [ "${PK_SEL[$i]}" = 1 ] && box="x"
    printf '   [%s] %3d) %8s  %-4s  %s\n' "$box" "$num" "${PK_SIZE[$i]}" "${PK_TIER[$i]}" "${PK_TEXT[$i]}"
  done
  [ "$num" -gt 0 ] || return 0
  printf '  %s?%s Enter=apply [x] · numbers (1 3 5-7) = exactly those · a=all · n=none · q=%s: ' \
    "$YLW" "$RST" "$PK_QUIT_LABEL"
  IFS= read -r line || { line=""; echo; }
  $TUI || [ -t 0 ] || echo "$line"
  case "$(printf '%s' "$line" | tr -d '[:space:]')" in
    q|Q) return 1 ;;
    '') ;;
    a|A|all) pk_set_all 1 ;;
    n|N|none) pk_set_all 0 ;;
    *) pk_set_all 0
       for idx in $(expand_sel "$line" "$num"); do PK_SEL[${map[$((idx-1))]}]=1; done ;;
  esac
  if $PK_CONFIRM && [ -t 0 ]; then
    pk_sel_summary
    if [ "$PK_PICKN" -gt 0 ]; then
      printf '  %s?%s Delete %s picked item(s) (%s)? [y/N] ' "$YLW" "$RST" "$PK_PICKN" "$(hkb "$PK_PICKKB")"
      IFS= read -r r || r=""
      case "$r" in y|Y|yes|YES) ;; *)
        for ((i=0; i<n; i++)); do [ "${PK_TIER[$i]}" = pick ] && PK_SEL[i]=0; done
        echo "  picked items deselected" ;;
      esac
    fi
  fi
  return 0
}

# ------------------------------------------------------------------ TUI
tui_enter() {
  $TUI_ON && return 0
  TUI_STTY=$(stty -g < /dev/tty 2>/dev/null)
  stty -echo -icanon < /dev/tty 2>/dev/null
  { tput smcup; tput civis; } > /dev/tty 2>/dev/null
  TUI_ON=true
}

tui_leave() {
  $TUI_ON || return 0
  [ -n "$TUI_STTY" ] && stty "$TUI_STTY" < /dev/tty 2>/dev/null
  { tput cnorm; tput rmcup; } > /dev/tty 2>/dev/null
  TUI_ON=false
}

# Picker finished: leave the alternate screen unless the apply phase holds it.
pk_close() { $TUI_HOLD || tui_leave; }

# Reads one key from the terminal into KEY.
pk_key() {
  local k="" r="" x=""
  if ! IFS= read -rsn1 k < /dev/tty; then KEY=quit; return; fi
  case "$k" in
    $'\033')
      IFS= read -rsn2 -t 1 r < /dev/tty
      case "$r" in
        '[A'|OA) KEY=up ;;
        '[B'|OB) KEY=down ;;
        '[5') IFS= read -rsn1 -t 1 x < /dev/tty; KEY=pgup ;;
        '[6') IFS= read -rsn1 -t 1 x < /dev/tty; KEY=pgdn ;;
        '[H'|OH) KEY=home ;;
        '[F'|OF) KEY=end ;;
        '') KEY=quit ;;
        *) KEY=other ;;
      esac ;;
    '') KEY=enter ;;
    ' ') KEY=space ;;
    k|K) KEY=up ;;
    j|J) KEY=down ;;
    g) KEY=home ;;
    G) KEY=end ;;
    a|A) KEY=all ;;
    n|N) KEY=none ;;
    y|Y) KEY=yes ;;
    q|Q) KEY=quit ;;
    '?') KEY=help ;;
    *) KEY=other ;;
  esac
}

pk_move() {
  local d="$1" n=${#PK_TYPE[@]} t s
  t=$((PK_CUR + d))
  [ "$t" -lt 0 ] && t=0
  [ "$t" -ge "$n" ] && t=$((n - 1))
  s=1; [ "$d" -lt 0 ] && s=-1
  while [ "$t" -ge 0 ] && [ "$t" -lt "$n" ] && [ "${PK_TYPE[$t]}" != i ]; do t=$((t + s)); done
  if [ "$t" -lt 0 ] || [ "$t" -ge "$n" ]; then
    t=$PK_CUR
  fi
  PK_CUR=$t
}

pk_draw() {
  local rows cols n=${#PK_TYPE[@]} i used body lw line out="" nmax k shown end
  rows=$(term_lines); cols=$(term_cols)
  lw=$((cols - 26)); [ "$lw" -lt 10 ] && lw=10
  out=$'\033[H'
  printf -v line ' %s%s%s  %s%s%s' "$BOLD$CYN" "${PK_TITLE:0:$((cols-4))}" "$RST" "$DIM" "$PK_SUB" "$RST"
  out+="$line"$'\033[K\n\033[K\n'
  used=2
  if $PK_HELP; then
    for line in "↑/↓ k/j  move" "PgUp/PgDn g/G  page / first / last" "space  toggle (and move down)" \
                "a / n  select all / none" "enter  confirm (picked items ask y/N)" "q / Esc  $PK_QUIT_LABEL" "?  hide help"; do
      out+="   $line"$'\033[K\n'; used=$((used + 1))
    done
    out+=$'\033[K\n'; used=$((used + 1))
  elif [ ${#PK_NTEXT[@]} -gt 0 ]; then
    nmax=$((rows / 4)); [ "$nmax" -lt 3 ] && nmax=3
    shown=0
    for ((k=0; k<${#PK_NTEXT[@]}; k++)); do
      if [ "$shown" -ge "$nmax" ]; then
        out+="   ${DIM}… $(( ${#PK_NTEXT[@]} - shown )) more note(s)${RST}"$'\033[K\n'; used=$((used + 1)); break
      fi
      out+=" $(pk_note_prefix "${PK_NKIND[$k]}")${PK_NTEXT[$k]:0:$((cols-5))}$RST"$'\033[K\n'
      used=$((used + 1)); shown=$((shown + 1))
    done
    out+=$'\033[K\n'; used=$((used + 1))
  fi
  body=$((rows - used - 3)); [ "$body" -lt 3 ] && body=3
  PK_BODY=$body
  # keep cursor (and the heading just above it) visible
  if [ "$PK_CUR" -lt "$PK_TOP" ]; then PK_TOP=$PK_CUR; fi
  if [ "$PK_CUR" -gt 0 ] && [ "$PK_TOP" -eq "$PK_CUR" ] && [ "${PK_TYPE[$((PK_CUR-1))]}" = h ]; then PK_TOP=$((PK_CUR - 1)); fi
  if [ "$PK_CUR" -ge $((PK_TOP + body)) ]; then PK_TOP=$((PK_CUR - body + 1)); fi
  end=$((PK_TOP + body)); [ "$end" -gt "$n" ] && end=$n
  for ((i=PK_TOP; i<PK_TOP+body; i++)); do
    if [ "$i" -ge "$n" ]; then out+=$'\033[K\n'; continue; fi
    if [ "${PK_TYPE[$i]}" = h ]; then
      out+="  $BOLD${PK_TEXT[$i]:0:$((cols-3))}$RST"$'\033[K\n'
      continue
    fi
    local box=" " tier="${PK_TIER[$i]}" tc=""
    [ "${PK_SEL[$i]}" = 1 ] && box="x"
    case "$tier" in safe) tc="$GRN" ;; pick) tc="$YLW" ;; esac
    case "${PK_ST[$i]}" in
      run)  printf -v line '%s›[%s] %8s  busy  %s%s' "$RED$BOLD" "$box" "${PK_SIZE[$i]}" "${PK_TEXT[$i]:0:$lw}" "$RST" ;;
      ok)   printf -v line '%s [-] %8s  gone  %s%s%s' "$RED$DIM" "${PK_SIZE[$i]}" "$STRIKE" "${PK_TEXT[$i]:0:$lw}" "$RST" ;;
      fail) printf -v line '%s [!] %8s  FAIL  %s%s' "$YLW$BOLD" "${PK_SIZE[$i]}" "${PK_TEXT[$i]:0:$lw}" "$RST" ;;
      *)
        printf -v line ' [%s] %8s  %s%-4s%s  %s' "$box" "${PK_SIZE[$i]}" "$tc" "$tier" "$RST" "${PK_TEXT[$i]:0:$lw}"
        if [ "$i" -eq "$PK_CUR" ] && ! $PK_APPLYING; then
          printf -v line '%s›[%s] %8s  %-4s  %s%s' "$REV" "$box" "${PK_SIZE[$i]}" "$tier" "${PK_TEXT[$i]:0:$lw}" "$RST"
        fi ;;
    esac
    out+="$line"$'\033[K\n'
  done
  local more=""
  [ "$end" -lt "$n" ] && more="  ↓ more"
  [ "$PK_TOP" -gt 0 ] && more="$more  ↑ more"
  if $PK_APPLYING; then
    out+=$'\033[K\n'" $PK_FOOT1$DIM$more$RST"$'\033[K\n'" $DIM${PK_FOOT2:0:$((cols-2))}$RST"$'\033[K'
    out+=$'\033[J'
    printf '%s' "$out" > /dev/tty
    return 0
  fi
  pk_sel_summary
  printf -v line ' %sselected: %d item(s), %s%s%s' "$BOLD" "$PK_SELN" "$(hkb "$PK_SELKB")" "$RST" "$DIM$more$RST"
  out+=$'\033[K\n'"$line"$'\033[K\n'
  if [ -n "$PK_ASK" ]; then
    out+=" $YLW$BOLD$PK_ASK$RST"$'\033[K'
  else
    out+=" ${DIM}↑↓ move · space toggle · a all · n none · enter confirm · q $PK_QUIT_LABEL · ? help$RST"$'\033[K'
  fi
  out+=$'\033[J'
  printf '%s' "$out" > /dev/tty
}

pk_tui() {
  local n=${#PK_TYPE[@]} i
  PK_CUR=0; PK_TOP=0; PK_BODY=10
  for ((i=0; i<n; i++)); do [ "${PK_TYPE[$i]}" = i ] && { PK_CUR=$i; break; }; done
  tui_enter
  while :; do
    pk_draw
    pk_key
    case "$KEY" in
      up)   pk_move -1 ;;
      down) pk_move 1 ;;
      pgup) pk_move $((-PK_BODY)) ;;
      pgdn) pk_move "$PK_BODY" ;;
      home) PK_CUR=0; pk_move 0; [ "${PK_TYPE[$PK_CUR]}" = i ] || pk_move 1 ;;
      end)  PK_CUR=$((n - 1)); [ "${PK_TYPE[$PK_CUR]}" = i ] || pk_move -1 ;;
      space)
        if [ "${PK_TYPE[$PK_CUR]}" = i ]; then
          if [ "${PK_SEL[$PK_CUR]}" = 1 ]; then PK_SEL[PK_CUR]=0; else PK_SEL[PK_CUR]=1; fi
        fi
        pk_move 1 ;;
      all)  pk_set_all 1 ;;
      none) pk_set_all 0 ;;
      help) if $PK_HELP; then PK_HELP=false; else PK_HELP=true; fi ;;
      enter)
        pk_sel_summary
        if $PK_CONFIRM && [ "$PK_PICKN" -gt 0 ]; then
          PK_ASK="Delete $PK_PICKN picked item(s) ($(hkb "$PK_PICKKB"))? y/N"
          pk_draw; pk_key; PK_ASK=""
          [ "$KEY" = yes ] || continue
        fi
        pk_close; return 0 ;;
      quit) pk_close; return 1 ;;
    esac
  done
}
