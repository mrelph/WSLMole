#!/usr/bin/env bash
# WSLMole - Interactive CLI Menu System
# Modern inline CLI menus

# Note: Strict mode set in main script

# ── UI Primitives ────────────────────────────────────────────────────

# Get usable terminal width (capped for readability)
_term_width() {
    local w
    w=$(tput cols 2>/dev/null || echo 60)
    (( w > 64 )) && w=64
    echo "$w"
}

# Draw a rounded box top:  ╭──────╮
_box_top() {
    local w; w=$(_term_width)
    local inner=$((w - 2))
    local line; line=$(printf '─%.0s' $(seq 1 "$inner"))
    echo -e "  ${DIM}╭${line}╮${NC}"
}

# Draw a rounded box bottom:  ╰──────╯
_box_bottom() {
    local w; w=$(_term_width)
    local inner=$((w - 2))
    local line; line=$(printf '─%.0s' $(seq 1 "$inner"))
    echo -e "  ${DIM}╰${line}╯${NC}"
}

# Draw a box row with content:  │  content  │
_box_row() {
    local content="$1"
    local w; w=$(_term_width)
    local inner=$((w - 2))
    # Strip ANSI for length calculation
    local stripped
    stripped=$(echo -e "$content" | sed 's/\x1b\[[0-9;]*m//g')
    local pad=$((inner - ${#stripped} - 2))
    (( pad < 0 )) && pad=0
    printf '  %b %b%*s %b\n' "${DIM}│${NC}" "$content" "$pad" "" "${DIM}│${NC}"
}

# Draw a separator inside box:  │ ─────── │
_box_sep() {
    local w; w=$(_term_width)
    local inner=$((w - 4))
    local line; line=$(printf '─%.0s' $(seq 1 "$inner"))
    echo -e "  ${DIM}│ ${line} │${NC}"
}

# Empty box row
_box_empty() {
    _box_row ""
}

press_enter() {
    echo ""
    echo -en "  ${DIM}press enter to continue...${NC}"
    read -r
}

# ── Menu Renderer ────────────────────────────────────────────────────
# Args: title, breadcrumb, then pairs of "key" "label"
# Sets MENU_CHOICE
_menu_prompt() {
    local title="$1"; shift
    local breadcrumb="$1"; shift

    echo ""
    _box_top
    _box_row "${BOLD}${WHITE}${title}${NC}"
    if [[ -n "$breadcrumb" ]]; then
        _box_row "${DIM}${breadcrumb}${NC}"
    fi
    _box_sep

    while [[ $# -ge 2 ]]; do
        local key="$1" label="$2"; shift 2
        if [[ "$key" == "0" ]]; then
            _box_sep
            _box_row "  ${DIM}0${NC}  ${DIM}${label}${NC}"
        else
            _box_row "  ${CYAN}${key}${NC}  ${label}"
        fi
    done

    _box_bottom
    echo ""
    echo -en "  ${MAGENTA}❯${NC} "
    read -r MENU_CHOICE
}

# Inline yes/no
_menu_yesno() {
    echo ""
    echo -en "  ${YELLOW}?${NC} $1 ${DIM}[y/N]${NC} "
    local ans; read -r ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

# Inline text input with default
_menu_input() {
    local prompt="$1" default="$2"
    echo ""
    echo -en "  ${MAGENTA}❯${NC} ${prompt} ${DIM}[${default}]${NC} "
    local ans; read -r ans
    echo "${ans:-$default}"
}

# ── Main Interactive Menu ────────────────────────────────────────────
run_interactive_menu() {
    _show_welcome

    while true; do
        _menu_prompt "WSLMole" "" \
            1 "Action Plan" \
            2 "System Cleanup" \
            3 "Disk Analysis" \
            4 "Developer Cleanup" \
            5 "System Diagnostics" \
            6 "Package Manager" \
            7 "WSL Tools" \
            8 "Quick Scan" \
            9 "Auto-Fix" \
            10 "Check for Updates" \
            0 "Exit"

        case "$MENU_CHOICE" in
            1) cmd_plan; press_enter ;;
            2) menu_clean ;;
            3) menu_disk ;;
            4) menu_dev ;;
            5) menu_diagnose ;;
            6) menu_packages ;;
            7) menu_wsl ;;
            8) run_quick_scan; press_enter ;;
            9) cmd_fix; press_enter ;;
            10) cmd_update; press_enter ;;
            0|q|"") break ;;
            *) print_error "Invalid choice" ;;
        esac
    done

    echo ""
    echo -e "  ${DIM}Goodbye! 👋${NC}"
    echo ""
}

_show_welcome() {
    echo ""
    echo -e "  ${CYAN}${BOLD} __      __  ___ _     __  __       _${NC}"
    echo -e "  ${CYAN}${BOLD} \\ \\    / / / __| |   |  \\/  | ___ | | ___${NC}"
    echo -e "  ${CYAN}${BOLD}  \\ \\/\\/ /  \\__ \\ |__ | |\\/| |/ _ \\| |/ -_)${NC}"
    echo -e "  ${CYAN}${BOLD}   \\_/\\_/   |___/____||_|  |_|\\___/|_|\\___|${NC}"
    echo ""
    echo -e "  ${DIM}WSL System Optimization Tool${NC}  ${BOLD}v${WSLMOLE_VERSION}${NC}"
    echo ""
}

