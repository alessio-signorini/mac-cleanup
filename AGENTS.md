# AGENTS.md

Orientation for coding agents. Read this first; open [docs/BUILD.md](docs/BUILD.md) (full spec)
only for the section you need. User-facing docs are [README.md](README.md) (GitHub landing page)
and [docs/USAGE.md](docs/USAGE.md) (full reference); contributor docs in
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## What this is

`mac-cleanup`: a macOS disk-cleanup CLI written in **bash 3.2** (stock `/bin/bash`). It scans
~19 areas (caches, WhatsApp, Docker, Xcode, Claude…), shows a dry-run report by default, and
with `--apply` lets the user tick what to delete in a full-screen checkbox picker.
`src/` is modular; `./build.sh` concatenates it into one file, `dist/mac-cleanup` (gitignored).

## Commands

```
./build.sh                          # build dist/mac-cleanup (+ shellcheck if installed)
tests/run.sh                        # test suite; builds first; fake $HOME
tests/run.sh --tui                  # + pty-driven picker tests (~15s more)
dev/sandbox.sh [ARGS]               # run src/main.sh against a fake HOME in a Seatbelt sandbox
dev/sandbox.sh --exec tests/run.sh  # tests inside the sandbox
./src/main.sh [ARGS]                # dev entry = dist/mac-cleanup; ./src/modules/<m>.sh runs one module
```

Always finish a change with `./build.sh && tests/run.sh` (add `--tui` when touching
`60-picker.sh`, `70-runner.sh` or `10-ui.sh`).

## Safety rules for agents (this tool deletes files)

- **Never run `--apply` against the real `$HOME`.** Use `dev/sandbox.sh …` or `HOME=<tmpdir>`.
  Dry-run (no `--apply`) against the real home is read-only and OK.
- `docker`, `brew`, `xcrun simctl`, `tmutil`, `sudo` actions affect real state regardless of
  `$HOME`. The sandbox blocks them; the test suite only runs file-based modules.
- Every deletion must go through the guarded deleters in `src/core/50-actions.sh`
  (`del_path`, `del_contents`, `del_listed`, …); never `rm` in a module.

## Layout

```
src/core/00-env.sh      constants, defaults, MC_ALL_MODULES (module order; build.sh reads it)
src/core/10-ui.sh       colors, TTY detection, progress line, emit/RES_BUF (buffered output)
src/core/20-size.sh     kb, hkb, parse_size, kb_meas, free_kb, jxa (JSON via osascript)
src/core/30-apps.sh     running-app detection (APP_TABLE, app_running, group_running)
src/core/40-plan.sh     item/note store + module API (safe_clear, pick_path, mc_item, note…)
src/core/50-actions.sh  guarded deleters (guard_path)
src/core/60-picker.sh   TUI picker (alternate screen) + numbered text fallback
src/core/70-runner.sh   phases: scan → report | review+apply → report modules → summary
src/core/80-cli.sh      flags, usage, mc_main
src/modules/*.sh        one file per area; caches.sh is the reference module
src/lib.sh, main.sh     dev loader / dev entry (regions stripped by build.sh)
tests/run.sh            test suite; tests/fixtures.sh = make_home (fake $HOME)
dev/sandbox.sh          sandbox-exec wrapper; fake home in .sandbox/ (gitignored)
legacy/                 v1/v2 scripts, read-only reference for parity
```

## Architecture in brief

- **Modules never print or delete.** `<m>_scan` only records items (`safe_*` = pre-selected,
  regenerable; `pick_*` = user data, never auto-applied) and notes. The runner owns output,
  selection and deletion. Actions are function names called as `"$action" "$id"`.
- Module contract: `<m>_meta` sets `MOD_TITLE` (+ `MOD_OPTIN=1` / `MOD_REPORT=1`), `<m>_scan`,
  optional `<m>_del_*` actions, and a `# @standalone-begin/end` block. New module: copy
  `caches.sh`, add the name to `MC_ALL_MODULES`.
- State is in parallel global arrays (`IT_*`, `NT_*`, `MD_*`, `PK_*`); no associative arrays.
- `--apply` in a TUI: `run_apply` sets `TUI_HOLD=true` and keeps one alternate-screen session
  for the module picker and item pickers. Deletion is animated inside the confirmed item picker
  (`apply_module` sets `PK_ST[row]` busy/ok/fail, `ap_foot` fills the footer; `RV_ROW` maps
  item → row). Result lines go through `emit` into `RES_BUF`, printed by `tui_release`.
- Report modules (`report`): with `--apply` they're scanned after applying, only if named or the
  user presses y at a 10s prompt (`want_report`). They subtract what other modules listed but
  the user kept (`plan_covered`), so they show space nobody reviewed.
- Never call state-changing helpers via `$(…)` (subshell): `mc_listfile` sets `LIST_FILE`.

## bash 3.2 constraints (docs/BUILD.md §2, §13)

No `declare -A`, `mapfile`, `${v,,}`, `local -n`, negative indexes, `&>>`, fractional
`read -t`, or `set -u`/`set -e` (only `pipefail`). Use BSD tool flags (`du -skx`, `stat -f`).
Quote everything (paths have spaces). Brace a variable before a multibyte char (`"${x}…"`).
Scans run in the main shell: feed loops with `done < <(cmd)`, never `cmd | while`, or the
items are lost in a subshell. Pad user text with `padr`/`fit` (printf pads bytes).

## Keeping docs in sync

Behavior changes: update docs/BUILD.md (spec), docs/USAGE.md (options, flow, safety), README.md
(only if the overview, quick usage or module table changes), docs/DEVELOPMENT.md and this file
when the layout, commands or core mechanisms change. Bump `VERSION` for releases only.
