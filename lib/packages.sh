#!/usr/bin/env bash
# WSLMole - Package Manager Module
# apt + snap package manager wrapper with audit, update, autoremove, clean, list

# Note: Strict mode set in main script

# Valid package actions
PACKAGES_ACTIONS=(audit update autoremove clean list)

# ── CLI Handler ────────────────────────────────────────────────────
cmd_packages() {
    local action=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cmd_packages_help
                return 0
                ;;
            -*)
                print_error "Unknown option: $1"
                cmd_packages_help
                return 1
                ;;
            *)
                action="$1"
                shift
                ;;
        esac
    done

    # Default to audit if no action specified
    if [[ -z "$action" ]]; then
        action="audit"
    fi

    cmd_packages_action "$action"
}

# ── Help ───────────────────────────────────────────────────────────
cmd_packages_help() {
    cat << 'EOF'
Usage: wslmole packages [action] [options]

Manage system packages via apt and snap.

Arguments:
  action               Package action to perform (default: audit)

Options:
  -h, --help           Show this help message

Actions:
  audit      Check for available apt and snap updates
  update     Update all apt and snap packages
  autoremove Remove unused apt dependencies
  clean      Clean apt cache and report snap old revisions
  list       List installed apt and snap packages

Examples:
  wslmole packages                    Check for updates (audit)
  wslmole packages audit              Check for available updates
  wslmole packages update             Update all packages
  wslmole packages autoremove         Remove unused dependencies
  wslmole packages clean              Clean package caches
  wslmole packages list               List installed packages
EOF
}

# ── Action Dispatcher ──────────────────────────────────────────────
cmd_packages_action() {
    local action="${1:-audit}"

    local rc=0
    case "$action" in
        audit|check)
            packages_audit || rc=$?
            ;;
        update)
            packages_update || rc=$?
            ;;
        autoremove)
            packages_autoremove || rc=$?
            ;;
        clean)
            packages_clean || rc=$?
            ;;
        list)
            packages_list || rc=$?
            ;;
        *)
            print_error "Unknown package action: $action"
            print_info "Valid actions: ${PACKAGES_ACTIONS[*]}"
            return 1
            ;;
    esac
    return $rc
}

# ── 1. Audit ──────────────────────────────────────────────────────
packages_audit() {
    print_header "Package Update Check"

    local has_updates=false

    # APT updates
    if command -v apt &>/dev/null; then
        print_info "Checking APT updates..."

        local upgradable
        upgradable=$(apt list --upgradable 2>/dev/null | grep -v "^Listing" || true)

        if [[ -n "$upgradable" ]]; then
            local apt_count
            apt_count=$(echo "$upgradable" | wc -l)
            has_updates=true
            print_warning "${apt_count} APT package(s) can be upgraded:"
            echo ""
            echo "$upgradable" | while IFS= read -r line; do
                print_item "$line"
            done
        else
            print_success "All APT packages are up to date"
        fi
    else
        print_info "apt not found - skipping APT check"
    fi

    echo ""

    # Snap updates
    if command -v snap &>/dev/null; then
        print_info "Checking Snap updates..."

        local snap_updates
        snap_updates=$(snap refresh --list 2>/dev/null || true)

        if [[ -n "$snap_updates" && ! "$snap_updates" =~ "All snaps up to date" ]]; then
            has_updates=true
            print_warning "Snap updates available:"
            echo ""
            echo "$snap_updates" | while IFS= read -r line; do
                print_item "$line"
            done
        else
            print_success "All Snap packages are up to date"
        fi
    else
        print_info "snap not installed - skipping Snap check"
    fi

    echo ""

    if [[ "${FORMAT:-text}" == "json" ]]; then
        json_output "$(to_json_kv "has_updates" "$has_updates")"
    elif [[ "$has_updates" == false ]]; then
        print_success "System is fully up to date!"
    else
        print_info "Run 'wslmole packages update' to install updates"
    fi
}

# ── 2. Update ─────────────────────────────────────────────────────
packages_update() {
    print_header "Package Update"

    # APT update + upgrade
    if command -v apt-get &>/dev/null; then
        print_info "APT Update & Upgrade"

        if ! require_root_or_skip "apt update/upgrade"; then
            print_info "Run with sudo to update APT packages"
        else
            if confirm "Run apt-get update && apt-get upgrade?"; then
                print_info "Running apt-get update..."
                if apt-get update 2>&1; then
                    print_success "Package lists updated"
                else
                    print_error "apt-get update failed"
                fi

                echo ""
                print_info "Running apt-get upgrade..."
                if apt-get upgrade -y 2>&1; then
                    print_success "APT packages upgraded"
                else
                    print_error "apt-get upgrade failed"
                fi
            else
                print_info "Skipped APT update"
            fi
        fi
    else
        print_info "apt-get not found - skipping APT update"
    fi

    echo ""

    # Snap refresh
    if command -v snap &>/dev/null; then
        print_info "Snap Refresh"

        if confirm "Run snap refresh to update all snaps?"; then
            print_info "Running snap refresh..."
            if snap refresh 2>&1; then
                print_success "Snap packages refreshed"
            else
                print_warning "snap refresh failed (may need sudo or network)"
            fi
        else
            print_info "Skipped Snap refresh"
        fi
    else
        print_info "snap not installed - skipping Snap refresh"
    fi

    echo ""
    print_success "Package update complete"
}

