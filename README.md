# WSLMole

**WSL System Optimization CLI**

WSLMole is a terminal-based system optimization tool built for WSL2 (Windows Subsystem for Linux) environments. It scans, cleans, and tunes your WSL instance through direct CLI commands or an inline interactive menu. Inspired by [WinMole](https://github.com/mrelph/WinMole) and [tw93/Mole](https://github.com/nicehash/Mole).

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
- **Action Plan** -- risk-labeled recommendations with suggested commands and safe auto-fix actions
- **Interactive CLI** -- inline Bash menu system with looping submenus for every module

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

Run a quick health scan:

```bash
wslmole
```

Launch the interactive menu:

```bash
wslmole -i
```

Review a risk-labeled action plan:

```bash
wslmole plan
```

---

## Commands

### clean -- System Cleanup

Remove cached packages, old kernels, temp files, and more.

```bash
wslmole clean           # clean default high-value categories
wslmole clean apt       # clean APT cache only
wslmole clean all       # run every cleanup category
```

### plan -- Action Plan

Review recommended actions with risk labels before changing the system.

```bash
wslmole plan           # show risk-labeled recommendations
wslmole --format json plan  # emit a machine-readable plan
wslmole fix --dry-run  # preview low-risk automatic cleanup
wslmole fix --yes      # apply low-risk cleanup without prompts
```

### disk -- Disk Analysis

Find large files, stale data, and filesystem hogs.

```bash
wslmole disk            # filesystem summary
wslmole disk large      # list largest files
wslmole disk usage      # filesystem usage overview
```

### dev -- Developer Cleanup

Purge build artifacts and dependency caches across languages.

```bash
wslmole dev             # scan current directory for artifacts
wslmole dev node        # remove node_modules directories
wslmole dev all         # clean all developer artifacts
```

### diagnose -- System Diagnostics

Inspect processes, memory, services, and WSL health.

```bash
wslmole diagnose            # run all diagnostics
wslmole diagnose memory     # memory breakdown
wslmole diagnose services   # list failed systemd services
```

### packages -- Package Manager

Audit and maintain APT and Snap packages.

```bash
wslmole packages            # audit available updates
wslmole packages update     # update all packages
wslmole packages audit      # security audit
```

### wsl -- WSL Tools

Manage WSL-specific settings and cross-OS integration.

```bash
wslmole wsl             # WSL environment info
wslmole wsl memory      # check/configure WSL memory limits
wslmole wsl interop     # Windows interop status
```

---

## Interactive Mode

Running `wslmole` with no arguments starts a quick health scan. Use `wslmole -i` to open the main menu:

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
0) Exit
```

Each option opens an inline submenu that loops until you return to the main menu.

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

WSLMole is written entirely in **Bash** and depends only on standard GNU/Linux tools. No compiled binaries and no runtime package manager required beyond what ships with Ubuntu on WSL2.

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
