# BUILD.md — mac-cleanup v3

This document is the complete specification for turning `legacy/mac-disk-cleanup-v2.sh`
(a single 50KB bash script) into a modular, testable CLI that is **built into one
executable file**. It is written so an agent can implement it end-to-end from a
single prompt ("build BUILD.md"). Follow it literally; where it says MUST, it is a
hard requirement.

Status: implemented. If you are re-building from scratch, follow §12 (Build order);
if you are extending, read §4–§7 and use `src/modules/caches.sh` as the reference module.

---

## 1. Goals

1. **Modules.** One file per cleanup area (WhatsApp, Docker, caches, Xcode…). Each module
   makes sense on its own and can be run on its own:
   - built: `dist/mac-cleanup whatsapp --apply`
   - dev:   `./src/modules/whatsapp.sh --apply`
2. **Coordinated output.** Scan everything first, then review module by module. In an
   interactive terminal each module is reviewed in a full-screen checkbox picker (alternate
   screen). When the user confirms, the picker disappears, the selection is applied, and only
   a single result line per module remains on the main screen.
3. **Single executable.** `./build.sh` concatenates core + modules + entry point into
   `dist/mac-cleanup` (one bash file, no external files needed at runtime).
4. **No dependencies.** Runtime uses only what ships with macOS 26+: `/bin/bash` 3.2, BSD
   coreutils (`find du df stat date awk sed sort tr xargs`), `tput stty`, `sqlite3`,
   `osascript` (JavaScript for Automation, used to parse JSON), `plutil`, `/usr/libexec/PlistBuddy`,
   `xxd`, `mdfind`, `lsappinfo`, `qlmanage`, `tmutil`. Third-party CLIs (`docker`, `colima`,
   `brew`, `npm`, `rustup`, `xcrun`…) are used **only if present** and only by the module
   that cleans them. `/usr/bin/python3` MUST NOT be used (it is a stub without Xcode CLT).
   `shellcheck` is an optional *build-time* linter only.

Non-goals: config files, launchd installation, a GUI app, Linux support, installing the binary.

---

## 2. Hard constraints (bash 3.2 compatibility)

`/bin/bash` on macOS is 3.2.57. All code MUST run on it. Forbidden:

| Forbidden | Use instead |
|---|---|
| `declare -A` (associative arrays) | parallel indexed arrays, or awk over a temp file |
| `mapfile` / `readarray` | `while IFS= read -r line; do arr+=("$line"); done < file` |
| `${var,,}` `${var^^}` | `tr '[:upper:]' '[:lower:]'` or awk `tolower` |
| `read -t 0.1` (fractional) | `read -t 1` (integer seconds only) |
| `${arr[-1]}` negative index | `${arr[$((${#arr[@]}-1))]}` |
| `&>>`, `|&` | `>>file 2>&1`, `2>&1 |` |
| `set -u` | not used (empty arrays break under `-u` on 3.2) |
| `local -n` namerefs, `declare -g` | globals with documented names |
| `$EPOCHSECONDS`, `printf '%(...)T'` | `date +%s` |
| GNU-only flags (`du -b`, `stat -c`, `find -printf`, `sed -i` without arg, `sort -h`) | BSD forms: `du -skx`, `stat -f`, `find … -exec stat -f`, avoid `-i` |

Other rules:
- `set -o pipefail` only. No `set -e`.
- Quote every expansion. Paths contain spaces (`Application Support`, `Group Containers`).
- Every function that deletes MUST go through the guarded deleters in `core/50-actions.sh`.
- Never `eval` user/disk-derived strings. Actions are **function names**, called as
  `"$action" "$id"`.
- Must refuse to run as root (system parts use `sudo` internally).
- `bash -n` must pass for every file and for `dist/mac-cleanup`.
- If `shellcheck` exists, `shellcheck -s bash -S warning dist/mac-cleanup` must pass
  (directives to disable SC2034/SC2154 for cross-file globals are allowed at file top).

---

## 3. Repository layout

