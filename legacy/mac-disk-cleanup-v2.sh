#!/bin/bash
#
# mac-disk-cleanup.sh v2 — reusable macOS disk reclaim tool
#
# Default run is READ-ONLY (dry-run). Nothing is deleted without --apply.
# Tiers:
#   SAFE    regenerable caches/logs; cleared on --apply (also with --yes)
#   PICK    your data or slow-to-rebuild items; numbered list, you choose
#           which to delete (never touched with --yes)
#   REPORT  shown for visibility only
#
# Usage:
#   mac-disk-cleanup.sh                        dry-run, all modules
#   mac-disk-cleanup.sh --apply                clear SAFE tier, prompt on PICK lists
#   mac-disk-cleanup.sh --apply --yes          SAFE tier only, no prompts (cron/launchd)
#   mac-disk-cleanup.sh --only xcode,docker    run selected modules
#   mac-disk-cleanup.sh --skip projects,report skip modules
#   mac-disk-cleanup.sh --apply --system       add sudo system-level cleanup
#   mac-disk-cleanup.sh --apply --reclaim-docker-vm   rebuild colima VM
#
# Options:
#   --days N         idle threshold for projects/downloads/Claude history (default 30)
#   --media-days N   WhatsApp media age threshold (default 90)
#
# Modules:
#   caches orphans apps editors claude browsers whatsapp xcode docker dev
#   runtimes projects brew gimp downloads models backups report system(opt-in)
#
# Tips: quit apps first (VS Code, Chrome, Vivaldi, Claude, WhatsApp...) — caches
# of running apps are skipped. Give your terminal Full Disk Access so it can
# clean sandboxed app caches (Safari, Mail, WhatsApp).
# Deletion history: ~/.local/state/mac-disk-cleanup/history.log

set -o pipefail

H="$HOME"
AS="$H/Library/Application Support"
DAYS=30
MEDIA_DAYS=90
APPLY=false; ASSUME_YES=false; RECLAIM_DOCKER_VM=false; SYSTEM=false
ONLY=""; SKIP=""
LOG_DIR="$H/.local/state/mac-disk-cleanup"; LOG_FILE="$LOG_DIR/history.log"

usage() { awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1{exit}' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --apply)             APPLY=true ;;
    --yes|-y)            ASSUME_YES=true ;;
    --reclaim-docker-vm) RECLAIM_DOCKER_VM=true ;;
    --system)            SYSTEM=true ;;
    --days)              DAYS="${2:?--days needs a number}"; shift ;;
    --media-days)        MEDIA_DAYS="${2:?--media-days needs a number}"; shift ;;
    --only)              ONLY="${2:?--only needs a module list}"; shift ;;
    --skip)              SKIP="${2:?--skip needs a module list}"; shift ;;
    -h|--help)           usage; exit 0 ;;
    *) echo "Unknown option: $1 (see --help)"; exit 1 ;;
  esac
  shift
done

if [ "$(id -u)" -eq 0 ]; then
  echo "Run as your normal user (not sudo). Use --system for the sudo parts."; exit 1
fi

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/diskclean.XXXXXX") || { echo "mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
$APPLY && mkdir -p "$LOG_DIR"

# ---------------------------------------------------------------- ui
if [ -t 1 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; GRN=$'\033[32m'; YLW=$'\033[33m'; CYN=$'\033[36m'; RST=$'\033[0m'
else BOLD=""; DIM=""; GRN=""; YLW=""; CYN=""; RST=""; fi
hdr()  { printf "\n%s== %s ==%s\n" "$BOLD$CYN" "$1" "$RST"; }
info() { printf "  %s\n" "$1"; }
act()  { printf "  %s➜ %s%s\n" "$GRN" "$1" "$RST"; }
skip() { printf "  %s· %s%s\n" "$DIM" "$1" "$RST"; }
warn() { printf "  %s! %s%s\n" "$YLW" "$1" "$RST"; }
log()  { $APPLY && printf '%s  %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE"; return 0; }
pretty() { printf '%s' "$1" | sed "s|^$H|~|"; }
urldecode() { printf '%b' "${1//%/\\x}"; }

ask() {
  local r=""
  printf '  %s?%s %s ' "$YLW" "$RST" "$1" >/dev/tty 2>/dev/null || printf '  ? %s ' "$1" >&2
  read -r r </dev/tty 2>/dev/null || read -r r
  printf '%s' "$r"
}
confirm() { $ASSUME_YES && return 0; local r; r=$(ask "$1 [y/N]"); [[ "$r" =~ ^[Yy] ]]; }

# ---------------------------------------------------------------- sizes
kb()  { [ -e "$1" ] || { echo 0; return; }; du -skx "$1" 2>/dev/null | awk '{s=$1} END{print s+0}'; }
hsz() { hkb "$(kb "$1")"; }
hkb() { awk -v k="${1:-0}" 'BEGIN{ if(k<0)k=0; s=k; u="KB";
  if(s>=1024){s/=1024;u="MB"} if(s>=1024){s/=1024;u="GB"} printf (u=="KB"?"%d%s":"%.1f%s"), s, u }'; }
free_kb() { df -k "$H" 2>/dev/null | awk 'NR==2{print $4}'; }

SAFE_KB=0; OPT_KB=0; FREED_KB=0
START_FREE=$(free_kb)

# ---------------------------------------------------------------- module gate
want() {
  local m="$1"
  if [ -n "$SKIP" ] && [[ ",$SKIP," == *",$m,"* ]]; then return 1; fi
  if [ -n "$ONLY" ]; then [[ ",$ONLY," == *",$m,"* ]]; return $?; fi
  if [ "$m" = system ]; then $SYSTEM; return $?; fi
  return 0
}

# ---------------------------------------------------------------- running apps
# key (folder name under Application Support) | bundle id | process / .app name
APP_TABLE='Claude|com.anthropic.claudefordesktop|Claude
Code|com.microsoft.VSCode|Code
Code - Insiders|com.microsoft.VSCodeInsiders|Code - Insiders
Cursor|com.todesktop.230313mzl4w4u92|Cursor
Windsurf|com.exafunction.windsurf|Windsurf
VSCodium|com.vscodium|VSCodium
Google|com.google.Chrome|Google Chrome
Vivaldi|com.vivaldi.Vivaldi|Vivaldi
BraveSoftware|com.brave.Browser|Brave Browser
krisp|ai.krisp.krispMac|krisp
Slack|com.tinyspeck.slackmacgap|Slack
discord|com.hnc.Discord|Discord
com.openai.chat|com.openai.chat|ChatGPT
WhatsApp|net.whatsapp.WhatsApp|WhatsApp
Safari|com.apple.Safari|Safari'
# Three independent signals; any one counts as "running".
RUNNING_BUNDLES=$(lsappinfo list 2>/dev/null | sed -n 's/.*bundleID="\([^"]*\)".*/\1/p' | sort -u)
RUNNING_PROCS=$(ps -axo comm= 2>/dev/null | sed 's|.*/||' | sort -u)
RUNNING_PATHS=$(ps -axo comm= 2>/dev/null)
bundle_running() { [ -n "$1" ] && printf '%s\n' "$RUNNING_BUNDLES" | grep -qixF "$1"; }
apppath_running() { printf '%s\n' "$RUNNING_PATHS" | grep -qiF "/$1.app/Contents/MacOS/"; }
root_running() {   # is the app owning this folder/bundle running?
  local r="$1" row b p
  row=$(printf '%s\n' "$APP_TABLE" | awk -F'|' -v k="$r" 'tolower($1)==tolower(k) || tolower($2)==tolower(k) {print; exit}')
  if [ -n "$row" ]; then
    b=$(printf '%s' "$row" | cut -d'|' -f2); p=$(printf '%s' "$row" | cut -d'|' -f3)
    bundle_running "$b" && return 0
    printf '%s\n' "$RUNNING_PROCS" | grep -qxF "$p" && return 0
    apppath_running "$p" && return 0
    return 1
  fi
  bundle_running "$r" || apppath_running "$r"
}
group_running() {  # group.<TEAMID>.<bundle…> vs running bundle ids (prefix match)
  local g="${1#group.}" b
  [[ "$g" =~ ^[A-Z0-9]{10}\.(.+)$ ]] && g="${BASH_REMATCH[1]}"
  while IFS= read -r b; do
    [ -z "$b" ] && continue
    case "$g" in "$b"*) return 0 ;; esac
    case "$b" in "$g"*) return 0 ;; esac
  done <<< "$RUNNING_BUNDLES"
  return 1
}

