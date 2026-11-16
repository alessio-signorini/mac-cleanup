#!/bin/bash
#
# mac-disk-cleanup.sh — reusable macOS disk reclaim tool
#
# Default run is READ-ONLY: it reports sizes and what WOULD be freed.
# Nothing is deleted unless you pass --apply. User data (LLM models, iOS
# backups) is NEVER deleted automatically — you confirm each one.
#
# Usage:
#   ./mac-disk-cleanup.sh                 # audit / dry-run (no changes)
#   ./mac-disk-cleanup.sh --apply         # clean safe caches; prompt for models/backups
#   ./mac-disk-cleanup.sh --apply --yes   # clean safe caches, no prompts (skips models/backups)
#   ./mac-disk-cleanup.sh --apply --reclaim-docker-vm   # also rebuild colima to shrink 23G VM
#   ./mac-disk-cleanup.sh --help
#
# Safe categories (cleared on --apply): user+app caches, Xcode DerivedData,
#   unavailable simulators, npm cache, Homebrew old versions, docker prune,
#   .omlx/cache, logs, Trash.
# Interactive categories (always ask): .omlx LLM models, iOS device backups.
#
set -uo pipefail

# ---------- config ----------
HOME_DIR="${HOME}"
APPLY=false
ASSUME_YES=false
RECLAIM_DOCKER_VM=false

# ---------- args ----------
for arg in "$@"; do
  case "$arg" in
    --apply)              APPLY=true ;;
    --yes|-y)             ASSUME_YES=true ;;
    --reclaim-docker-vm)  RECLAIM_DOCKER_VM=true ;;
    --help|-h)
      sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown option: $arg (use --help)"; exit 1 ;;
  esac
done

# ---------- ui helpers ----------
BOLD=$'\033[1m'; DIM=$'\033[2m'; GRN=$'\033[32m'; YLW=$'\033[33m'; RED=$'\033[31m'; CYN=$'\033[36m'; RST=$'\033[0m'
hdr()  { printf "\n%s== %s ==%s\n" "$BOLD$CYN" "$1" "$RST"; }
info() { printf "  %s\n" "$1"; }
act()  { printf "  %s➜ %s%s\n" "$GRN" "$1" "$RST"; }
skip() { printf "  %s· %s%s\n" "$DIM" "$1" "$RST"; }
warn() { printf "  %s! %s%s\n" "$YLW" "$1" "$RST"; }

FREED_KB=0
add_freed() { FREED_KB=$(( FREED_KB + ${1:-0} )); }

# size of a path in KB (0 if missing)
kb()   { [ -e "$1" ] && du -sx -k "$1" 2>/dev/null | awk '{print $1}' || echo 0; }
# human-readable size of a path
hsz()  { [ -e "$1" ] && du -shx "$1" 2>/dev/null | awk '{print $1}' || echo "-"; }
# human-readable from KB
hkb()  { awk -v k="$1" 'BEGIN{s=k*1024; u="B"; if(s>=1024){s/=1024;u="KB"} if(s>=1024){s/=1024;u="MB"} if(s>=1024){s/=1024;u="GB"} printf "%.1f%s", s, u}'; }

