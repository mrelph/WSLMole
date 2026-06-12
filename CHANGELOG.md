# Changelog

## v2.0.0 (2026-06-11)

### Breaking Changes

- **Dry-run by default.** All destructive commands preview changes unless `--yes` is passed. Scripts relying on `wslmole clean` deleting immediately must add `--yes`.
- **Whiptail TUI removed.** The interactive mode (`wslmole -i`) now uses inline Bash menus; `whiptail` is no longer a dependency.
- **Config file is no longer sourced.** `~/.config/wslmole/config` is parsed as strict `KEY=VALUE` pairs. Shell syntax (including the old `WSLMOLE_PROTECTED_PATHS_EXTRA` array) is no longer supported; unknown or malformed lines are skipped with a warning.

### New Features

- `wslmole scan` — quick health scan with 0–100 score (also the default when run with no command)
- `wslmole plan` — risk-labeled action plan with `--risk`, `--auto`, and `--category` filters
- `wslmole fix` — apply low-risk cleanup actions from the plan (`--only`, `--dry-run`, `--yes`)
- `wslmole update` — self-update from published `v*` releases, with a non-blocking daily background check
- `NO_COLOR` / `--no-color` support and automatic color suppression for non-TTY output
- "Did you mean?" suggestions for mistyped commands and categories

### Fixes & Hardening

- Confirmed cleanup actions now actually execute (`DRY_RUN` was never disabled in `fix --yes` and interactive confirm paths)
- Protected-path checking now blocks children of system trees (`/usr`, `/etc`, `/bin`, …) while keeping `/tmp`, `/var/log`, and `$HOME` cleanup targets deletable
- File-deletion loops are NUL-delimited (filenames with newlines can no longer split into bogus delete targets)
- Self-update verifies the origin remote, checks GPG tag signatures when present, and sanitizes version strings before display
- Windows username from interop is validated before being used in `/mnt/c/Users/...` paths
- JSON mode (`--format json`) emits clean, parseable stdout on every path
- Test runner aggregation fixed (was reporting 0 tests on BSD grep); suites: 10, tests: 114