# ---------------------------------------------------------------- SAFE tier primitives
wipe_contents() { find "${1:?}" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null; return 0; }

safe_clear() {   # clear contents of a dir
  local p="$1" label="$2" k
  [ -d "$p" ] || return 0
  k=$(kb "$p"); [ "$k" -lt 1024 ] && return 0
  SAFE_KB=$((SAFE_KB+k))
  if $APPLY; then wipe_contents "$p"; act "cleared $label ($(hkb "$k"))"; log "cleared $p ($(hkb "$k"))"; FREED_KB=$((FREED_KB+k))
  else info "$(printf '%8s  %s' "$(hkb "$k")" "$label")"; fi
}

safe_remove() {  # remove a path entirely
  local p="$1" label="$2" k
  [ -e "$p" ] || return 0
  k=$(kb "$p")
  SAFE_KB=$((SAFE_KB+k))
  if $APPLY; then rm -rf "${p:?}"; act "removed $label ($(hkb "$k"))"; log "removed $p"; FREED_KB=$((FREED_KB+k))
  else info "$(printf '%8s  %s' "$(hkb "$k")" "$label")"; fi
}

clear_children() {  # remove each child of a dir, except those belonging to running apps
  local dir="$1" label="$2" c n k tot=0 sk=""
  [ -d "$dir" ] || return 0
  : > "$TMP/cc"
  for c in "$dir"/* "$dir"/.[!.]*; do
    [ -e "$c" ] || continue
    n="${c##*/}"
    if root_running "$n"; then sk="$sk $n"; continue; fi
    k=$(kb "$c"); tot=$((tot+k)); printf '%s\n' "$c" >> "$TMP/cc"
  done
  if [ "$tot" -ge 1024 ]; then
    SAFE_KB=$((SAFE_KB+tot))
    if $APPLY; then
      while IFS= read -r c; do rm -rf "$c" 2>/dev/null; done < "$TMP/cc"
      act "cleared $label ($(hkb "$tot"))"; log "cleared $dir ($(hkb "$tot"))"; FREED_KB=$((FREED_KB+tot))
    else info "$(printf '%8s  %s' "$(hkb "$tot")" "$label")"; fi
  fi
  [ -n "$sk" ] && skip "kept (app running):$sk"
  return 0
}

run() {  # dry-run aware command
  local label="$1"; shift
  if $APPLY; then act "$label"; "$@" 2>&1 | tail -n 4 | sed 's/^/      /'; log "ran: $*"
  else info "[dry-run] would run: $label"; fi
}

# ---------------------------------------------------------------- PICK tier
PICK_LIST_ONLY=false
reset_items() { IT_PATH=(); IT_LABEL=(); IT_KB=(); IT_SZ=(); }
add_item() { IT_PATH+=("$1"); IT_LABEL+=("$2"); IT_KB+=("${3:-0}"); IT_SZ+=("${4:-}"); }
reset_items

expand_sel() {  # "1 3 5-7" | "a"  -> unique indexes 1..n
  local s n="$2" t
  s=$(printf '%s' "$1" | tr ',' ' ')
  case "$s" in a|A|all|ALL) seq 1 "$n"; return ;; esac
  for t in $s; do
    if [[ "$t" =~ ^([0-9]+)-([0-9]+)$ ]]; then seq "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    elif [[ "$t" =~ ^[0-9]+$ ]]; then echo "$t"; fi
  done | awk -v n="$n" '$1>=1 && $1<=n' | sort -un
}

