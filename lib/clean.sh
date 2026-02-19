#!/usr/bin/env bash
# WSLMole - System Cleanup Module
# 7 cleanup categories: apt, snap, logs, tmp, browser, user, wsl

# Note: Strict mode set in main script

# All valid cleanup categories
CLEAN_CATEGORIES=(apt snap logs tmp browser user wsl)

# ── CLI Handler ────────────────────────────────────────────────────
cmd_clean() {
    local categories=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -c|--category)
                if [[ -z "${2:-}" ]]; then
                    print_error "--category requires a comma-separated list"
                    return 1
                fi
                IFS=',' read -ra categories <<< "$2"
                shift 2
                ;;
            -h|--help)
                cmd_clean_help
                return 0
                ;;
            *)
                print_error "Unknown option: $1"
                cmd_clean_help
                return 1
                ;;
        esac
    done

    # Default categories if none specified
    if [[ ${#categories[@]} -eq 0 ]]; then
        categories=("${CLEAN_CATEGORIES[@]}")
    fi

    # Expand "all" to all categories
    local expanded=()
    for cat in "${categories[@]}"; do
        if [[ "$cat" == "all" ]]; then
            expanded=("${CLEAN_CATEGORIES[@]}")
            break
        else
            expanded+=("$cat")
        fi
    done
    categories=("${expanded[@]}")

    print_header "System Cleanup"

    if [[ "$DRY_RUN" == true ]]; then
        print_warning "DRY RUN mode - no files will be deleted"
        echo ""
    fi

    local rc=0
    for cat in "${categories[@]}"; do
        cmd_clean_category "$cat" || rc=1
    done

    echo ""
    if [[ "${FORMAT:-text}" == "json" ]]; then
        json_output "$(to_json_kv "status" "complete" "dry_run" "$DRY_RUN" "categories" "${categories[*]}")"
    else
        print_success "Cleanup scan complete."
    fi
    return $rc
}

# ── Help ───────────────────────────────────────────────────────────
cmd_clean_help() {
    cat << 'EOF'
Usage: wslmole clean [options]

Scan and clean system caches, logs, temp files, and more.

Options:
  -n, --dry-run          Preview what would be cleaned without deleting
  -f, --force            Skip all confirmation prompts
  -c, --category LIST    Comma-separated categories to clean
  -h, --help             Show this help message

Categories:
  apt        APT package cache
  snap       Disabled snap revisions
  logs       Rotated log files and journal
  tmp        Temp files (/tmp, /var/tmp, ~/.cache)
  browser    Browser cache (Chrome, Chromium, Firefox, Edge)
  user       User data (thumbnails, trash, recent files)
  wsl        WSL-specific cleanup
  all        All of the above

Examples:
  wslmole clean --dry-run              Preview all categories
  wslmole clean -c apt,logs            Clean APT and logs only
  wslmole clean -f -c tmp              Force-clean temp files
  wslmole clean -n -c browser,user     Preview browser & user cleanup
EOF
}

# ── Category Dispatcher ────────────────────────────────────────────
cmd_clean_category() {
    local category="$1"

    case "$category" in
        apt)
            clean_apt
            ;;
        snap)
            clean_snap
            ;;
        logs)
            clean_logs
            ;;
        tmp|temp)
            clean_tmp
            ;;
        browser)
            clean_browser
            ;;
        user|userdata)
            clean_user
            ;;
        wsl)
            clean_wsl
            ;;
        all)
            for cat in "${CLEAN_CATEGORIES[@]}"; do
                cmd_clean_category "$cat"
            done
            ;;
        preview)
            # Preview mode: temporarily enable dry run, run all
            local prev_dry_run="$DRY_RUN"
            DRY_RUN=true
            for cat in "${CLEAN_CATEGORIES[@]}"; do
                cmd_clean_category "$cat"
            done
            DRY_RUN="$prev_dry_run"
            ;;
        *)
            print_error "Unknown cleanup category: $category"
            ;;
    esac
}

