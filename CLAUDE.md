# WSLMole

Pure-Bash CLI that scans, cleans, and tunes WSL2 (Ubuntu) instances — cleanup, disk analysis, diagnostics, package audits, and an interactive menu. Sibling of `/Volumes/CodingProjects/WinMole`, the Rust-based Windows counterpart that inspired this project.

## Commands

```bash
./lint.sh              # ShellCheck on wslmole, lib/*.sh, install.sh
./tests/run_all.sh     # Full test suite (auto-discovers tests/test_*.sh)
./tests/test_safety.sh # Run a single suite directly
./wslmole --help       # Manual smoke test
./wslmole -q           # Quick scan (safe on any system, incl. macOS)
```

No build step — plain Bash, no dependencies beyond standard GNU tools (`bc` needed for tests in CI). `./install.sh` symlinks into `/usr/local/bin`.

## Architecture

- `wslmole` — entry point: sources every `lib/*.sh`, parses global flags, dispatches `cmd_<name>` functions
- `lib/common.sh` — shared utilities: colors, logging, `load_config`, `validate_path`, `safe_delete`, protected-path list, and `WSLMOLE_VERSION` (the single version source; bump here)
- `lib/{clean,disk,dev,diagnose,packages,wsl,plan,quickscan,update,menu}.sh` — one module per subcommand; each defines `cmd_<module>` and `cmd_<module>_help`
- `tests/` — self-contained Bash test scripts; each prints `Tests run:/Passed:/Failed:` lines that `run_all.sh` parses (a suite without that summary counts as failed)
- User config: `~/.config/wslmole/config` (template in `docs/config.example`); only keys in `VALID_CONFIG_KEYS` are honored
- Man page: `docs/wslmole.1` (CI validates with `mandoc`)

## Conventions

- Every script: `set -euo pipefail`; ShellCheck-clean at `warning` severity (`.shellcheckrc` disables SC1091/SC2034)
- All deletions must go through `safe_delete`/`validate_path` — never raw `rm -rf`
- `DRY_RUN=true` is the global default; `--yes` sets `FORCE=true DRY_RUN=false`
- Dispatch args with `"${args[@]+"${args[@]}"}"` to stay safe under `set -u` with empty arrays
- Conventional commit messages (`feat:`, `fix:`, ...)
- New tests: copy the skeleton in DEVELOPMENT.md, `chmod +x`, name it `tests/test_*.sh` — the runner picks it up automatically

## Gotchas

- Code targets WSL2/Ubuntu but development happens on macOS: keep dual-platform fallbacks (e.g. `stat -c%s` vs `stat -f%z`); `wslmole wsl` and `update --check` may legitimately fail outside WSL/git-repo contexts (CI tolerates this)
- `--format json`: stdout is re-`exec`ed to stderr and JSON is written via fd 3 (`JSON_STDOUT_FD`) — stray `echo`s in command paths won't corrupt JSON but must not write to fd 3
- `lib/menu.sh` is an inline looping menu (`wslmole -i`) — interactive, don't invoke it in CI/tests
- Auto-update (`lib/update.sh`) runs a background git-tag check every 24h via `maybe_check_for_updates`; it reads the version back out of `lib/common.sh` after updating
- CI (`.github/workflows/ci.yml`) pushes to `main`/`master`/`develop` + PRs to main; tags `v*` trigger a GitHub release — release flow is tag-driven

See DEVELOPMENT.md for the test skeleton, safety-feature details, and pre-commit checklist.
