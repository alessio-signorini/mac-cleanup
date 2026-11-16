# mac-cleanup

Reclaim disk space on macOS without being surprised by what gets deleted.

`mac-cleanup` scans 19 areas of your Mac (caches, WhatsApp, Docker, Xcode, editors,
Claude, dev toolchains, …). It shows what can be freed, then lets you review each
area in a checkbox list before anything is deleted. It's a single bash file and
needs nothing beyond what ships with macOS.

```
mac-cleanup 3.0.0 — Disk: 144Gi used of 228Gi, 56Gi free (72%)

== RESULTS ==
  ✔ Caches & logs                freed 425.6MB  (6 item(s))
  ✔ WhatsApp                     freed 5.5GB  (3 item(s))
  – Xcode & simulators           skipped  (safe 3.9GB · review 18.2GB)
  ✔ Docker / colima              freed 836MB  (2 item(s))
  · nothing to clean: Browsers, GIMP, iOS device backups

== SUMMARY ==
  freed ≈ 6.7GB   (free space change: +6.5GB; APFS may take a minute to report)
```

## Build

```sh
./build.sh            # -> dist/mac-cleanup (single executable)
tests/run.sh          # optional: test suite (add --tui for terminal-UI tests)
```

Nothing is installed for you. To put it on your PATH:

```sh
cp dist/mac-cleanup ~/.local/bin/    # or /usr/local/bin, or anywhere on $PATH
```

Requirements: macOS 26 or later with the stock `/bin/bash` (3.2). No Homebrew, Python or
Xcode needed. Tools like `docker`, `brew`, `xcrun`, `npm` or `rustup` are used only
when installed. `shellcheck` is optional and used only by `build.sh` to lint the output.

## Usage

```sh
mac-cleanup                      # dry-run: report everything, delete nothing
mac-cleanup --apply              # review each module and delete what you select
mac-cleanup --apply --yes        # unattended: safe tier only (cron/launchd)
mac-cleanup whatsapp --apply     # just one module (same as --only whatsapp)
mac-cleanup --only xcode,docker  # several modules
mac-cleanup --skip projects,report
mac-cleanup --apply --system     # include sudo system-level cleanup
mac-cleanup --list               # list modules
```

| Option | Meaning |
|---|---|
| `--apply` | review and delete (otherwise dry-run) |
| `--yes`, `-y` | with `--apply`: no prompts, safe tier only |
| `--only a,b` / `MODULE…` | run only these modules |
| `--skip a,b` | skip modules |
| `--days N` | idle threshold for projects, downloads, editor workspaces, Claude history (default 30) |
| `--media-days N` | WhatsApp media age threshold (default 90; `0` = all media in a chat) |
| `--system` | include the `system` module (sudo) |
| `--reclaim-docker-vm` | offer a colima VM rebuild (all images/containers/volumes lost) |
| `--no-tui` | numbered text prompts instead of the full-screen picker |
| `-q`, `--quiet` | dry-run: overview table and summary only |
| `-v`, `--verbose` | apply: also print each item result and module notes |

## How it works

1. **Scan.** Every module scans first and deletes nothing. A single progress line shows which one is running.
2. **Review.** With `--apply` in a terminal:
   - First pick the modules you want to review.
   - Then each module opens a full-screen checkbox list:

     | Key | Action |
     |---|---|
     | `↑` `↓` (or `k` `j`) | move |
     | `space` | tick or untick |
     | `a` / `n` | select all / none |
     | `enter` | confirm |
     | `q` | skip this module |
     | `?` | show help |

   - Items you ticked from the review tier need one extra `y` to confirm.
3. **Apply.** The list closes, the selection is deleted, and one result line per module stays on screen.
4. **Summary.** Total freed and the change in free disk space.

Without a terminal (piped, cron), or with `--no-tui`, each module prints a numbered list
and reads one line from stdin:
- Enter (or end of input) applies the items marked `[x]`.
- `1 3 5-7` applies exactly those.
- `a` selects all, `n` none, `q` skips the module.

### Tiers

| Tier | What | Selected by default | `--yes` applies it |
|---|---|---|---|
| **safe** | regenerable caches and logs | yes | yes |
| **pick** | your data, or slow to rebuild (WhatsApp media, simulators, backups, models, old runtimes, docker images…) | no | **never** |

### Safety

- **Dry-run by default.** Nothing is deleted without `--apply`.
- **Running apps:** their caches are skipped. Quit VS Code, Chrome, Claude, WhatsApp and similar apps first for a fuller cleanup.
- **Protected paths:** every deletion goes through one guard that refuses `/`, your home folder, `~/Library`, `~/Documents`, `/Applications` and similar top-level paths, plus relative or `..` paths.
- **WhatsApp unreferenced media:** only files that no message references and that are older than 48h are candidates. If the database paths don't match the files on disk, the sweep stops with a warning.
- **History:** every deletion is logged to `~/.local/state/mac-disk-cleanup/history.log`.
- **Full Disk Access:** give it to your terminal app so sandboxed caches (Safari, Mail, WhatsApp) can be cleaned.

## Modules

| Module | What it looks at |
|---|---|
| `caches` | `~/Library/Caches`, Logs, Trash, Mail downloads, .ipsw firmware, sandboxed/group container caches, QuickLook |
| `orphans` | containers of apps that are no longer installed |
| `apps` | Electron/Chromium caches per app (VS Code, Slack, Chrome…), krisp, GoogleUpdater |
| `editors` | VS Code/Cursor/Windsurf logs, superseded extensions, orphaned/idle workspace storage |
| `claude` | Claude Code old binaries, debug logs, old history; Claude desktop Cowork sessions and VM |
| `browsers` | Chrome on-device AI model; profile sizes |
| `whatsapp` | logs, unreferenced media per chat, old media per chat |
| `xcode` | DerivedData, simulator caches/runtimes/devices, DeviceSupport, archives |
| `docker` | stopped containers, dangling volumes, unused images, build cache, colima fstrim/rebuild |
| `dev` | npm/pnpm/yarn/pip/uv/go/CocoaPods/bun/cargo/Gradle caches, `~/.cache`, Go module cache |
| `runtimes` | non-current rbenv/pyenv/nvm versions, rust toolchains |
| `projects` | `node_modules`, `.venv`, `target`, `.next`… in projects idle > `--days` |
| `brew` | `brew cleanup`, `brew autoremove` |
| `gimp` | temp/swap files, old version profiles |
| `downloads` | old .dmg/.pkg/.zip/… in Downloads/Desktop, macOS installers |
| `models` | local LLM models in `~/.omlx` |
| `backups` | iOS device backups |
| `system` | (opt-in, sudo) `/Library/Caches`, crash reports, rotated logs, Time Machine local snapshots |
| `report` | read-only: largest folders and files > 1GB |

## Development

```
src/core/      shared engine: UI, sizes, running-app detection, item store, deleters, picker, runner, CLI
src/modules/   one file per module (each runnable on its own: ./src/modules/whatsapp.sh --apply)
src/main.sh    dev entry point (./src/main.sh behaves like dist/mac-cleanup)
build.sh       concatenates core + modules + main into dist/mac-cleanup
tests/run.sh   test suite against a fake $HOME
legacy/        v1 and v2 scripts, for reference and parity checks
```

Modules only *describe* what they found (`safe_clear`, `pick_path`, `note`…). The core
does all printing, selection and deletion. To add a module, copy
`src/modules/caches.sh`, add its name to `MC_ALL_MODULES` in `src/core/00-env.sh`, and
run `./build.sh && tests/run.sh`. The full specification is in [BUILD.md](BUILD.md).