choose_items() {  # choose_items "what" [deleter_fn]
  local what="$1" deleter="${2:-del_path}" n=${#IT_PATH[@]} i j total=0 sz sel idx
  if [ "$n" -eq 0 ]; then skip "nothing to review: $what"; return 0; fi
  local order=()
  while read -r _ i; do order+=("$i"); done < <(for ((i=0;i<n;i++)); do echo "${IT_KB[$i]} $i"; done | sort -rn)
  for ((j=0;j<n;j++)); do
    i=${order[$j]}
    sz="${IT_SZ[$i]}"; [ -z "$sz" ] && sz=$(hkb "${IT_KB[$i]}")
    printf '    %s%3d)%s %8s  %s\n' "$BOLD" $((j+1)) "$RST" "$sz" "${IT_LABEL[$i]}"
    total=$((total + IT_KB[i]))
  done
  [ "$total" -gt 0 ] && info "    total: $(hkb "$total")"
  if ! $APPLY; then OPT_KB=$((OPT_KB+total)); return 0; fi
  $PICK_LIST_ONLY && return 0
  if $ASSUME_YES; then skip "--yes: review list skipped (never auto-deleted)"; return 0; fi
  sel=$(ask "Delete which $what? (e.g. 1 3 5-7, a=all, Enter=none)")
  for idx in $(expand_sel "$sel" "$n"); do
    i=${order[$((idx-1))]}
    if "$deleter" "${IT_PATH[$i]}" >/dev/null 2>&1; then
      act "deleted: ${IT_LABEL[$i]}"; FREED_KB=$((FREED_KB + IT_KB[i])); log "deleted ($what): ${IT_PATH[$i]}"
    else warn "failed: ${IT_LABEL[$i]}"; fi
  done
}

# deleters
del_path()            { rm -rf "${1:?}"; }
del_older_than_days() { find "$1" -type f -mtime +"$DAYS" -delete 2>/dev/null; find "$1" -mindepth 1 -type d -empty -delete 2>/dev/null; return 0; }
del_wa_old() {
  if [ "$MEDIA_DAYS" -eq 0 ]; then find "$1" -type f -delete 2>/dev/null
  else find "$1" -type f -mtime +"$MEDIA_DAYS" -delete 2>/dev/null; fi
  return 0
}
# WhatsApp: media files on disk that no ZWAMEDIAITEM row references.
# Keeps any file whose path stem (dir + uuid, extension ignored) matches a
# referenced media, thumbnail or xmpp-thumb path. Skips files touched < 48h.
# Aborts if referenced paths don't line up with what's on disk.
wa_orphan_scan() {
  local msg="$WA/Message" db="$WA/ChatStorage.sqlite" nref nmatch norph
  : > "$TMP/wa_orphans"; : > "$TMP/wa_orphan_by_chat"
  [ -f "$db" ] && command -v sqlite3 >/dev/null 2>&1 || { skip "WhatsApp DB/sqlite3 not found — orphan sweep skipped"; return 0; }
  if ! sqlite3 -readonly "$db" "SELECT ZMEDIALOCALPATH FROM ZWAMEDIAITEM WHERE ZMEDIALOCALPATH<>''
        UNION SELECT ZTHUMBNAILLOCALPATH FROM ZWAMEDIAITEM WHERE ZTHUMBNAILLOCALPATH<>''
        UNION SELECT ZXMPPTHUMBPATH FROM ZWAMEDIAITEM WHERE ZXMPPTHUMBPATH<>'';" > "$TMP/wa_refs" 2>"$TMP/wa_err"; then
    warn "WhatsApp DB query failed ($(head -1 "$TMP/wa_err")) — orphan sweep skipped"; return 0
  fi
  sed -nE 's|^.*(Media/[^/]+@[^/]+/.*)$|\1|p' "$TMP/wa_refs" | sed -E 's/\.[^./]+$//' | sort -u > "$TMP/wa_ref_stems"
  ( cd "$msg" && find Media -mindepth 2 -type f \( -path 'Media/*@g.us/*' -o -path 'Media/*@s.whatsapp.net/*' \
      -o -path 'Media/*@lid/*' -o -path 'Media/*@newsletter/*' -o -path 'Media/*@broadcast/*' \) 2>/dev/null ) > "$TMP/wa_disk_all"
  ( cd "$msg" && find Media -mindepth 2 -type f -mtime +1 \( -path 'Media/*@g.us/*' -o -path 'Media/*@s.whatsapp.net/*' \
      -o -path 'Media/*@lid/*' -o -path 'Media/*@newsletter/*' -o -path 'Media/*@broadcast/*' \) 2>/dev/null ) > "$TMP/wa_disk"
  nref=$(wc -l < "$TMP/wa_ref_stems" | tr -d ' ')
  nmatch=$(awk 'NR==FNR{r[$0]=1;next}{s=$0;sub(/\.[^.\/]+$/,"",s); if(s in r) c++} END{print c+0}' "$TMP/wa_ref_stems" "$TMP/wa_disk_all")
  if [ "$nref" -gt 0 ] && [ "$nmatch" -eq 0 ]; then
    warn "Safety stop: $nref referenced media in DB but none match files on disk (path format changed?). Orphan sweep skipped."
    return 0
  fi
  awk 'NR==FNR{r[$0]=1;next}{s=$0;sub(/\.[^.\/]+$/,"",s); if(!(s in r)) print}' "$TMP/wa_ref_stems" "$TMP/wa_disk" > "$TMP/wa_orphans"
  norph=$(wc -l < "$TMP/wa_orphans" | tr -d ' ')
  info "DB references: $nref media  |  on disk: $(wc -l < "$TMP/wa_disk_all" | tr -d ' ') files ($nmatch referenced)  |  unreferenced: $norph"
  [ "$norph" -gt 0 ] || return 0
  ( cd "$msg" && tr '\n' '\0' < "$TMP/wa_orphans" | xargs -0 du -k 2>/dev/null ) |
    awk '{split($2,a,"/"); s[a[2]]+=$1; n[a[2]]++} END{for(j in s) if(s[j]>=1024) print s[j]"\t"n[j]"\t"j}' | sort -rn > "$TMP/wa_orphan_by_chat"
}
del_wa_orphans() {  # $1 = chat jid
  local msg="$WA/Message"
  grep -F "Media/$1/" "$TMP/wa_orphans" | while IFS= read -r f; do rm -f "$msg/$f"; done
  find "$msg/Media/$1" -mindepth 1 -type d -empty -delete 2>/dev/null
  return 0
}
del_runtime()         { xcrun simctl runtime delete "$1"; }
del_sim()             { xcrun simctl delete "$1"; }
del_container()       { docker rm -v "$1"; }
del_volume()          { docker volume rm "$1"; }
del_rust()            { rustup toolchain uninstall "$1"; }
del_gomod()           { go clean -modcache; }

report_top() {  # report_top dir [n]
  local dir="$1" n="${2:-8}" k p
  [ -d "$dir" ] || return 0
  du -skx "$dir"/* "$dir"/.[!.]* 2>/dev/null | sort -rn | head -"$n" | while read -r k p; do
    info "$(printf '  %8s  %s' "$(hkb "$k")" "$(pretty "$p")")"
  done
}

have_py() { [ -x /usr/bin/python3 ] && xcode-select -p >/dev/null 2>&1; }

# ================================================================ START
hdr "DISK"
df -h "$H" | awk 'NR==2{printf "  %s used of %s, %s free (%s)\n", $3, $2, $4, $5}'
$APPLY || info "${YLW}DRY-RUN${RST} — nothing will be deleted. Re-run with --apply."
running=""
while IFS='|' read -r key _ pname; do
  root_running "$key" && running="$running, $pname"
done <<< "$APP_TABLE"
[ -n "$running" ] && warn "running now (their caches will be skipped): ${running#, }"

# ---------------------------------------------------------------- caches
if want caches; then
  hdr "CACHES & LOGS  [safe]"
  clear_children "$H/Library/Caches" "~/Library/Caches"
  safe_clear "$H/Library/Logs" "~/Library/Logs"
  safe_clear "$H/Library/Containers/com.apple.mail/Data/Library/Mail Downloads" "Mail attachment downloads"
  safe_clear "$H/Library/iTunes/iPhone Software Updates" "iPhone firmware (.ipsw)"
  safe_clear "$H/Library/iTunes/iPad Software Updates" "iPad firmware (.ipsw)"
  safe_clear "$H/.Trash" "Trash"
  sk=""
  for c in "$H"/Library/Containers/*/Data/Library/Caches; do
    [ -d "$c" ] || continue
    b="${c#"$H/Library/Containers/"}"; b="${b%%/*}"
    if bundle_running "$b"; then sk="$sk $b"; continue; fi
    safe_clear "$c" "sandboxed app cache: $b"
  done
  for c in "$H"/Library/"Group Containers"/*/Library/Caches; do
    [ -d "$c" ] || continue
    g="${c#"$H/Library/Group Containers/"}"; g="${g%%/*}"
    if group_running "$g"; then sk="$sk $g"; continue; fi
    safe_clear "$c" "group container cache: $g"
  done
  [ -n "$sk" ] && skip "kept (app running):$sk"
  run "reset QuickLook thumbnail cache" qlmanage -r cache
fi

# ---------------------------------------------------------------- leftovers of uninstalled apps
if want orphans; then
  hdr "LEFTOVERS FROM UNINSTALLED APPS  [pick]"
  mdfind -attr kMDItemCFBundleIdentifier "kMDItemContentType == 'com.apple.application-bundle'" 2>/dev/null |
    sed -n 's/.*kMDItemCFBundleIdentifier = \(.*\)$/\1/p' | grep -v '(null)' | sort -u > "$TMP/installed"
  if [ "$(wc -l < "$TMP/installed" | tr -d ' ')" -lt 20 ]; then
    skip "Spotlight app index unavailable — skipping (needs Spotlight enabled on the system volume)"
  else
    vendor_installed() {  # any installed app from the same vendor (first two reverse-DNS parts)?
      local v; v=$(printf '%s' "$1" | awk -F. 'NF>=2{print $1"."$2}')
      [ -z "$v" ] && return 0                                        # unknown shape: treat as installed
      grep -qiF "$v." "$TMP/installed" || grep -qixF "$v" "$TMP/installed"
    }
    reset_items
    for c in "$H"/Library/Containers/*/; do
      c="${c%/}"; b="${c##*/}"
      case "$b" in com.apple.*|*" "*) continue ;; esac
      [[ "$b" == *.*.* ]] || continue
      bundle_running "$b" && continue
      vendor_installed "$b" && continue
      k=$(kb "$c"); [ "$k" -ge 1024 ] || continue
      add_item "$c" "container  $b" "$k"
    done
    for c in "$H"/Library/"Group Containers"/*/; do
      c="${c%/}"; g="${c##*/}"; g="${g#group.}"
      [[ "$g" =~ ^[A-Z0-9]{10}\.(.+)$ ]] && g="${BASH_REMATCH[1]}"
      case "$g" in com.apple.*|systemgroup.*) continue ;; esac
      [[ "$g" == *.*.* ]] || continue
      group_running "${c##*/}" && continue
      vendor_installed "$g" && continue
      k=$(kb "$c"); [ "$k" -ge 1024 ] || continue
      add_item "$c" "group      ${c##*/}" "$k"
    done
    info "No installed app from the same vendor was found for these (e.g. UTM VMs left behind):"
    choose_items "leftover app containers"
    info "If a delete fails with 'Operation not permitted', grant your terminal Full Disk Access or drag the folder to Trash in Finder."
  fi