confirm() { # confirm "question" ; returns 0=yes
  $ASSUME_YES && return 0
  local reply
  printf "  %s? %s [y/N] %s" "$YLW" "$1" "$RST"
  read -r reply < /dev/tty 2>/dev/null || read -r reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# Clear the CONTENTS of a directory (keeps the dir). Dry-run aware.
purge_contents() {
  local path="$1" label="$2"
  [ -d "$path" ] || { skip "$label — not present"; return; }
  local ksz; ksz=$(kb "$path")
  [ "$ksz" -eq 0 ] && { skip "$label — empty"; return; }
  if $APPLY; then
    rm -rf "${path:?}/"* "${path:?}/".[!.]* 2>/dev/null
    act "cleared $label ($(hkb "$ksz"))"
    add_freed "$ksz"
  else
    info "[dry-run] would clear $label ($(hkb "$ksz"))"
    add_freed "$ksz"
  fi
}

run() { # run "human label" cmd...   (dry-run aware)
  local label="$1"; shift
  if $APPLY; then
    act "$label"
    "$@"
  else
    info "[dry-run] would: $label"
  fi
}

# ============================================================
hdr "DISK STATUS"
df -h /System/Volumes/Data | awk 'NR==1||/Data/{print "  "$0}'

# ---------- 1. Safe caches ----------
hdr "SAFE CACHES (regenerate automatically)"
purge_contents "$HOME_DIR/Library/Caches"                         "user Library caches"
purge_contents "$HOME_DIR/Library/Developer/Xcode/DerivedData"    "Xcode DerivedData"
purge_contents "$HOME_DIR/Library/Logs"                           "user logs"
purge_contents "$HOME_DIR/.omlx/cache"                            ".omlx cache"

# npm
if command -v npm >/dev/null 2>&1; then
  nsz=$(kb "$HOME_DIR/.npm"); [ "$nsz" -gt 0 ] && add_freed "$nsz"
  run "npm cache clean --force ($(hkb "${nsz:-0}"))" npm cache clean --force >/dev/null 2>&1
else skip "npm not found"; fi

# ---------- 2. Xcode simulators ----------
hdr "XCODE SIMULATORS"
info "CoreSimulator total: $(hsz "$HOME_DIR/Library/Developer/CoreSimulator")"
if command -v xcrun >/dev/null 2>&1; then
  run "delete unavailable simulators" xcrun simctl delete unavailable
else skip "xcrun not found"; fi

# ---------- 3. Homebrew ----------
hdr "HOMEBREW"
if command -v brew >/dev/null 2>&1; then
  info "old-version/cache reclaimable:"
  brew cleanup -n 2>/dev/null | tail -n 3 | sed 's/^/    /'
  run "brew cleanup -s" brew cleanup -s >/dev/null 2>&1
else skip "brew not found"; fi

# ---------- 4. Docker / colima ----------
hdr "DOCKER / COLIMA"
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  docker system df 2>/dev/null | sed 's/^/  /'
  run "docker system prune -af (images + stopped containers; keeps volumes)" \
      docker system prune -af
  if $RECLAIM_DOCKER_VM; then
    warn "Rebuilding colima VM to shrink the ~23G host disk image."
    warn "This stops all containers. Named volumes are preserved; anonymous data in the VM is lost."
    if confirm "Proceed with colima stop/delete/start?"; then
      run "colima rebuild" bash -c 'colima stop && colima delete -f && colima start'
    else skip "colima rebuild skipped"; fi
  else
    info "VM host image: $(hsz "$HOME_DIR/.colima/_lima")  — pass --reclaim-docker-vm to shrink it"
  fi
else
  skip "docker not running (start colima first if you want this cleaned)"
fi

# ---------- 5. Trash ----------
hdr "TRASH"
purge_contents "$HOME_DIR/.Trash" "Trash"

# ---------- 6. LLM models (interactive) ----------
hdr ".omlx LLM MODELS (confirm each)"
MODELS_DIR="$HOME_DIR/.omlx/models"
if [ -d "$MODELS_DIR" ]; then
  info "$(printf '%-40s %8s  %s' 'MODEL' 'SIZE' 'LAST ACCESS')"
  for m in "$MODELS_DIR"/*; do
    [ -e "$m" ] || continue
    name=$(basename "$m")
    msz=$(hsz "$m")
    mkbv=$(kb "$m")
    atime=$(stat -f "%Sa" -t "%Y-%m-%d" "$m" 2>/dev/null)
    printf '  %-40s %8s  %s\n' "$name" "$msz" "$atime"
    if $APPLY && ! $ASSUME_YES; then
      if confirm "delete model '$name' ($msz)?"; then
        rm -rf "${m:?}"; act "deleted $name"; add_freed "$mkbv"
      else skip "kept $name"; fi
    fi
  done
  $APPLY || info "[dry-run] re-run with --apply to be prompted per model"
  $ASSUME_YES && warn "--yes set: models skipped (never auto-deleted)"
else skip ".omlx/models not present"; fi

# ---------- 7. iOS backups (interactive) ----------
hdr "iOS DEVICE BACKUPS (confirm each)"
BK_DIR="$HOME_DIR/Library/Application Support/MobileSync/Backup"
PB=/usr/libexec/PlistBuddy
if [ -d "$BK_DIR" ]; then
  for b in "$BK_DIR"/*/; do
    [ -d "$b" ] || continue
    bsz=$(hsz "$b")
    bkbv=$(kb "$b")
    dev="?"; last="?"
    if [ -f "$b/Info.plist" ] && [ -x "$PB" ]; then
      dev=$($PB -c "Print :\"Device Name\"" "$b/Info.plist" 2>/dev/null || echo "?")
      last=$($PB -c "Print :\"Last Backup Date\"" "$b/Info.plist" 2>/dev/null || echo "?")
    fi
    printf '  %s%s%s  size=%s  last=%s\n' "$BOLD" "$dev" "$RST" "$bsz" "$last"
    printf '    %s%s%s\n' "$DIM" "$(basename "$b")" "$RST"
    if $APPLY && ! $ASSUME_YES; then
      if confirm "delete this backup ($dev, $bsz)?"; then
        rm -rf "${b:?}"; act "deleted backup $dev"; add_freed "$bkbv"
      else skip "kept $dev"; fi
    fi
  done
  $APPLY || info "[dry-run] re-run with --apply to be prompted per backup"
  $ASSUME_YES && warn "--yes set: backups skipped (never auto-deleted)"
else skip "no iOS backups present"; fi

# ---------- 8. Local snapshots (report only) ----------
hdr "APFS LOCAL SNAPSHOTS (informational)"
snaps=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c "com.apple")
info "$snaps local snapshot(s). macOS purges these automatically under space pressure."
info "To force-thin now: sudo tmutil thinlocalsnapshots / 999999999999 4"

# ---------- summary ----------
hdr "SUMMARY"
if $APPLY; then
  printf "  %sReclaimed ≈ %s%s\n" "$GRN$BOLD" "$(hkb "$FREED_KB")" "$RST"
else
  printf "  %sReclaimable ≈ %s%s  (dry-run — nothing deleted)\n" "$YLW$BOLD" "$(hkb "$FREED_KB")" "$RST"
  printf "  Re-run with %s--apply%s to act.\n" "$BOLD" "$RST"
fi
df -h /System/Volumes/Data | awk '/Data/{printf "  Free now: %s (%s used)\n", $4, $5}'