# ── 3. Autoremove ─────────────────────────────────────────────────
packages_autoremove() {
    print_header "Autoremove Unused Packages"

    if ! command -v apt-get &>/dev/null; then
        print_info "apt-get not found - nothing to do"
        return 0
    fi

    # Show what would be removed (dry-run works without root)
    print_info "Checking for unused dependencies..."

    local dry_run_output
    dry_run_output=$(apt-get --dry-run autoremove 2>/dev/null || true)

    local to_remove
    to_remove=$(echo "$dry_run_output" | grep "^Remv " || true)

    if [[ -z "$to_remove" ]]; then
        print_success "No unused packages to remove"
        return 0
    fi

    local remove_count
    remove_count=$(echo "$to_remove" | wc -l)
    print_warning "${remove_count} package(s) would be removed:"
    echo ""
    echo "$to_remove" | while IFS= read -r line; do
        local pkg_name
        pkg_name=$(echo "$line" | awk '{print $2}')
        print_item "$pkg_name"
    done

    echo ""

    if ! require_root_or_skip "apt autoremove"; then
        print_info "Run with sudo to remove unused packages"
        return 0
    fi

    if confirm "Remove ${remove_count} unused package(s)?"; then
        print_info "Running apt-get autoremove..."
        if apt-get autoremove -y 2>&1; then
            print_success "Unused packages removed"
        else
            print_error "apt-get autoremove failed"
        fi
    else
        print_info "Skipped autoremove"
    fi
}

# ── 4. Clean ──────────────────────────────────────────────────────
packages_clean() {
    print_header "Package Cache Cleanup"

    # APT cache size
    if command -v apt-get &>/dev/null; then
        local cache_dir="/var/cache/apt/archives"
        if [[ -d "$cache_dir" ]]; then
            local cache_bytes
            cache_bytes=$(du -sb "$cache_dir" 2>/dev/null | cut -f1 || echo 0)
            print_info "APT cache size: $(format_size "$cache_bytes")"
        else
            print_info "APT cache directory not found"
        fi

        echo ""

        if ! require_root_or_skip "apt cache clean"; then
            print_info "Run with sudo to clean APT cache"
        else
            if confirm "Run apt-get clean and autoclean?"; then
                print_info "Running apt-get clean..."
                if apt-get clean 2>/dev/null; then
                    print_success "apt-get clean completed"
                else
                    print_error "apt-get clean failed"
                fi

                print_info "Running apt-get autoclean..."
                if apt-get autoclean 2>/dev/null; then
                    print_success "apt-get autoclean completed"
                else
                    print_error "apt-get autoclean failed"
                fi

                # Show new cache size
                if [[ -d "$cache_dir" ]]; then
                    local new_bytes
                    new_bytes=$(du -sb "$cache_dir" 2>/dev/null | cut -f1 || echo 0)
                    print_info "APT cache now: $(format_size "$new_bytes")"
                fi
            else
                print_info "Skipped APT cache cleanup"
            fi
        fi
    else
        print_info "apt-get not found - skipping APT cache cleanup"
    fi

    echo ""

    # Snap old revisions count
    if command -v snap &>/dev/null; then
        print_info "Snap Old Revisions:"

        local disabled_snaps
        disabled_snaps=$(snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' || true)

        if [[ -n "$disabled_snaps" ]]; then
            local snap_count
            snap_count=$(echo "$disabled_snaps" | wc -l)
            print_warning "${snap_count} disabled snap revision(s) found"
            echo "$disabled_snaps" | while read -r snap_name snap_rev; do
                print_item "$snap_name (revision $snap_rev)"
            done
            print_info "Use 'wslmole clean -c snap' to remove disabled revisions"
        else
            print_success "No disabled snap revisions found"
        fi
    else
        print_info "snap not installed - skipping Snap check"
    fi
}

# ── 5. List ───────────────────────────────────────────────────────
packages_list() {
    print_header "Installed Packages"

    # APT packages
    if command -v dpkg &>/dev/null; then
        local apt_count
        apt_count=$(dpkg --get-selections 2>/dev/null | wc -l)
        print_info "APT packages installed: ${BOLD}${apt_count}${NC}"
    else
        print_info "dpkg not found - cannot count APT packages"
    fi

    echo ""

    # Snap packages
    if command -v snap &>/dev/null; then
        local snap_output
        snap_output=$(snap list 2>/dev/null || true)

        if [[ -n "$snap_output" ]]; then
            local snap_count
            # Subtract 1 for the header line
            snap_count=$(echo "$snap_output" | wc -l)
            snap_count=$((snap_count - 1))
            print_info "Snap packages installed: ${BOLD}${snap_count}${NC}"
            echo ""
            echo "$snap_output" | while IFS= read -r line; do
                echo "    $line"
            done
        else
            print_info "No snap packages installed"
        fi
    else
        print_info "snap not installed - skipping Snap list"
    fi

    echo ""
}