fi

# ---------------------------------------------------------------- Electron / Chromium app caches
if want apps && [ -d "$AS" ]; then
  hdr "APP CACHES  [safe]  (VS Code, Claude, ChatGPT, Chrome, Vivaldi, Cursor, Slack…)"
  find "$AS" -maxdepth 5 \
    \( -path "$AS/MobileSync" -o -path "$AS/com.apple.*" -o -path "$AS/AddressBook" -o -path "$AS/CallHistoryDB" \
       -o -path "$AS/Knowledge" -o -path "$AS/CloudDocs" -o -path "$AS/FileProvider" \
       -o -path "$AS/Claude/local-agent-mode-sessions" -o -path "$AS/Claude/vm_bundles" \) -prune -o \
    -type d \( -name Cache -o -name "Code Cache" -o -name GPUCache -o -name DawnCache -o -name DawnGraphiteCache \
       -o -name DawnWebGPUCache -o -name GraphiteDawnCache -o -name ShaderCache -o -name GrShaderCache \
       -o -name CacheStorage -o -name ScriptCache -o -name CachedData -o -name CachedExtensionVSIXs \
       -o -name CachedProfilesData -o -name component_crx_cache \) -prune -print 2>/dev/null > "$TMP/appdirs"
  : > "$TMP/apps"; sk=""
  while IFS= read -r d; do
    rel="${d#"$AS/"}"; root="${rel%%/*}"
    if root_running "$root"; then case " $sk " in *" $root "*) ;; *) sk="$sk $root" ;; esac; continue; fi
    k=$(kb "$d"); [ "$k" -lt 1024 ] && continue
    printf '%s\t%s\t%s\n' "$root" "$k" "$d" >> "$TMP/apps"
  done < "$TMP/appdirs"
  if [ -s "$TMP/apps" ]; then
    awk -F'\t' '{s[$1]+=$2} END{for(r in s) print s[r]"\t"r}' "$TMP/apps" | sort -rn |
      while IFS=$'\t' read -r k r; do info "$(printf '%8s  %s' "$(hkb "$k")" "$r")"; done
    tk=$(awk -F'\t' '{s+=$2} END{print s+0}' "$TMP/apps"); SAFE_KB=$((SAFE_KB+tk))
    if $APPLY; then
      while IFS=$'\t' read -r r k d; do wipe_contents "$d"; done < "$TMP/apps"
      FREED_KB=$((FREED_KB+tk)); act "cleared app caches ($(hkb "$tk"))"; log "cleared electron/chromium caches ($(hkb "$tk"))"
    fi
  fi
  [ -n "$sk" ] && skip "kept (app running — quit to clean):$sk"

  # krisp: leftover installers + logs [safe]; speech models [pick]
  K="$AS/krisp"
  if [ -d "$K" ]; then
    if root_running krisp; then skip "krisp is running — quit it to clean installer/logs/models"
    else
      for f in "$K"/update/*.pkg "$K"/update/*.dmg "$K"/update/*.zip; do
        [ -f "$f" ] && safe_remove "$f" "krisp leftover installer ${f##*/}"
      done
      safe_clear "$K/logs" "krisp logs"
      reset_items
      [ -d "$K/models" ] && add_item "$K/models" "krisp speech models (transcription; re-downloaded when needed)" "$(kb "$K/models")"
      choose_items "krisp models"
    fi
  fi

  # Google updater download cache + superseded updater versions [safe]
  GU="$AS/Google/GoogleUpdater"
  if [ -d "$GU" ]; then
    safe_clear "$GU/crx_cache" "GoogleUpdater download cache"
    newest=$(ls -1 "$GU" 2>/dev/null | grep -E '^[0-9]+\.' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1)
    for v in "$GU"/[0-9]*; do
      [ -d "$v" ] && [ "${v##*/}" != "$newest" ] && safe_remove "$v" "GoogleUpdater old version ${v##*/}"
    done
  fi
fi

