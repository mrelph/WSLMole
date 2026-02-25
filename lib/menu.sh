#!/usr/bin/env bash
# WSLMole - Interactive TUI Menu System
# Whiptail-based menu for interactive mode

# Note: Strict mode set in main script

# ── Terminal Dimensions ──────────────────────────────────────────────
TERM_HEIGHT=$(tput lines 2>/dev/null || echo 24)
TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)
MENU_HEIGHT=$((TERM_HEIGHT - 10))

# ── Helpers ──────────────────────────────────────────────────────────
press_enter() {
    echo ""
    echo -en "  ${DIM}Press Enter to continue...${NC}"
    read -r
}

# ── Main Interactive Menu ────────────────────────────────────────────
run_interactive_menu() {
    # Check for whiptail
    if ! command -v whiptail &>/dev/null; then
        print_error "whiptail is required for interactive mode but is not installed."
        echo ""
        print_info "Install it with:"
        echo "    sudo apt install whiptail"
        echo ""
        exit 1
    fi

    show_logo

    while true; do
        local choice
        choice=$(whiptail --title "WSLMole - Main Menu" \
            --menu "Choose an option:" \
            "$TERM_HEIGHT" "$TERM_WIDTH" "$MENU_HEIGHT" \
            "1" "System Cleanup" \
            "2" "Disk Analysis" \
            "3" "Developer Cleanup" \
            "4" "System Diagnostics" \
            "5" "Package Manager" \
            "6" "WSL Tools" \
            "7" "Quick Health Scan" \
            "8" "Auto-Fix" \
            "9" "Exit" \
            3>&1 1>&2 2>&3) || break

        case "$choice" in
            1) menu_clean ;;
            2) menu_disk ;;
            3) menu_dev ;;
            4) menu_diagnose ;;
            5) menu_packages ;;
            6) menu_wsl ;;
            7) run_quick_scan; press_enter ;;
            8) cmd_fix; press_enter ;;
            9) break ;;
        esac
    done

    echo ""
    print_success "Thanks for using WSLMole!"
    echo ""
}

# ── System Cleanup Submenu ───────────────────────────────────────────
menu_clean() {
    while true; do
        local choice
        choice=$(whiptail --title "System Cleanup" \
            --menu "Choose a cleanup category:" \
            "$TERM_HEIGHT" "$TERM_WIDTH" "$MENU_HEIGHT" \
            "1"  "Preview All" \
            "2"  "APT Cache" \
            "3"  "Snap Cache" \
            "4"  "Log Files" \
            "5"  "Temp Files" \
            "6"  "Browser Cache" \
            "7"  "User Data" \
            "8"  "WSL Specific" \
            "9"  "Clean All" \
            "10" "Back to Main Menu" \
            3>&1 1>&2 2>&3) || return

        case "$choice" in
            1)  cmd_clean_category "preview" ;;
            2)  _menu_clean_confirm "apt" ;;
            3)  _menu_clean_confirm "snap" ;;
            4)  _menu_clean_confirm "logs" ;;
            5)  _menu_clean_confirm "temp" ;;
            6)  _menu_clean_confirm "browser" ;;
            7)  _menu_clean_confirm "userdata" ;;
            8)  _menu_clean_confirm "wsl" ;;
            9)  _menu_clean_confirm "all" ;;
            10) return ;;
        esac
        press_enter
    done
}

# Helper: preview then confirm for cleanup categories
_menu_clean_confirm() {
    local category="$1"
    # Preview first
    local prev_dry_run="$DRY_RUN"
    DRY_RUN=true
    cmd_clean_category "$category"
    DRY_RUN="$prev_dry_run"
    echo ""
    # Ask to proceed
    if whiptail --title "Confirm Cleanup" \
        --yesno "Proceed with ${category} cleanup?" \
        "$TERM_HEIGHT" "$TERM_WIDTH" 3>&1 1>&2 2>&3; then
        cmd_clean_category "$category"
    else
        print_info "Cleanup cancelled."
    fi
}

