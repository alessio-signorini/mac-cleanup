#!/bin/bash
# Argument parsing and the entry point.

usage() {
  cat <<EOF
$MC_NAME $MC_VERSION — reclaim disk space on macOS

Usage: $MC_NAME [MODULE...] [options]

  (no options)          dry-run report of all modules (nothing is deleted)
  --apply               review each module and delete what you select
  --apply --yes, -y     non-interactive: safe tier only (for cron/launchd)
  --only a,b            run only these modules (same as positional MODULE args)
  --skip a,b            skip modules
  --days N              idle threshold for projects/downloads/workspaces/Claude history (default $DAYS)
  --media-days N        WhatsApp media age threshold (default $MEDIA_DAYS; 0 = all media)
  --system              include the sudo 'system' module
  --reclaim-docker-vm   offer a colima VM rebuild in the docker module
  --no-tui              numbered text prompts instead of the full-screen picker
  -q, --quiet           dry-run: overview table and summary only
  -v, --verbose         apply: print each item result and module notes
  --list                list modules and exit
  --version             print version and exit
  -h, --help            this help

Tiers: safe = regenerable caches (pre-selected; --yes applies them),
       pick = your data or slow to rebuild (never selected for you).

Picker keys: ↑/↓ move · space toggle · a all · n none · enter confirm · q skip · ? help
Tips: quit apps first (caches of running apps are skipped); give your terminal
Full Disk Access to clean sandboxed app caches. History: $(pretty "$LOG_FILE")
EOF
}

list_modules() {
  local m
  for m in $MC_ALL_MODULES; do
    declare -F "${m}_scan" >/dev/null || continue
    mod_meta "$m"
    printf '  %-10s %s%s\n' "$m" "$MOD_TITLE" "$([ "$MOD_OPTIN" = 1 ] && printf '  (opt-in)')"
  done
}

need_uint() { [[ "$2" =~ ^[0-9]+$ ]] || die "$1 needs a non-negative integer (got '${2:-}')"; }

valid_modules() {   # valid_modules "a,b" -> dies on unknown names
  local m
  for m in $(printf '%s' "$1" | tr ',' ' '); do
    case " $MC_ALL_MODULES " in *" $m "*) ;; *) die "unknown module '$m' (see --list)" ;; esac
  done
}

cli_parse() {
  local pos=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply)             APPLY=true ;;
      --dry-run)           APPLY=false ;;
      --yes|-y)            ASSUME_YES=true ;;
      --reclaim-docker-vm) RECLAIM_DOCKER_VM=true ;;
      --system)            EXTRA="$EXTRA,system" ;;
      --no-tui)            NO_TUI=true ;;
      -q|--quiet)          QUIET=true ;;
      -v|--verbose)        VERBOSE=true ;;
      --days)              need_uint --days "${2:-}"; DAYS="$2"; shift ;;
      --media-days)        need_uint --media-days "${2:-}"; MEDIA_DAYS="$2"; shift ;;
      --only)              [ -n "${2:-}" ] || die "--only needs a module list"; ONLY="$ONLY,$2"; shift ;;
      --skip)              [ -n "${2:-}" ] || die "--skip needs a module list"; SKIP="$SKIP,$2"; shift ;;
      --list)              list_modules; exit 0 ;;
      --version)           echo "$MC_NAME $MC_VERSION"; exit 0 ;;
      -h|--help)           usage; exit 0 ;;
      -*)                  die "unknown option: $1 (see --help)" ;;
      *)                   pos="$pos,$1" ;;
    esac
    shift
  done
  [ -n "$pos" ] && ONLY="$ONLY$pos"
  ONLY="${ONLY#,}"; SKIP="${SKIP#,}"; EXTRA="${EXTRA#,}"
  [ -n "$ONLY" ] && valid_modules "$ONLY"
  [ -n "$SKIP" ] && valid_modules "$SKIP"
  return 0
}

mc_init() {
  [ "$(id -u)" -eq 0 ] && die "run as your normal user (not sudo); use --system for the sudo parts"
  MC_TMP=$(mktemp -d "${TMPDIR:-/tmp}/mac-cleanup.XXXXXX") || die "mktemp failed"
  trap mc_cleanup EXIT
  trap mc_on_interrupt INT TERM
  ui_init
  apps_init
  resolve_modules
  [ ${#MODS[@]} -gt 0 ] || die "no modules selected"
}

mc_main() {
  local src="${BASH_SOURCE[${#BASH_SOURCE[@]}-1]}"
  MC_SELF="$(cd "$(dirname "$src")" 2>/dev/null && pwd)/$(basename "$src")"
  cli_parse "$@"
  mc_init
  mc_run
}