# ---------------------------------------------------------------- VS Code & forks
ws_target() {  # print "kind|path" for a workspaceStorage entry
  local j="$1/workspace.json" uri p="" kind="" hex dec
  [ -f "$j" ] || return 1
  uri=$(sed -nE 's/.*"(folder|workspace)"[[:space:]]*:[[:space:]]*"([^"]*)".*/\2/p' "$j" | head -1)
  case "$uri" in
    file://*) p=$(urldecode "${uri#file://}") ;;
    vscode-remote://dev-container+*)
      hex="${uri#vscode-remote://dev-container+}"; hex="${hex%%/*}"
      dec=$(printf '%s' "$hex" | xxd -r -p 2>/dev/null)
      p=$(printf '%s' "$dec" | sed -nE 's/.*"hostPath"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p')
      [ -z "$p" ] && p="$dec"; kind="devcontainer: " ;;
    *) return 1 ;;
  esac
  [ -n "$p" ] || return 1
  printf '%s|%s' "$kind" "$p"
}
if want editors; then
  hdr "EDITORS  (VS Code, Cursor, Windsurf)"
  for spec in "Code|.vscode|Visual Studio Code" "Code - Insiders|.vscode-insiders|Visual Studio Code - Insiders" \
              "Cursor|.cursor|Cursor" "Windsurf|.windsurf|Windsurf" "VSCodium|.vscode-oss|VSCodium"; do
    app="${spec%%|*}"; rest="${spec#*|}"; dot="${rest%%|*}"; appname="${rest#*|}"
    base="$AS/$app"; edir="$H/$dot/extensions"
    [ -d "$base" ] || [ -d "$edir" ] || continue
    info "${BOLD}$app${RST}"
    if root_running "$app"; then
      skip "$app is running — quit it to clean logs and old extension versions"
    else
      safe_clear "$base/logs" "$app logs"
      json="$edir/extensions.json"
      if [ -f "$json" ]; then
        valid=$(grep -oE '"relativeLocation"[[:space:]]*:[[:space:]]*"[^"]*"' "$json" | sed -E 's/.*"([^"]*)"$/\1/')
        if [ -n "$valid" ]; then
          for e in "$edir"/*/; do
            e="${e%/}"; n="${e##*/}"
            printf '%s\n' "$valid" | grep -qxF "$n" && continue
            safe_remove "$e" "$app superseded extension: $n"
          done
        fi
      fi
    fi
    ws="$base/User/workspaceStorage"
    if [ -d "$ws" ]; then
      info "workspace storage $(hsz "$ws")  (per-folder state incl. Copilot/Claude chat history)"
      : > "$TMP/ws_orphan"; : > "$TMP/ws_idle"
      for w in "$ws"/*/; do
        w="${w%/}"
        t=$(ws_target "$w") || continue
        kind="${t%%|*}"; p="${t#*|}"
        if [ ! -e "$p" ]; then
          printf '%s\t%s\n' "$w" "${kind}$(pretty "$p")  (folder gone)" >> "$TMP/ws_orphan"
        else
          db="$w/state.vscdb"
          [ -f "$db" ] && [ -n "$(find "$db" -mtime +"$DAYS" 2>/dev/null)" ] || continue
          printf '%s\t%s\n' "$w" "${kind}$(pretty "$p")  (last opened $(stat -f '%Sm' -t '%Y-%m-%d' "$db" 2>/dev/null))" >> "$TMP/ws_idle"
        fi
      done
      reset_items
      while IFS=$'\t' read -r w l; do add_item "$w" "$l" "$(kb "$w")"; done < "$TMP/ws_orphan"
      info "Orphaned (folder no longer exists)  [pick]:"
      choose_items "orphaned $app workspaces"
      reset_items
      while IFS=$'\t' read -r w l; do k=$(kb "$w"); [ "$k" -ge 10240 ] && add_item "$w" "$l" "$k"; done < "$TMP/ws_idle"
      info "Idle > ${DAYS}d, > 10MB (reopening the folder starts with fresh state/chat)  [pick]:"
      choose_items "idle $app workspaces"
    fi
    gs="$base/User/globalStorage"
    if [ -d "$gs" ]; then info "largest extension data (globalStorage)  [report]"; report_top "$gs" 5; fi
    [ -d "$base/User/History" ] && info "$(printf '  %8s  %s' "$(hsz "$base/User/History")" "Local History (file snapshots)  [report]")"
  done
fi

# ---------------------------------------------------------------- Claude
if want claude; then
  hdr "CLAUDE  (desktop app + Claude Code)"
  vdir="$H/.local/share/claude/versions"
  if [ -d "$vdir" ]; then
    active=$(readlink "$H/.local/bin/claude" 2>/dev/null); active="${active##*/}"
    newest=$(ls -t "$vdir" 2>/dev/null | head -1)
    for v in "$vdir"/*; do
      [ -e "$v" ] || continue
      n="${v##*/}"
      if [ "$n" = "$active" ] || [ "$n" = "$newest" ]; then continue; fi
      safe_remove "$v" "Claude Code old binary $n"
    done
  fi
  safe_clear "$H/.claude/debug" "Claude Code debug logs"
  safe_clear "$H/.claude/shell-snapshots" "Claude Code shell snapshots"
  reset_items
  for sub in projects file-history todos; do
    d="$H/.claude/$sub"; [ -d "$d" ] || continue
    n=$(find "$d" -type f -mtime +"$DAYS" 2>/dev/null | wc -l | tr -d ' ')
    [ "$n" -gt 0 ] || continue
    k=$(find "$d" -type f -mtime +"$DAYS" -exec du -k {} + 2>/dev/null | awk '{s+=$1} END{print s+0}')
    add_item "$d" "~/.claude/$sub: $n files older than ${DAYS}d (used by claude --resume)" "$k"
  done
  choose_items "Claude Code history sets" del_older_than_days
  CL="$AS/Claude"
  if [ -d "$CL" ]; then
    info "${BOLD}Claude desktop${RST} ($(hsz "$CL"))"
    claude_up=false; root_running Claude && claude_up=true
    # bundled Claude Code binaries: keep newest version only [safe]
    for sub in claude-code claude-code-vm; do
      d="$CL/$sub"; [ -d "$d" ] || continue
      newest=$(ls -t "$d" 2>/dev/null | head -1)
      for v in "$d"/*; do
        [ -e "$v" ] || continue
        [ "${v##*/}" = "$newest" ] && continue
        safe_remove "$v" "Claude desktop bundled $sub ${v##*/} (superseded)"
      done
    done
    # Cowork sessions idle > DAYS [pick]
    reset_items
    while IFS= read -r s; do
      case "$SELF" in "$s"/*) continue ;; esac            # never delete the session holding this script
      [ -n "$(find "$s" -type f -mtime -"$DAYS" -print 2>/dev/null | head -1)" ] && continue
      ts=$(find "$s" -type f -exec stat -f '%m' {} + 2>/dev/null | sort -n | tail -1)
      la="?"; [ -n "$ts" ] && la=$(date -r "$ts" '+%Y-%m-%d' 2>/dev/null)
      k=$(kb "$s"); [ "$k" -ge 1024 ] || continue
      add_item "$s" "Cowork session ${s##*/}  (last active $la)" "$k"
    done < <(find "$CL/local-agent-mode-sessions" -mindepth 3 -maxdepth 3 -type d -name 'local_*' 2>/dev/null)
    info "Cowork sessions idle > ${DAYS}d (removes their files/history in the app)  [pick]:"
    choose_items "Cowork sessions"
    # Cowork VM image [pick, only with Claude quit]
    vm="$CL/vm_bundles"
    if [ -d "$vm" ]; then
      if $claude_up; then
        skip "Cowork VM image $(hsz "$vm") — quit Claude to reset it"
      else
        reset_items
        add_item "$vm" "Cowork VM image (re-downloads ~1.2GB and rebuilds to ~10GB on next Cowork task)" "$(kb "$vm")"
        info "Cowork VM — only worth deleting if you rarely use Cowork  [pick]:"
        choose_items "Cowork VM image"
      fi
    fi
    $claude_up && skip "Claude is running — its ~$(hsz "$CL/Cache") cache is cleared only when Claude is quit"
  fi
fi

# ---------------------------------------------------------------- browsers
if want browsers; then
  hdr "BROWSERS  (Chrome, Vivaldi, Safari)"
  m="$AS/Google/Chrome/OptGuideOnDeviceModel"
  reset_items
  if [ -d "$m" ]; then
    if root_running Google; then skip "Chrome on-device AI model $(hsz "$m") — quit Chrome to remove"
    else add_item "$m" "Chrome on-device AI model (Gemini Nano; re-downloads unless disabled)" "$(kb "$m")"; fi
  fi
  choose_items "browser items"
  [ -d "$m" ] && info "Stop the re-download: defaults write com.google.Chrome GenAILocalFoundationalModelSettings -int 1"
  info "Profile sizes  [report — mostly site data; clear in-browser]"
  for p in "$AS/Google/Chrome" "$AS/Vivaldi" "$H/Library/Safari" "$H/Library/Containers/com.apple.Safari"; do
    [ -d "$p" ] && info "$(printf '  %8s  %s' "$(hsz "$p")" "$(pretty "$p")")"
  done
fi

