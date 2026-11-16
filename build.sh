#!/bin/bash
# Builds dist/mac-cleanup: one self-contained bash file from src/.
# Usage: ./build.sh [--no-lint]
set -o pipefail
cd "$(dirname "$0")" || exit 1

LINT=true
[ "${1:-}" = "--no-lint" ] && LINT=false

VERSION=$(tr -d '[:space:]' < VERSION 2>/dev/null)
[ -n "$VERSION" ] || { echo "build: VERSION file missing or empty" >&2; exit 1; }
MODULES=$(sed -n 's/^MC_ALL_MODULES="\(.*\)"$/\1/p' src/core/00-env.sh)
[ -n "$MODULES" ] || { echo "build: MC_ALL_MODULES not found in src/core/00-env.sh" >&2; exit 1; }

OUT=dist/mac-cleanup
TMP_OUT="$OUT.tmp.$$"
mkdir -p dist

# Drops the shebang and the @standalone/@dev regions; stamps the version.
strip() {
  awk -v ver="$VERSION" '
    NR==1 && /^#!/ { next }
    /^# @(standalone|dev)-begin/ { skip=1; next }
    /^# @(standalone|dev)-end/   { skip=0; next }
    skip { next }
    /^MC_VERSION=/ { print "MC_VERSION=\"" ver "\""; next }
    { print }' "$1"
}

{
  echo '#!/bin/bash'
  echo "# mac-cleanup $VERSION — built $(date '+%Y-%m-%d %H:%M') from src/ by build.sh"
  echo '# GENERATED FILE — edit src/ and run ./build.sh. See BUILD.md / README.md.'
  echo '# shellcheck disable=SC2034,SC2154'
  for f in src/core/*.sh; do
    printf '\n# ==== %s\n' "$f"; strip "$f"
  done
  for m in $MODULES; do
    f="src/modules/$m.sh"
    [ -f "$f" ] || { echo "build: missing module $f" >&2; exit 1; }
    printf '\n# ==== %s\n' "$f"; strip "$f"
  done
  printf '\n# ==== src/main.sh\n'; strip src/main.sh
} > "$TMP_OUT" || { rm -f "$TMP_OUT"; exit 1; }

bash -n "$TMP_OUT" || { echo "build: syntax check failed" >&2; rm -f "$TMP_OUT"; exit 1; }
mv "$TMP_OUT" "$OUT" && chmod +x "$OUT"

got=$("$OUT" --version 2>&1)
[ "$got" = "mac-cleanup $VERSION" ] || { echo "build: --version check failed: $got" >&2; exit 1; }

if $LINT; then
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -s bash -S warning "$OUT" || { echo "build: shellcheck failed" >&2; exit 1; }
    echo "shellcheck: ok"
  else
    echo "shellcheck: not installed — lint skipped (optional: brew install shellcheck)"
  fi
fi

printf 'built %s (%s, %s lines, version %s)\n' "$OUT" "$(du -h "$OUT" | awk '{print $1}')" "$(wc -l < "$OUT" | tr -d ' ')" "$VERSION"
