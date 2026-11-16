#!/bin/bash
# shellcheck disable=SC2034
# Constants, defaults and the module order. Sourced first.

MC_NAME="mac-cleanup"
MC_VERSION="3.0.0-dev"

# Scan/review order. build.sh reads this line to order modules in dist/.
MC_ALL_MODULES="caches orphans apps editors claude browsers whatsapp xcode docker dev runtimes projects brew gimp downloads models backups system report"

H="$HOME"
AS="$H/Library/Application Support"

DAYS=30
MEDIA_DAYS=90
APPLY=false
ASSUME_YES=false
RECLAIM_DOCKER_VM=false
NO_TUI=false
QUIET=false
VERBOSE=false
ONLY=""
SKIP=""
EXTRA=""            # opt-in modules enabled by flags (e.g. --system)

LOG_DIR="$H/.local/state/mac-disk-cleanup"
LOG_FILE="$LOG_DIR/history.log"

MC_TMP=""
MC_SELF=""
MC_INTERRUPTED=false