# ---------------------------------------------------------------- WhatsApp
if want whatsapp; then
  WA="$H/Library/Group Containers/group.net.whatsapp.WhatsApp.shared"
  MEDIA="$WA/Message/Media"
  if [ -d "$MEDIA" ]; then
    if [ "$MEDIA_DAYS" -eq 0 ]; then scope="ALL media"; else scope="media older than ${MEDIA_DAYS}d"; fi
    hdr "WHATSAPP  [safe + pick]  (pick removes $scope in the chats you choose)"
    info "media $(hsz "$MEDIA"), whole container $(hsz "$WA")"
    wa_up=false; root_running WhatsApp && wa_up=true
    if $wa_up; then skip "WhatsApp is running — logs kept"; else safe_clear "$WA/Logs" "WhatsApp logs"; fi
    sqlite3 -readonly -separator $'\t' "$WA/ChatStorage.sqlite" \
      "SELECT ZCONTACTJID, ifnull(ZPARTNERNAME,'') FROM ZWACHATSESSION;" > "$TMP/wa_names" 2>/dev/null
    wa_orphan_scan
    reset_items
    while IFS=$'\t' read -r k n jid; do
      name=$(awk -F'\t' -v j="$jid" '$1==j{print $2; exit}' "$TMP/wa_names" 2>/dev/null); [ -z "$name" ] && name="$jid"
      add_item "$jid" "$(printf '%-34.34s %6s unreferenced files' "$name" "$n")" "$k"
    done < "$TMP/wa_orphan_by_chat"
    info "Unreferenced media (no message points to it; invisible in WhatsApp's own storage view)  [pick]:"
    if $APPLY && $wa_up; then warn "WhatsApp is running — quit it to delete. Listing only."; PICK_LIST_ONLY=true; fi
    choose_items "chats to sweep" del_wa_orphans
    PICK_LIST_ONLY=false
    [ "$MEDIA_DAYS" -gt 0 ] && info "Tip: --only whatsapp --media-days 0 targets all (referenced) media in a chat."
    : > "$TMP/wa_list"
    for d in "$MEDIA"/*/; do
      d="${d%/}"; k=$(kb "$d")
      [ "$k" -ge 10240 ] && printf '%s\t%s\n' "$k" "$d" >> "$TMP/wa_list"
    done
    sort -rn "$TMP/wa_list" | head -30 > "$TMP/wa_top"
    reset_items
    while IFS=$'\t' read -r k d; do
      jid="${d##*/}"
      name=$(awk -F'\t' -v j="$jid" '$1==j{print $2; exit}' "$TMP/wa_names" 2>/dev/null)
      [ -z "$name" ] && name="$jid"
      if [ "$MEDIA_DAYS" -eq 0 ]; then old="$k"
      else old=$(find "$d" -type f -mtime +"$MEDIA_DAYS" -exec du -k {} + 2>/dev/null | awk '{s+=$1} END{print s+0}'); fi
      [ "$old" -lt 1024 ] && { info "$(printf '  %8s  %-34.34s (nothing older than %sd)' "$(hkb "$k")" "$name" "$MEDIA_DAYS")"; continue; }
      add_item "$d" "$(printf '%-34.34s (chat total %s)' "$name" "$(hkb "$k")")" "$old"
    done < "$TMP/wa_top"
    warn "Deleted media shows as unavailable in WhatsApp and may not be re-downloadable."
    info "Cleaner alternative: WhatsApp > Settings > Storage and Data > Manage Storage > pick the chat."
    if $APPLY && $wa_up; then
      warn "WhatsApp is running — quit it to delete media. Listing only."; PICK_LIST_ONLY=true
    fi
    choose_items "chats" del_wa_old
    PICK_LIST_ONLY=false
  fi
fi

# ---------------------------------------------------------------- Xcode
if want xcode && [ -d "$H/Library/Developer" ]; then
  hdr "XCODE  [safe + pick]"
  safe_clear "$H/Library/Developer/Xcode/DerivedData" "Xcode DerivedData"
  safe_clear "$H/Library/Developer/CoreSimulator/Caches" "CoreSimulator caches"
  safe_clear "$H/Library/Developer/Xcode/UserData/Previews" "SwiftUI preview simulators"
  safe_clear "$H/Library/Developer/Xcode/DocumentationCache" "Xcode documentation cache"
  safe_clear "$H/Library/Developer/XCPGDevices" "Playground devices"
  if command -v xcrun >/dev/null 2>&1; then
    run "delete unavailable simulators" xcrun simctl delete unavailable
    if have_py; then
      PY_RT=$(cat <<'EOF'
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
rows=[]
for k,v in d.items():
    plat=v.get("platformIdentifier","").split(".")[-1].replace("simulator","")
    last=(v.get("lastUsedAt") or "never")[:10]
    rows.append((int(v.get("sizeBytes") or 0),k,"%s %s (%s)  last used %s"%(plat,v.get("version","?"),v.get("build","?"),last)))
for s,k,l in sorted(rows,reverse=True): print("%s\t%d\t%s"%(k,s,l))
EOF
)
      reset_items
      while IFS=$'\t' read -r id bytes label; do
        [ -n "$id" ] && add_item "$id" "$label" $((bytes/1024))
      done < <(xcrun simctl runtime list -j 2>/dev/null | /usr/bin/python3 -c "$PY_RT")
      info "Simulator runtimes (5-10GB each; reinstall via Xcode > Settings > Components):"
      choose_items "simulator runtimes" del_runtime

      PY_DEV=$(cat <<'EOF'
import json,sys
try: d=json.load(sys.stdin).get("devices",{})
except Exception: sys.exit(0)
for rt,devs in d.items():
    r=rt.split(".")[-1].replace("-"," ",1).replace("-",".")
    for x in devs:
        print("%s\t%s - %s  last booted %s"%(x["udid"],x.get("name","?"),r,(x.get("lastBootedAt") or "never")[:10]))
EOF
)
      reset_items
      while IFS=$'\t' read -r udid label; do
        [ -n "$udid" ] || continue
        k=$(kb "$H/Library/Developer/CoreSimulator/Devices/$udid")
        [ "$k" -ge 51200 ] && add_item "$udid" "$label" "$k"
      done < <(xcrun simctl list devices -j 2>/dev/null | /usr/bin/python3 -c "$PY_DEV")
      info "Simulator devices > 50MB (apps + data inside the simulator):"
      choose_items "simulators" del_sim
    fi
  fi
  reset_items
  for d in "$H"/Library/Developer/Xcode/*DeviceSupport/*/; do
    [ -d "$d" ] || continue; d="${d%/}"
    platf=$(basename "$(dirname "$d")"); platf="${platf% DeviceSupport}"
    add_item "$d" "$platf ${d##*/}  ($(stat -f '%Sm' -t '%Y-%m-%d' "$d" 2>/dev/null))" "$(kb "$d")"
  done
  info "Device support files (re-created when that device connects):"
  choose_items "DeviceSupport folders"
  reset_items
  while IFS= read -r a; do add_item "$a" "${a##*/}" "$(kb "$a")"; done \
    < <(find "$H/Library/Developer/Xcode/Archives" -maxdepth 2 -name '*.xcarchive' 2>/dev/null)
  info "Archives (keep the ones you need to symbolicate shipped builds):"
  choose_items "Xcode archives"
fi

# ---------------------------------------------------------------- Docker / colima
if want docker; then
  hdr "DOCKER / COLIMA / DEVCONTAINERS"
  LIMA="$H/.colima/_lima"
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    docker system df 2>/dev/null | sed 's/^/    /'
    reset_items
    while IFS=$'\t' read -r id name image size since; do
      [ -n "$id" ] && add_item "$id" "$(printf '%-28.28s %-34.34s %s' "$name" "$image" "$since")" 0 "${size%% *}"
    done < <(docker ps -a -s --filter status=exited --filter status=created --filter status=dead \
               --format '{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Size}}\t{{.CreatedSince}}' 2>/dev/null)
    info "Stopped containers  [pick]  (devcontainers rebuild on 'Reopen in Container'):"
    choose_items "stopped containers" del_container

    docker system df -v 2>/dev/null | awk '/^Local Volumes space usage/{f=1;next} f&&/^VOLUME NAME/{h=1;next} f&&h&&NF==0{exit} f&&h{print $1"\t"$NF}' > "$TMP/vols"
    reset_items
    while IFS= read -r v; do
      [ -n "$v" ] || continue
      s=$(awk -F'\t' -v v="$v" '$1==v{print $2}' "$TMP/vols")
      add_item "$v" "$v" 0 "${s:-?}"
    done < <(docker volume ls -qf dangling=true 2>/dev/null)
    info "Unused volumes  [pick]  (may hold devcontainer DBs, node_modules, shell history):"
    choose_items "unused volumes" del_volume

    info "Images / build cache / networks  [safe]:"
    run "docker image prune -af (unused images, incl. stale devcontainer images)" docker image prune -af
    run "docker builder prune -af (build cache)" docker builder prune -af
    run "docker network prune -f" docker network prune -f

    if command -v colima >/dev/null 2>&1 && colima status >/dev/null 2>&1; then
      if $APPLY; then
        b=$(kb "$LIMA"); act "fstrim inside colima VM (hands freed blocks back to macOS)"
        colima ssh -- sudo fstrim -av 2>&1 | sed 's/^/      /'
        a=$(kb "$LIMA")
        if [ "$b" -gt "$a" ]; then act "VM disk shrank by $(hkb $((b-a)))"; FREED_KB=$((FREED_KB+b-a)); log "colima fstrim freed $(hkb $((b-a)))"; fi
      else info "[dry-run] would run: fstrim inside colima VM to return freed space to macOS"; fi
      colima list 2>/dev/null | sed 's/^/    /'
    fi
  else
    skip "docker not reachable — start colima to clean images/containers/volumes"
  fi
  if $RECLAIM_DOCKER_VM && command -v colima >/dev/null 2>&1; then
    warn "Rebuilding colima VM (current disk $(hsz "$LIMA")). Stops all containers; ALL images, containers and volumes are lost."
    if confirm "Proceed with colima stop/delete/start?"; then
      run "colima rebuild" bash -c 'colima stop; colima delete -f && colima start'
    else skip "colima rebuild skipped"; fi
  elif [ -d "$LIMA" ]; then
    info "VM disk on host: $(hsz "$LIMA")  (--reclaim-docker-vm rebuilds it from scratch)"
  fi