# ── 1. APT Cache ──────────────────────────────────────────────────
clean_apt() {
    print_header "APT Cache Cleanup"

    if ! command -v apt-get &>/dev/null; then
        print_info "apt-get not found - skipping"
        return 0
    fi

    require_root_or_skip "APT cache cleanup" || return 0

    # Show current cache size
    local cache_dir="/var/cache/apt/archives"
    if [[ -d "$cache_dir" ]]; then
        local cache_size
        cache_size=$(get_size_bytes "$cache_dir")
        print_info "APT cache size: $(format_size "$cache_size")"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] Would run: apt-get clean"
        print_info "[DRY RUN] Would run: apt-get autoclean"
        return 0
    fi

    if confirm "Clean APT package cache?"; then
        apt-get clean 2>/dev/null && print_success "apt-get clean completed"
        apt-get autoclean 2>/dev/null && print_success "apt-get autoclean completed"

        # Show new cache size
        if [[ -d "$cache_dir" ]]; then
            local new_size
            new_size=$(get_size_bytes "$cache_dir")
            print_info "APT cache now: $(format_size "$new_size")"
        fi
    else
        print_info "Skipped APT cache cleanup"
    fi
}

# ── 2. Snap Cache ─────────────────────────────────────────────────
clean_snap() {
    print_header "Snap Cleanup"

    if ! command -v snap &>/dev/null; then
        print_info "snap not installed - skipping"
        return 0
    fi

    # Find disabled snap revisions
    local disabled_snaps
    disabled_snaps=$(snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}')

    if [[ -z "$disabled_snaps" ]]; then
        print_success "No disabled snap revisions found"
        return 0
    fi

    print_info "Found disabled snap revisions:"
    echo "$disabled_snaps" | while read -r snap_name snap_rev; do
        print_item "$snap_name (revision $snap_rev)"
    done

    if [[ "$DRY_RUN" == true ]]; then
        echo "$disabled_snaps" | while read -r snap_name snap_rev; do
            print_info "[DRY RUN] Would remove: $snap_name revision $snap_rev"
        done
        return 0
    fi

    echo "$disabled_snaps" | while read -r snap_name snap_rev; do
        if confirm "Remove $snap_name revision $snap_rev?"; then
            if snap remove "$snap_name" --revision="$snap_rev" 2>/dev/null; then
                print_success "Removed $snap_name revision $snap_rev"
            else
                print_warning "Could not remove $snap_name revision $snap_rev (may need sudo)"
            fi
        else
            print_info "Skipped $snap_name revision $snap_rev"
        fi
    done
}

# ── 3. Log Files ──────────────────────────────────────────────────
clean_logs() {
    print_header "Log File Cleanup"

    local log_dir="/var/log"
    local total_cleaned=0

    # Find rotated logs
    print_info "Scanning for rotated log files..."
    local rotated_files
    rotated_files=$(find "$log_dir" -type f \( -name "*.gz" -o -name "*.old" -o -name "*.1" -o -name "*.2" -o -name "*.3" \) 2>/dev/null || true)

    if [[ -n "$rotated_files" ]]; then
        local count
        count=$(echo "$rotated_files" | wc -l)
        local total_size=0
        while IFS= read -r file; do
            local fsize
            fsize=$(get_size_bytes "$file")
            total_size=$((total_size + fsize))
        done <<< "$rotated_files"

        print_info "Found $count rotated log files ($(format_size "$total_size"))"

        while IFS= read -r file; do
            safe_delete "$file" "$(basename "$file")"
        done <<< "$rotated_files"
    else
        print_success "No rotated log files found"
    fi

    # Vacuum journalctl
    echo ""
    if command -v journalctl &>/dev/null; then
        if require_root_or_skip "journalctl vacuum"; then
            if [[ "$DRY_RUN" == true ]]; then
                local journal_size
                journal_size=$(journalctl --disk-usage 2>/dev/null | grep -oP '[\d.]+\s*[KMGT]?i?B' || echo "unknown")
                print_info "[DRY RUN] Would vacuum journalctl to 7 days (current usage: $journal_size)"
            else
                if confirm "Vacuum journalctl logs older than 7 days?"; then
                    journalctl --vacuum-time=7d 2>/dev/null && print_success "Journal vacuumed to 7 days"
                else
                    print_info "Skipped journal vacuum"
                fi
            fi
        fi
    fi
}