```
BUILD.md                this file
README.md               user documentation
VERSION                 semantic version, e.g. 3.0.0
build.sh                produces dist/mac-cleanup
.gitignore              dist/
src/
  lib.sh                dev loader: sources src/core/*.sh in lexical order
  main.sh               dev entry: sources lib.sh + every module, calls mc_main "$@"
  core/
    00-env.sh           constants, defaults, MC_ALL_MODULES (module order)
    10-ui.sh            colors, tty detection, print helpers, progress line
    20-size.sh          kb, hkb, parse_size, kb_meas, free_kb, jxa (JSON via osascript)
    30-apps.sh          running-app detection (APP_TABLE, app_running, bundle_running, group_running)
    40-plan.sh          the item/notes store + module-facing API (mc_item, safe_clear, pick_path, note…)
    50-actions.sh       guarded deleters (del_path, del_contents, del_listed, …)
    60-picker.sh        full-screen checkbox picker (TUI) + numbered text fallback
    70-runner.sh        phases: scan → report|review → apply → summary
    80-cli.sh           argument parsing, usage, mc_main
  modules/
    caches.sh orphans.sh apps.sh editors.sh claude.sh browsers.sh whatsapp.sh xcode.sh
    docker.sh dev.sh runtimes.sh projects.sh brew.sh gimp.sh downloads.sh models.sh
    backups.sh system.sh report.sh
tests/
  run.sh                self-contained test suite (fake $HOME), exit 0 = pass
  fixtures.sh           make_home: the fake $HOME used by run.sh and dev/sandbox.sh
dev/
  sandbox.sh            runs the tool/tests against a fake $HOME under a Seatbelt sandbox
legacy/
  mac-disk-cleanup-v2.sh   reference implementation (read-only; used for parity checks)
  cleanup.sh               v1 (historical)
dist/                   build output (gitignored)
```

Module order (= scan/review order) is defined once, in `src/core/00-env.sh`:

```
MC_ALL_MODULES="caches orphans apps editors claude browsers whatsapp xcode docker dev runtimes projects brew gimp downloads models backups system report"
```

---

## 4. Architecture

### 4.1 Phases

```
mc_main "$@"
  cli_parse            flags → globals; positional module names → ONLY
  mc_init              refuse root, mktemp MC_TMP, traps, ui_init, apps_init, resolve active modules
  disk_banner          "Disk: 412Gi used of 460Gi, 48Gi free (90%)" (+ DRY-RUN banner, + running apps warning)
  scan_all             for each active module: MOD_CUR=m; ${m}_scan   (progress line on stderr)
  then ONE of:
    dry-run            print each module section (items + notes), overview table, summary
    --apply --yes      apply pre-selected (safe) items of every module; one result line each
    --apply (TUI)      module picker → per-module item picker → apply → one result line each
    --apply (no TUI)   per-module numbered list + typed selection → apply → one result line each
  report modules       (MOD_REPORT=1, i.e. `report`) print their notes at the end, any mode
  summary              freed / free-space delta / history log path
```

Modules **never print and never delete directly**. During scan they only *describe*
candidates (items) and observations (notes) through the API in §5. The runner owns all
output, selection and deletion. This is what makes the collapsed, coordinated output
possible and makes a future GUI possible.

### 4.2 Tiers

| Tier | Meaning | Pre-selected | Applied by `--yes` |
|---|---|---|---|
| `safe` | regenerable caches/logs; no user cost beyond re-download/rebuild | yes | yes |
| `pick` | user data or slow/expensive to rebuild | no | **never** |
| notes  | observations (`info warn skip tip report`) — not deletable | – | – |

Anything destructive that v2 auto-confirmed under `--yes` MUST be a `pick` item in v3
(colima VM rebuild, Time Machine snapshot thinning, `docker image prune -a`).

### 4.3 Running modules standalone

Every module file ends with this block (exactly; `build.sh` strips the marked region):

```bash
# @standalone-begin
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
  mc_main --only <module> "$@"
fi
# @standalone-end
```

`mc_main` only runs modules whose `<m>_scan` function is defined, so a standalone module
works with just the core loaded.

---

## 5. Core API (contract between core and modules)

### 5.1 Module file contract

A module named `foo` lives in `src/modules/foo.sh` and defines:

| Function | Required | Purpose |
|---|---|---|
| `foo_meta` | yes | sets `MOD_TITLE` (display name), `MOD_OPTIN` (1 = only runs when named via `--only`/positional or enabled by its flag, e.g. `--system`), `MOD_REPORT` (1 = notes-only report module printed at the end) |
| `foo_scan` | yes | discovers items/notes using the API below. MUST NOT delete. MUST NOT print (except via `note`). May run read-only commands and write temp files under `$MC_TMP`. |
| `foo_<action>` | optional | custom action functions `foo_<verb> ID` returning 0 on success. Called only at apply time. Prefix with the module name. |

All module-private helpers and temp files MUST be prefixed with the module name
(`whatsapp_orphan_scan`, `$MC_TMP/whatsapp_refs`).

### 5.2 Globals available to modules

`H` (=$HOME), `AS` ("$H/Library/Application Support"), `DAYS`, `MEDIA_DAYS`, `APPLY`, `ASSUME_YES`,
`RECLAIM_DOCKER_VM`, `MC_TMP` (private temp dir), `MC_SELF` (absolute path of the running
script), color vars `BOLD DIM RED GRN YLW CYN RST`.

### 5.3 Item store (core/40-plan.sh)

Parallel arrays, one entry per item (index `i`):

| Array | Content |
|---|---|
| `IT_MOD` | module id |
| `IT_TIER` | `safe` / `pick` |
| `IT_ID` | argument passed to the action (a path, a docker id, a list file…) |
| `IT_LABEL` | human label (already `pretty`-fied, `~` for $HOME) |
| `IT_KB` | estimated size in KB (integer; 0 if unknown) |
| `IT_SZ` | optional display size override (e.g. `—`, `≈1.2GB`) |
| `IT_ACT` | action function name |
| `IT_MEAS` | optional measure target: a path, or `@<listfile>` (sum of listed paths). If set, freed = size before − size after, measured at apply time. If empty, freed = `IT_KB` on success. |
| `IT_GRP` / `IT_GSEQ` | group heading text and group sequence number (display grouping) |
| `IT_SEL` | 1 selected / 0 not (init: safe→1, pick→0) |
| `IT_RES` | apply result: `ok` / `fail` / empty |

Notes: `NT_MOD NT_KIND NT_TEXT` (kinds: `info warn skip tip report`).

### 5.4 Functions modules call

```
mc_group TEXT                                  start a display group (heading) for subsequent items
mc_item TIER ID LABEL KB ACTION [SZ] [MEAS]    generic item
safe_clear PATH LABEL [MINKB=1024]             safe: delete *contents* of dir (action del_contents, MEAS=PATH); skipped if missing or < MINKB
safe_remove PATH LABEL                         safe: remove path entirely (del_path, MEAS=PATH); skipped if missing
safe_clear_children DIR LABEL                  safe: remove each child of DIR except those owned by running apps (one aggregated item, del_listed over a list file); adds a `skip` note listing kept children
safe_cmd ID LABEL ACTION [KB] [SZ] [MEAS]      safe: run a command-type action (e.g. qlmanage reset, brew cleanup)
pick_path PATH LABEL [KB] [ACTION=del_path]    pick: delete a path (KB computed if empty; MEAS=PATH)
pick_item ID LABEL KB ACTION [SZ] [MEAS]       pick: generic
note KIND TEXT                                 attach a note to the current module
note_kept "a b c"                              one condensed `skip` note: "kept N (app running): a b c … +M more"
report_top DIR [N=8]                           adds `report` notes for the N largest children of DIR
mc_listfile                                    prints a fresh unique list-file path under $MC_TMP
```

Text helpers (`core/10-ui.sh`): `padr TEXT W`, `padl TEXT W`, `fit TEXT W` (truncate + pad to
exactly W characters). bash `printf '%-20s'` pads by **bytes**, so any column containing
user text (chat names, titles with `…`) MUST use these instead.

