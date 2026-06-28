# WSLMole Development Guide

Developer/contributor guide for WSLMole (v2.0.0), a Bash CLI for WSL2/Linux
system cleanup, disk analysis, diagnostics, and WSL tooling. This document
covers the project architecture, the module map, how to run tests and the
linter, the CI workflow, the release/self-update model, and contribution
conventions.

> Looking for user-facing usage? See `README.md` and the man page
> (`man wslmole`, source at `docs/wslmole.1`).

## Project Layout

```
wslmole                  Entry script (CLI parser + dispatcher)
lib/                     Sourced modules — one per command, plus shared code
  common.sh              Shared utilities, global state, config, safety, logging
  clean.sh               clean command
  disk.sh                disk command
  dev.sh                 dev command
  diagnose.sh            diagnose command
  packages.sh            packages command
  wsl.sh                 wsl command
  quickscan.sh           scan command / quick-scan engine
  plan.sh                plan command + shared plan engine (also used by fix)
  update.sh              update command + self-update + periodic update check
  menu.sh                interactive menu (-i / --interactive)
tests/                   Test suites (test_*.sh) + run_all.sh runner
docs/                    wslmole.1 (man page), config.example
lint.sh                  ShellCheck wrapper
install.sh               Installer (symlink + man page)
.shellcheckrc            ShellCheck configuration
.github/workflows/ci.yml CI pipeline
```

The single source of truth for the version string is
`WSLMOLE_VERSION="2.0.0"` in `lib/common.sh` (around line 30). Update it there
when cutting a release.

## Architecture

### Entry script + sourced modules

`wslmole` is the only executable entry point. At startup it:

1. Sets strict mode — `set -euo pipefail` — **only in the entry script**.
   `lib/common.sh` deliberately does *not* set strict mode (see its header
   comment) so the modules can be sourced safely from tests and tools without
   inheriting `errexit`/`nounset`. Strict mode lives in `wslmole`, `lint.sh`,
   `install.sh`, and each `tests/*.sh` file — never in `lib/`.
2. Resolves its own directory through `readlink -f` (so a `/usr/local/bin`
   symlink still finds `lib/`), then sources **every** `lib/*.sh` in a glob
   loop. There is no selective/lazy loading — all modules are always loaded.
3. Calls `load_config` to read `~/.config/wslmole/config`.
4. Parses global flags, then dispatches to a command.

### The cmd_*/dispatcher pattern

Each command is implemented in its own module as a trio of functions:

- `cmd_<name>()` — the command's own argument parser and entry point.
- `cmd_<name>_help()` — prints command-specific help.
- `cmd_<name>_<unit>()` — the worker that does one category/mode/action/type
  (e.g. `cmd_clean_category`, `cmd_disk_mode`, `cmd_dev_scan`,
  `cmd_diagnose_type`, `cmd_packages_action`, `cmd_wsl_action`).

`main()` in `wslmole` is the global parser. Its key behaviors (preserve these
when editing):

- **Global flags are only recognized BEFORE the first non-flag token** (the
  command). Once a command is identified, every remaining argument is appended
  to `args[]` verbatim and forwarded to the subcommand — including unknown
  `-*` flags seen before the command. This is why `--yes`/`-y` (the real force
  switch) must come *before* the command, and why `clean -f` / `dev -f` fail:
  their own parsers have no `-f`/`--force` case despite the help text. Do not
  document `clean -f` / `dev -f` as working.
- With **no command and no action flag**, `wslmole` runs `run_quick_scan`.
- Global action flags exit immediately: `-h/--help` (`show_usage`),
  `--version`, `-i/--interactive` (`run_interactive_menu`), `-q/--quick`
  (`run_quick_scan`).
- **JSON dispatch:** when `--format json` is set, fd 3 is duped to the original
  stdout (`JSON_STDOUT_FD=3`) and stdout is redirected to stderr, so only
  `json_output` writes reach the caller's stdout. Human text goes to stderr.
  The periodic update check and interactive menu are suppressed in JSON /
  non-TTY mode.

The `scan` and `fix` commands are defined directly in `wslmole` (not in a
module file), but `fix` delegates entirely to the plan engine in `lib/plan.sh`.

## Module Map

