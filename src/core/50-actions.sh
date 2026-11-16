#!/bin/bash
# Guarded deleters. Every deletion in the tool goes through these.

# guard_path P: 0 if P is safe to delete, 1 otherwise.
guard_path() {
  local p="$1" q
  [ -n "$p" ] || return 1
  case "$p" in /*) ;; *) return 1 ;; esac
  case "$p" in */../*|*/..|*/./*|*/.) return 1 ;; esac
  q="$p"
  while [ "${#q}" -gt 1 ] && [ "${q%/}" != "$q" ]; do q="${q%/}"; done
  case "$q" in
    /|"$H"|"$H/Library"|"$AS"|"$H/Library/Caches"|"$H/Library/Containers"|"$H/Library/Group Containers"|\
    "$H/Documents"|"$H/Desktop"|"$H/Downloads"|/Applications|/Library|/System|/Users|/private|"/private/var")
      return 1 ;;
  esac
  return 0
}

del_path() {
  guard_path "$1" || { mc_log "REFUSED unsafe path: $1"; return 1; }
  [ -e "$1" ] || [ -L "$1" ] || return 0
  rm -rf "$1" 2>/dev/null
  [ ! -e "$1" ]
}

del_contents() {
  local d="$1" c
  [ -d "$d" ] || return 0
  case "$d" in /*) ;; *) return 1 ;; esac
  [ "$d" = "/" ] && return 1
  for c in "$d"/* "$d"/.[!.]* "$d"/..?*; do
    [ -e "$c" ] || [ -L "$c" ] || continue
    del_path "$c"
  done
  return 0
}

del_listed() {
  local p
  [ -f "$1" ] || return 1
  while IFS= read -r p; do [ -n "$p" ] && del_path "$p"; done < "$1"
  return 0
}

del_listed_contents() {
  local p
  [ -f "$1" ] || return 1
  while IFS= read -r p; do [ -n "$p" ] && del_contents "$p"; done < "$1"
  return 0
}

del_older_than_days() {
  guard_path "$1" || return 1
  [ -d "$1" ] || return 0
  find "$1" -type f -mtime +"$DAYS" -delete 2>/dev/null
  find "$1" -mindepth 1 -type d -empty -delete 2>/dev/null
  return 0
}