Size helpers (`core/20-size.sh`): `kb PATH` (du -skx, 0 if missing), `hkb KB` (→ `1.2GB`),
`hsz PATH`, `parse_size "1.2GB"` (→ KB; accepts docker/brew strings, decimal units treated as
binary), `kb_meas MEAS`, `free_kb`, `jxa JSONFILE 'JS body using d'` (parses JSON with
`osascript -l JavaScript`, returns the body's string result).

Running-app helpers (`core/30-apps.sh`): `app_running KEY` (KEY = Application Support folder
name, bundle id, or app name; uses `APP_TABLE` + three signals: lsappinfo bundle ids, process
names, `/X.app/Contents/MacOS/` paths), `bundle_running BUNDLEID`, `group_running GROUPID`,
`running_app_names`. Env `MC_RUNNING_OVERRIDE` (any value, `none` = nothing running) replaces
detection with a fixed newline-separated bundle-id/process list — used by tests.

Misc (`core/10-ui.sh`): `pretty PATH` (~ for $HOME), `urldecode`, `mc_log TEXT` (appends
to history log, only when `APPLY=true`).

### 5.5 Deleters (core/50-actions.sh)

All take one argument (the item ID) and return 0 on success:

| Action | Behavior |
|---|---|
| `del_path P` | `rm -rf P` after `guard_path` |
| `del_contents D` | remove every child of D (incl. dotfiles), keep D |
| `del_listed LIST` | `del_path` each line of the list file |
| `del_listed_contents LIST` | `del_contents` each directory in the list file |
| `del_older_than_days D` | delete files in D with mtime older than `$DAYS`, then empty dirs |

`guard_path P` MUST reject: empty, relative paths, paths containing `/../` or ending in `/..`,
and these exact paths (after stripping a trailing `/`): `/`, `$H`, `$H/Library`, `$AS`,
`$H/Library/Caches`, `$H/Library/Containers`, `$H/Library/Group Containers`, `$H/Documents`,
`$H/Desktop`, `$H/Downloads`, `/Applications`, `/Library`, `/System`, `/Users`, `/private`.
A rejected path is a failed item (`IT_RES=fail`) and is logged, never deleted.
(`del_contents` on `$H/Library/Caches` is allowed — it guards each child, not the parent.)

---

## 6. Output and interaction spec

### 6.1 Banner (all modes)

```
mac-cleanup 3.0.0 — Disk: 412Gi used of 460Gi, 48Gi free (90%)
DRY-RUN — nothing will be deleted. Re-run with --apply.          (dry-run only)
! running now (their caches will be skipped): Code, Vivaldi       (if any)
```

### 6.2 Scan progress

On a TTY (stderr), a single self-overwriting line: `Scanning  7/19  Xcode…`. Cleared when done.
Nothing else is printed during scan. (The `system` module may trigger a `sudo` password
prompt; the progress line is cleared before calling `sudo -v`.)

### 6.3 Dry-run (default)

For each module that has items or notes (unless `-q`):

```
== Xcode ==                                        safe 4.1GB · review 18.2GB
     safe   3.9GB  Xcode DerivedData
     safe       -  delete unavailable simulators
  Simulator runtimes (5-10GB each; reinstall via Xcode > Settings > Components)
     pick   8.1GB  iOS 18.2 (22C150)  last used 2025-01-10
  · kept 2 (app running): Code Vivaldi
  ! warning text
  i info text
```

Unknown sizes display as ASCII `-` (never `—`: multibyte characters break byte-based padding).

Then the overview table (modules without items are folded into one dim line):

```
== OVERVIEW ==
  MODULE                               SAFE     REVIEW
  Caches & logs                       3.2GB          -
  Xcode & simulators                  4.1GB     18.2GB
  ...
  TOTAL                               9.8GB     41.0GB
  nothing to clean: Browsers, GIMP, iOS device backups
```

Then `report` module notes, then summary (`safe tier ≈ X`, `review lists up to ≈ Y`,
`Re-run with --apply to act.`, `free now: …`).

### 6.4 Apply, interactive TUI (stdin+stdout are TTYs, not `--no-tui`, `TERM`≠dumb)

1. **Module picker** (alternate screen): rows = modules with ≥1 item, label = title, size
   column = `safe X · review Y`. Modules with items are pre-ticked. Enter = continue,
   q = quit (nothing applied, go to summary).
2. For each ticked module: **item picker** (alternate screen):
   - header: module title, `safe X · review Y`, then up to N notes (N = max(3, rows/4)),
     each truncated to screen width.
   - body: group heading rows (not selectable) and item rows
     `> [x]   3.9GB  label   safe|pick`; scrolls; cursor skips heading rows.
   - footer: `selected: 5 items, 4.0GB` and the key help line.
   - keys: ↑/↓ or k/j move, PgUp/PgDn, Home/End or g/G, **space** toggle (and move down),
     **a** all, **n** none, **Enter** confirm, **q** / Esc skip module, **?** toggles help.
   - On Enter, if the selection contains any `pick` item: footer asks
     `Delete N picked items (X)? y/N` — only `y` confirms.
3. After the picker closes (back on the main screen), the selection is applied with a
   progress line `applying 3/12  label…`, then replaced by **one result line**:

```
  ✔ Caches & logs                freed 3.2GB  (14 item(s))
  ✔ WhatsApp                     freed 1.1GB  (3 item(s)) · 1 failed
  – Xcode & simulators           skipped  (safe 3.9GB · review 18.2GB)
  · nothing to clean: Homebrew, GIMP
```

   Rules: a module whose confirmed selection is empty is `skipped`. Modules with no items are
   folded into the single `nothing to clean:` line, **unless** they have `warn` notes (e.g. the
   WhatsApp safety stop): then they get their own `·` line followed by those warnings.
   `-v/--verbose` additionally prints each applied item and the module's notes under it.
4. Ctrl-C at any time: restore terminal, print `interrupted`, print summary of what was
   already applied, exit 130.

The terminal MUST always be restored (stty, cursor, alternate screen) via `trap … EXIT INT TERM`.

### 6.5 Apply, text fallback (no TTY or `--no-tui`)

For each module with items: print the dry-run style section but with numbered rows and
checkboxes (`[x]  3)   3.9GB  Xcode DerivedData`), then prompt:

```
? Enter=apply [x] items · numbers (1 3 5-7) = exactly those · a=all · n=none · q=skip
```

Read one line from stdin. EOF counts as Enter (so non-interactive runs apply only
pre-selected safe items). If stdin is a TTY and the selection includes `pick` items,
ask `Delete N picked items (X)? [y/N]`. Then apply and print the result line.

### 6.6 `--apply --yes`

No prompts. For each module: apply pre-selected items (safe tier only) and print the result
line. Pick items are never applied.

### 6.7 Summary

```
== SUMMARY ==
  freed ≈ 6.4GB   (free space change: +6.1GB; APFS may take a minute to report)
  free now: 54Gi (88% used)
  history: ~/.local/state/mac-disk-cleanup/history.log
```

### 6.8 History log

`~/.local/state/mac-disk-cleanup/history.log` (dir created only with `--apply`). One line per
applied item: `YYYY-MM-DD HH:MM:SS  <module>  ok|fail  <freed>  <label>  [<id>]`, plus a run
start and run complete line.

---

## 7. CLI

```
mac-cleanup [MODULE...] [options]

  (no options)          dry-run report of all modules
  --apply               review and delete (interactive)
  --apply --yes, -y     non-interactive: safe tier only (cron/launchd)
  --only a,b            run only these modules (same as positional MODULE args)
  --skip a,b            skip modules
  --days N              idle threshold for projects/downloads/editor workspaces/Claude history (default 30)
  --media-days N        WhatsApp media age threshold (default 90; 0 = all media)
  --system              include the sudo `system` module
  --reclaim-docker-vm   offer a colima VM rebuild (pick item) in the docker module
  --no-tui              numbered text prompts instead of the full-screen picker
  -q, --quiet           dry-run: overview table + summary only
  -v, --verbose         apply: also print per-item results and notes
  --list                list modules (id, title, opt-in) and exit
  --version             print version and exit
  -h, --help            usage
```

Unknown options or module names → message + exit 1. `--days`/`--media-days` must be
non-negative integers. Exit codes: 0 success, 1 usage error, 130 interrupted.

---

## 8. Build (build.sh)

`./build.sh [--no-lint]` MUST:

1. Read version from `VERSION`.
2. Write `dist/mac-cleanup`:
   - `#!/bin/bash` + a generated header comment (name, version, build date, "generated — edit src/").
   - Every `src/core/*.sh` in lexical order, then every module in `MC_ALL_MODULES` order (read
     the list from `src/core/00-env.sh` with sed), then `src/main.sh`.
   - Strip from every file: its shebang line, regions between `# @standalone-begin` and
     `# @standalone-end`, and regions between `# @dev-begin` and `# @dev-end`.
   - Replace the `MC_VERSION=` line with the version from `VERSION`.
   - Final line calls `mc_main "$@"` (comes from main.sh, outside the dev region).
3. `chmod +x`, run `bash -n dist/mac-cleanup`, run `dist/mac-cleanup --version` and check it
   prints the version.
4. Run `shellcheck` on the output if installed (skip with a note otherwise, or with `--no-lint`).
5. Print the output path and size. Never install anything.

---

## 9. Module specs

Port each module from the matching section of `legacy/mac-disk-cleanup-v2.sh`
(`if want <name>` blocks). Preserve all safety checks (running-app skips, thresholds,
prunes, sanity stops). Changes from v2 are marked **CHANGE**.

| Module | Title | v2 section | Items (tier) | Notes |
|---|---|---|---|---|
| caches | Caches & logs | `want caches` | `~/Library/Caches` children except running apps (safe, `safe_clear_children`); `~/Library/Logs`, Mail Downloads, iPhone/iPad .ipsw, Trash (safe_clear); each `Containers/*/Data/Library/Caches` and `Group Containers/*/Library/Caches` whose app isn't running (safe_clear); QuickLook reset (safe_cmd `caches_ql_reset`, SZ `—`) | skip note for kept caches |
| orphans | Leftovers of uninstalled apps | `want orphans` | containers / group containers with no installed app from same vendor, ≥1MB (pick) | skip whole module with a skip note if Spotlight returns < 20 apps; tip about Full Disk Access |
| apps | App caches | `want apps` | **CHANGE** one safe item *per app root* (e.g. `Code`, `Google`, `Slack`), id = list file of cache dirs, action `del_listed_contents`, MEAS `@list`; krisp leftover installers + logs (safe), krisp models (pick); GoogleUpdater crx_cache + old versions (safe) | skip note for running roots |
| editors | Editors (VS Code, Cursor, Windsurf) | `want editors` | per editor: logs (safe), superseded extensions not in extensions.json (safe); groups "<App> — orphaned workspaces (folder gone)" and "<App> — idle > Nd, > 10MB" (pick) | skip note if editor running (logs/extensions skipped, workspaces still listed); report notes: globalStorage top 5, Local History size |
| claude | Claude (desktop + Claude Code) | `want claude` | old Claude Code binaries (safe; keep active symlink target and newest); `~/.claude/debug`, `shell-snapshots` (safe); `projects/file-history/todos` files older than DAYS (pick, `del_older_than_days`, KB = size of old files); desktop bundled `claude-code*` superseded (safe); Cowork sessions idle > DAYS (pick; never the one containing `MC_SELF`); Cowork VM image (pick; only when Claude not running) | skip note when Claude running |
| browsers | Browsers | `want browsers` | Chrome on-device model `OptGuideOnDeviceModel` (pick, only if Chrome not running) | tip with the `defaults write` command; report notes: profile sizes |
| whatsapp | WhatsApp | `want whatsapp` | logs (safe, not running); group "Unreferenced media (no message points to it)" per chat (pick, `whatsapp_del_orphans JID`, MEAS chat dir); group "Media older than Nd (or all media if 0)" top 30 chats ≥10MB (pick, `whatsapp_del_old DIR`, MEAS DIR) | **CHANGE** if WhatsApp running: no media items, list the candidates as report notes + warn note "quit WhatsApp to delete". Keep the orphan sanity stop exactly (DB refs > 0 but 0 match on disk → abort sweep with warn); **CHANGE** add a second stop: DB references 0 media but files exist on disk → abort. Files touched < 48h never orphan candidates. Warn (only if media items were added): deleted media may not be re-downloadable; tip: WhatsApp's own Manage Storage |
| xcode | Xcode & simulators | `want xcode` | DerivedData, CoreSimulator caches, Previews, DocumentationCache, XCPGDevices (safe); "delete unavailable simulators" (safe_cmd); simulator runtimes (pick, `xcode_del_runtime`); simulator devices > 50MB (pick, `xcode_del_sim`); DeviceSupport folders (pick); archives (pick) | **CHANGE** JSON parsed with `jxa`, not python3 |
| docker | Docker / colima | `want docker` | stopped containers (pick, `docker_del_container`; **CHANGE** age column uses `{{.RunningFor}}` — v2's `{{.CreatedSince}}` is not a container field, so v2 never listed any); dangling volumes (pick, `docker_del_volume`); **CHANGE** unused images `docker image prune -af` (pick, KB from `docker system df` Images reclaimable); build cache prune (safe, KB from Build Cache reclaimable); network prune (safe, SZ `—`); colima fstrim (safe, MEAS `~/.colima/_lima`); **CHANGE** colima rebuild (pick, only with `--reclaim-docker-vm`) | info note with VM disk size; skip note if docker not reachable |
| dev | Dev toolchain caches | `want dev` | npm/pnpm/yarn/pip/uv/go/pod caches via their own clean commands (safe_cmd, KB = cache dir size, MEAS = cache dir → **CHANGE** accurate freed); bun, cargo registry cache/src, cargo git checkouts, Gradle (safe_clear); `~/.cache/*` ≥10MB (pick); Go module cache (pick, `dev_del_gomod`) | |
| runtimes | Language runtime versions | `want runtimes` | rbenv/pyenv/nvm versions other than current (pick); non-default rust toolchains (pick, `runtimes_del_rust`) | **CHANGE** exact version match: keep `n == cur` or `n` starting with `cur.` (nvm alias `20` keeps `v20.*`), not substring |
| projects | Stale project artifacts | `want projects` | artifact dirs (node_modules, .venv, venv, .next, target…) in projects idle > DAYS, ≥10MB (pick) | same prunes/validations as v2 |
| brew | Homebrew | `want brew` | `brew cleanup --prune=all -s` (safe_cmd, KB parsed from `brew cleanup -n` "free approximately X"); `brew autoremove` (safe_cmd, only if orphans > 0) | |
| gimp | GIMP | `want gimp` | tmp + swap (safe); old version profiles (pick) | skip note if running |
| downloads | Old installers & archives | `want downloads` | dmg/pkg/iso/xip/ipsw/zip/tar.gz/tgz in Downloads/Desktop (depth 2) > DAYS, > 5MB; `/Applications/Install macOS*.app` (pick) | |
| models | Local LLM models | `want models` | `~/.omlx/cache` (safe); each model dir with last-used date (pick) | |
| backups | iOS device backups | `want backups` | each backup with device name + date via PlistBuddy (pick) | |
| system | System-level (sudo) | `want system` | `/Library/Caches`, DiagnosticReports, system CoreSimulator caches (safe, `system_del_contents` via sudo); rotated logs > 7d (safe_cmd); **CHANGE** thin Time Machine local snapshots (pick) | MOD_OPTIN=1, enabled by `--system`; info notes: local snapshot list |
| report | Where else is space going | `want report` | none | MOD_REPORT=1; report notes: top 6 of Application Support/Containers/Group Containers, files > 1GB in home (excluding colima, omlx, MobileSync, Mobile Documents) |

---

## 10. Tests (tests/run.sh)

Plain bash, no framework. Creates a fake `$HOME` under `$TMPDIR`, exports `HOME`,
`MC_RUNNING_OVERRIDE=none`, `NO_COLOR=1`, and runs the **dev** entry (`src/main.sh`) and the
**built** file. MUST NOT touch the real home or run third-party clean commands: only use
modules that act on files under `$HOME` (`caches claude editors whatsapp downloads projects gimp`).
Required cases:

1. Every `src/**/*.sh` passes `bash -n`; `build.sh --no-lint` succeeds; `dist/mac-cleanup --version` matches `VERSION`.
2. Unit: `hkb`, `parse_size`, `expand_sel`, `guard_path` (rejects `$HOME`, `/`, relative, `..`).
3. Dry-run on the fake home lists the expected items and deletes nothing (checksum of the tree before/after).
4. `--apply --yes --only caches,claude` deletes safe items (Caches child, Logs content, Claude debug) and **does not** delete pick items (old `~/.claude/projects` files).
5. Running-app skip: with `MC_RUNNING_OVERRIDE=com.google.Chrome`, `~/Library/Caches/Google` survives `--apply --yes --only caches`.
6. WhatsApp orphan sweep (fake `ChatStorage.sqlite` built with `sqlite3`): with input `1` piped to `--apply --no-tui --only whatsapp`, the unreferenced old file is deleted, the referenced file and the < 48h unreferenced file survive. Sanity stop: when no DB path matches disk, nothing is deleted.
7. Standalone module: `src/modules/caches.sh` (dry-run) prints the Caches section and not other modules.
8. Text fallback selection: `--apply --no-tui --only downloads` with input `n` deletes nothing; with `1` deletes the largest item only; `q` skips; EOF applies pre-selected safe items.
9. `--list` lists all 19 modules; unknown module → exit 1; non-numeric `--days` → exit 1.
10. Dev entry (`src/main.sh`) and built file produce identical dry-run reports.
11. `tests/run.sh --tui` (opt-in, ~15s): drives the picker through a pseudo-terminal with
    `script -q LOG dist/mac-cleanup --apply --only downloads`, piping timed keystrokes
    (`\r`, space, `\r`, `y`) — ticked item deleted, result line present; then `\003` (Ctrl-C)
    → log contains `ESC[?1049l` and `ESC[?25h` (screen/cursor restored), nothing deleted.
    macOS has no `timeout(1)`; keystroke sequences must let the program exit on its own.

The fake home lives in `tests/fixtures.sh` (`make_home`), shared with `dev/sandbox.sh`.
The whole suite also runs inside the sandbox: `dev/sandbox.sh --exec tests/run.sh --tui`.

---

## 11. Acceptance criteria

- `./build.sh` produces a single `dist/mac-cleanup` that runs with only stock macOS tools.
- `tests/run.sh` passes.
- On a real machine, `dist/mac-cleanup` (dry-run) item set matches the legacy v2 dry-run for the same
  modules (allowing the documented CHANGEs). Parity check:
  `bash legacy/mac-disk-cleanup-v2.sh --only <m>` vs `dist/mac-cleanup --only <m>`.
- `--apply --yes` never deletes a `pick` item.
- Interrupting the TUI with Ctrl-C leaves the terminal usable.

---

## 12. Build order (for an agent building from scratch)

1. Create layout, `VERSION`, `.gitignore`, move v1/v2 into `legacy/`.
2. `core/00-env.sh`…`core/80-cli.sh`, `lib.sh`, `main.sh` (§4–§7).
3. `modules/caches.sh` as reference (with standalone block). Verify dry-run + `--apply --yes` on a fake home.
4. `build.sh` (§8). Verify the built file.
5. Port the remaining modules in `MC_ALL_MODULES` order (§9). After each: `bash -n`, dry-run
   `--only <m>`, compare with legacy.
6. `60-picker.sh` TUI, then text fallback.
7. `tests/run.sh` (§10), `README.md`.
8. Final: `./build.sh && tests/run.sh`.

## 13. Pitfalls

- `du` on a missing path prints errors: always go through `kb`.
- `find … -mtime +N` means strictly older than N*24h.
- `read -n1` returns an empty string for Enter; `IFS=` is required to read a space.
- Arrow keys arrive as `ESC [ A`; read the remaining 2 bytes with `read -rsn2 -t 1`.
- Keep `isig` on in raw mode so Ctrl-C delivers SIGINT; restore with the saved `stty -g`.
- All TUI output goes to `/dev/tty`; all keyboard reads come from `/dev/tty`.
- `printf` widths in bash 3.2 count bytes: use `padr`/`fit` for columns with user text.
- A multibyte character right after a variable name (`"$shown…"`) is parsed as part of the
  name in bash 3.2 → always brace: `"${shown}…"`.
- docker's container template has no `.CreatedSince`; use `.RunningFor`.
- Module scan functions run in the main shell (not subshells) so they can append to the item arrays. Never pipe into a `while` loop that calls `mc_item`; use `done < file` or `done < <(cmd)`.
