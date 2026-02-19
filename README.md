# WSLMole

**WSL System Optimization CLI**

WSLMole is a terminal-based system optimization tool built for WSL2 (Windows Subsystem for Linux) environments. It scans, cleans, and tunes your WSL instance through an interactive whiptail TUI or direct CLI commands. Inspired by [WinMole](https://github.com/mrelph/WinMole) and [tw93/Mole](https://github.com/nicehash/Mole).

![Bash](https://img.shields.io/badge/Bash-4EAA25?logo=gnubash&logoColor=white)
![WSL2](https://img.shields.io/badge/WSL2-0078D4?logo=windows&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?logo=ubuntu&logoColor=white)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

---

## Features

- **System Cleanup** -- APT cache, old kernels, orphan packages, temp files, journal logs, thumbnail cache, and crash reports
- **Disk Analysis** -- largest files/directories, old files, duplicates, filesystem usage, and mount-point breakdown
- **Developer Cleanup** -- node_modules, Python venvs, Rust target dirs, Go caches, Docker artifacts, and build outputs
- **System Diagnostics** -- top processes, memory analysis, failed services, WSL-specific checks, and network diagnostics
- **Package Manager** -- audit, update, autoremove, and snap refresh for both APT and Snap
- **WSL Tools** -- memory/swap configuration, Windows interop status, filesystem performance, and distro management
- **Quick Scan** -- one-command health check with a 0-100 score, cleanable-space summary, and actionable recommendations
- **Interactive TUI** -- whiptail-based menu system with looping submenus for every module

---

## Installation

```bash
git clone https://github.com/mrelph/WSLMole.git
cd WSLMole
./install.sh
```

If the installer cannot write to `/usr/local/bin`, it will print a `sudo` command you can run manually, or you can add the project directory to your PATH:

```bash
export PATH="/path/to/WSLMole:$PATH"
```

---

## Quick Start

Launch the interactive TUI:

```bash
wslmole
```

Run a quick health scan:

```bash
wslmole -q
```

---

## Commands

### clean -- System Cleanup

Remove cached packages, old kernels, temp files, and more.

```bash
wslmole clean           # interactive submenu
wslmole clean apt       # clean APT cache only
wslmole clean all       # run every cleanup category
```

### disk -- Disk Analysis

Find large files, stale data, and filesystem hogs.

```bash
wslmole disk            # interactive submenu
wslmole disk large      # list largest files
wslmole disk usage      # filesystem usage overview
```

### dev -- Developer Cleanup

Purge build artifacts and dependency caches across languages.

```bash
wslmole dev             # interactive submenu
wslmole dev node        # remove node_modules directories
wslmole dev all         # clean all developer artifacts
```

### diagnose -- System Diagnostics

Inspect processes, memory, services, and WSL health.

```bash
wslmole diagnose            # interactive submenu
wslmole diagnose memory     # memory breakdown
wslmole diagnose services   # list failed systemd services
```

### packages -- Package Manager

Audit and maintain APT and Snap packages.

```bash
wslmole packages            # interactive submenu
wslmole packages update     # update all packages
wslmole packages audit      # security audit
```

### wsl -- WSL Tools

Manage WSL-specific settings and cross-OS integration.

```bash
wslmole wsl             # interactive submenu
wslmole wsl memory      # check/configure WSL memory limits
wslmole wsl interop     # Windows interop status
```

---

## Interactive Mode

Running `wslmole` with no arguments opens the main menu:

```
1) System Cleanup
2) Disk Analysis
3) Developer Cleanup
4) System Diagnostics
5) Package Manager
6) WSL Tools
7) Quick Scan
8) Exit
```

Each option opens a whiptail submenu that loops until you return to the main menu.

---

## Example Output

```
      /\_/\
     ( o.o )
      > ^ <   WSLMole Quick Scan
     /|   |\
    (_|   |_)

  Health Score: 92/100 (Excellent)

  Cleanable space found: 1.8 GB
    APT cache:      680 MB
    Old logs:       340 MB
    Snap revisions: 520 MB
    Temp files:     260 MB

  Recommendations:
    ⚠ 3 failed systemd services detected
    ⚠ WSL memory limit not configured
```

---

## Safety Features

- **Dry-run mode** -- preview what would be removed before committing
- **Protected paths** -- critical system directories are never touched
- **Root detection** -- warns and adjusts behavior when running as root
- **Confirmation prompts** -- destructive actions require explicit approval
- **Logging** -- every operation is logged for auditability

---

## Technology

WSLMole is written entirely in **Bash** and depends only on standard GNU/Linux tools plus **whiptail** for the TUI. No compiled binaries, no runtime dependencies, no package manager required beyond what ships with Ubuntu on WSL2.

---

## Contributing

Contributions are welcome! To get started:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes and test inside a WSL2 instance
4. Commit with a clear message (`git commit -m "feat: add my feature"`)
5. Push and open a pull request

Please keep scripts POSIX-friendly where possible and include comments for non-obvious logic.

---

## License

This project is licensed under the [MIT License](LICENSE).

---

## Acknowledgments

- [WinMole](https://github.com/mrelph/WinMole) -- the Windows counterpart that inspired this project
- [tw93/Mole](https://github.com/nicehash/Mole) -- original concept and naming inspiration