# ── 4. Temp Files ─────────────────────────────────────────────────
clean_tmp() {
    print_header "Temp File Cleanup"

    # /tmp - files older than 7 days
    print_info "Scanning /tmp for files older than 7 days..."
    local tmp_files
    tmp_files=$(find /tmp -type f -mtime +7 2>/dev/null || true)

    if [[ -n "$tmp_files" ]]; then
        local count
        count=$(echo "$tmp_files" | wc -l)
        print_info "Found $count old files in /tmp"
        while IFS= read -r file; do
            safe_delete "$file" "/tmp/$(basename "$file")"
        done <<< "$tmp_files"
    else
        print_success "No old files in /tmp"
    fi

    # /var/tmp - files older than 7 days
    echo ""
    print_info "Scanning /var/tmp for files older than 7 days..."
    local var_tmp_files
    var_tmp_files=$(find /var/tmp -type f -mtime +7 2>/dev/null || true)

    if [[ -n "$var_tmp_files" ]]; then
        local count
        count=$(echo "$var_tmp_files" | wc -l)
        print_info "Found $count old files in /var/tmp"
        while IFS= read -r file; do
            safe_delete "$file" "/var/tmp/$(basename "$file")"
        done <<< "$var_tmp_files"
    else
        print_success "No old files in /var/tmp"
    fi

    # ~/.cache cleanup
    echo ""
    local user_cache="$HOME/.cache"
    if [[ -d "$user_cache" ]]; then
        local cache_size
        cache_size=$(get_size_bytes "$user_cache")
        print_info "User cache size (~/.cache): $(format_size "$cache_size")"

        if [[ "$DRY_RUN" == true ]]; then
            print_info "[DRY RUN] Would offer to clean ~/.cache contents"
        else
            if confirm "Clean ~/.cache contents? (keeps directory structure)"; then
                find "$user_cache" -type f -mtime +7 -delete 2>/dev/null
                local new_size
                new_size=$(get_size_bytes "$user_cache")
                print_success "Cleaned old cache files (now $(format_size "$new_size"))"
            else
                print_info "Skipped ~/.cache cleanup"
            fi
        fi
    fi
}

# ── 5. Browser Cache ──────────────────────────────────────────────
clean_browser() {
    print_header "Browser Cache Cleanup"

    local found_any=false

    # Browser cache directories to check
    local -A browsers=(
        ["Google Chrome"]="$HOME/.cache/google-chrome"
        ["Chromium"]="$HOME/.cache/chromium"
        ["Mozilla Firefox"]="$HOME/.cache/mozilla/firefox"
        ["Microsoft Edge"]="$HOME/.cache/microsoft-edge"
    )

    # Also check config directories for additional cache
    local -A browser_configs=(
        ["Google Chrome"]="$HOME/.config/google-chrome"
        ["Chromium"]="$HOME/.config/chromium"
        ["Mozilla Firefox"]="$HOME/.mozilla/firefox"
        ["Microsoft Edge"]="$HOME/.config/microsoft-edge"
    )

    for browser in "Google Chrome" "Chromium" "Mozilla Firefox" "Microsoft Edge"; do
        local cache_dir="${browsers[$browser]}"
        local config_dir="${browser_configs[$browser]}"
        local total_size=0

        if [[ -d "$cache_dir" ]]; then
            local size
            size=$(get_size_bytes "$cache_dir")
            total_size=$((total_size + size))
        fi

        if [[ $total_size -gt 0 || -d "$cache_dir" ]]; then
            found_any=true
            print_info "$browser cache: $(format_size "$total_size")"

            if [[ "$DRY_RUN" == true ]]; then
                print_info "[DRY RUN] Would clean $browser cache"
            else
                if confirm "Clean $browser cache?"; then
                    if [[ -d "$cache_dir" ]]; then
                        find "$cache_dir" -type f -delete 2>/dev/null
                        print_success "Cleaned $browser cache"
                    fi
                else
                    print_info "Skipped $browser"
                fi
            fi
            echo ""
        fi
    done

    if [[ "$found_any" == false ]]; then
        print_success "No browser caches found"
    fi
}