# ── System Cleanup Submenu ───────────────────────────────────────────
menu_clean() {
    while true; do
        _menu_prompt "System Cleanup" "wslmole › clean" \
            1 "Preview All" \
            2 "APT Cache" \
            3 "Snap Cache" \
            4 "Log Files" \
            5 "Temp Files" \
            6 "Browser Cache" \
            7 "User Data" \
            8 "WSL Specific" \
            9 "Clean All" \
            0 "Back"

        case "$MENU_CHOICE" in
            1) cmd_clean_category "preview"; press_enter ;;
            2) _menu_clean_confirm "apt" ;;
            3) _menu_clean_confirm "snap" ;;
            4) _menu_clean_confirm "logs" ;;
            5) _menu_clean_confirm "temp" ;;
            6) _menu_clean_confirm "browser" ;;
            7) _menu_clean_confirm "userdata" ;;
            8) _menu_clean_confirm "wsl" ;;
            9) _menu_clean_confirm "all" ;;
            0|q) return ;;
            *) print_error "Invalid choice" ;;
        esac
    done
}

_menu_clean_confirm() {
    local category="$1"
    local prev_dry_run="$DRY_RUN"
    DRY_RUN=true
    cmd_clean_category "$category"
    echo ""
    if _menu_yesno "Proceed with ${category} cleanup?"; then
        DRY_RUN=false
        cmd_clean_category "$category"
    else
        print_info "Cleanup cancelled."
    fi
    DRY_RUN="$prev_dry_run"
    press_enter
}

# ── Disk Analysis Submenu ────────────────────────────────────────────
menu_disk() {
    while true; do
        _menu_prompt "Disk Analysis" "wslmole › disk" \
            1 "Summary" \
            2 "Tree View" \
            3 "Largest Files" \
            4 "Largest Folders" \
            5 "File Types" \
            6 "Old Files" \
            0 "Back"

        case "$MENU_CHOICE" in
            1) cmd_disk_mode "summary"; press_enter ;;
            2) cmd_disk_mode "tree"; press_enter ;;
            3) cmd_disk_mode "files"; press_enter ;;
            4) cmd_disk_mode "folders"; press_enter ;;
            5) cmd_disk_mode "types"; press_enter ;;
            6) cmd_disk_mode "old"; press_enter ;;
            0|q) return ;;
            *) print_error "Invalid choice" ;;
        esac
    done
}

# ── Developer Cleanup Submenu ────────────────────────────────────────
menu_dev() {
    local path
    path=$(_menu_input "Project path to scan" "$HOME")

    local prev_dry_run="$DRY_RUN"
    print_header "Developer Cleanup Preview"
    DRY_RUN=true
    cmd_dev_scan "$path"
    echo ""

    if _menu_yesno "Proceed with cleanup?"; then
        DRY_RUN=false
        cmd_dev_scan "$path"
    else
        print_info "Cleanup cancelled."
    fi
    DRY_RUN="$prev_dry_run"
    press_enter
}

# ── System Diagnostics Submenu ───────────────────────────────────────
menu_diagnose() {
    while true; do
        _menu_prompt "System Diagnostics" "wslmole › diagnose" \
            1 "All" \
            2 "Processes" \
            3 "Memory" \
            4 "Services" \
            5 "WSL Resources" \
            0 "Back"

        case "$MENU_CHOICE" in
            1) cmd_diagnose_type "all"; press_enter ;;
            2) cmd_diagnose_type "process"; press_enter ;;
            3) cmd_diagnose_type "memory"; press_enter ;;
            4) cmd_diagnose_type "service"; press_enter ;;
            5) cmd_diagnose_type "wsl"; press_enter ;;
            0|q) return ;;
            *) print_error "Invalid choice" ;;
        esac
    done
}

# ── Package Manager Submenu ──────────────────────────────────────────
menu_packages() {
    while true; do
        _menu_prompt "Package Manager" "wslmole › packages" \
            1 "Check Updates" \
            2 "Update All" \
            3 "Autoremove" \
            4 "Clean Cache" \
            5 "List Installed" \
            0 "Back"

        case "$MENU_CHOICE" in
            1) cmd_packages_action "check"; press_enter ;;
            2) cmd_packages_action "update"; press_enter ;;
            3) cmd_packages_action "autoremove"; press_enter ;;
            4) cmd_packages_action "clean"; press_enter ;;
            5) cmd_packages_action "list"; press_enter ;;
            0|q) return ;;
            *) print_error "Invalid choice" ;;
        esac
    done
}

# ── WSL Tools Submenu ────────────────────────────────────────────────
menu_wsl() {
    while true; do
        _menu_prompt "WSL Tools" "wslmole › wsl" \
            1 "WSL Info" \
            2 "Memory Check" \
            3 "Disk Compact Guide" \
            4 "Interop Status" \
            0 "Back"

        case "$MENU_CHOICE" in
            1) cmd_wsl_action "info"; press_enter ;;
            2) cmd_wsl_action "memory"; press_enter ;;
            3) cmd_wsl_action "compact"; press_enter ;;
            4) cmd_wsl_action "interop"; press_enter ;;
            0|q) return ;;
            *) print_error "Invalid choice" ;;
        esac
    done
}