| Module | Entry point(s) | Responsibility |
|--------|----------------|----------------|
| `common.sh` | sourced by all | Colors (`_init_colors`, NO_COLOR/TTY aware), global state defaults (`DRY_RUN=true`, `FORCE=false`, `VERBOSE=false`), `PROTECTED_PATHS`/`PROTECTED_PREFIXES`, config loading/validation (`load_config`, `VALID_CONFIG_KEYS`), `safe_delete`/`validate_path`/`is_protected_path`, `confirm`, `require_root_or_skip`, `is_wsl`, `format_size`/`get_size_bytes`, logging (`init_logging`, `log_*`), `json_output`, `suggest_correction`, print helpers |
| `clean.sh` | `cmd_clean`, `cmd_clean_category` | System cleanup across 7 categories (apt, snap, logs, tmp, browser, user, wsl). Default set: apt,snap,logs,tmp,wsl |
| `disk.sh` | `cmd_disk`, `cmd_disk_mode` | Disk usage analysis: summary, tree, files, folders, types, old |
| `dev.sh` | `cmd_dev`, `cmd_dev_scan` | Developer artifact cleanup (node_modules, target, `__pycache__`, etc.) via `find -prune` + `safe_delete` |
| `diagnose.sh` | `cmd_diagnose`, `cmd_diagnose_type` | Diagnostics: process, memory, service, wsl |
| `packages.sh` | `cmd_packages`, `cmd_packages_action` | apt + snap wrapper: audit, update, autoremove, clean, list |
| `wsl.sh` | `cmd_wsl`, `cmd_wsl_action` | WSL tools: info, memory, compact, interop. Requires a WSL environment (errors otherwise) |
| `quickscan.sh` | `run_quick_scan` | Health score (0–100) + grade + cleanable-space estimate + recommendations. The default no-command behavior and `-q` |
| `plan.sh` | `plan_collect`, `plan_print_text`, `plan_print_json`, `plan_has_auto_actions`, `plan_apply_auto_actions`, `cmd_plan` | Read-only risk-labeled action plan. Shared by `plan` and `fix`; `plan_apply_auto_actions` maps auto categories apt/logs/tmp to `cmd_clean_category` |
| `update.sh` | `cmd_update`, `perform_update`, `check_for_updates`, `maybe_check_for_updates` | Git-based self-update and periodic background update check |
| `menu.sh` | `run_interactive_menu` | Inline interactive menu (`-i`) |

## Running Tests

The runner discovers and executes every `tests/test_*.sh` file:

```bash
./tests/run_all.sh           # Run all suites; prints suite + test totals
./tests/test_safety.sh       # Run a single suite directly
```

There are currently **10 suites**:

| Suite | Focus |
|-------|-------|
| `test_common.sh` | `format_size`, `is_protected_path`, `validate_path`, `safe_delete` |
| `test_safety.sh` | Protected paths/prefixes, root, relative, traversal blocking; dry-run vs real delete |
| `test_clean.sh` | `clean` category parsing/behavior |
| `test_cli.sh` | Top-level CLI parsing, flags, dispatch |
| `test_config.sh` | Config parsing/validation (`VALID_CONFIG_KEYS`) |
| `test_disk.sh` | `disk` modes |
| `test_json.sh` | JSON output / `json_output` |
| `test_logging.sh` | Logging behavior |
| `test_menu.sh` | Interactive menu |
| `test_update.sh` | Update/self-update helpers |

Each suite sources `lib/common.sh` (safe because modules don't set strict
mode), runs assertions, and prints a three-line summary that `run_all.sh`
parses (portably, with `sed` — no `grep -P`):

```
Tests run: N
Passed: N
Failed: N
```

A suite that exits non-zero, or fails to print that summary, is counted as a
failed suite. Exit code is non-zero if any suite fails.

### Adding a test suite

Create `tests/test_<module>.sh`, make it executable (`chmod +x`), and follow
the existing pattern: strict mode, resolve `PROJECT_ROOT`, `source
"$PROJECT_ROOT/lib/common.sh"`, track `TESTS_RUN`/`TESTS_PASSED`/
`TESTS_FAILED`, print the three summary lines, and `exit 1` on any failure.
The runner picks it up automatically.

## Linting

```bash
./lint.sh                          # ShellCheck wslmole, lib/*.sh, install.sh
shellcheck wslmole lib/*.sh        # Direct invocation
```

