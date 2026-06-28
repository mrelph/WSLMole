# WSLMole

**Housekeeping for your WSL2 / Linux instance — scan, clean, and tune from one CLI.**

WSLMole is a terminal-based system optimization tool built for WSL2 (Windows Subsystem for Linux) and general Linux environments. It scans for cruft, reclaims disk space, diagnoses resource pressure, and surfaces WSL-specific tuning tips — all through direct CLI commands or an inline interactive menu. It is for developers and WSL users who want a fast, scriptable way to keep a distro lean without memorizing a dozen `apt`, `du`, and `find` incantations. Inspired by [WinMole](https://github.com/mrelph/WinMole), the Windows counterpart.

![Bash](https://img.shields.io/badge/Bash-4EAA25?logo=gnubash&logoColor=white)
![WSL2](https://img.shields.io/badge/WSL2-0078D4?logo=windows&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?logo=ubuntu&logoColor=white)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

---

## Features

- **System Cleanup** — APT cache, disabled snap revisions, rotated logs, `/tmp` files, browser caches, user thumbnail/trash data, and WSL log files across 7 categories
- **Disk Analysis** — six view modes: summary, tree, largest files, largest folders, usage by file type, and old (90+ day) files
- **Developer Cleanup** — `node_modules`, `target`, `__pycache__`, virtualenvs, `build`/`dist`, `.next`/`.nuxt`, caches, and more build artifacts
- **System Diagnostics** — top CPU/memory processes, memory breakdown, failed systemd services, and WSL resource checks
- **Package Manager** — audit, update, autoremove, clean, and list for both APT and Snap
- **WSL Tools** — environment info, memory/swap status, an ext4 VHDX compaction guide, and Windows interop status
- **Quick Scan** — one-command health check with a 0–100 score, cleanable-space estimate, and actionable recommendations
- **Action Plan** — risk-labeled recommendations (low / medium / review) with suggested commands and safe auto-fix actions
- **Self-Update** — checks for new Git-tagged releases, with periodic background checks
- **Interactive CLI** — inline Bash menu system with looping submenus for every module

---

## Installation

```bash
git clone https://github.com/mrelph/WSLMole.git
cd WSLMole
./install.sh
```

`install.sh` symlinks the `wslmole` entry script into `/usr/local/bin/wslmole` and installs the man page to `/usr/local/share/man/man1/wslmole.1`. If the installer cannot write to those locations, it prints the equivalent `sudo` commands for you to run manually.

After installation, read the manual any time with:

```bash
man wslmole
```

> **Note:** Install from a `git clone` (not a downloaded archive). The self-update command (`wslmole update`) requires a Git checkout — it fetches tags and checks out the latest release, and will not run without the `.git` directory.

If you prefer not to symlink, add the project directory to your PATH instead:

```bash
export PATH="/path/to/WSLMole:$PATH"
```

---

## Quick Start

```bash
wslmole              # quick health scan (default when run with no command)
wslmole scan         # same quick health scan, explicitly
wslmole plan         # review a read-only, risk-labeled action plan
wslmole -i           # launch the interactive menu
wslmole fix --dry-run  # preview the low-risk auto-cleanup actions
```

WSLMole previews destructive actions by default — see [Safety](#safety) below.

---

## Command Summary

| Command | What it does |
|---------|--------------|
| `scan` | Quick system health scan with a 0–100 score, grade, cleanable-space estimate, and recommendations. Default when run with no command. |
| `plan` | Show a read-only, risk-labeled action plan (never modifies the system). |
| `fix` | Preview and apply the low-risk automatic cleanup actions from the plan. |
| `clean` | Cleanup of temp files, caches, logs, and more across 7 categories. |
| `disk` | Disk usage analysis with 6 view modes. |
| `dev` | Developer artifact cleanup (build dirs, dependency dirs, caches). |
| `diagnose` | System diagnostics for processes, memory, services, and WSL resources. |
| `packages` | Package-manager wrapper for APT + Snap (audit/update/autoremove/clean/list). |
| `wsl` | WSL-specific tools and information (requires a WSL environment). |
| `update` | Check for and install updates from the Git repository (self-update). |
| `help` | Show general usage or command-specific help (`wslmole help <command>`). |

### Global flags

These are recognized only **before** the command (the first non-flag token):

| Flag | Effect |
|------|--------|
| `-h, --help` | Show full usage and exit. |
| `--version` | Print `WSLMole v2.0.0` and exit. |
| `-i, --interactive` | Launch the inline interactive menu. |
| `-q, --quick` | Run the quick system scan. |
| `-v, --verbose` | Enable session logging to `~/.local/share/wslmole/wslmole.log`. |
| `--no-color` | Disable colored output. |
| `--format text\|json` | Set output format (default `text`). |
| `-y, --yes` | Skip confirmation prompts; this is the real "force" switch (sets `FORCE=true`, `DRY_RUN=false`). |

---

## Commands in Detail

### scan — Quick Health Scan

```bash
wslmole scan
wslmole --format json scan   # machine-readable score + recommendations
```

Computes a health score (0–100) and grade (Excellent ≥ 90, Good ≥ 70, Fair ≥ 50, else Poor), applying penalties for high memory/disk usage, failed services, a missing `.wslconfig`, and pending APT updates.

### plan — Action Plan (read-only)

```bash
wslmole plan                 # show all recommendations
wslmole plan --risk low      # only low-risk items (valid: low, medium, review)
wslmole plan --auto          # only low-risk automatic actions
wslmole plan --category logs # only one category
wslmole --format json plan   # emit a machine-readable plan
```

### fix — Apply Low-Risk Cleanup

```bash
wslmole fix --dry-run        # preview without applying (default behavior)
wslmole fix --only logs,tmp  # apply only these automatic categories
wslmole fix --yes            # apply low-risk actions without prompting
```

Only items flagged auto-eligible (categories `apt`, `logs`, `tmp`) are applied. `fix` previews by default; pass `--yes` or confirm at the prompt to apply.

### clean — System Cleanup

```bash
wslmole clean                # clean the default categories: apt, snap, logs, tmp, wsl
wslmole clean apt logs       # clean specific categories positionally
wslmole clean -c apt,snap    # or via -c/--category
wslmole clean all            # all 7 categories
wslmole clean --dry-run      # preview only (this is already the default)
wslmole --yes clean          # actually delete (note: --yes goes BEFORE the command)
```

Categories: `apt`, `snap`, `logs`, `tmp` (alias `temp`), `browser`, `user` (alias `userdata`), `wsl`. The default set omits `browser` and `user`, which are opt-in.

### disk — Disk Analysis

```bash
wslmole disk                 # filesystem summary of /
wslmole disk ~               # summary of a specific path
wslmole disk -m tree -d 2 /var   # hierarchical tree, depth 2
wslmole disk -m files -n 20 ~    # 20 largest files under home
wslmole disk -m folders          # largest immediate subdirectories
wslmole disk -m types            # usage grouped by file extension
wslmole disk -m old              # files not modified in 90+ days
```

Modes: `summary`, `tree`, `files`, `folders`, `types`, `old`. The top-results flag is `-n, --top` (default 10); tree depth is `-d, --depth` (default 3).

### dev — Developer Cleanup

```bash
wslmole dev                  # scan current directory for all artifact types
wslmole dev ~/projects       # scan a specific path
wslmole dev node             # target node_modules (alias for node_modules)
wslmole dev -t target,dist   # target specific artifact types
wslmole dev --older-than 30  # only artifacts older than 30 days
```

### diagnose — System Diagnostics

```bash
wslmole diagnose             # run all diagnostics
wslmole diagnose process     # top CPU/memory consumers
wslmole diagnose memory      # /proc/meminfo breakdown (JSON available)
wslmole diagnose service     # failed systemd services + top consumers
wslmole diagnose wsl         # WSL version/kernel/.wslconfig (WSL only)
```

### packages — Package Manager

```bash
wslmole packages             # audit available APT/Snap updates (default)
wslmole packages update      # apt update && upgrade + snap refresh (root)
wslmole packages autoremove  # remove orphaned APT packages (root)
wslmole packages clean       # apt clean/autoclean + report snap revisions (root)
wslmole packages list        # count installed packages and list snaps
```

### wsl — WSL Tools

```bash
wslmole wsl                  # WSL environment info (default)
wslmole wsl memory           # allocated/used/available memory + limits
wslmole wsl compact          # step-by-step ext4 VHDX compaction guide
wslmole wsl interop          # Windows interop / binfmt_misc status
```

The entire `wsl` command requires a WSL environment; outside WSL it reports "Not running in WSL" and exits.

### update — Self-Update

```bash
wslmole update               # fetch tags and check out the latest release
wslmole update --check       # check only, do not install
```

WSLMole also checks for new tagged releases automatically every 24 hours (suppressed in JSON/non-TTY mode). Requires a Git checkout.

---

## Interactive Mode

Running `wslmole` with no arguments starts a quick health scan. Use `wslmole -i` to open the main menu, where each option opens an inline submenu that loops until you return:

```
1) Action Plan
2) System Cleanup
3) Disk Analysis
4) Developer Cleanup
5) System Diagnostics
6) Package Manager
7) WSL Tools
8) Quick Scan
9) Auto-Fix
10) Check for Updates
0) Exit
```

---

## Safety

WSLMole is conservative by design:

- **Dry-run by default** — `DRY_RUN=true` globally. `clean`, `dev`, and `fix` only **preview** changes. To actually delete or apply, pass the global `-y/--yes` flag (which sets `DRY_RUN=false`) **before** the command, or confirm at the interactive prompt.
- **Protected paths** — critical system directories (`/`, `/bin`, `/boot`, `/etc`, `/usr`, `/lib`, and more) are never deleted, and nothing inside protected trees can be removed. Deletions go through a `safe_delete` guard that refuses relative paths, `..` components, and protected locations.
- **Root awareness** — APT operations and journal vacuuming require root and are skipped with a warning otherwise.
- **Confirmation prompts** — destructive actions require explicit approval unless `--yes` (or `FORCE=true` in config) is set.
- **Verifiable updates** — self-update verifies the remote origin, prefers GPG-signed tags, and stashes local changes only with your consent.

> **Tip:** The `-f/--force` flag shown in some command help text is not implemented by `clean` or `dev` — passing it *after* those commands errors out. The real force switch is the global `--yes/-y` placed *before* the command.

### Configuration

Optional config lives at `~/.config/wslmole/config` as strict `KEY=VALUE` lines (`#` comments and blank lines are ignored). Recognized keys: `DRY_RUN`, `FORCE`, `VERBOSE`, `WSLMOLE_LOG_LEVEL`, `WSLMOLE_UPDATE_INTERVAL`. Unknown keys, malformed lines, and unsafe values are rejected with a warning. See `docs/config.example`.

---

## Documentation

- **[docs/COMMANDS.md](docs/COMMANDS.md)** — full command and option reference.
- **`man wslmole`** — the installed man page (also at [`docs/wslmole.1`](docs/wslmole.1)).
- **[DEVELOPMENT.md](DEVELOPMENT.md)** — testing and contribution workflow.
- **[CHANGELOG.md](CHANGELOG.md)** — release history.

---

## Technology

WSLMole is written entirely in **Bash** (entry script `wslmole`, modules under `lib/`) and depends only on standard GNU/Linux tools. No compiled binaries and no extra runtimes beyond what ships with Ubuntu on WSL2.

---

## Contributing

Contributions are welcome:

1. Fork the repository.
2. Create a feature branch (`git checkout -b feature/my-feature`).
3. Make your changes and test inside a WSL2 instance (`tests/run_all.sh`).
4. Commit with a clear message (`git commit -m "feat: add my feature"`).
5. Push and open a pull request.

See [DEVELOPMENT.md](DEVELOPMENT.md) for the test layout and CI details.

---

## License

This project is licensed under the [MIT License](LICENSE).

---

## Acknowledgments

- [WinMole](https://github.com/mrelph/WinMole) — the Windows counterpart that inspired this project.
