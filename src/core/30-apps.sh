#!/bin/bash
# Running-app detection. Caches of running apps are never touched.

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
GIMP|org.gimp.gimp-2.10|GIMP
Safari|com.apple.Safari|Safari'

RUNNING_BUNDLES=""
RUNNING_PROCS=""
RUNNING_PATHS=""

apps_init() {
  if [ -n "${MC_RUNNING_OVERRIDE+x}" ]; then
    # Tests: fixed list of running bundle ids / process names ("none" = nothing).
    [ "$MC_RUNNING_OVERRIDE" = none ] && MC_RUNNING_OVERRIDE=""
    RUNNING_BUNDLES=$(printf '%s\n' "$MC_RUNNING_OVERRIDE" | tr ', ' '\n\n')
    RUNNING_PROCS="$RUNNING_BUNDLES"
    RUNNING_PATHS=""
    return 0
  fi
  RUNNING_BUNDLES=$(lsappinfo list 2>/dev/null | sed -n 's/.*bundleID="\([^"]*\)".*/\1/p' | sort -u)
  RUNNING_PATHS=$(ps -axo comm= 2>/dev/null)
  RUNNING_PROCS=$(printf '%s\n' "$RUNNING_PATHS" | sed 's|.*/||' | sort -u)
}

bundle_running() { [ -n "$1" ] && printf '%s\n' "$RUNNING_BUNDLES" | grep -qixF "$1"; }
apppath_running() { [ -n "$1" ] && printf '%s\n' "$RUNNING_PATHS" | grep -qiF "/$1.app/Contents/MacOS/"; }

# Is the app owning this Application Support folder / bundle id / app name running?
app_running() {
  local r="$1" row b p
  row=$(printf '%s\n' "$APP_TABLE" | awk -F'|' -v k="$r" \
    'tolower($1)==tolower(k) || tolower($2)==tolower(k) || tolower($3)==tolower(k) {print; exit}')
  if [ -n "$row" ]; then
    b=$(printf '%s' "$row" | cut -d'|' -f2); p=$(printf '%s' "$row" | cut -d'|' -f3)
    bundle_running "$b" && return 0
    printf '%s\n' "$RUNNING_PROCS" | grep -qxF "$p" && return 0
    apppath_running "$p" && return 0
    return 1
  fi
  bundle_running "$r" && return 0
  printf '%s\n' "$RUNNING_PROCS" | grep -qxF "$r" && return 0
  apppath_running "$r"
}

# group.<TEAMID>.<bundle…> vs running bundle ids (prefix match either way)
group_running() {
  local g="${1#group.}" b
  [[ "$g" =~ ^[A-Z0-9]{10}\.(.+)$ ]] && g="${BASH_REMATCH[1]}"
  while IFS= read -r b; do
    [ -z "$b" ] && continue
    case "$g" in "$b"*) return 0 ;; esac
    case "$b" in "$g"*) return 0 ;; esac
  done <<< "$RUNNING_BUNDLES"
  return 1
}

running_app_names() {
  local key pname out=""
  while IFS='|' read -r key _ pname; do
    app_running "$key" && out="$out, $pname"
  done <<< "$APP_TABLE"
  printf '%s' "${out#, }"
}