# ── Disk Analysis Submenu ────────────────────────────────────────────
menu_disk() {
    while true; do
        local choice
        choice=$(whiptail --title "Disk Analysis" \
            --menu "Choose an analysis mode:" \
            "$TERM_HEIGHT" "$TERM_WIDTH" "$MENU_HEIGHT" \
            "1" "Summary" \
            "2" "Tree View" \
            "3" "Largest Files" \
            "4" "Largest Folders" \
            "5" "File Types" \
            "6" "Old Files" \
            "7" "Back to Main Menu" \
            3>&1 1>&2 2>&3) || return

        case "$choice" in
            1) cmd_disk_mode "summary" ;;
            2) cmd_disk_mode "tree" ;;
            3) cmd_disk_mode "files" ;;
            4) cmd_disk_mode "folders" ;;
            5) cmd_disk_mode "types" ;;
            6) cmd_disk_mode "old" ;;
            7) return ;;
        esac
        press_enter
    done
}

# ── Developer Cleanup Submenu ────────────────────────────────────────
menu_dev() {
    local path
    path=$(whiptail --title "Developer Cleanup" \
        --inputbox "Enter project path to scan:" \
        "$TERM_HEIGHT" "$TERM_WIDTH" "$HOME" \
        3>&1 1>&2 2>&3) || return

    # Dry-run preview first
    print_header "Developer Cleanup Preview"
    DRY_RUN=true cmd_dev_scan "$path"
    echo ""

    if whiptail --title "Confirm Cleanup" \
        --yesno "Proceed with cleanup of developer artifacts in:\n${path}?" \
        "$TERM_HEIGHT" "$TERM_WIDTH" 3>&1 1>&2 2>&3; then
        cmd_dev_scan "$path"
    else
        print_info "Cleanup cancelled."
    fi
    press_enter
}

# ── System Diagnostics Submenu ───────────────────────────────────────
menu_diagnose() {
    while true; do
        local choice
        choice=$(whiptail --title "System Diagnostics" \
            --menu "Choose a diagnostic type:" \
            "$TERM_HEIGHT" "$TERM_WIDTH" "$MENU_HEIGHT" \
            "1" "All" \
            "2" "Process" \
            "3" "Memory" \
            "4" "Service" \
            "5" "WSL Resources" \
            "6" "Back to Main Menu" \
            3>&1 1>&2 2>&3) || return

        case "$choice" in
            1) cmd_diagnose_type "all" ;;
            2) cmd_diagnose_type "process" ;;
            3) cmd_diagnose_type "memory" ;;
            4) cmd_diagnose_type "service" ;;
            5) cmd_diagnose_type "wsl" ;;
            6) return ;;
        esac
        press_enter
    done
}

# ── Package Manager Submenu ──────────────────────────────────────────
menu_packages() {
    while true; do
        local choice
        choice=$(whiptail --title "Package Manager" \
            --menu "Choose an action:" \
            "$TERM_HEIGHT" "$TERM_WIDTH" "$MENU_HEIGHT" \
            "1" "Check Updates" \
            "2" "Update All" \
            "3" "Autoremove" \
            "4" "Clean Cache" \
            "5" "List Installed" \
            "6" "Back to Main Menu" \
            3>&1 1>&2 2>&3) || return

        case "$choice" in
            1) cmd_packages_action "check" ;;
            2) cmd_packages_action "update" ;;
            3) cmd_packages_action "autoremove" ;;
            4) cmd_packages_action "clean" ;;
            5) cmd_packages_action "list" ;;
            6) return ;;
        esac
        press_enter
    done
}

# ── WSL Tools Submenu ────────────────────────────────────────────────
menu_wsl() {
    while true; do
        local choice
        choice=$(whiptail --title "WSL Tools" \
            --menu "Choose an action:" \
            "$TERM_HEIGHT" "$TERM_WIDTH" "$MENU_HEIGHT" \
            "1" "WSL Info" \
            "2" "Memory Check" \
            "3" "Disk Compact Guide" \
            "4" "Interop Status" \
            "5" "Back to Main Menu" \
            3>&1 1>&2 2>&3) || return

        case "$choice" in
            1) cmd_wsl_action "info" ;;
            2) cmd_wsl_action "memory" ;;
            3) cmd_wsl_action "compact" ;;
            4) cmd_wsl_action "interop" ;;
            5) return ;;
        esac
        press_enter
    done
}
