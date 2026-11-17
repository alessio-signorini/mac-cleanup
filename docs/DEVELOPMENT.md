# Development

`mac-cleanup` is written in bash 3.2 (stock `/bin/bash`) and split into small files under
`src/`. `./build.sh` concatenates them into the single executable `dist/mac-cleanup`.
The full specification is in [BUILD.md](BUILD.md).

## Build and test

```sh
./build.sh            # -> dist/mac-cleanup (+ shellcheck lint if installed)
tests/run.sh          # test suite against a fake $HOME
tests/run.sh --tui    # + pty-driven terminal-UI tests (~15s more)
```

`shellcheck` is optional and used only by `build.sh` to lint the output.

## Layout

```
src/core/      shared engine: UI, sizes, running-app detection, item store, deleters, picker, runner, CLI
src/modules/   one file per module (each runnable on its own: ./src/modules/whatsapp.sh --apply)
src/main.sh    dev entry point (./src/main.sh behaves like dist/mac-cleanup)
build.sh       concatenates core + modules + main into dist/mac-cleanup
tests/run.sh   test suite against a fake $HOME (fixture in tests/fixtures.sh)
dev/sandbox.sh run the tool against a fake $HOME inside a macOS sandbox
legacy/        v1 and v2 scripts, for reference and parity checks
```

## Adding a module

Modules only *describe* what they found (`safe_clear`, `pick_path`, `note`…). The core
does all printing, selection and deletion. To add a module, copy
`src/modules/caches.sh`, add its name to `MC_ALL_MODULES` in `src/core/00-env.sh`, and
run `./build.sh && tests/run.sh`. See [BUILD.md §5](BUILD.md#5-core-api-contract-between-core-and-modules)
for the module API.

## Experimenting safely

Don't try `--apply` changes against your real home. `dev/sandbox.sh` runs the tool with
`HOME` set to a fake home (`.sandbox/home`, built from `tests/fixtures.sh`) under macOS's
built-in `sandbox-exec` (Seatbelt). The kernel refuses writes outside `.sandbox/`, `dist/`
and `/tmp`, blocks the network (so `docker` can't reach colima), and blocks `sudo`,
`tmutil` and `xcrun`/`simctl`:

```sh
dev/sandbox.sh --apply                # src/main.sh against the fake home
dev/sandbox.sh --dist --apply         # same with dist/mac-cleanup
dev/sandbox.sh --exec tests/run.sh    # whole test suite inside the sandbox
dev/sandbox.sh --shell                # poke around; --reset rebuilds the fake home
```

A devcontainer or chroot doesn't help here: the tool needs macOS itself (`lsappinfo`,
`osascript`, BSD `du`, app containers). For a realistic end-to-end run on real apps, use a
throwaway macOS VM (for example [Tart](https://tart.run) on Apple Silicon).