fi

# ---------------------------------------------------------------- dev toolchains
tool_cache() {  # tool_cache name path cmd...
  local name="$1" p="$2" k; shift 2
  command -v "$1" >/dev/null 2>&1 || return 0
  [ -n "$p" ] && [ -d "$p" ] || return 0
  k=$(kb "$p"); [ "$k" -lt 1024 ] && return 0
  SAFE_KB=$((SAFE_KB+k))
  if $APPLY; then "$@" >/dev/null 2>&1; act "$name cache cleaned (up to $(hkb "$k"))"; log "$name: $*"; FREED_KB=$((FREED_KB+k))
  else info "$(printf '%8s  %s cache  (%s)' "$(hkb "$k")" "$name" "$*")"; fi
}
if want dev; then
  hdr "DEV TOOLCHAIN CACHES  [safe]"
  tool_cache npm  "$H/.npm/_cacache" npm cache clean --force
  tool_cache pnpm "$(command -v pnpm >/dev/null 2>&1 && pnpm store path 2>/dev/null)" pnpm store prune
  tool_cache yarn "$(command -v yarn >/dev/null 2>&1 && yarn cache dir 2>/dev/null)" yarn cache clean
  tool_cache pip  "$(command -v pip3 >/dev/null 2>&1 && pip3 cache dir 2>/dev/null)" pip3 cache purge
  tool_cache uv   "$(command -v uv >/dev/null 2>&1 && uv cache dir 2>/dev/null)" uv cache clean
  tool_cache go   "$(command -v go >/dev/null 2>&1 && go env GOCACHE 2>/dev/null)" go clean -cache
  tool_cache pod  "$H/Library/Caches/CocoaPods" pod cache clean --all
  safe_clear "$H/.bun/install/cache"     "bun cache"
  safe_clear "$H/.cargo/registry/cache"  "cargo registry cache"
  safe_clear "$H/.cargo/registry/src"    "cargo registry sources"
  safe_clear "$H/.cargo/git/checkouts"   "cargo git checkouts"
  safe_clear "$H/.gradle/caches"         "Gradle caches"
  reset_items
  for c in "$H/.cache"/*/; do
    [ -d "$c" ] || continue; c="${c%/}"; k=$(kb "$c")
    [ "$k" -ge 10240 ] && add_item "$c" "$(pretty "$c")" "$k"
  done
  info "~/.cache folders  [pick]  (huggingface models, puppeteer/playwright browsers…):"
  choose_items "~/.cache folders"
  if command -v go >/dev/null 2>&1; then
    mc=$(go env GOMODCACHE 2>/dev/null)
    if [ -d "$mc" ]; then reset_items; add_item "$mc" "Go module cache" "$(kb "$mc")"; choose_items "Go module cache" del_gomod; fi
  fi
fi

# ---------------------------------------------------------------- language runtimes
vm_pick() {  # vm_pick label dir current
  local label="$1" dir="$2" cur="$3" v n
  [ -d "$dir" ] && [ -n "$cur" ] || return 0
  reset_items
  for v in "$dir"/*/; do
    [ -d "$v" ] || continue; v="${v%/}"; n="${v##*/}"
    [[ "$n" == *"$cur"* ]] && continue
    add_item "$v" "$label $n" "$(kb "$v")"
  done
  [ ${#IT_PATH[@]} -gt 0 ] || return 0
  info "$label versions (keeping $cur; projects pinned to removed versions need a reinstall):"
  choose_items "$label versions"
}
if want runtimes; then
  hdr "LANGUAGE RUNTIME VERSIONS  [pick]"
  command -v rbenv >/dev/null 2>&1 && vm_pick ruby "$H/.rbenv/versions" "$(rbenv global 2>/dev/null)"
  command -v pyenv >/dev/null 2>&1 && vm_pick python "$H/.pyenv/versions" "$(pyenv global 2>/dev/null | head -1)"
  if [ -d "$H/.nvm/versions/node" ]; then
    def=$(cat "$H/.nvm/alias/default" 2>/dev/null)
    case "$def" in [0-9]*) cur="v$def" ;; v[0-9]*) cur="$def" ;; *) cur=$(node -v 2>/dev/null) ;; esac
    vm_pick node "$H/.nvm/versions/node" "$cur"
  fi
  if command -v rustup >/dev/null 2>&1; then
    reset_items
    while IFS= read -r t; do
      case "$t" in *"(default)"*|*"(active"*|"") continue ;; esac
      t="${t%% *}"; add_item "$t" "rust toolchain $t" "$(kb "$H/.rustup/toolchains/$t")"
    done < <(rustup toolchain list 2>/dev/null)
    choose_items "rust toolchains" del_rust
  fi
fi

# ---------------------------------------------------------------- stale project artifacts
if want projects; then
  hdr "STALE PROJECT ARTIFACTS  [pick]  (project idle > ${DAYS}d; all regenerable)"
  ART=( -name node_modules -o -name .venv -o -name venv -o -name .next -o -name .nuxt -o -name .turbo
        -o -name .svelte-kit -o -name .parcel-cache -o -name .gradle -o -name Pods -o -name DerivedData
        -o -name .terraform -o -name .serverless -o -name .pytest_cache -o -name .mypy_cache
        -o -name .ruff_cache -o -name target )
  {
    find "$H" -maxdepth 7 \( -path "$H/Library" -o -path "$H/.*" -o -path "$H/Movies" -o -path "$H/Music" \
      -o -path "$H/Pictures" -o -path "$H/Applications" -o -name .git \) -prune -o -type d \( "${ART[@]}" \) -prune -print 2>/dev/null
    [ -d "$H/Library/Projects" ] && find "$H/Library/Projects" -maxdepth 6 -name .git -prune -o -type d \( "${ART[@]}" \) -prune -print 2>/dev/null
  } > "$TMP/artifacts"
  reset_items
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
    add_item "$a" "$(pretty "$a")" "$k"
  done < "$TMP/artifacts"
  choose_items "artifact folders"
fi

# ---------------------------------------------------------------- Homebrew
if want brew && command -v brew >/dev/null 2>&1; then
  hdr "HOMEBREW  [safe]"
  brew cleanup --prune=all -n 2>/dev/null | tail -1 | sed 's/^/    /'
  orphans=$(brew autoremove --dry-run 2>/dev/null | grep -vc '^==>')
  info "orphaned dependencies: ${orphans:-0}"
  run "brew cleanup --prune=all -s" brew cleanup --prune=all -s
  run "brew autoremove" brew autoremove
fi

