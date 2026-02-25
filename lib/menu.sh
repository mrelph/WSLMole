#!/usr/bin/env bash
# WSLMole - Interactive CLI Menu System
# Pure bash inline menus - no whiptail dependency

# Note: Strict mode set in main script

# ── Menu Helper ────────────────────────────────────────────────────
# Usage: _menu_prompt "Title" "option1" "option2" ... "optionN"
# Last option is always treated as the exit/back option (mapped to 0)
# Returns: selected number via $REPLY
_menu_prompt() {
    local title="$1"
    shift
    local -a options=("$@")
    local count=${#options[@]}
    local last_idx=$((count - 1))

    echo ""
    echo -e "  ${BOLD}${title}${NC}"
    echo -e "  ${DIM}─────────────────────────────────${NC}"
    echo ""

    # Print numbered options (last item gets 0)
    local i
    for ((i = 0; i < last_idx; i++)); do
        echo -e "    ${BOLD}$((i + 1))${NC}) ${options[$i]}"
    done
    echo -e "    ${BOLD}0${NC}) ${options[$last_idx]}"
    echo ""

    local max=$last_idx
    while true; do
        echo -en "  ${CYAN}Choose [0-${max}]:${NC} "
        read -r REPLY
        # Validate input
        if [[ "$REPLY" =~ ^[0-9]+$ ]] && [[ "$REPLY" -ge 0 ]] && [[ "$REPLY" -le $max ]]; then
            return 0
        fi
        echo -e "  ${RED}Invalid choice.${NC} Enter a number 0-${max}."
    done
}

# ── Helpers ────────────────────────────────────────────────────────
press_enter() {
    echo ""
    echo -en "  ${DIM}Press Enter to continue...${NC}"
    read -r
}

# ── Main Interactive Menu ──────────────────────────────────────────
run_interactive_menu() {
    show_logo

    while true; do
        _menu_prompt "WSLMole Interactive Menu" \
            "System Cleanup" \
            "Disk Analysis" \
            "Developer Cleanup" \
            "System Diagnostics" \
            "Package Manager" \
            "WSL Tools" \
            "Quick Health Scan" \
            "Auto-Fix" \
            "Exit"

        case "$REPLY" in
            1) menu_clean ;;
            2) menu_disk ;;
            3) menu_dev ;;
            4) menu_diagnose ;;
            5) menu_packages ;;
            6) menu_wsl ;;
            7) run_quick_scan; press_enter ;;
            8) cmd_fix; press_enter ;;
            0) break ;;
        esac
    done

    echo ""
    print_success "Thanks for using WSLMole!"
    echo ""
}

# ── System Cleanup Submenu ─────────────────────────────────────────
menu_clean() {
    while true; do
        _menu_prompt "System Cleanup" \
            "Preview All" \
            "APT Cache" \
            "Snap Cache" \
            "Log Files" \
            "Temp Files" \
            "Browser Cache" \
            "User Data" \
            "WSL Specific" \
            "Clean All" \
            "Back"

        case "$REPLY" in
            1) cmd_clean_category "preview"; press_enter ;;
            2) _menu_clean_confirm "apt"; press_enter ;;
            3) _menu_clean_confirm "snap"; press_enter ;;
            4) _menu_clean_confirm "logs"; press_enter ;;
            5) _menu_clean_confirm "temp"; press_enter ;;
            6) _menu_clean_confirm "browser"; press_enter ;;
            7) _menu_clean_confirm "userdata"; press_enter ;;
            8) _menu_clean_confirm "wsl"; press_enter ;;
            9) _menu_clean_confirm "all"; press_enter ;;
            0) return ;;
        esac
    done
}

# Helper: preview then confirm for cleanup categories
_menu_clean_confirm() {
    local category="$1"
    # Preview first (dry run)
    local prev_dry_run="$DRY_RUN"
    DRY_RUN=true
    cmd_clean_category "$category"
    DRY_RUN="$prev_dry_run"
    echo ""
    # Ask to proceed
    if confirm "Proceed with ${category} cleanup?"; then
        cmd_clean_category "$category"
    else
        print_info "Cleanup cancelled."
    fi
}

# ── Disk Analysis Submenu ──────────────────────────────────────────
menu_disk() {
    while true; do
        _menu_prompt "Disk Analysis" \
            "Summary" \
            "Tree View" \
            "Largest Files" \
            "Largest Folders" \
            "File Types" \
            "Old Files" \
            "Back"

        case "$REPLY" in
            1) cmd_disk_mode "summary"; press_enter ;;
            2) cmd_disk_mode "tree"; press_enter ;;
            3) cmd_disk_mode "files"; press_enter ;;
            4) cmd_disk_mode "folders"; press_enter ;;
            5) cmd_disk_mode "types"; press_enter ;;
            6) cmd_disk_mode "old"; press_enter ;;
            0) return ;;
        esac
    done
}

# ── Developer Cleanup Submenu ──────────────────────────────────────
menu_dev() {
    echo ""
    echo -en "  ${CYAN}Enter project path to scan${NC} [${HOME}]: "
    read -r path
    path="${path:-$HOME}"

    # Dry-run preview first
    print_header "Developer Cleanup Preview"
    DRY_RUN=true cmd_dev_scan "$path"
    echo ""

    if confirm "Proceed with cleanup of developer artifacts in ${path}?"; then
        cmd_dev_scan "$path"
    else
        print_info "Cleanup cancelled."
    fi
    press_enter
}

# ── System Diagnostics Submenu ─────────────────────────────────────
menu_diagnose() {
    while true; do
        _menu_prompt "System Diagnostics" \
            "All" \
            "Process" \
            "Memory" \
            "Service" \
            "WSL Resources" \
            "Back"

        case "$REPLY" in
            1) cmd_diagnose_type "all"; press_enter ;;
            2) cmd_diagnose_type "process"; press_enter ;;
            3) cmd_diagnose_type "memory"; press_enter ;;
            4) cmd_diagnose_type "service"; press_enter ;;
            5) cmd_diagnose_type "wsl"; press_enter ;;
            0) return ;;
        esac
    done
}

# ── Package Manager Submenu ────────────────────────────────────────
menu_packages() {
    while true; do
        _menu_prompt "Package Manager" \
            "Check Updates" \
            "Update All" \
            "Autoremove" \
            "Clean Cache" \
            "List Installed" \
            "Back"

        case "$REPLY" in
            1) cmd_packages_action "check"; press_enter ;;
            2) cmd_packages_action "update"; press_enter ;;
            3) cmd_packages_action "autoremove"; press_enter ;;
            4) cmd_packages_action "clean"; press_enter ;;
            5) cmd_packages_action "list"; press_enter ;;
            0) return ;;
        esac
    done
}

# ── WSL Tools Submenu ──────────────────────────────────────────────
menu_wsl() {
    while true; do
        _menu_prompt "WSL Tools" \
            "WSL Info" \
            "Memory Check" \
            "Disk Compact Guide" \
            "Interop Status" \
            "Back"

        case "$REPLY" in
            1) cmd_wsl_action "info"; press_enter ;;
            2) cmd_wsl_action "memory"; press_enter ;;
            3) cmd_wsl_action "compact"; press_enter ;;
            4) cmd_wsl_action "interop"; press_enter ;;
            0) return ;;
        esac
    done
}
