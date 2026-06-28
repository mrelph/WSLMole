# Changelog

All notable changes to WSLMole are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Anchored the path-traversal guard so `safe_delete` reliably blocks `..` path components anywhere in a target (not just leading ones).
- Dropped the `bc` dependency; numeric comparisons (health-score penalties, percentages, sizes) now use pure Bash/`awk` arithmetic, so WSLMole no longer requires `bc` to be installed.
- Config warnings are now surfaced on stderr: malformed lines, unknown keys, and values containing shell metacharacters (`$ ; ` | `) are reported by `load_config` instead of being silently skipped.

### Changed

- Documentation overhaul: reconciled `README.md`, `docs/wslmole.1`, `docs/config.example`, and `DEVELOPMENT.md` with the actual code. Removed claims for capabilities that do not exist (network diagnostics, disk duplicate/mount-point modes, WSL filesystem-performance/distro-management actions), documented the previously omitted actions (`packages autoremove|clean|list`, `wsl compact`, disk `tree`/`folders`/`types` modes), fixed the man page's disk top-results flag (`-n`, not `-N`), and updated `config.example` to drop the removed `WSLMOLE_PROTECTED_PATHS_EXTRA` array and add `WSLMOLE_UPDATE_INTERVAL`.

## [2.0.0] - 2026-06-12

### Breaking Changes

- **Whiptail TUI removed.** The interactive mode (`wslmole -i`) now uses inline Bash menus; `whiptail` is no longer a dependency.
- **Config file is no longer sourced.** `~/.config/wslmole/config` is parsed as strict `KEY=VALUE` pairs. Shell syntax (including the old `WSLMOLE_PROTECTED_PATHS_EXTRA` array) is no longer supported; unknown or malformed lines are skipped with a warning.

### Added

- `wslmole scan` — quick health scan with a 0–100 score and grade (also the default when run with no command, and via `-q`/`--quick`).
- `wslmole plan` — read-only, risk-labeled action plan with `--risk`, `--auto`, and `--category` filters.
- `wslmole fix` — apply low-risk cleanup actions from the plan (`--only`, `--dry-run`, `--yes`).
- `wslmole update` — self-update from published `v*` Git tags, with a non-blocking daily background update check.
- `NO_COLOR` / `--no-color` support and automatic color suppression for non-TTY output.
- "Did you mean?" suggestions for mistyped commands and categories.

### Fixed

- Confirmed cleanup actions now actually execute (`DRY_RUN` was never disabled in the `fix --yes` and interactive confirm paths).
- File-deletion loops are NUL-delimited, so filenames containing newlines can no longer split into bogus delete targets.
- JSON mode (`--format json`) emits clean, parseable stdout on every path.
- Test-runner aggregation fixed (was reporting 0 tests under BSD grep); suites: 10, tests: 122.

### Security

- Protected-path checking now blocks children of system trees (`/usr`, `/etc`, `/bin`, …) via prefix matching, while keeping `/tmp`, `/var/log`, and `$HOME` cleanup targets deletable.
- Self-update verifies the origin remote is the official repository, checks GPG tag signatures when present, and sanitizes version strings before display.
- The Windows username obtained via interop is validated before being used to build `/mnt/c/Users/...` paths.

## [1.0.0] - 2026-02-19

### Added

- Initial release of WSLMole, a Bash-based WSL2/Linux maintenance toolkit.
- `wslmole clean` — system cleanup across 7 categories (apt, snap, logs, tmp, browser, user, wsl).
- `wslmole disk` — disk usage analysis with 6 view modes (summary, tree, files, folders, types, old).
- `wslmole dev` — developer artifact cleanup (build dirs, dependency dirs, caches).
- `wslmole diagnose` — system diagnostics for processes, memory, services, and WSL resources.
- `wslmole packages` — apt + snap package manager wrapper (audit, update, autoremove, clean, list).
- `wslmole wsl` — WSL-specific tools and information (info, memory, compact, interop).
- Quick system health scan with score and recommendations.
- Interactive whiptail TUI menu system.
- `--format json` machine-readable output, progress spinners, dry-run-by-default deletions, config validation, and a `help` command.
- Install script, README, and MIT license.

[Unreleased]: https://github.com/mrelph/WSLMole/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/mrelph/WSLMole/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/mrelph/WSLMole/releases/tag/v1.0.0