# ── 6. User Data ──────────────────────────────────────────────────
clean_user() {
    print_header "User Data Cleanup"

    # Thumbnail cache
    local thumb_dir="$HOME/.cache/thumbnails"
    if [[ -d "$thumb_dir" ]]; then
        local thumb_size
        thumb_size=$(get_size_bytes "$thumb_dir")
        print_info "Thumbnail cache: $(format_size "$thumb_size")"
        safe_delete "$thumb_dir" "thumbnail cache"
        # Recreate the directory
        if [[ "$DRY_RUN" != true ]]; then
            mkdir -p "$thumb_dir" 2>/dev/null
        fi
    else
        print_success "No thumbnail cache found"
    fi

    # Trash
    echo ""
    local trash_dir="$HOME/.local/share/Trash"
    if [[ -d "$trash_dir" ]]; then
        local trash_size
        trash_size=$(get_size_bytes "$trash_dir")
        print_info "Trash size: $(format_size "$trash_size")"

        if [[ "$DRY_RUN" == true ]]; then
            print_info "[DRY RUN] Would empty trash"
        else
            if confirm "Empty trash?"; then
                rm -rf "${trash_dir:?}/files"/* 2>/dev/null
                rm -rf "${trash_dir:?}/info"/* 2>/dev/null
                print_success "Trash emptied"
            else
                print_info "Skipped trash cleanup"
            fi
        fi
    else
        print_success "Trash is empty"
    fi

    # Recently used file
    echo ""
    local recent_file="$HOME/.local/share/recently-used.xbel"
    if [[ -f "$recent_file" ]]; then
        local recent_size
        recent_size=$(get_size_bytes "$recent_file")
        print_info "Recently used file: $(format_size "$recent_size")"
        safe_delete "$recent_file" "recently-used.xbel"
    else
        print_success "No recently-used.xbel file found"
    fi
}

# ── 7. WSL Specific ───────────────────────────────────────────────
clean_wsl() {
    print_header "WSL Cleanup"

    if ! is_wsl; then
        print_info "Not running in WSL - skipping WSL-specific cleanup"
        return 0
    fi

    # Clean WSL log files
    print_info "Scanning for WSL log files..."
    local wsl_logs
    wsl_logs=$(find /var/log -maxdepth 1 -name "wsl*.log" -type f 2>/dev/null || true)

    if [[ -n "$wsl_logs" ]]; then
        local count
        count=$(echo "$wsl_logs" | wc -l)
        print_info "Found $count WSL log file(s)"
        while IFS= read -r logfile; do
            safe_delete "$logfile" "$(basename "$logfile")"
        done <<< "$wsl_logs"
    else
        print_success "No WSL log files found"
    fi

    # Performance tip about /mnt/c
    echo ""
    print_info "Performance tip: Files on /mnt/c (Windows filesystem) are"
    print_info "significantly slower to access from WSL. For best performance,"
    print_info "keep frequently-accessed files in the Linux filesystem (~/)."

    if [[ -d "/mnt/c" ]]; then
        # Check if cwd is on Windows filesystem
        local cwd
        cwd=$(pwd)
        if [[ "$cwd" == /mnt/* ]]; then
            print_warning "Your current directory ($cwd) is on the Windows filesystem."
        fi
    fi
}
