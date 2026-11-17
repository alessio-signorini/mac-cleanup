#!/bin/bash
# Development sandbox: runs mac-cleanup (or any command) against a fake $HOME inside a macOS
# Seatbelt sandbox (sandbox-exec), so a bug can't delete anything real.
#
#   dev/sandbox.sh [ARGS…]          src/main.sh ARGS   (e.g. --apply, --only caches --apply)
#   dev/sandbox.sh --dist [ARGS…]   dist/mac-cleanup ARGS
#   dev/sandbox.sh --exec CMD…      any command (e.g. --exec tests/run.sh --tui)
#   dev/sandbox.sh --shell          interactive bash inside the sandbox
#   dev/sandbox.sh --reset          recreate the fake home from tests/fixtures.sh
#
# Enforced by the kernel, not by the tool:
#   - file writes/deletes only under .sandbox/ (fake home + TMPDIR), dist/, /tmp (bash 3.2
#     here-docs and Apple diff hard-code it) and terminal devices
#   - no network (also blocks the docker/colima unix socket)
#   - no sudo, tmutil, xcrun/simctl (they act through system daemons, outside file rules)
# The fake home is .sandbox/home (gitignored); it is created on first use.
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT=$(pwd -P)
SB="$ROOT/.sandbox"
FAKE="$SB/home"

command -v sandbox-exec >/dev/null 2>&1 || { echo "sandbox: sandbox-exec not found" >&2; exit 1; }
case "$ROOT" in *'"'*|*'\'*) echo "sandbox: unsupported characters in $ROOT" >&2; exit 1 ;; esac

PROFILE="(version 1)
(allow default)
(deny file-write*)
(allow file-write*
  (subpath \"$SB\")
  (subpath \"$ROOT/dist\")
  (subpath \"/private/tmp\")
  (literal \"/dev/null\") (literal \"/dev/zero\") (literal \"/dev/dtracehelper\")
  (regex #\"^/dev/tty\") (regex #\"^/dev/fd/\") (regex #\"^/dev/ptmx\"))
(deny network*)
(deny process-exec
  (literal \"/usr/bin/sudo\") (literal \"/usr/bin/tmutil\") (literal \"/usr/bin/xcrun\")
  (regex #\"/simctl$\"))"

reset_home() {
  # shellcheck source=tests/fixtures.sh
  . "$ROOT/tests/fixtures.sh"
  mkdir -p "$SB/tmp"
  make_home "$FAKE"
  echo "sandbox: fake home ready at ${FAKE#"$ROOT"/}"
}

sbx() {
  mkdir -p "$SB/tmp"
  HOME="$FAKE" TMPDIR="$SB/tmp/" sandbox-exec -p "$PROFILE" "$@"
}

case "${1:-}" in
  --reset) reset_home; exit 0 ;;
esac
[ -d "$FAKE" ] || reset_home

case "${1:-}" in
  --shell) PS1="(sandbox) \\w \\$ " sbx /bin/bash --norc -i ;;
  --exec)  shift; [ $# -gt 0 ] || { echo "sandbox: --exec needs a command" >&2; exit 1; }; sbx "$@" ;;
  --dist)  shift; [ -x "$ROOT/dist/mac-cleanup" ] || ./build.sh --no-lint >/dev/null || exit 1
           sbx "$ROOT/dist/mac-cleanup" "$@" ;;
  *)       sbx "$ROOT/src/main.sh" "$@" ;;
esac