# ---------------------------------------------------------------- GIMP
if want gimp && [ -d "$AS/GIMP" ]; then
  hdr "GIMP"
  if pgrep -fi '/GIMP[^/]*\.app/' >/dev/null 2>&1; then skip "GIMP is running — quit it to clean"
  else
    for g in "$AS/GIMP"/*/; do
      [ -d "$g" ] || continue; g="${g%/}"
      safe_clear "$g/tmp" "GIMP ${g##*/} temp"
      for s in "$g"/gimpswap.*; do [ -f "$s" ] && safe_remove "$s" "GIMP swap ${s##*/}"; done
    done
    vers=$(ls -1 "$AS/GIMP" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+' | sort -t. -k1,1n -k2,2n)
    latest=$(printf '%s\n' "$vers" | tail -1)
    reset_items
    for v in $vers; do
      [ "$v" = "$latest" ] && continue
      add_item "$AS/GIMP/$v" "GIMP $v profile (older version: settings, brushes, plug-ins)" "$(kb "$AS/GIMP/$v")"
    done
    choose_items "old GIMP profiles"
  fi
fi

# ---------------------------------------------------------------- installers & archives
if want downloads; then
  hdr "OLD INSTALLERS & ARCHIVES  [pick]  (> ${DAYS}d, > 5MB, in Downloads/Desktop)"
  reset_items
  while IFS= read -r f; do
    add_item "$f" "$(pretty "$f")  ($(stat -f '%Sm' -t '%Y-%m-%d' "$f" 2>/dev/null))" "$(kb "$f")"
  done < <(find "$H/Downloads" "$H/Desktop" -maxdepth 2 -type f \( -iname '*.dmg' -o -iname '*.pkg' -o -iname '*.iso' \
             -o -iname '*.xip' -o -iname '*.ipsw' -o -iname '*.zip' -o -iname '*.tar.gz' -o -iname '*.tgz' \) \
             -mtime +"$DAYS" -size +5M 2>/dev/null)
  for a in /Applications/Install\ macOS*.app; do [ -d "$a" ] && add_item "$a" "$a" "$(kb "$a")"; done
  choose_items "files"
fi

# ---------------------------------------------------------------- local LLM models
if want models && [ -d "$H/.omlx/models" ]; then
  hdr "LOCAL LLM MODELS (~/.omlx)  [pick]"
  safe_clear "$H/.omlx/cache" ".omlx cache"
  {
    for c in "$H/.omlx/models"/*/; do
      [ -d "$c" ] || continue; c="${c%/}"
      case "${c##*/}" in models--*) echo "$c"; continue ;; esac
      if ls "$c" 2>/dev/null | grep -qE '\.(safetensors|gguf|bin|npz)$|^config\.json$'; then echo "$c"
      else for cc in "$c"/*/; do [ -d "$cc" ] && echo "${cc%/}"; done; fi
    done
  } > "$TMP/models"
  reset_items
  while IFS= read -r m; do
    ts=$(find "$m" -type f \( -name '*.safetensors' -o -name '*.gguf' -o -name '*.bin' -o -name '*.npz' \) \
           -exec stat -f '%a' {} + 2>/dev/null | sort -n | tail -1)
    la="never"; [ -n "$ts" ] && la=$(date -r "$ts" '+%Y-%m-%d' 2>/dev/null)
    add_item "$m" "$(printf '%-52.52s last used %s' "${m#"$H/.omlx/models/"}" "$la")" "$(kb "$m")"
  done < "$TMP/models"
  choose_items "models"
fi

# ---------------------------------------------------------------- iOS backups
if want backups; then
  BK="$H/Library/Application Support/MobileSync/Backup"
  if [ -d "$BK" ]; then
    hdr "iOS DEVICE BACKUPS  [pick]"
    PB=/usr/libexec/PlistBuddy
    reset_items
    for b in "$BK"/*/; do
      [ -d "$b" ] || continue; b="${b%/}"
      dev="?"; last="?"
      if [ -f "$b/Info.plist" ] && [ -x "$PB" ]; then
        dev=$($PB -c 'Print :"Device Name"' "$b/Info.plist" 2>/dev/null || echo "?")
        last=$($PB -c 'Print :"Last Backup Date"' "$b/Info.plist" 2>/dev/null || echo "?")
      fi
      add_item "$b" "$(printf '%-24.24s last backup %s' "$dev" "$last")" "$(kb "$b")"
    done
    choose_items "backups"
  fi
fi

# ---------------------------------------------------------------- system (opt-in, sudo)
sudo_clear() {
  local p="$1" label="$2" k
  sudo test -d "$p" || return 0
  k=$(sudo du -skx "$p" 2>/dev/null | awk '{print $1+0}'); [ "${k:-0}" -lt 1024 ] && return 0
  SAFE_KB=$((SAFE_KB+k))
  if $APPLY; then sudo find "$p" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null; act "cleared $label ($(hkb "$k"))"; log "sudo cleared $p"; FREED_KB=$((FREED_KB+k))
  else info "$(printf '%8s  %s' "$(hkb "$k")" "$label")"; fi
}
if want system; then
  hdr "SYSTEM-LEVEL  [safe, sudo]"
  if sudo -v; then
    sudo_clear /Library/Caches "/Library/Caches"
    sudo_clear /Library/Logs/DiagnosticReports "system crash reports"
    sudo_clear /Library/Developer/CoreSimulator/Caches "simulator dyld caches (system)"
    run "delete rotated system logs older than 7d" sudo find /private/var/log -name '*.gz' -mtime +7 -delete
    info "local snapshots:"; tmutil listlocalsnapshots / 2>/dev/null | sed 's/^/    /'
    info "com.apple.os.update-* snapshots belong to Software Update and clear after the update/reboot."
    if $APPLY && confirm "Thin Time Machine local snapshots now?"; then
      run "thin local snapshots" sudo tmutil thinlocalsnapshots / 999999999999 4
    fi
  fi
fi

# ---------------------------------------------------------------- report
if want report; then
  hdr "WHERE ELSE IS SPACE GOING  [report]"
  for d in "$AS" "$H/Library/Containers" "$H/Library/Group Containers"; do
    [ -d "$d" ] || continue
    info "${BOLD}$(pretty "$d")${RST}"; report_top "$d" 6
  done
  info "${BOLD}Files > 1GB in home${RST} (excluding colima, omlx, iOS backups)"
  find "$H" -xdev \( -path "$H/.colima" -o -path "$H/.omlx" -o -path "$H/Library/Application Support/MobileSync" \
       -o -path "$H/Library/Mobile Documents" \) -prune -o -type f -size +1G -print0 2>/dev/null |
    xargs -0 du -k 2>/dev/null | sort -rn | head -15 |
    while read -r k p; do info "$(printf '  %8s  %s' "$(hkb "$k")" "$(pretty "$p")")"; done
fi

# ---------------------------------------------------------------- summary
hdr "SUMMARY"
if $APPLY; then
  END_FREE=$(free_kb); delta=$(( ${END_FREE:-0} - ${START_FREE:-0} ))
  printf "  %scleared ≈ %s%s   (free space change: %s; APFS may take a minute to report)\n" \
    "$GRN$BOLD" "$(hkb "$FREED_KB")" "$RST" "$(hkb "$delta")"
  log "run complete: cleared≈$(hkb "$FREED_KB") df-delta=$(hkb "$delta")"
else
  printf "  %ssafe tier ≈ %s%s  (+ docker reclaimable shown above)\n" "$YLW$BOLD" "$(hkb "$SAFE_KB")" "$RST"
  printf "  %sreview lists up to ≈ %s%s\n" "$YLW$BOLD" "$(hkb "$OPT_KB")" "$RST"
  info "Re-run with --apply to act."
fi
df -h "$H" | awk 'NR==2{printf "  free now: %s (%s used)\n", $4, $5}'
