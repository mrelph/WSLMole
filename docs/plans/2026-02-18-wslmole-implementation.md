# WSLMole Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a WSL-aware Ubuntu system cleanup and optimization CLI tool as a multi-file bash project with interactive whiptail TUI.

**Architecture:** Multi-file bash project. A main `wslmole` entry point sources modules from `lib/`. Each module is self-contained with its own functions. whiptail provides the interactive TUI. CLI args are parsed with a manual case-based parser (no external deps).

**Tech Stack:** Bash 5.x, whiptail, standard GNU coreutils (`du`, `find`, `df`, `ps`, `sort`), `apt`, `snap`, `systemctl`

---

### Task 1: Project Skeleton and Common Utilities

**Files:**
- Create: `wslmole`
- Create: `lib/common.sh`

**Step 1: Create `lib/common.sh` with shared utilities**

This is the foundation everything else depends on. It provides: color constants, size formatting, confirmation prompts, protected path checks, logging, and root detection.

```bash
#!/usr/bin/env bash
# WSLMole - Common Utilities
# Shared functions used by all modules

# ── Colors ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# ── Global State ────────────────────────────────────────────────────
WSLMOLE_VERSION="1.0.0"
WSLMOLE_LOG_DIR="${HOME}/.local/share/wslmole"
WSLMOLE_LOG_FILE="${WSLMOLE_LOG_DIR}/wslmole.log"
DRY_RUN=false
FORCE=false
VERBOSE=false

# Protected paths - NEVER delete these
PROTECTED_PATHS=(
    "/" "/bin" "/boot" "/dev" "/etc" "/home" "/lib" "/lib64"
    "/media" "/mnt" "/opt" "/proc" "/root" "/run" "/sbin"
    "/srv" "/sys" "/usr" "/var"
)

# ── Output Helpers ──────────────────────────────────────────────────
print_header() {
    echo -e "\n${BOLD}${BLUE}═══ $1 ═══${NC}\n"
}

print_success() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "  ${RED}✗${NC} $1"
}

print_info() {
    echo -e "  ${CYAN}ℹ${NC} $1"
}

print_item() {
    echo -e "  ${DIM}•${NC} $1"
}

# ── Size Formatting ─────────────────────────────────────────────────
format_size() {
    local bytes=$1
    if [[ $bytes -ge 1073741824 ]]; then
        printf "%.1f GB" "$(echo "scale=1; $bytes / 1073741824" | bc)"
    elif [[ $bytes -ge 1048576 ]]; then
        printf "%.1f MB" "$(echo "scale=1; $bytes / 1048576" | bc)"
    elif [[ $bytes -ge 1024 ]]; then
        printf "%.1f KB" "$(echo "scale=1; $bytes / 1024" | bc)"
    else
        printf "%d B" "$bytes"
    fi
}

# Get directory/file size in bytes
get_size_bytes() {
    local path="$1"
    if [[ -d "$path" ]]; then
        du -sb "$path" 2>/dev/null | cut -f1
    elif [[ -f "$path" ]]; then
        stat -c%s "$path" 2>/dev/null
    else
        echo 0
    fi
}

# ── Safety ──────────────────────────────────────────────────────────
is_protected_path() {
    local path
    path=$(realpath -m "$1" 2>/dev/null || echo "$1")
    for protected in "${PROTECTED_PATHS[@]}"; do
        if [[ "$path" == "$protected" ]]; then
            return 0
        fi
    done
    return 1
}

is_root() {
    [[ $EUID -eq 0 ]]
}

require_root_or_skip() {
    local operation="$1"
    if ! is_root; then
        print_warning "Skipping '$operation' - requires root (run with sudo)"
        return 1
    fi
    return 0
}

confirm() {
    local message="$1"
    if [[ "$FORCE" == true ]]; then
        return 0
    fi
    echo -en "  ${YELLOW}?${NC} ${message} [y/N] "
    read -r response
    [[ "$response" =~ ^[Yy]$ ]]
}

# ── Logging ─────────────────────────────────────────────────────────
init_logging() {
    if [[ "$VERBOSE" == true ]]; then
        mkdir -p "$WSLMOLE_LOG_DIR"
        echo "--- WSLMole session $(date -Iseconds) ---" >> "$WSLMOLE_LOG_FILE"
    fi
}

log() {
    if [[ "$VERBOSE" == true ]]; then
        echo "[$(date -Iseconds)] $1" >> "$WSLMOLE_LOG_FILE"
    fi
}

# ── Safe Deletion ───────────────────────────────────────────────────
safe_delete() {
    local path="$1"
    local description="${2:-$path}"

    if is_protected_path "$path"; then
        print_error "BLOCKED: Refusing to delete protected path: $path"
        log "BLOCKED: protected path $path"
        return 1
    fi

    if [[ ! -e "$path" ]]; then
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        local size
        size=$(get_size_bytes "$path")
        print_info "[DRY RUN] Would delete: $description ($(format_size "$size"))"
        log "DRY RUN: would delete $path ($size bytes)"
        return 0
    fi

    local size
    size=$(get_size_bytes "$path")
    if rm -rf "$path" 2>/dev/null; then
        print_success "Deleted: $description ($(format_size "$size"))"
        log "DELETED: $path ($size bytes)"
    else
        print_warning "Could not delete: $description (permission denied or in use)"
        log "FAILED: could not delete $path"
    fi
}

# ── WSL Detection ───────────────────────────────────────────────────
is_wsl() {
    [[ -f /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null
}

get_wsl_version() {
    if is_wsl; then
        if grep -qi "WSL2" /proc/version 2>/dev/null; then
            echo "2"
        else
            echo "1"
        fi
    else
        echo "0"
    fi
}
```

**Step 2: Create main `wslmole` entry point with CLI parser**

```bash
#!/usr/bin/env bash
# WSLMole - WSL System Optimization Tool
# https://github.com/mrelph/WSLMole
set -euo pipefail

# Resolve script directory (works with symlinks)
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# Source all library modules
for lib in "$SCRIPT_DIR"/lib/*.sh; do
    # shellcheck source=/dev/null
    source "$lib"
done

# ── ASCII Art ───────────────────────────────────────────────────────
show_logo() {
    echo -e "${CYAN}"
    cat << 'LOGO'
 __      __  ___ _     __  __       _
 \ \    / / / __| |   |  \/  | ___ | | ___
  \ \/\/ /  \__ \ |__ | |\/| |/ _ \| |/ -_)
   \_/\_/   |___/____||_|  |_|\___/|_|\___|
LOGO
    echo -e "${NC}"
    echo -e "        ${BOLD}WSL System Optimization Tool${NC} v${WSLMOLE_VERSION}"
    echo ""
}

# ── Usage ───────────────────────────────────────────────────────────
show_usage() {
    show_logo
    cat << 'USAGE'
Usage: wslmole [command] [options]

Commands:
  clean              System cleanup (temp files, caches, logs)
  disk [path]        Disk usage analysis
  dev [path]         Developer artifact cleanup
  diagnose [type]    System diagnostics
  packages [action]  Package manager (apt + snap)
  wsl [action]       WSL-specific tools

Options:
  -i, --interactive  Launch interactive TUI menu
  -q, --quick        Run quick system scan
  -v, --verbose      Enable verbose logging
  -h, --help         Show this help message
  --version          Show version

Run 'wslmole <command> --help' for command-specific options.
USAGE
}

# ── Main CLI Parser ─────────────────────────────────────────────────
main() {
    local command=""
    local args=()

    # Parse global flags and extract command
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            --version)
                echo "WSLMole v${WSLMOLE_VERSION}"
                exit 0
                ;;
            -i|--interactive)
                run_interactive_menu
                exit 0
                ;;
            -q|--quick)
                run_quick_scan
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -*)
                # Pass unknown flags to subcommand
                args+=("$1")
                shift
                ;;
            *)
                if [[ -z "$command" ]]; then
                    command="$1"
                else
                    args+=("$1")
                fi
                shift
                ;;
        esac
    done

    init_logging

    # No command = interactive mode
    if [[ -z "$command" ]]; then
        run_interactive_menu
        exit 0
    fi

    # Dispatch to module
    case "$command" in
        clean)
            cmd_clean "${args[@]+"${args[@]}"}"
            ;;
        disk)
            cmd_disk "${args[@]+"${args[@]}"}"
            ;;
        dev)
            cmd_dev "${args[@]+"${args[@]}"}"
            ;;
        diagnose)
            cmd_diagnose "${args[@]+"${args[@]}"}"
            ;;
        packages)
            cmd_packages "${args[@]+"${args[@]}"}"
            ;;
        wsl)
            cmd_wsl "${args[@]+"${args[@]}"}"
            ;;
        *)
            print_error "Unknown command: $command"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
```

**Step 3: Make entry point executable and verify it loads**

Run: `chmod +x /mnt/c/Coding/WSLMole/wslmole && /mnt/c/Coding/WSLMole/wslmole --version`
Expected: `WSLMole v1.0.0`

