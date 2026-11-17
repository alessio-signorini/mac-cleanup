#!/bin/bash
# Test suite for mac-cleanup. Builds dist/, creates a fake $HOME and exercises the tool.
# Never touches the real home: only file-based modules run, with HOME pointing to a temp dir.
# Usage: tests/run.sh [--tui]   exit 0 = all passed (--tui adds pty-driven picker tests, ~15s)
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT=$(pwd)
BIN="$ROOT/dist/mac-cleanup"
DEV="$ROOT/src/main.sh"

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  \033[32mok\033[0m   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /' | head -40; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }   # check NAME 'test-expr' [context]
exists() { [ -e "$1" ]; }
gone()   { [ ! -e "$1" ]; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/mc-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

export NO_COLOR=1 MC_RUNNING_OVERRIDE=none LANG="${LANG:-en_US.UTF-8}"

# shellcheck source=tests/fixtures.sh
. "$ROOT/tests/fixtures.sh"

tree_sum() { (cd "$1" && find . -path ./.local -prune -o -print | sort | md5); }

FH="$WORK/home"
run_bin() { HOME="$FH" "$BIN" "$@" 2>&1; }

echo "== build & syntax"
synerr=""
for f in src/lib.sh src/main.sh src/core/*.sh src/modules/*.sh build.sh tests/run.sh tests/fixtures.sh dev/sandbox.sh; do
  bash -n "$f" 2>/dev/null || synerr="$synerr $f"
done
check "bash -n on all sources" '[ -z "$synerr" ]' "$synerr"
out=$(./build.sh --no-lint 2>&1); brc=$?
check "build.sh succeeds" '[ $brc -eq 0 ] && [ -x "$BIN" ]' "$out"
check "--version matches VERSION" '[ "$("$BIN" --version)" = "mac-cleanup $(tr -d "[:space:]" < VERSION)" ]'
check "built file has no dev/standalone regions" '! grep -qE "@(dev|standalone)-begin|lib\.sh\"$" "$BIN"'

echo "== unit"
unit=$(HOME="$WORK/unit" bash -c '
  . src/lib.sh
  echo "hkb=$(hkb 1536) $(hkb 0) $(hkb 1048576)"
  echo "parse=$(parse_size 1.2GB) $(parse_size 512MB) $(parse_size 0B) $(parse_size "45.6kB") $(parse_size "836MB (virtual 2.6GB)")"
  echo "sel=$(expand_sel "1 3 5-7 99" 10 | tr "\n" " ")"
  r=""; for p in "$HOME" "$HOME/" / relative "$HOME/a/../b" "$HOME/Library" "$HOME/Library/Caches/x"; do
    if guard_path "$p"; then r="$r 1"; else r="$r 0"; fi; done; echo "guard=$r"
  echo "fit=[$(fit "Cursor…é" 10)]"
')
check "hkb" '[[ "$unit" == *"hkb=1.5MB 0KB 1.0GB"* ]]' "$unit"
check "parse_size" '[[ "$unit" == *"parse=1258291 524288 0 45 856064"* ]]' "$unit"
check "expand_sel" '[[ "$unit" == *"sel=1 3 5 6 7 "* ]]' "$unit"
check "guard_path rejects home, /, relative, .., Library; allows children" '[[ "$unit" == *"guard= 0 0 0 0 0 0 1"* ]]' "$unit"
check "fit pads by characters" '[[ "$unit" == *"fit=[Cursor…é  ]"* ]]' "$unit"

echo "== CLI"
check "--list shows 19 modules" '[ "$("$BIN" --list | wc -l | tr -d " ")" -eq 19 ]'
"$BIN" --only nosuchmodule >/dev/null 2>&1; rc=$?
check "unknown module exits 1" '[ $rc -eq 1 ]'
"$BIN" --days abc >/dev/null 2>&1; rc=$?
check "non-numeric --days exits 1" '[ $rc -eq 1 ]'

M="caches,claude,downloads,projects,whatsapp"

echo "== dry-run"
make_home "$FH"
before=$(tree_sum "$FH")
out=$(run_bin --only "$M")
after=$(tree_sum "$FH")
check "dry-run deletes nothing" '[ "$before" = "$after" ]'
check "dry-run lists ~/Library/Caches" '[[ "$out" == *"~/Library/Caches"* ]]' "$out"
check "dry-run lists old Claude history (pick)" '[[ "$out" == *"pick"*"~/.claude/projects: 1 files older than 30d"* ]]' "$out"
check "dry-run lists old installers, not new ones" '[[ "$out" == *"older.zip"* && "$out" == *"old.dmg"* && "$out" != *"new.dmg"* ]]' "$out"
check "dry-run lists stale node_modules" '[[ "$out" == *"~/code/proj/node_modules"* ]]' "$out"
check "dry-run lists WhatsApp orphans" '[[ "$out" == *"Test Chat"*"unreferenced files"* ]]' "$out"
check "dry-run shows overview + summary" '[[ "$out" == *"OVERVIEW"* && "$out" == *"SUMMARY"* ]]' "$out"
dev_out=$(HOME="$FH" "$DEV" --only "$M" 2>&1 | sed 1d)
check "dev entry and built file produce the same report" '[ "$dev_out" = "$(printf "%s\n" "$out" | sed 1d)" ]' \
  "$(diff <(printf '%s\n' "$dev_out") <(printf '%s\n' "$out" | sed 1d) | head -20)"
out=$(run_bin --only "$M" -q)
check "--quiet prints only overview/summary" '[[ "$out" == *"OVERVIEW"* && "$out" != *"== Caches & logs =="* ]]' "$out"

echo "== apply --yes (safe tier only)"
make_home "$FH"
out=$(run_bin --apply --yes --only caches,claude,downloads,projects)
check "Caches child removed" 'gone "$FH/Library/Caches/com.example.app"' "$out"
check "Logs contents removed, dir kept" 'gone "$FH/Library/Logs/app" && exists "$FH/Library/Logs"' "$out"
check "Claude debug logs removed" 'gone "$FH/.claude/debug/d.log"' "$out"
check "pick items untouched (claude history, downloads, node_modules)" \
  'exists "$FH/.claude/projects/p/old.jsonl" && exists "$FH/Downloads/older.zip" && exists "$FH/code/proj/node_modules"' "$out"
check "result line + freed summary" '[[ "$out" == *"✔ Caches & logs"*"freed"* && "$out" == *"freed ≈"* ]]' "$out"
check "history log written" '[ -s "$FH/.local/state/mac-disk-cleanup/history.log" ]'

echo "== list items keep separate lists"
make_home "$FH"
mkf "$FH/Library/Application Support/FooApp/Cache/blob" 2048
out=$(printf '1\nn\n' | run_bin --apply --no-tui --only caches,apps)
check "~/Library/Caches item deletes its own children" 'gone "$FH/Library/Caches/com.example.app"' "$out"
check "unselected app-cache list item untouched" 'exists "$FH/Library/Application Support/FooApp/Cache/blob"' "$out"

echo "== report"
make_home "$FH"
mkf "$FH/Library/Application Support/Claude/claude-code/0.9/bin" 8192 old
mkf "$FH/Library/Application Support/Claude/claude-code/1.0/bin" 12288
out=$(run_bin --apply --yes --only claude,report)
check "superseded Claude bundle removed" 'gone "$FH/Library/Application Support/Claude/claude-code/0.9"' "$out"
check "report measures Application Support after deleting" \
  '[[ "$out" == *"12.0MB  ~/Library/Application Support/Claude"* && "$out" != *"20.0MB  ~/Library/Application Support/Claude"* ]]' "$out"
mkf "$FH/Library/Application Support/MobileSync/Backup/0000-AAAA/blob" 20480
mkf "$FH/Library/Application Support/BigApp/data" 15360
out=$(run_bin --only backups,report)
check "report leaves out what modules listed (iOS backup), keeps the rest" \
  '[[ "$out" == *"15.0MB  ~/Library/Application Support/BigApp"* && "$out" != *"MB  ~/Library/Application Support/MobileSync"* ]]' "$out"
others=$("$BIN" --list | awk '{print $1}' | grep -vx -e caches -e report | paste -sd, -)
out=$(run_bin --apply --yes --skip "$others")
check "non-interactive apply skips the report unless named" '[[ "$out" == *"SUMMARY"* && "$out" != *"Where else"* ]]' "$out"

echo "== running-app protection"
make_home "$FH"
out=$(HOME="$FH" MC_RUNNING_OVERRIDE=com.google.Chrome "$BIN" --apply --yes --only caches 2>&1)
check "cache of running app (Google) kept" 'exists "$FH/Library/Caches/Google/blob" && gone "$FH/Library/Caches/com.example.app"' "$out"
check "kept note shown" '[[ "$(HOME="$FH" MC_RUNNING_OVERRIDE=com.google.Chrome "$BIN" --only caches 2>&1)" == *"kept 1 (app running): Google"* ]]'

echo "== text picker"
make_home "$FH"
out=$(printf 'n\n' | run_bin --apply --no-tui --only downloads)
check "input 'n' deletes nothing" 'exists "$FH/Downloads/older.zip" && exists "$FH/Downloads/old.dmg"' "$out"
out=$(printf '1\n' | run_bin --apply --no-tui --only downloads)
check "input '1' deletes only the largest item" 'gone "$FH/Downloads/older.zip" && exists "$FH/Downloads/old.dmg" && exists "$FH/Downloads/new.dmg"' "$out"
out=$(printf 'q\n' | run_bin --apply --no-tui --only caches)
check "input 'q' skips the module" 'exists "$FH/Library/Caches/com.example.app" && [[ "$out" == *"skipped"* ]]' "$out"
out=$(run_bin --apply --no-tui --only caches < /dev/null)
check "EOF applies pre-selected safe items" 'gone "$FH/Library/Caches/com.example.app"' "$out"

echo "== WhatsApp orphan sweep"
make_home "$FH"
CHAT="$FH/$WA_REL/Message/Media/123@s.whatsapp.net"
out=$(printf '1\n' | run_bin --apply --no-tui --only whatsapp)
check "old unreferenced file deleted" 'gone "$CHAT/c/d/orphan-old.jpg"' "$out"
check "referenced file and thumbnail kept" 'exists "$CHAT/a/b/ref.jpg" && exists "$CHAT/a/b/ref-thumb.jpg"' "$out"
check "recent (<48h) unreferenced file kept" 'exists "$CHAT/e/f/orphan-new.jpg"' "$out"
make_home "$FH" bad-db
out=$(printf 'a\n' | run_bin --apply --no-tui --only whatsapp)
check "sanity stop: DB paths not matching disk deletes nothing" \
  'exists "$CHAT/c/d/orphan-old.jpg" && exists "$CHAT/a/b/ref.jpg" && [[ "$out" == *"Safety stop"* ]]' "$out"

echo "== standalone module"
make_home "$FH"
out=$(HOME="$FH" "$ROOT/src/modules/caches.sh" 2>&1)
check "src/modules/caches.sh runs alone" '[[ "$out" == *"== Caches & logs =="* && "$out" != *"Claude"* ]]' "$out"
out=$(HOME="$FH" "$BIN" claude 2>&1)
check "positional module name works with the built file" '[[ "$out" == *"Claude"* && "$out" != *"== Caches & logs =="* ]]' "$out"

if [ "${1:-}" = "--tui" ]; then
  # Drives the full-screen picker through a pseudo-terminal (script(1)) with timed keystrokes.
  echo "== TUI (pty)"
  make_home "$FH"
  log="$WORK/tui.log"
  # module picker: Enter · item picker: space (tick largest) · Enter · confirm: y
  (sleep 2; printf '\r'; sleep 1; printf ' '; sleep 1; printf '\r'; sleep 1; printf 'y'; sleep 3) |
    HOME="$FH" TERM=xterm-256color script -q "$log" "$BIN" --apply --only downloads >/dev/null 2>&1
  check "TUI: tick + enter + y deletes only the ticked item" 'gone "$FH/Downloads/older.zip" && exists "$FH/Downloads/old.dmg"' \
    "$(tr '\r' '\n' < "$log" | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' | tail -8)"
  check "TUI: one result line left on the main screen" 'grep -q "✔ Old installers" "$log"'
  check "TUI: pickers and apply share one alternate-screen session" \
    '[ "$(grep -o $'"'"'\x1b\[?1049h'"'"' "$log" | wc -l | tr -d " ")" -eq 1 ]'
  check "TUI: deletion shown live in the picker (busy/gone rows, Deleting footer)" \
    'grep -q "Deleting" "$log" && grep -q "gone" "$log"'
  check "TUI: result line printed after leaving the alternate screen" \
    '[[ "$(cat "$log")" == *$'"'"'\x1b[?1049l'"'"'*"✔ Old installers"* ]]'
  (sleep 2; printf '\003'; sleep 2) |
    HOME="$FH" TERM=xterm-256color script -q "$log" "$BIN" --apply --only downloads >/dev/null 2>&1
  check "TUI: Ctrl-C restores the screen and cursor" 'grep -q $'"'"'\x1b\[?1049l'"'"' "$log" && grep -q $'"'"'\x1b\[?25h'"'"' "$log"'
  check "TUI: Ctrl-C deletes nothing" 'exists "$FH/Downloads/old.dmg"'
fi

echo
printf 'passed: %d  failed: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