`lint.sh` runs ShellCheck over `wslmole`, every `lib/*.sh`, and `install.sh`,
reporting per-file pass/fail and a non-zero exit if any file fails. It prints
an install hint if `shellcheck` is missing.

`.shellcheckrc` disables two checks project-wide:

- `SC1091` — "Not following sourced file" (the `lib/*.sh` glob source can't be
  statically followed).
- `SC2034` — "Variable appears unused" (many globals are consumed across
  sourced modules).

## CI Workflow

`.github/workflows/ci.yml` defines four jobs.

**Triggers:**
- Push to `master`, `main`, or `develop`.
- Push of tags matching `v*`.
- Pull requests targeting `master` or `main`.

(`master` is the repo's default branch.)

**Jobs:**

1. **`shellcheck`** — `ludeeus/action-shellcheck` over the repo at `warning`
   severity.
2. **`test`** — `chmod +x` then `./tests/run_all.sh`, followed by
   `./install.sh` to verify installation.
3. **`smoke-test`** — installs `mandoc`, runs `--help`/`--version`, the
   `--format json --version` path, every `<command> --help`, plus
   `update --check`; verifies `docs/wslmole.1` renders with `mandoc`.
   (`wsl --help` and `update --check` are allowed to fail outside WSL/a git
   checkout via `|| true`.)
4. **`release`** — gated on `refs/tags/v*`, `needs: [shellcheck, test,
   smoke-test]`, `contents: write`. Runs `gh release create
   "$GITHUB_REF_NAME" --title "WSLMole $GITHUB_REF_NAME" --generate-notes`.

## Release & Tag Process

1. Bump `WSLMOLE_VERSION` in `lib/common.sh` and update `CHANGELOG.md`.
2. Ensure `./lint.sh` and `./tests/run_all.sh` pass.
3. Tag with a strict semver tag: `vMAJOR.MINOR.PATCH` (e.g. `v2.0.0`). The
   self-updater's `_validate_tag` enforces `^v[0-9]+\.[0-9]+\.[0-9]+$`, and
   `_get_latest_tag` selects the highest `v[0-9]*` by `version:refname`.
4. **GPG-sign the tag.** Self-update runs `git verify-tag` and warns loudly if
   a tag is *not* signed, because checked-out code is sourced on the next run.
   Signing protects users who self-update.
5. Push the tag. CI's `release` job auto-creates the GitHub release with
   generated notes.

## Self-Update Model

Implemented in `lib/update.sh`. Self-update only works from a Git checkout
(`.git` present).

- `wslmole update` → `perform_update`: fetches tags, compares versions, and
  (with consent) checks out the latest tag.
- `wslmole update --check` / `-c` → `check_for_updates`: reports up-to-date vs
  update-available only.
- **Origin verification:** before checkout it confirms `origin` is the
  official repo (`WSLMOLE_REPO_URL=https://github.com/mrelph/WSLMole.git`, with
  or without `.git`) and prompts if it isn't.
- **Tag signature:** runs `git verify-tag` and warns if the tag isn't
  GPG-signed.
- **Local changes:** stashes local modifications with consent, then checks out
  the tag (detached HEAD) and reports how to return to `master`.
- **DRY_RUN:** honored — prints `[DRY RUN] Would update` instead of acting.
- **Periodic background check:** `maybe_check_for_updates` runs at startup at
  most once per `WSLMOLE_UPDATE_INTERVAL` (default `86400`s / 24h). It is
  skipped in JSON mode and non-TTY contexts.

## Safety Model

These guarantees live in `lib/common.sh` and must be preserved by any change
that deletes files.

- **Dry-run by default:** `DRY_RUN=true` globally. `clean`, `dev`, and `fix`
  preview only; deletion requires the global `--yes`/`-y` (sets
  `DRY_RUN=false`) or an interactive confirm. `update` also honors `DRY_RUN`.
- **`safe_delete "<path>" "<description>"`** refuses relative paths, blocks
  `..` components and `/`, and refuses protected paths. Return codes:
  `0` success, `1` blocked, `2` not-found, `3` permission-denied. In dry-run it
  logs `[DRY RUN] Would delete`.
- **`PROTECTED_PATHS`** (exact match, never deleted): `/ /bin /boot /dev /etc
  /home /lib /lib64 /media /mnt /opt /proc /root /run /sbin /srv /sys /usr
  /var /usr/bin /usr/lib /usr/lib64 /usr/sbin`.
- **`PROTECTED_PREFIXES`** (nothing inside these trees may be deleted):
  `/bin /sbin /boot /dev /etc /lib /lib64 /proc /sys /usr /run`. Note `/var`,
  `/tmp`, and `/home` are intentionally *not* prefixes — the tool legitimately
  deletes children there (`/var/log/*.gz`, `/tmp/*`, `~/.cache`).
- **Root requirements:** apt operations and `journalctl` vacuum require root
  (`require_root_or_skip` skips with a warning otherwise). The `wsl` command
  requires a WSL environment (`is_wsl`) or errors out.
- **Colors** auto-disable on `NO_COLOR` / `WSLMOLE_NO_COLOR=1` and non-TTY.

## Configuration

Config file: `~/.config/wslmole/config`, parsed by `load_config` as **strict
`KEY=VALUE` lines** (not sourced as shell). Comments (`#`) and blank lines are
skipped. Malformed lines, unknown keys, and values containing `$ ; ` |` are
rejected with a warning on stderr; only values matching each key's pattern are
applied.

`VALID_CONFIG_KEYS`: `DRY_RUN FORCE VERBOSE WSLMOLE_LOG_LEVEL
WSLMOLE_UPDATE_INTERVAL`.

| Key | Type / default | Effect |
|-----|----------------|--------|
| `DRY_RUN` | `true`\|`false` (default `true`) | Preview-only deletions when true |
| `FORCE` | `true`\|`false` (default `false`) | `confirm()` auto-approves prompts |
| `VERBOSE` | `true`\|`false` (default `false`) | Enables session logging to `WSLMOLE_LOG_FILE` |
| `WSLMOLE_LOG_LEVEL` | `DEBUG`\|`INFO`\|`WARN`\|`ERROR` (default `INFO`) | Gates which `log_*` messages are written |
| `WSLMOLE_UPDATE_INTERVAL` | integer seconds (default `86400`) | Background update-check frequency |

See `docs/config.example` for an annotated template. Logs (when `VERBOSE`)
go to `~/.local/share/wslmole/wslmole.log`, rotated at ~1 MB.

## Installation (for testing locally)

`./install.sh` symlinks `wslmole` into `/usr/local/bin` and copies the man page
to `/usr/local/share/man/man1/wslmole.1` (view with `man wslmole`). If
`/usr/local/bin` isn't writable it prints `sudo` / PATH fallbacks. The symlink
is safe because `wslmole` resolves its real directory via `readlink -f`.

## Cross-Platform Notes

The tool targets WSL2/Ubuntu, but the test suite is written to run on macOS for
development convenience:

- `get_size_bytes()` supports both Linux (`stat -c%s`) and macOS (`stat -f%z`).
- `du -sb` works on both platforms.
- Tests use `/tmp`, which exists on both.

## Contribution Conventions

- Keep `set -euo pipefail` in `wslmole`/scripts/tests only; never add it to
  `lib/*.sh` (they must stay sourceable).
- New commands follow the `cmd_<name>` / `cmd_<name>_help` /
  `cmd_<name>_<unit>` trio in a new `lib/<name>.sh`, and are wired into
  `main()`'s dispatch `case` plus the `help <command>` and `suggest_correction`
  command lists in `wslmole`.
- All destructive actions go through `safe_delete` and respect `DRY_RUN`.
- Reach the caller's stdout only via `json_output` when `FORMAT=json`; keep
  human output on stderr in JSON mode.
- Add or update a `tests/test_*.sh` suite for behavior changes.
- Update `README.md`, `docs/wslmole.1`, and `CHANGELOG.md` for user-facing
  changes; bump `WSLMOLE_VERSION` for releases.

### Pre-commit checklist

- [ ] `./lint.sh` — all files pass ShellCheck
- [ ] `./tests/run_all.sh` — all suites pass
- [ ] Manual smoke test if adding/altering a command (`./wslmole <cmd> --help`,
      `./wslmole -q`)
- [ ] Tests added/updated for the change
- [ ] `README.md` / man page / `CHANGELOG.md` updated for user-facing changes
