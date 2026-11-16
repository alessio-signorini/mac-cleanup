#!/bin/bash
# shellcheck disable=SC2034
# Terminal detection, colors and low-level print helpers.

IS_TTY=false
ERR_TTY=false
TUI=false
BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; CYN=""; RST=""; REV=""

ui_init() {
  [ -t 1 ] && IS_TTY=true
  [ -t 2 ] && ERR_TTY=true
  if $IS_TTY && [ -z "${NO_COLOR:-}" ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'
    YLW=$'\033[33m'; CYN=$'\033[36m'; RST=$'\033[0m'; REV=$'\033[7m'
  fi
  if $IS_TTY && [ -t 0 ] && ! $NO_TUI && [ "${TERM:-dumb}" != dumb ] && [ -r /dev/tty ]; then
    TUI=true
  fi
}

hdr()  { printf "\n%s== %s ==%s\n" "$BOLD$CYN" "$1" "$RST"; }
info() { printf "  %s\n" "$1"; }
okay() { printf "  %s✔ %s%s\n" "$GRN" "$1" "$RST"; }
skip() { printf "  %s· %s%s\n" "$DIM" "$1" "$RST"; }
warn() { printf "  %s! %s%s\n" "$YLW" "$1" "$RST"; }
die()  { printf "%s: %s\n" "$MC_NAME" "$1" >&2; exit "${2:-1}"; }

term_cols() {
  local c
  c=$(tput cols 2>/dev/null)
  case "$c" in ''|*[!0-9]*) c=80 ;; esac
  [ "$c" -lt 40 ] && c=40
  echo "$c"
}

term_lines() {
  local l
  l=$(tput lines 2>/dev/null)
  case "$l" in ''|*[!0-9]*) l=24 ;; esac
  [ "$l" -lt 10 ] && l=10
  echo "$l"
}

# Self-overwriting status line on stderr (TTY only).
progress() { $ERR_TTY && printf '\r\033[K%s%s%s' "$DIM" "$1" "$RST" >&2; return 0; }
progress_done() { $ERR_TTY && printf '\r\033[K' >&2; return 0; }

pretty() { case "$1" in "$H"/*) printf '~%s' "${1#"$H"}" ;; "$H") printf '~' ;; *) printf '%s' "$1" ;; esac; }
urldecode() { printf '%b' "${1//%/\\x}"; }

# Character-aware padding (bash printf pads by bytes, which breaks on UTF-8).
padr() { local s="$1" w="$2" n; n=${#s}; printf '%s%*s' "$s" $(( w > n ? w - n : 0 )) ''; }
padl() { local s="$1" w="$2" n; n=${#s}; printf '%*s%s' $(( w > n ? w - n : 0 )) '' "$s"; }
fit()  { padr "${1:0:$2}" "$2"; }   # truncate + pad to exactly N characters

mc_log() {
  $APPLY || return 0
  mkdir -p "$LOG_DIR" 2>/dev/null
  printf '%s  %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE" 2>/dev/null
  return 0
}
