# WSLMole Design Document

**Date:** 2026-02-18
**Status:** Approved
**Inspired by:** [WinMole](https://github.com/mrelph/WinMole) (Windows/Rust) and [tw93/Mole](https://github.com/tw93/Mole) (macOS/Shell)

## Overview

WSLMole is a WSL-aware Ubuntu system cleanup and optimization CLI tool built as a multi-file shell (bash) project. It provides interactive TUI menus via whiptail and a full CLI interface for scripted use.

## Decisions

- **Language:** Bash shell scripts (like Mole macOS)
- **Architecture:** Multi-file project with `lib/` modules sourced by main entry point
- **TUI:** whiptail (pre-installed on Ubuntu)
- **WSL awareness:** Handles WSL-specific concerns (memory limits, vhdx, interop) alongside standard Linux cleanup
- **Package managers:** apt + snap integration
- **Safety model:** Dry-run previews, confirmations, protected paths (same as WinMole)

## Project Structure

```
WSLMole/
  wslmole                  # Main entry point (executable bash script)
  lib/
    common.sh              # Shared utilities (colors, formatting, size helpers, confirmations)
    menu.sh                # Interactive TUI menu (whiptail-based)
    clean.sh               # System cleanup module
    disk.sh                # Disk analysis module
    dev.sh                 # Developer artifact cleanup
    diagnose.sh            # System diagnostics
    packages.sh            # apt + snap package manager wrapper
    wsl.sh                 # WSL-specific optimizations
  install.sh               # Install script (symlinks to /usr/local/bin)
  README.md
  LICENSE
```

## Feature Modules

### 1. System Cleanup (`clean.sh`)

| Category | Targets |
|----------|---------|
| `apt` | `/var/cache/apt/archives/*.deb`, apt lists, old kernels |
| `snap` | Old snap revisions (keeps current), snap cache |
| `logs` | Rotated logs in `/var/log/`, journal logs older than 7 days |
| `tmp` | `/tmp/*`, `/var/tmp/*`, user `~/.cache/` trash |
| `browser` | Chrome/Firefox/Edge cache under `~/.cache/` and `~/.mozilla/` |
| `user` | Thumbnails, recently-used, bash history (with confirmation), trash |
| `wsl` | `/mnt/c/` temp file references, WSL `.log` files, drvfs cache |

### 2. Disk Analysis (`disk.sh`)

Uses `du`, `find`, `stat` — no external dependencies.

- **Tree view** — `du --max-depth=N` with formatted output
- **Largest files** — `find + sort` for top N files
- **Largest folders** — `du + sort` for top N directories
- **File types** — Extension-based breakdown with size totals
- **Old files** — Files not modified in 90+ days
- **Summary** — Disk usage overview via `df`

### 3. Developer Cleanup (`dev.sh`)

Scans for and removes build artifacts:
- `node_modules/`, `target/`, `__pycache__/`, `.gradle/`, `venv/`, `.venv/`, `build/`, `dist/`, `.next/`, `.nuxt/`, `.cache/` (project-level)
- Interactive selection with size display
- Age filter (`--older-than N` days)

### 4. System Diagnostics (`diagnose.sh`)

- **Process analysis** — Top CPU/memory consumers via `ps` and `/proc`
- **Memory analysis** — Detailed breakdown from `/proc/meminfo`
- **Service analysis** — `systemctl` status of running/failed services
- **WSL resource check** — Memory vs `.wslconfig` limits, vhdx disk usage, WSL version

### 5. Package Manager (`packages.sh`)

- **apt:** audit (list upgradable), update + upgrade, autoremove + clean
- **snap:** refresh, list installed, remove old revisions

### 6. WSL Tools (`wsl.sh`)

- **WSL info** — Version, distro, kernel, `.wslconfig` settings
- **Memory optimization** — Detect pressure, suggest `.wslconfig` limits
- **Disk compaction** — Guide to compact ext4.vhdx (PowerShell instructions)
- **Interop check** — Windows interop and PATH integration status

## CLI Interface

```bash
wslmole                        # Interactive menu (default)
wslmole -i                     # Explicit interactive mode
wslmole -q                     # Quick scan

wslmole clean                  # System cleanup (interactive category selection)
wslmole clean --dry-run        # Preview only
wslmole clean -c apt,logs      # Clean specific categories
wslmole clean --force          # Skip confirmations

wslmole disk [path]            # Disk analysis (default: /)
wslmole disk -m tree -d 3      # Tree view, depth 3
wslmole disk -m largest -n 20  # Top 20 largest files

wslmole dev [path]             # Dev artifact cleanup
wslmole dev --dry-run          # Preview artifacts
wslmole dev --older-than 30    # Only artifacts > 30 days old

wslmole diagnose               # All diagnostics
wslmole diagnose processes     # Process analysis only

wslmole packages               # Package manager submenu
wslmole packages audit         # Check for updates
wslmole packages clean         # autoremove + clean

wslmole wsl                    # WSL info and tools
wslmole wsl compact            # Guide for vhdx compaction
```

## Interactive TUI

Uses whiptail for menu dialogs (pre-installed on Ubuntu).

**Flow:** ASCII logo -> Main Menu -> Module Submenu -> Action -> Result -> Back to Submenu

**Main Menu:**
1. System Cleanup
2. Disk Analysis
3. Developer Cleanup
4. System Diagnostics
5. Package Manager
6. WSL Tools
7. Quick Scan
8. Exit

Each module has a looping submenu — user stays until choosing "Back to Main Menu".

## Quick Scan

Fast health check showing:
- Health score (0-100)
- Cleanable space breakdown
- Recommendations (failed services, unconfigured WSL limits, etc.)

## Safety & Error Handling

- **Dry-run by default** in interactive mode (preview then confirm)
- **`--dry-run`** flag on every destructive CLI command
- **`--force`** flag to skip confirmations for automation
- **Protected paths** — Hardcoded never-delete list (`/bin`, `/usr`, `/etc`, `/boot`, `/home` root)
- **Root detection** — Warns but doesn't require root; skips operations needing root with clear message
- **Graceful failures** — Skip files in use or permission-denied, report at end
- **Size reporting** — Always show space freed/freeable
- **Logging** — `--verbose` writes to `~/.local/share/wslmole/wslmole.log`

## ASCII Art

```
 __      __  ___ _     __  __       _
 \ \    / / / __| |   |  \/  | ___ | | ___
  \ \/\/ /  \__ \ |__ | |\/| |/ _ \| |/ -_)
   \_/\_/   |___/____||_|  |_|\___/|_|\___|

        WSL System Optimization Tool
```
