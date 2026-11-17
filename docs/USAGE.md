# Usage

Full reference for `mac-cleanup`. For a quick overview see the [README](../README.md).

## Examples

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

## Options

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
3. **Apply.** The selection is deleted right in the same list: rows turn red and are struck through as they go, with progress at the bottom. Then the next module opens. When every module is done, the screen closes and one result line per module is printed in the console.
4. **Summary.** Optionally (press `y` within 10s) the "where else is space going" report, measured after deleting and leaving out what you just reviewed and kept; then the total freed and the change in free disk space.

### Without a terminal

Without a terminal (piped, cron), or with `--no-tui`, each module prints a numbered list
and reads one line from stdin:

- Enter (or end of input) applies the items marked `[x]`.
- `1 3 5-7` applies exactly those.
- `a` selects all, `n` none, `q` skips the module.

## Tiers

| Tier | What | Selected by default | `--yes` applies it |
|---|---|---|---|
| **safe** | regenerable caches and logs | yes | yes |
| **pick** | your data, or slow to rebuild (WhatsApp media, simulators, backups, models, old runtimes, docker images…) | no | **never** |

## Safety details

- **Dry-run by default.** Nothing is deleted without `--apply`.
- **Running apps:** their caches are skipped. Quit VS Code, Chrome, Claude, WhatsApp and similar apps first for a fuller cleanup.
- **Protected paths:** every deletion goes through one guard that refuses `/`, your home folder, `~/Library`, `~/Documents`, `/Applications` and similar top-level paths, plus relative or `..` paths.
- **WhatsApp unreferenced media:** only files that no message references and that are older than 48h are candidates. If the database paths don't match the files on disk, the sweep stops with a warning.
- **History:** every deletion is logged to `~/.local/state/mac-disk-cleanup/history.log`.
- **Full Disk Access:** give it to your terminal app so sandboxed caches (Safari, Mail, WhatsApp) can be cleaned.