Run: `/mnt/c/Coding/WSLMole/wslmole --help`
Expected: Shows logo + usage text (commands will fail until modules are created — that's fine, the errors will come from missing functions not missing source files)

**Step 4: Commit**

```bash
cd /mnt/c/Coding/WSLMole
git add wslmole lib/common.sh
git commit -m "feat: add project skeleton with CLI parser and common utilities"
```

---

### Task 2: Interactive Menu System

**Files:**
- Create: `lib/menu.sh`

**Step 1: Create `lib/menu.sh` with whiptail-based TUI**

```bash
#!/usr/bin/env bash
# WSLMole - Interactive Menu System
# Uses whiptail for TUI dialogs

# Terminal dimensions for whiptail
TERM_HEIGHT=$(tput lines 2>/dev/null || echo 24)
TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)
MENU_HEIGHT=$((TERM_HEIGHT - 8))

# ── Main Interactive Menu ───────────────────────────────────────────
run_interactive_menu() {
    # Check for whiptail
    if ! command -v whiptail &>/dev/null; then
        print_error "whiptail is required for interactive mode."
        print_info "Install it with: sudo apt install whiptail"
        exit 1
    fi

    show_logo

    while true; do
        local choice
        choice=$(whiptail --title "WSLMole - Main Menu" \
            --menu "Choose an operation:" \
            "$TERM_HEIGHT" "$TERM_WIDTH" "$MENU_HEIGHT" \
            "1" "System Cleanup       - Clean temp files, caches, logs" \
            "2" "Disk Analysis        - Analyze disk usage" \
            "3" "Developer Cleanup    - Remove build artifacts" \
            "4" "System Diagnostics   - Process, memory, service analysis" \
            "5" "Package Manager      - apt + snap operations" \
            "6" "WSL Tools            - WSL-specific optimizations" \
            "7" "Quick Scan           - Fast system health check" \
            "8" "Exit" \
            3>&1 1>&2 2>&3) || break

        case "$choice" in
            1) menu_clean ;;
            2) menu_disk ;;
            3) menu_dev ;;
            4) menu_diagnose ;;
            5) menu_packages ;;
            6) menu_wsl ;;
            7) run_quick_scan; press_enter ;;
            8|"") break ;;
        esac
    done

    echo -e "\n${CYAN}Thanks for using WSLMole! 🐾${NC}\n"
}

# ── Helper ──────────────────────────────────────────────────────────
press_enter() {
    echo ""
    echo -en "  Press ${BOLD}Enter${NC} to continue..."
    read -r
}

# ── Module Submenus ─────────────────────────────────────────────────
# Each module will register its own menu_* function.
# Stubs here for modules not yet loaded (prevents errors during development).

menu_clean() {
    local choice
    while true; do
        choice=$(whiptail --title "System Cleanup" \
            --menu "Choose a cleanup category:" \
            "$TERM_HEIGHT" "$TERM_WIDTH" "$MENU_HEIGHT" \
            "1" "Preview All       - Dry run of all categories" \
            "2" "APT Cache         - Clean package manager cache" \
            "3" "Snap Cache        - Remove old snap revisions" \
            "4" "Log Files         - Clean rotated and journal logs" \
            "5" "Temp Files        - Clean /tmp, /var/tmp, ~/.cache" \
            "6" "Browser Cache     - Chrome, Firefox, Edge caches" \
            "7" "User Data         - Thumbnails, trash, recent files" \
            "8" "WSL Specific      - WSL log and temp files" \
            "9" "Clean All         - Run all categories" \
            "0" "Back to Main Menu" \
            3>&1 1>&2 2>&3) || return

        case "$choice" in
            1) DRY_RUN=true cmd_clean_category "all"; press_enter ;;
            2) cmd_clean_category "apt"; press_enter ;;
            3) cmd_clean_category "snap"; press_enter ;;
            4) cmd_clean_category "logs"; press_enter ;;
            5) cmd_clean_category "tmp"; press_enter ;;
            6) cmd_clean_category "browser"; press_enter ;;
            7) cmd_clean_category "user"; press_enter ;;
            8) cmd_clean_category "wsl"; press_enter ;;
            9) cmd_clean_category "all"; press_enter ;;
            0|"") return ;;
        esac
    done
}

menu_disk() {
    local choice
    while true; do
        choice=$(whiptail --title "Disk Analysis" \
            --menu "Choose analysis mode:" \
            "$TERM_HEIGHT" "$TERM_WIDTH" "$MENU_HEIGHT" \
            "1" "Summary          - Disk usage overview" \
            "2" "Tree View        - Directory tree with sizes" \
            "3" "Largest Files    - Find biggest files" \
            "4" "Largest Folders  - Find biggest directories" \
            "5" "File Types       - Breakdown by extension" \
            "6" "Old Files        - Files not modified in 90+ days" \
            "0" "Back to Main Menu" \
            3>&1 1>&2 2>&3) || return

        case "$choice" in
            1) cmd_disk_mode "summary" "/" 3 10; press_enter ;;
            2) cmd_disk_mode "tree" "$HOME" 3 10; press_enter ;;
            3) cmd_disk_mode "largest-files" "$HOME" 3 20; press_enter ;;
            4) cmd_disk_mode "largest-folders" "$HOME" 3 20; press_enter ;;
            5) cmd_disk_mode "file-types" "$HOME" 3 10; press_enter ;;
            6) cmd_disk_mode "old-files" "$HOME" 3 20; press_enter ;;
            0|"") return ;;
        esac
    done
}

menu_dev() {
    local path
    path=$(whiptail --title "Developer Cleanup" \
        --inputbox "Enter path to scan for build artifacts:" \
        8 60 "$HOME" \
        3>&1 1>&2 2>&3) || return

    DRY_RUN=true
    print_header "Developer Artifact Preview"
    cmd_dev_scan "$path"
    DRY_RUN=false

    if confirm "Proceed with cleanup?"; then
        cmd_dev_scan "$path"
    else
        print_info "Cleanup cancelled."
    fi
    press_enter
}

menu_diagnose() {
    local choice
    while true; do
        choice=$(whiptail --title "System Diagnostics" \
            --menu "Choose diagnostic type:" \
            "$TERM_HEIGHT" "$TERM_WIDTH" "$MENU_HEIGHT" \
            "1" "All Diagnostics    - Run everything" \
            "2" "Process Analysis   - Top CPU/memory consumers" \
            "3" "Memory Analysis    - Detailed memory breakdown" \
            "4" "Service Analysis   - systemd service status" \
            "5" "WSL Resources      - WSL memory and disk info" \
            "0" "Back to Main Menu" \
            3>&1 1>&2 2>&3) || return

        case "$choice" in
            1) cmd_diagnose_type "all"; press_enter ;;
            2) cmd_diagnose_type "processes"; press_enter ;;
            3) cmd_diagnose_type "memory"; press_enter ;;
            4) cmd_diagnose_type "services"; press_enter ;;
            5) cmd_diagnose_type "wsl"; press_enter ;;
            0|"") return ;;
        esac
    done
}

menu_packages() {
    local choice
    while true; do
        choice=$(whiptail --title "Package Manager" \
            --menu "Choose an action:" \
            "$TERM_HEIGHT" "$TERM_WIDTH" "$MENU_HEIGHT" \
            "1" "Check for Updates  - List upgradable packages" \
            "2" "Update All         - apt upgrade + snap refresh" \
            "3" "Autoremove         - Remove orphaned packages" \
            "4" "Clean Cache        - Clear apt + snap caches" \
            "5" "List Installed     - Show installed packages" \
            "0" "Back to Main Menu" \
            3>&1 1>&2 2>&3) || return

        case "$choice" in
            1) cmd_packages_action "audit"; press_enter ;;
            2) cmd_packages_action "update"; press_enter ;;
            3) cmd_packages_action "autoremove"; press_enter ;;
            4) cmd_packages_action "clean"; press_enter ;;
            5) cmd_packages_action "list"; press_enter ;;
            0|"") return ;;
        esac
    done
}

menu_wsl() {
    local choice
    while true; do
        choice=$(whiptail --title "WSL Tools" \
            --menu "Choose a tool:" \
            "$TERM_HEIGHT" "$TERM_WIDTH" "$MENU_HEIGHT" \
            "1" "WSL Info           - Version, distro, config" \
            "2" "Memory Check       - Memory usage vs limits" \
            "3" "Disk Compact Guide - Compact ext4.vhdx" \
            "4" "Interop Status     - Windows interop check" \
            "0" "Back to Main Menu" \
            3>&1 1>&2 2>&3) || return

        case "$choice" in
            1) cmd_wsl_action "info"; press_enter ;;
            2) cmd_wsl_action "memory"; press_enter ;;
            3) cmd_wsl_action "compact"; press_enter ;;
            4) cmd_wsl_action "interop"; press_enter ;;
            0|"") return ;;
        esac
    done
}
```

**Step 2: Verify interactive menu loads**

Run: `/mnt/c/Coding/WSLMole/wslmole --help`
Expected: Still shows help (menu module is sourced but not called)

**Step 3: Commit**

```bash
cd /mnt/c/Coding/WSLMole
git add lib/menu.sh
git commit -m "feat: add interactive whiptail TUI menu system"
```

---

### Task 3: System Cleanup Module

**Files:**
- Create: `lib/clean.sh`

**Step 1: Create `lib/clean.sh`**

```bash
#!/usr/bin/env bash
# WSLMole - System Cleanup Module

# ── CLI Handler ─────────────────────────────────────────────────────
cmd_clean() {
    local categories=()
    local dry_run=false
    local force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run) dry_run=true; shift ;;
            -f|--force) force=true; shift ;;
            -c|--category) IFS=',' read -ra categories <<< "$2"; shift 2 ;;
            -h|--help)
                echo "Usage: wslmole clean [options]"
                echo ""
                echo "Options:"
                echo "  -n, --dry-run         Preview without deleting"
                echo "  -f, --force           Skip confirmation prompts"
                echo "  -c, --category LIST   Categories: apt,snap,logs,tmp,browser,user,wsl,all"
                echo "  -h, --help            Show this help"
                return 0
                ;;
            *) print_error "Unknown option: $1"; return 1 ;;
        esac
    done

    DRY_RUN=$dry_run
    FORCE=$force

    if [[ ${#categories[@]} -eq 0 ]]; then
        categories=("apt" "snap" "logs" "tmp" "browser" "user" "wsl")
    fi

    # Expand "all"
    if [[ " ${categories[*]} " == *" all "* ]]; then
        categories=("apt" "snap" "logs" "tmp" "browser" "user" "wsl")
    fi

    print_header "System Cleanup"
    if [[ "$DRY_RUN" == true ]]; then
        print_info "DRY RUN MODE - No files will be deleted"
        echo ""
    fi

    local total_saved=0
    for cat in "${categories[@]}"; do
        cmd_clean_category "$cat"
    done
}

# ── Category Dispatch ───────────────────────────────────────────────
cmd_clean_category() {
    local category="$1"

    case "$category" in
        apt)    clean_apt ;;
        snap)   clean_snap ;;
        logs)   clean_logs ;;
        tmp)    clean_tmp ;;
        browser) clean_browser ;;
        user)   clean_user ;;
        wsl)    clean_wsl ;;
        all)
            clean_apt
            clean_snap
            clean_logs
            clean_tmp
            clean_browser
            clean_user
            clean_wsl
            ;;
        *)
            print_error "Unknown category: $category"
            ;;
    esac
}

# ── APT Cache ───────────────────────────────────────────────────────
clean_apt() {
    print_header "APT Cache Cleanup"

    if ! require_root_or_skip "APT cache cleanup"; then
        # Show what we'd clean even without root
        local apt_cache_size
        apt_cache_size=$(du -sb /var/cache/apt/archives/ 2>/dev/null | cut -f1 || echo 0)
        print_info "APT cache size: $(format_size "${apt_cache_size:-0}")"
        print_info "Run with sudo to clean APT cache"
        return
    fi

    if [[ "$DRY_RUN" == true ]]; then
        local apt_cache_size
        apt_cache_size=$(du -sb /var/cache/apt/archives/ 2>/dev/null | cut -f1 || echo 0)
        print_info "[DRY RUN] Would clean APT cache: $(format_size "${apt_cache_size:-0}")"
        return
    fi

    if confirm "Clean APT package cache?"; then
        apt-get clean -y 2>/dev/null
        apt-get autoclean -y 2>/dev/null
        print_success "APT cache cleaned"
        log "Cleaned APT cache"
    fi
}

# ── Snap Cache ──────────────────────────────────────────────────────
clean_snap() {
    print_header "Snap Cache Cleanup"

    if ! command -v snap &>/dev/null; then
        print_info "Snap is not installed, skipping"
        return
    fi

    # Find old snap revisions (disabled ones)
    local old_snaps
    old_snaps=$(snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}')

    if [[ -z "$old_snaps" ]]; then
        print_success "No old snap revisions found"
        return
    fi

    echo "$old_snaps" | while read -r snapname revision; do
        if [[ "$DRY_RUN" == true ]]; then
            print_info "[DRY RUN] Would remove: $snapname (revision $revision)"
        else
            if confirm "Remove old snap revision: $snapname rev $revision?"; then
                snap remove "$snapname" --revision="$revision" 2>/dev/null && \
                    print_success "Removed: $snapname revision $revision" || \
                    print_warning "Could not remove: $snapname revision $revision (may need sudo)"
            fi
        fi
    done
}

# ── Log Files ───────────────────────────────────────────────────────
clean_logs() {
    print_header "Log File Cleanup"

    # Rotated logs (.gz, .old, .1, .2, etc.)
    local log_size=0
    while IFS= read -r -d '' file; do
        local fsize
        fsize=$(stat -c%s "$file" 2>/dev/null || echo 0)
        log_size=$((log_size + fsize))
        safe_delete "$file" "$(basename "$file")"
    done < <(find /var/log -type f \( -name "*.gz" -o -name "*.old" -o -name "*.1" -o -name "*.2" -o -name "*.3" \) -print0 2>/dev/null)

    # Journal logs older than 7 days
    if command -v journalctl &>/dev/null; then
        if [[ "$DRY_RUN" == true ]]; then
            local journal_size
            journal_size=$(journalctl --disk-usage 2>/dev/null | grep -oP '[\d.]+\s*[KMGT]?i?B' || echo "unknown")
            print_info "[DRY RUN] Journal usage: $journal_size (would vacuum to 7 days)"
        else
            if require_root_or_skip "journal vacuum"; then
                if confirm "Vacuum journal logs older than 7 days?"; then
                    journalctl --vacuum-time=7d 2>/dev/null
                    print_success "Journal logs vacuumed"
                fi
            fi
        fi
    fi
}

# ── Temp Files ──────────────────────────────────────────────────────
clean_tmp() {
    print_header "Temporary File Cleanup"

    # /tmp (files older than 7 days to be safe)
    local tmp_size=0
    while IFS= read -r -d '' file; do
        local fsize
        fsize=$(stat -c%s "$file" 2>/dev/null || echo 0)
        tmp_size=$((tmp_size + fsize))
        safe_delete "$file"
    done < <(find /tmp -type f -atime +7 -print0 2>/dev/null)

    # /var/tmp
    while IFS= read -r -d '' file; do
        local fsize
        fsize=$(stat -c%s "$file" 2>/dev/null || echo 0)
        tmp_size=$((tmp_size + fsize))
        safe_delete "$file"
    done < <(find /var/tmp -type f -atime +7 -print0 2>/dev/null)

    # ~/.cache (only if not in dry run, and with confirmation)
    local cache_size
    cache_size=$(du -sb "$HOME/.cache" 2>/dev/null | cut -f1 || echo 0)
    if [[ "${cache_size:-0}" -gt 0 ]]; then
        print_info "User cache (~/.cache): $(format_size "$cache_size")"
        if [[ "$DRY_RUN" == true ]]; then
            print_info "[DRY RUN] Would offer to clean user cache"
        elif confirm "Clean user cache directory (~/.cache)?"; then
            # Remove contents but keep the directory
            find "$HOME/.cache" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
            print_success "User cache cleaned"
        fi
    fi
}

# ── Browser Cache ───────────────────────────────────────────────────
clean_browser() {
    print_header "Browser Cache Cleanup"

    local browser_paths=(
        "$HOME/.cache/google-chrome"
        "$HOME/.cache/chromium"
        "$HOME/.cache/mozilla/firefox"
        "$HOME/.cache/microsoft-edge"
        "$HOME/.mozilla/firefox/*/cache2"
        "$HOME/.config/google-chrome/Default/Cache"
        "$HOME/.config/chromium/Default/Cache"
    )

    local found=false
    for bpath in "${browser_paths[@]}"; do
        # Handle glob patterns
        for expanded in $bpath; do
            if [[ -d "$expanded" ]]; then
                found=true
                local bsize
                bsize=$(du -sb "$expanded" 2>/dev/null | cut -f1 || echo 0)
                if [[ "$DRY_RUN" == true ]]; then
                    print_info "[DRY RUN] Would clean: $expanded ($(format_size "${bsize:-0}"))"
                elif confirm "Clean browser cache: $(basename "$(dirname "$expanded")")/$(basename "$expanded") ($(format_size "${bsize:-0}"))?"; then
                    find "$expanded" -mindepth 1 -exec rm -rf {} + 2>/dev/null
                    print_success "Cleaned: $expanded"
                fi
            fi
        done
    done

    if [[ "$found" == false ]]; then
        print_success "No browser caches found"
    fi
}

# ── User Data ───────────────────────────────────────────────────────
clean_user() {
    print_header "User Data Cleanup"

    # Thumbnails
    local thumb_dir="$HOME/.cache/thumbnails"
    if [[ -d "$thumb_dir" ]]; then
        safe_delete "$thumb_dir" "Thumbnail cache"
        mkdir -p "$thumb_dir" 2>/dev/null
    fi

    # Trash
    local trash_dir="$HOME/.local/share/Trash"
    if [[ -d "$trash_dir" ]]; then
        local trash_size
        trash_size=$(du -sb "$trash_dir" 2>/dev/null | cut -f1 || echo 0)
        if [[ "${trash_size:-0}" -gt 0 ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                print_info "[DRY RUN] Would empty trash: $(format_size "$trash_size")"
            elif confirm "Empty trash ($(format_size "$trash_size"))?"; then
                rm -rf "${trash_dir:?}/files/"* "${trash_dir:?}/info/"* 2>/dev/null
                print_success "Trash emptied"
            fi
        else
            print_success "Trash is empty"
        fi
    fi

    # Recently used
    local recent_file="$HOME/.local/share/recently-used.xbel"
    if [[ -f "$recent_file" ]]; then
        safe_delete "$recent_file" "Recently used file list"
    fi
}

# ── WSL Specific ────────────────────────────────────────────────────
clean_wsl() {
    print_header "WSL-Specific Cleanup"

    if ! is_wsl; then
        print_info "Not running in WSL, skipping"
        return
    fi

    # WSL log files
    local wsl_logs=(/var/log/wsl*.log 2>/dev/null)
    for logfile in "${wsl_logs[@]}"; do
        if [[ -f "$logfile" ]]; then
            safe_delete "$logfile" "WSL log: $(basename "$logfile")"
        fi
    done

    # Temp files in WSL metadata areas
    if [[ -d "/tmp/.X11-unix" ]]; then
        print_info "X11 socket directory found (normal for WSLg)"
    fi

    # Report /mnt/c access performance note
    print_info "Tip: Files on /mnt/c are slower than native Linux paths."
    print_info "Consider moving frequently-accessed projects to ~/projects"
}
```

**Step 2: Test the clean command**

Run: `/mnt/c/Coding/WSLMole/wslmole clean --dry-run`
Expected: Shows dry-run preview of each category with sizes.

Run: `/mnt/c/Coding/WSLMole/wslmole clean --help`
Expected: Shows clean subcommand help text.

**Step 3: Commit**

```bash
cd /mnt/c/Coding/WSLMole
git add lib/clean.sh
git commit -m "feat: add system cleanup module with 7 categories"
```

---

### Task 4: Disk Analysis Module

**Files:**
- Create: `lib/disk.sh`

**Step 1: Create `lib/disk.sh`**

```bash
#!/usr/bin/env bash
# WSLMole - Disk Analysis Module

# ── CLI Handler ─────────────────────────────────────────────────────
cmd_disk() {
    local path="/"
    local mode="summary"
    local depth=3
    local top=10

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m|--mode) mode="$2"; shift 2 ;;
            -d|--depth) depth="$2"; shift 2 ;;
            -n|--top) top="$2"; shift 2 ;;
            -h|--help)
                echo "Usage: wslmole disk [path] [options]"
                echo ""
                echo "Options:"
                echo "  -m, --mode MODE    Mode: summary, tree, largest-files, largest-folders, file-types, old-files"
                echo "  -d, --depth N      Max depth for tree view (default: 3)"
                echo "  -n, --top N        Number of results (default: 10)"
                echo "  -h, --help         Show this help"
                return 0
                ;;
            -*)
                print_error "Unknown option: $1"; return 1
                ;;
            *)
                path="$1"; shift
                ;;
        esac
    done

    cmd_disk_mode "$mode" "$path" "$depth" "$top"
}

# ── Mode Dispatch ───────────────────────────────────────────────────
cmd_disk_mode() {
    local mode="$1"
    local path="$2"
    local depth="${3:-3}"
    local top="${4:-10}"

    if [[ ! -d "$path" ]]; then
        print_error "Path does not exist: $path"
        return 1
    fi

    case "$mode" in
        summary)        disk_summary "$path" ;;
        tree)           disk_tree "$path" "$depth" ;;
        largest-files)  disk_largest_files "$path" "$top" ;;
        largest-folders) disk_largest_folders "$path" "$top" ;;
        file-types)     disk_file_types "$path" "$top" ;;
        old-files)      disk_old_files "$path" "$top" ;;
        *)
            print_error "Unknown mode: $mode"
            print_info "Available: summary, tree, largest-files, largest-folders, file-types, old-files"
            return 1
            ;;
    esac
}

# ── Summary ─────────────────────────────────────────────────────────
disk_summary() {
    local path="$1"
    print_header "Disk Usage Summary"

    # Overall filesystem usage
    df -h "$path" 2>/dev/null | while IFS= read -r line; do
        echo "  $line"
    done
    echo ""

    # Quick breakdown of major directories
    if [[ "$path" == "/" ]]; then
        print_info "Top-level directory sizes:"
        du -sh /home /var /tmp /opt /usr /snap 2>/dev/null | sort -rh | while IFS=$'\t' read -r size dir; do
            printf "  %-8s %s\n" "$size" "$dir"
        done
    else
        print_info "Directory sizes under $path:"
        du -sh "$path"/*/ 2>/dev/null | sort -rh | head -10 | while IFS=$'\t' read -r size dir; do
            printf "  %-8s %s\n" "$size" "$dir"
        done
    fi
}

# ── Tree View ───────────────────────────────────────────────────────
disk_tree() {
    local path="$1"
    local depth="$2"
    print_header "Disk Usage Tree: $path (depth $depth)"

    du -h --max-depth="$depth" "$path" 2>/dev/null | sort -rh | head -40 | while IFS=$'\t' read -r size dir; do
        # Calculate indentation based on path depth relative to base
        local rel="${dir#"$path"}"
        local indent_level
        indent_level=$(echo "$rel" | tr -cd '/' | wc -c)
        local indent=""
        for ((i = 0; i < indent_level; i++)); do
            indent="${indent}|   "
        done
        printf "  %s%-8s %s\n" "$indent" "$size" "$(basename "$dir")"
    done
}

# ── Largest Files ───────────────────────────────────────────────────
disk_largest_files() {
    local path="$1"
    local top="$2"
    print_header "Largest Files in $path (top $top)"

    find "$path" -type f -printf '%s\t%p\n' 2>/dev/null | \
        sort -rn | head -"$top" | while IFS=$'\t' read -r size filepath; do
            printf "  %-12s %s\n" "$(format_size "$size")" "$filepath"
        done
}

# ── Largest Folders ─────────────────────────────────────────────────
disk_largest_folders() {
    local path="$1"
    local top="$2"
    print_header "Largest Folders in $path (top $top)"

    du -sb "$path"/*/ 2>/dev/null | sort -rn | head -"$top" | while IFS=$'\t' read -r size dirpath; do
        printf "  %-12s %s\n" "$(format_size "$size")" "$dirpath"
    done
}

# ── File Types ──────────────────────────────────────────────────────
disk_file_types() {
    local path="$1"
    local top="$2"
    print_header "File Type Breakdown in $path (top $top)"

    find "$path" -type f -printf '%s %f\n' 2>/dev/null | \
        awk '{
            split($2, parts, ".");
            if (length(parts) > 1)
                ext = tolower(parts[length(parts)]);
            else
                ext = "(no ext)";
            size[ext] += $1;
            count[ext]++;
        }
        END {
            for (e in size) printf "%d\t%d\t%s\n", size[e], count[e], e;
        }' | sort -rn | head -"$top" | while IFS=$'\t' read -r size count ext; do
            printf "  %-12s %6d files   .%s\n" "$(format_size "$size")" "$count" "$ext"
        done
}

# ── Old Files ───────────────────────────────────────────────────────
disk_old_files() {
    local path="$1"
    local top="$2"
    print_header "Old Files in $path (not modified in 90+ days, top $top)"

    find "$path" -type f -mtime +90 -printf '%s\t%T+\t%p\n' 2>/dev/null | \
        sort -rn | head -"$top" | while IFS=$'\t' read -r size mtime filepath; do
            local mdate="${mtime%%+*}"
            printf "  %-12s %-12s %s\n" "$(format_size "$size")" "${mdate%.*}" "$filepath"
        done
}
```

**Step 2: Test disk analysis**

Run: `/mnt/c/Coding/WSLMole/wslmole disk "$HOME" -m summary`
Expected: Shows disk usage summary with directory sizes.

Run: `/mnt/c/Coding/WSLMole/wslmole disk --help`
Expected: Shows disk subcommand help text.

**Step 3: Commit**

```bash
cd /mnt/c/Coding/WSLMole
git add lib/disk.sh
git commit -m "feat: add disk analysis module with 6 modes"
```

---

### Task 5: Developer Cleanup Module

**Files:**
- Create: `lib/dev.sh`

**Step 1: Create `lib/dev.sh`**

```bash
#!/usr/bin/env bash
# WSLMole - Developer Artifact Cleanup Module

# Artifact directories to scan for
DEV_ARTIFACTS=(
    "node_modules"
    "target"
    "__pycache__"
    ".gradle"
    "venv"
    ".venv"
    "build"
    "dist"
    ".next"
    ".nuxt"
    ".cache"
    "vendor"      # Go/PHP
    ".tox"        # Python
    ".pytest_cache"
    "coverage"
    ".nyc_output"
)

# ── CLI Handler ─────────────────────────────────────────────────────
cmd_dev() {
    local path="."
    local dry_run=false
    local force=false
    local older_than=""
    local types=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run) dry_run=true; shift ;;
            -f|--force) force=true; shift ;;
            -t|--types) IFS=',' read -ra types <<< "$2"; shift 2 ;;
            --older-than) older_than="$2"; shift 2 ;;
            -h|--help)
                echo "Usage: wslmole dev [path] [options]"
                echo ""
                echo "Options:"
                echo "  -n, --dry-run          Preview without deleting"
                echo "  -f, --force            Skip confirmations"
                echo "  -t, --types LIST       Artifact types (comma-separated)"
                echo "  --older-than DAYS      Only remove artifacts older than N days"
                echo "  -h, --help             Show this help"
                echo ""
                echo "Default artifact types: node_modules, target, __pycache__, .gradle,"
                echo "  venv, .venv, build, dist, .next, .nuxt, .cache, vendor,"
                echo "  .tox, .pytest_cache, coverage, .nyc_output"
                return 0
                ;;
            -*)
                print_error "Unknown option: $1"; return 1
                ;;
            *)
                path="$1"; shift
                ;;
        esac
    done

    DRY_RUN=$dry_run
    FORCE=$force

    # Use specified types or defaults
    if [[ ${#types[@]} -eq 0 ]]; then
        types=("${DEV_ARTIFACTS[@]}")
    fi

    # Expand "all"
    if [[ " ${types[*]} " == *" all "* ]]; then
        types=("${DEV_ARTIFACTS[@]}")
    fi

    cmd_dev_scan "$path" "$older_than" "${types[@]}"
}

# ── Scan and Clean ──────────────────────────────────────────────────
cmd_dev_scan() {
    local path="$1"
    local older_than="${2:-}"
    shift 2 2>/dev/null || true
    local types=("${@:-${DEV_ARTIFACTS[@]}}")

    if [[ ! -d "$path" ]]; then
        print_error "Path does not exist: $path"
        return 1
    fi

    # Resolve to absolute path
    path=$(realpath "$path")

    print_header "Developer Artifact Scan: $path"

    local total_size=0
    local found_count=0

    # Build the find -name arguments
    local find_args=()
    for artifact in "${types[@]}"; do
        if [[ ${#find_args[@]} -gt 0 ]]; then
            find_args+=("-o")
        fi
        find_args+=("-name" "$artifact" "-type" "d")
    done

    # Find artifacts and process
    while IFS= read -r -d '' artifact_path; do
        # Check age filter
        if [[ -n "$older_than" ]]; then
            local mtime
            mtime=$(stat -c%Y "$artifact_path" 2>/dev/null || echo 0)
            local now
            now=$(date +%s)
            local age_days=$(( (now - mtime) / 86400 ))
            if [[ $age_days -lt $older_than ]]; then
                continue
            fi
        fi

        local asize
        asize=$(du -sb "$artifact_path" 2>/dev/null | cut -f1 || echo 0)
        total_size=$((total_size + asize))
        found_count=$((found_count + 1))

        # Show relative path for readability
        local rel_path="${artifact_path#"$path"/}"

        if [[ "$DRY_RUN" == true ]]; then
            printf "  ${DIM}•${NC} %-50s %s\n" "$rel_path" "$(format_size "$asize")"
        else
            safe_delete "$artifact_path" "$rel_path ($(format_size "$asize"))"
        fi
    done < <(find "$path" \( "${find_args[@]}" \) -prune -print0 2>/dev/null)

    echo ""
    if [[ $found_count -eq 0 ]]; then
        print_success "No build artifacts found"
    else
        print_info "Found $found_count artifacts totaling $(format_size $total_size)"
        if [[ "$DRY_RUN" == true ]]; then
            print_info "Run without --dry-run to clean these artifacts"
        fi
    fi
}
```

**Step 2: Test dev cleanup**

Run: `/mnt/c/Coding/WSLMole/wslmole dev "$HOME" --dry-run`
Expected: Lists found build artifacts with sizes.

**Step 3: Commit**

```bash
cd /mnt/c/Coding/WSLMole
git add lib/dev.sh
git commit -m "feat: add developer artifact cleanup module"
```

---

### Task 6: System Diagnostics Module

**Files:**
- Create: `lib/diagnose.sh`

**Step 1: Create `lib/diagnose.sh`**

```bash
#!/usr/bin/env bash
# WSLMole - System Diagnostics Module

# ── CLI Handler ─────────────────────────────────────────────────────
cmd_diagnose() {
    local action="all"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                echo "Usage: wslmole diagnose [type]"
                echo ""
                echo "Types:"
                echo "  all         Run all diagnostics (default)"
                echo "  processes   Top CPU and memory consumers"
                echo "  memory      Detailed memory breakdown"
                echo "  services    systemd service status"
                echo "  wsl         WSL resource analysis"
                return 0
                ;;
            -*)
                print_error "Unknown option: $1"; return 1
                ;;
            *)
                action="$1"; shift
                ;;
        esac
    done

    cmd_diagnose_type "$action"
}

# ── Type Dispatch ───────────────────────────────────────────────────
cmd_diagnose_type() {
    local action="$1"

    case "$action" in
        all)
            diagnose_processes
            diagnose_memory
            diagnose_services
            if is_wsl; then
                diagnose_wsl_resources
            fi
            ;;
        processes) diagnose_processes ;;
        memory)    diagnose_memory ;;
        services)  diagnose_services ;;
        wsl)       diagnose_wsl_resources ;;
        *)
            print_error "Unknown diagnostic type: $action"
            print_info "Available: all, processes, memory, services, wsl"
            return 1
            ;;
    esac
}

# ── Process Analysis ────────────────────────────────────────────────
diagnose_processes() {
    print_header "Process Analysis"

    print_info "Top 10 CPU consumers:"
    echo ""
    printf "  ${BOLD}%-8s %-8s %-8s %s${NC}\n" "PID" "%CPU" "%MEM" "COMMAND"
    ps aux --sort=-%cpu 2>/dev/null | head -11 | tail -10 | while read -r user pid cpu mem vsz rss tty stat start time command; do
        printf "  %-8s %-8s %-8s %s\n" "$pid" "$cpu" "$mem" "$command"
    done

    echo ""
    print_info "Top 10 memory consumers:"
    echo ""
    printf "  ${BOLD}%-8s %-8s %-12s %s${NC}\n" "PID" "%MEM" "RSS" "COMMAND"
    ps aux --sort=-%mem 2>/dev/null | head -11 | tail -10 | while read -r user pid cpu mem vsz rss tty stat start time command; do
        printf "  %-8s %-8s %-12s %s\n" "$pid" "$mem" "$(format_size $((rss * 1024)))" "$command"
    done
}

# ── Memory Analysis ─────────────────────────────────────────────────
diagnose_memory() {
    print_header "Memory Analysis"

    if [[ ! -f /proc/meminfo ]]; then
        print_error "Cannot read /proc/meminfo"
        return 1
    fi

    local total available used free buffers cached swap_total swap_used
    total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
    available=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
    free=$(awk '/^MemFree:/ {print $2}' /proc/meminfo)
    buffers=$(awk '/^Buffers:/ {print $2}' /proc/meminfo)
    cached=$(awk '/^Cached:/ {print $2}' /proc/meminfo)
    swap_total=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
    swap_used=$((swap_total - $(awk '/^SwapFree:/ {print $2}' /proc/meminfo)))

    used=$((total - available))
    local pct=$((used * 100 / total))

    # Progress bar
    local bar_width=30
    local filled=$((pct * bar_width / 100))
    local empty=$((bar_width - filled))
    local bar=""
    for ((i = 0; i < filled; i++)); do bar+="="; done
    for ((i = 0; i < empty; i++)); do bar+=" "; done

    local color="$GREEN"
    if [[ $pct -ge 80 ]]; then color="$RED"
    elif [[ $pct -ge 60 ]]; then color="$YELLOW"
    fi

    echo ""
    printf "  Memory Usage:  ${color}%3d%%${NC}  [${color}%s${NC}]  %s / %s\n" \
        "$pct" "$bar" "$(format_size $((used * 1024)))" "$(format_size $((total * 1024)))"
    echo ""
    printf "  %-16s %s\n" "Total:" "$(format_size $((total * 1024)))"
    printf "  %-16s %s\n" "Used:" "$(format_size $((used * 1024)))"
    printf "  %-16s %s\n" "Free:" "$(format_size $((free * 1024)))"
    printf "  %-16s %s\n" "Buffers:" "$(format_size $((buffers * 1024)))"
    printf "  %-16s %s\n" "Cached:" "$(format_size $((cached * 1024)))"
    printf "  %-16s %s\n" "Available:" "$(format_size $((available * 1024)))"
    echo ""
    if [[ $swap_total -gt 0 ]]; then
        local swap_pct=$((swap_used * 100 / swap_total))
        printf "  %-16s %s / %s (%d%%)\n" "Swap:" \
            "$(format_size $((swap_used * 1024)))" \
            "$(format_size $((swap_total * 1024)))" \
            "$swap_pct"
    else
        printf "  %-16s %s\n" "Swap:" "Not configured"
    fi
}

# ── Service Analysis ────────────────────────────────────────────────
diagnose_services() {
    print_header "Service Analysis"

    if ! command -v systemctl &>/dev/null; then
        print_warning "systemctl not available (systemd may not be running in this WSL)"
        return
    fi

    # Failed services
    local failed
    failed=$(systemctl --no-pager list-units --state=failed --plain --no-legend 2>/dev/null)
    if [[ -n "$failed" ]]; then
        print_warning "Failed services:"
        echo "$failed" | while read -r unit load active sub description; do
            printf "  ${RED}✗${NC} %-40s %s\n" "$unit" "$description"
        done
    else
        print_success "No failed services"
    fi

    echo ""

    # Running services count
    local running_count
    running_count=$(systemctl --no-pager list-units --state=running --plain --no-legend 2>/dev/null | wc -l)
    print_info "Running services: $running_count"

    # Top 5 services by memory
    echo ""
    print_info "Top 5 services by memory:"
    systemctl --no-pager list-units --type=service --state=running --plain --no-legend 2>/dev/null | \
        awk '{print $1}' | while read -r svc; do
            local mem
            mem=$(systemctl show "$svc" --property=MemoryCurrent 2>/dev/null | cut -d= -f2)
            if [[ -n "$mem" && "$mem" != "[not set]" && "$mem" != "infinity" ]]; then
                printf "%s\t%s\n" "$mem" "$svc"
            fi
        done | sort -rn | head -5 | while IFS=$'\t' read -r mem svc; do
            printf "  %-12s %s\n" "$(format_size "$mem")" "$svc"
        done
}

# ── WSL Resources ──────────────────────────────────────────────────
diagnose_wsl_resources() {
    print_header "WSL Resource Analysis"

    if ! is_wsl; then
        print_info "Not running in WSL, skipping"
        return
    fi

    # WSL version
    local wsl_ver
    wsl_ver=$(get_wsl_version)
    print_info "WSL Version: $wsl_ver"

    # Kernel
    print_info "Kernel: $(uname -r)"

    # Distro
    if [[ -f /etc/os-release ]]; then
        local distro
        distro=$(. /etc/os-release && echo "$PRETTY_NAME")
        print_info "Distro: $distro"
    fi

    echo ""

    # Check .wslconfig
    local wslconfig="/mnt/c/Users/$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')/.wslconfig"
    if [[ -f "$wslconfig" ]]; then
        print_info ".wslconfig found:"
        while IFS= read -r line; do
            [[ -n "$line" ]] && echo "    $line"
        done < "$wslconfig"
    else
        print_warning ".wslconfig not found — WSL will use default resource limits"
        print_info "Consider creating $wslconfig to limit memory/CPU usage"
    fi

    echo ""

    # Disk usage of WSL root filesystem
    print_info "WSL filesystem usage:"
    df -h / 2>/dev/null | tail -1 | while read -r fs size used avail pct mount; do
        printf "  Size: %-8s  Used: %-8s  Avail: %-8s  (%s)\n" "$size" "$used" "$avail" "$pct"
    done
}
```

**Step 2: Test diagnostics**

Run: `/mnt/c/Coding/WSLMole/wslmole diagnose memory`
Expected: Shows memory breakdown with progress bar.

Run: `/mnt/c/Coding/WSLMole/wslmole diagnose processes`
Expected: Shows top CPU and memory consumers.

**Step 3: Commit**

```bash
cd /mnt/c/Coding/WSLMole
git add lib/diagnose.sh
git commit -m "feat: add system diagnostics module with WSL resource analysis"
```

---

### Task 7: Package Manager Module

**Files:**
- Create: `lib/packages.sh`

**Step 1: Create `lib/packages.sh`**

```bash
#!/usr/bin/env bash
# WSLMole - Package Manager Module (apt + snap)

# ── CLI Handler ─────────────────────────────────────────────────────
cmd_packages() {
    local action=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                echo "Usage: wslmole packages [action]"
                echo ""
                echo "Actions:"
                echo "  audit       Check for available updates"
                echo "  update      Update all packages (apt + snap)"
                echo "  autoremove  Remove orphaned packages"
                echo "  clean       Clean package caches"
                echo "  list        List installed packages"
                return 0
                ;;
            -*)
                print_error "Unknown option: $1"; return 1
                ;;
            *)
                action="$1"; shift
                ;;
        esac
    done

    if [[ -z "$action" ]]; then
        # Interactive: show all info
        cmd_packages_action "audit"
        return
    fi

    cmd_packages_action "$action"
}

# ── Action Dispatch ─────────────────────────────────────────────────
cmd_packages_action() {
    local action="$1"

    case "$action" in
        audit)     packages_audit ;;
        update)    packages_update ;;
        autoremove) packages_autoremove ;;
        clean)     packages_clean ;;
        list)      packages_list ;;
        *)
            print_error "Unknown action: $action"
            print_info "Available: audit, update, autoremove, clean, list"
            return 1
            ;;
    esac
}

# ── Audit (Check Updates) ──────────────────────────────────────────
packages_audit() {
    print_header "Package Update Check"

    # APT updates
    print_info "Checking apt updates..."
    apt list --upgradable 2>/dev/null | tail -n +2 | while IFS= read -r line; do
        print_item "$line"
    done

    local apt_count
    apt_count=$(apt list --upgradable 2>/dev/null | tail -n +2 | wc -l)
    echo ""
    if [[ $apt_count -gt 0 ]]; then
        print_warning "$apt_count apt package(s) can be upgraded"
    else
        print_success "All apt packages are up to date"
    fi

    # Snap updates
    if command -v snap &>/dev/null; then
        echo ""
        print_info "Checking snap updates..."
        local snap_refresh
        snap_refresh=$(snap refresh --list 2>/dev/null)
        if [[ -n "$snap_refresh" && "$snap_refresh" != *"All snaps up to date"* ]]; then
            echo "$snap_refresh" | while IFS= read -r line; do
                print_item "$line"
            done
        else
            print_success "All snaps are up to date"
        fi
    fi
}

# ── Update All ──────────────────────────────────────────────────────
packages_update() {
    print_header "Package Updates"

    # APT
    if require_root_or_skip "apt update"; then
        if confirm "Run apt update && apt upgrade?"; then
            print_info "Updating package lists..."
            apt-get update -qq 2>/dev/null
            print_info "Upgrading packages..."
            apt-get upgrade -y 2>/dev/null
            print_success "APT packages updated"
        fi
    fi

    # Snap
    if command -v snap &>/dev/null; then
        echo ""
        if confirm "Refresh snap packages?"; then
            print_info "Refreshing snaps..."
            snap refresh 2>/dev/null && \
                print_success "Snap packages refreshed" || \
                print_warning "Snap refresh may need sudo"
        fi
    fi
}

# ── Autoremove ──────────────────────────────────────────────────────
packages_autoremove() {
    print_header "Remove Orphaned Packages"

    if ! require_root_or_skip "apt autoremove"; then
        # Show what would be removed
        local autoremove_list
        autoremove_list=$(apt-get --dry-run autoremove 2>/dev/null | grep "^Remv " | awk '{print $2}')
        if [[ -n "$autoremove_list" ]]; then
            print_info "Packages that would be removed:"
            echo "$autoremove_list" | while IFS= read -r pkg; do
                print_item "$pkg"
            done
            print_info "Run with sudo to remove these packages"
        else
            print_success "No orphaned packages found"
        fi
        return
    fi

    if confirm "Remove orphaned packages?"; then
        apt-get autoremove -y 2>/dev/null
        print_success "Orphaned packages removed"
    fi
}

# ── Clean Cache ─────────────────────────────────────────────────────
packages_clean() {
    print_header "Clean Package Caches"

    # APT cache size
    local apt_cache_size
    apt_cache_size=$(du -sb /var/cache/apt/archives/ 2>/dev/null | cut -f1 || echo 0)
    print_info "APT cache: $(format_size "${apt_cache_size:-0}")"

    if require_root_or_skip "clean apt cache"; then
        if confirm "Clean APT cache?"; then
            apt-get clean 2>/dev/null
            apt-get autoclean 2>/dev/null
            print_success "APT cache cleaned"
        fi
    fi

    # Snap cache (old revisions)
    if command -v snap &>/dev/null; then
        echo ""
        local old_snap_count
        old_snap_count=$(snap list --all 2>/dev/null | awk '/disabled/' | wc -l)
        print_info "Old snap revisions: $old_snap_count"
        if [[ $old_snap_count -gt 0 ]]; then
            print_info "Use 'System Cleanup > Snap Cache' to remove old revisions"
        fi
    fi
}

# ── List Installed ──────────────────────────────────────────────────
packages_list() {
    print_header "Installed Packages"

    # APT count
    local apt_count
    apt_count=$(dpkg --get-selections 2>/dev/null | wc -l)
    print_info "APT packages installed: $apt_count"

    # Snap list
    if command -v snap &>/dev/null; then
        echo ""
        print_info "Snap packages:"
        snap list 2>/dev/null | while IFS= read -r line; do
            echo "    $line"
        done
    fi
}
```

**Step 2: Test package manager**

Run: `/mnt/c/Coding/WSLMole/wslmole packages audit`
Expected: Shows available apt/snap updates.

Run: `/mnt/c/Coding/WSLMole/wslmole packages --help`
Expected: Shows packages help text.

**Step 3: Commit**

```bash
cd /mnt/c/Coding/WSLMole
git add lib/packages.sh
git commit -m "feat: add package manager module for apt and snap"
```

---

### Task 8: WSL Tools Module

**Files:**
- Create: `lib/wsl.sh`

**Step 1: Create `lib/wsl.sh`**

```bash
#!/usr/bin/env bash
# WSLMole - WSL-Specific Tools Module

# ── CLI Handler ─────────────────────────────────────────────────────
cmd_wsl() {
    local action=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                echo "Usage: wslmole wsl [action]"
                echo ""
                echo "Actions:"
                echo "  info       WSL version, distro, config info"
                echo "  memory     Memory usage vs .wslconfig limits"
                echo "  compact    Guide to compact ext4.vhdx"
                echo "  interop    Windows interop status"
                return 0
                ;;
            -*)
                print_error "Unknown option: $1"; return 1
                ;;
            *)
                action="$1"; shift
                ;;
        esac
    done

    if [[ -z "$action" ]]; then
        action="info"
    fi

    cmd_wsl_action "$action"
}

# ── Action Dispatch ─────────────────────────────────────────────────
cmd_wsl_action() {
    local action="$1"

    if ! is_wsl; then
        print_error "Not running inside WSL"
        return 1
    fi

    case "$action" in
        info)    wsl_info ;;
        memory)  wsl_memory ;;
        compact) wsl_compact_guide ;;
        interop) wsl_interop ;;
        *)
            print_error "Unknown action: $action"
            print_info "Available: info, memory, compact, interop"
            return 1
            ;;
    esac
}

# ── WSL Info ────────────────────────────────────────────────────────
wsl_info() {
    print_header "WSL Information"

    print_info "WSL Version: $(get_wsl_version)"
    print_info "Kernel: $(uname -r)"

    if [[ -f /etc/os-release ]]; then
        local distro
        distro=$(. /etc/os-release && echo "$PRETTY_NAME")
        print_info "Distro: $distro"
    fi

    print_info "Hostname: $(hostname)"
    print_info "User: $(whoami)"
    print_info "Shell: $SHELL"

    echo ""

    # .wslconfig
    local win_user
    win_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
    local wslconfig="/mnt/c/Users/${win_user}/.wslconfig"

    if [[ -f "$wslconfig" ]]; then
        print_info ".wslconfig ($wslconfig):"
        echo ""
        while IFS= read -r line; do
            echo "    $line"
        done < "$wslconfig"
    else
        print_warning "No .wslconfig found"
        print_info "Path checked: $wslconfig"
        print_info "Create one to control WSL resource limits"
        echo ""
        print_info "Example .wslconfig:"
        echo "    [wsl2]"
        echo "    memory=8GB"
        echo "    processors=4"
        echo "    swap=4GB"
    fi

    echo ""

    # /etc/wsl.conf
    if [[ -f /etc/wsl.conf ]]; then
        print_info "/etc/wsl.conf:"
        echo ""
        while IFS= read -r line; do
            echo "    $line"
        done < /etc/wsl.conf
    else
        print_info "No /etc/wsl.conf (using defaults)"
    fi
}

# ── Memory Check ────────────────────────────────────────────────────
wsl_memory() {
    print_header "WSL Memory Analysis"

    local total_kb available_kb used_kb
    total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
    available_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
    used_kb=$((total_kb - available_kb))
    local pct=$((used_kb * 100 / total_kb))

    printf "  Allocated to WSL: %s\n" "$(format_size $((total_kb * 1024)))"
    printf "  Used:             %s (%d%%)\n" "$(format_size $((used_kb * 1024)))" "$pct"
    printf "  Available:        %s\n" "$(format_size $((available_kb * 1024)))"

    echo ""

    # Check .wslconfig memory limit
    local win_user
    win_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
    local wslconfig="/mnt/c/Users/${win_user}/.wslconfig"
    local configured_limit=""

    if [[ -f "$wslconfig" ]]; then
        configured_limit=$(grep -i "^memory" "$wslconfig" 2>/dev/null | cut -d= -f2 | tr -d ' ')
    fi

    if [[ -n "$configured_limit" ]]; then
        print_info "Configured memory limit: $configured_limit"
    else
        print_warning "No memory limit configured in .wslconfig"
        print_info "WSL defaults to 50% of host RAM or 8GB (whichever is less)"

        # Suggest a limit
        local host_ram_gb=$((total_kb / 1048576))
        local suggested=$((host_ram_gb > 8 ? 8 : host_ram_gb))
        echo ""
        print_info "Suggestion: Add to .wslconfig:"
        echo "    [wsl2]"
        echo "    memory=${suggested}GB"
    fi

    # Swap info
    echo ""
    local swap_total swap_free
    swap_total=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
    swap_free=$(awk '/^SwapFree:/ {print $2}' /proc/meminfo)
    local swap_used=$((swap_total - swap_free))

    if [[ $swap_total -gt 0 ]]; then
        printf "  Swap Total: %s\n" "$(format_size $((swap_total * 1024)))"
        printf "  Swap Used:  %s\n" "$(format_size $((swap_used * 1024)))"
    else
        print_info "Swap not configured"
    fi
}

# ── Disk Compact Guide ─────────────────────────────────────────────
wsl_compact_guide() {
    print_header "WSL Disk Compaction Guide"

    print_info "WSL2 uses a virtual disk (ext4.vhdx) that grows but doesn't auto-shrink."
    print_info "After cleaning files, compact the vhdx to reclaim Windows disk space."
    echo ""

    # Show current WSL disk usage
    print_info "Current WSL disk usage:"
    df -h / 2>/dev/null | tail -1 | while read -r fs size used avail pct mount; do
        printf "    Size: %-8s  Used: %-8s  Avail: %-8s  (%s)\n" "$size" "$used" "$avail" "$pct"
    done

    echo ""
    print_info "To compact the virtual disk, run these commands in ${BOLD}Windows PowerShell (Admin)${NC}:"
    echo ""
    echo "    # 1. Shut down WSL"
    echo "    wsl --shutdown"
    echo ""
    echo "    # 2. Find your vhdx file (usually at):"

    local win_user
    win_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
    local distro_name
    distro_name=$(. /etc/os-release 2>/dev/null && echo "${ID^}" || echo "Ubuntu")

    echo "    # C:\\Users\\${win_user}\\AppData\\Local\\Packages\\*${distro_name}*\\LocalState\\ext4.vhdx"
    echo ""
    echo "    # 3. Compact the disk"
    echo "    wsl --manage ${distro_name} --compact"
    echo ""
    echo "    # Alternative (older WSL versions):"
    echo "    diskpart"
    echo "    select vdisk file=\"C:\\Users\\${win_user}\\AppData\\Local\\Packages\\...\\ext4.vhdx\""
    echo "    compact vdisk"
    echo "    exit"
    echo ""
    print_info "This can recover significant space after large cleanups."
}

# ── Interop Status ──────────────────────────────────────────────────
wsl_interop() {
    print_header "WSL Interop Status"

    # Check if interop is enabled
    if [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
        print_success "Windows interop: Enabled"
    else
        print_warning "Windows interop: Disabled"
    fi

    # Check PATH integration
    if echo "$PATH" | grep -q "/mnt/c/"; then
        print_success "Windows PATH integration: Enabled"
        local win_path_count
        win_path_count=$(echo "$PATH" | tr ':' '\n' | grep -c "/mnt/c/")
        print_info "Windows PATH entries: $win_path_count"
    else
        print_info "Windows PATH integration: Disabled"
    fi

    # /etc/wsl.conf interop settings
    if [[ -f /etc/wsl.conf ]]; then
        local interop_enabled
        interop_enabled=$(grep -i "^enabled" /etc/wsl.conf 2>/dev/null | head -1 | cut -d= -f2 | tr -d ' ')
        local append_path
        append_path=$(grep -i "^appendWindowsPath" /etc/wsl.conf 2>/dev/null | head -1 | cut -d= -f2 | tr -d ' ')

        if [[ -n "$interop_enabled" ]]; then
            print_info "wsl.conf interop.enabled: $interop_enabled"
        fi
        if [[ -n "$append_path" ]]; then
            print_info "wsl.conf interop.appendWindowsPath: $append_path"
        fi
    fi

    echo ""

    # Windows executable access
    print_info "Windows executable access:"
    for exe in cmd.exe powershell.exe explorer.exe code; do
        if command -v "$exe" &>/dev/null; then
            print_success "$exe: $(command -v "$exe")"
        else
            print_item "$exe: not found"
        fi
    done
}
```

**Step 2: Test WSL tools**

Run: `/mnt/c/Coding/WSLMole/wslmole wsl info`
Expected: Shows WSL version, distro, .wslconfig contents.

Run: `/mnt/c/Coding/WSLMole/wslmole wsl --help`
Expected: Shows wsl subcommand help.

**Step 3: Commit**

```bash
cd /mnt/c/Coding/WSLMole
git add lib/wsl.sh
git commit -m "feat: add WSL-specific tools module"
```

---

### Task 9: Quick Scan

The quick scan function lives in the main `wslmole` script since it pulls from multiple modules. We'll add it as a function in `lib/common.sh` or a new small file.

**Files:**
- Create: `lib/quickscan.sh`

**Step 1: Create `lib/quickscan.sh`**

```bash
#!/usr/bin/env bash
# WSLMole - Quick Scan Module

run_quick_scan() {
    # Cute mole ASCII art
    echo -e "${CYAN}"
    cat << 'ART'
      /\_/\
     ( o.o )
      > ^ <   WSLMole Quick Scan
     /|   |\
    (_|   |_)
ART
    echo -e "${NC}"

    local score=100
    local recommendations=()
    local cleanable_total=0

    # ── Cleanable Space ─────────────────────────────────────────────
    # APT cache
    local apt_cache_size
    apt_cache_size=$(du -sb /var/cache/apt/archives/ 2>/dev/null | cut -f1 || echo 0)
    cleanable_total=$((cleanable_total + apt_cache_size))

    # Old logs
    local log_size=0
    while IFS= read -r -d '' file; do
        local fsize
        fsize=$(stat -c%s "$file" 2>/dev/null || echo 0)
        log_size=$((log_size + fsize))
    done < <(find /var/log -type f \( -name "*.gz" -o -name "*.old" -o -name "*.1" \) -print0 2>/dev/null)
    cleanable_total=$((cleanable_total + log_size))

    # Snap old revisions
    local snap_size=0
    if command -v snap &>/dev/null; then
        local old_snaps
        old_snaps=$(snap list --all 2>/dev/null | awk '/disabled/{print $1}' | wc -l)
        if [[ $old_snaps -gt 0 ]]; then
            snap_size=$((old_snaps * 100 * 1048576))  # Rough estimate: 100MB per revision
        fi
    fi
    cleanable_total=$((cleanable_total + snap_size))

    # Tmp files
    local tmp_size=0
    tmp_size=$(du -sb /tmp 2>/dev/null | cut -f1 || echo 0)
    cleanable_total=$((cleanable_total + tmp_size))

    # ── Health Checks ───────────────────────────────────────────────
    # Memory pressure
    local mem_total mem_available
    mem_total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 1)
    mem_available=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 1)
    local mem_pct=$(( (mem_total - mem_available) * 100 / mem_total ))
    if [[ $mem_pct -ge 80 ]]; then
        score=$((score - 15))
        recommendations+=("High memory usage detected (${mem_pct}%)")
    elif [[ $mem_pct -ge 60 ]]; then
        score=$((score - 5))
    fi

    # Disk usage
    local disk_pct
    disk_pct=$(df / 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
    if [[ "${disk_pct:-0}" -ge 90 ]]; then
        score=$((score - 20))
        recommendations+=("Disk usage critical (${disk_pct}%)")
    elif [[ "${disk_pct:-0}" -ge 75 ]]; then
        score=$((score - 10))
        recommendations+=("Disk usage high (${disk_pct}%)")
    fi

    # Failed services
    if command -v systemctl &>/dev/null; then
        local failed_count
        failed_count=$(systemctl --no-pager list-units --state=failed --plain --no-legend 2>/dev/null | wc -l)
        if [[ $failed_count -gt 0 ]]; then
            score=$((score - 5))
            recommendations+=("$failed_count failed systemd service(s) detected")
        fi
    fi

    # WSL-specific checks
    if is_wsl; then
        local win_user
        win_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
        local wslconfig="/mnt/c/Users/${win_user}/.wslconfig"
        if [[ ! -f "$wslconfig" ]]; then
            score=$((score - 5))
            recommendations+=("WSL memory limit not configured (.wslconfig)")
        fi

        # Upgradable packages
        local upgradable
        upgradable=$(apt list --upgradable 2>/dev/null | tail -n +2 | wc -l)
        if [[ $upgradable -gt 10 ]]; then
            score=$((score - 5))
            recommendations+=("$upgradable packages have available updates")
        fi
    fi

    # Clamp score
    [[ $score -lt 0 ]] && score=0

    # ── Output ──────────────────────────────────────────────────────
    local grade color
    if [[ $score -ge 90 ]]; then
        grade="Excellent"; color="$GREEN"
    elif [[ $score -ge 70 ]]; then
        grade="Good"; color="$YELLOW"
    elif [[ $score -ge 50 ]]; then
        grade="Fair"; color="$YELLOW"
    else
        grade="Poor"; color="$RED"
    fi

    echo -e "  Health Score: ${color}${BOLD}${score}/100${NC} (${grade})"
    echo ""

    if [[ $cleanable_total -gt 0 ]]; then
        echo -e "  Cleanable space found: ${BOLD}$(format_size $cleanable_total)${NC}"
        [[ $apt_cache_size -gt 0 ]] && printf "    APT cache:       %s\n" "$(format_size "$apt_cache_size")"
        [[ $log_size -gt 0 ]]       && printf "    Old logs:        %s\n" "$(format_size "$log_size")"
        [[ $snap_size -gt 0 ]]      && printf "    Snap revisions:  %s\n" "$(format_size "$snap_size")"
        [[ $tmp_size -gt 0 ]]       && printf "    Temp files:      %s\n" "$(format_size "$tmp_size")"
        echo ""
    fi

    if [[ ${#recommendations[@]} -gt 0 ]]; then
        echo "  Recommendations:"
        for rec in "${recommendations[@]}"; do
            echo -e "    ${YELLOW}⚠${NC} $rec"
        done
        echo ""
    fi

    echo -e "  Run ${BOLD}wslmole${NC} for full interactive menu"
    echo -e "  Run ${BOLD}wslmole clean --dry-run${NC} to preview cleanup"
    echo ""
}
```

**Step 2: Test quick scan**

Run: `/mnt/c/Coding/WSLMole/wslmole -q`
Expected: Shows mole ASCII art, health score, cleanable space, and recommendations.

**Step 3: Commit**

```bash
cd /mnt/c/Coding/WSLMole
git add lib/quickscan.sh
git commit -m "feat: add quick scan with health score and recommendations"
```

---

### Task 10: Install Script and README

**Files:**
- Create: `install.sh`
- Create: `README.md`
- Create: `LICENSE`

**Step 1: Create `install.sh`**

```bash
#!/usr/bin/env bash
# WSLMole Installer
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/usr/local/bin"

echo "Installing WSLMole..."

if [[ -w "$INSTALL_DIR" ]]; then
    ln -sf "$SCRIPT_DIR/wslmole" "$INSTALL_DIR/wslmole"
    echo "Installed: $INSTALL_DIR/wslmole -> $SCRIPT_DIR/wslmole"
else
    echo "Need write access to $INSTALL_DIR"
    echo "Run: sudo ln -sf '$SCRIPT_DIR/wslmole' '$INSTALL_DIR/wslmole'"
    echo ""
    echo "Or add to PATH manually:"
    echo "  echo 'export PATH=\"$SCRIPT_DIR:\$PATH\"' >> ~/.bashrc"
fi

echo "Done! Run 'wslmole' to get started."
```

**Step 2: Create `README.md`**

Write a README following the same style as WinMole's README but adapted for WSLMole. Include: description, features list, installation instructions (clone + install.sh), quick start, CLI reference, safety features, and license.

**Step 3: Create `LICENSE` (MIT)**

Standard MIT license file.

**Step 4: Make install.sh executable and test**

Run: `chmod +x /mnt/c/Coding/WSLMole/install.sh`

**Step 5: Commit**

```bash
cd /mnt/c/Coding/WSLMole
git add install.sh README.md LICENSE
git commit -m "feat: add install script, README, and MIT license"
```

---

### Task 11: Integration Test — Full Interactive Flow

**Step 1: Verify all CLI commands work**

Run each of these and check for no bash errors:

```bash
/mnt/c/Coding/WSLMole/wslmole --version
/mnt/c/Coding/WSLMole/wslmole --help
/mnt/c/Coding/WSLMole/wslmole -q
/mnt/c/Coding/WSLMole/wslmole clean --dry-run
/mnt/c/Coding/WSLMole/wslmole clean --help
/mnt/c/Coding/WSLMole/wslmole disk "$HOME" -m summary
/mnt/c/Coding/WSLMole/wslmole disk --help
/mnt/c/Coding/WSLMole/wslmole dev "$HOME" --dry-run
/mnt/c/Coding/WSLMole/wslmole dev --help
/mnt/c/Coding/WSLMole/wslmole diagnose memory
/mnt/c/Coding/WSLMole/wslmole diagnose --help
/mnt/c/Coding/WSLMole/wslmole packages audit
/mnt/c/Coding/WSLMole/wslmole packages --help
/mnt/c/Coding/WSLMole/wslmole wsl info
/mnt/c/Coding/WSLMole/wslmole wsl --help
```

Expected: Each command produces meaningful output with no bash syntax errors.

**Step 2: Fix any issues found**

**Step 3: Final commit if fixes were needed**

```bash
cd /mnt/c/Coding/WSLMole
git add -A
git commit -m "fix: resolve issues found during integration testing"
```
