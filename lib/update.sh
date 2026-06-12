#!/usr/bin/env bash
# WSLMole - Auto-Update Module
# Check for updates from Git repo and self-update

# Note: Strict mode set in main script

WSLMOLE_UPDATE_CHECK_FILE="${WSLMOLE_LOG_DIR}/.last_update_check"
WSLMOLE_UPDATE_INTERVAL=86400  # 24 hours in seconds
WSLMOLE_REPO_URL="https://github.com/mrelph/WSLMole.git"

# ── CLI Handler ────────────────────────────────────────────────────
cmd_update() {
    local check_only=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--check)
                check_only=true
                shift
                ;;
            -h|--help)
                cmd_update_help
                return 0
                ;;
            *)
                print_error "Unknown option: $1"
                cmd_update_help
                return 1
                ;;
        esac
    done

    if [[ "$check_only" == true ]]; then
        check_for_updates
    else
        perform_update
    fi
}

# ── Help ───────────────────────────────────────────────────────────
cmd_update_help() {
    cat << 'EOF'
Usage: wslmole update [options]

Check for and install updates from the Git repository.

Options:
  -c, --check    Check for updates without installing
  -h, --help     Show this help message

WSLMole checks for updates automatically every 24 hours. You can
also run 'wslmole update' manually at any time.

The update interval can be configured in ~/.config/wslmole/config:
  WSLMOLE_UPDATE_INTERVAL=86400   # seconds (default: 24h)
EOF
}

# ── Update Check ──────────────────────────────────────────────────
check_for_updates() {
    local install_dir
    install_dir="$(_get_install_dir)" || return 1

    if ! _is_git_repo "$install_dir"; then
        print_warning "WSLMole is not installed from Git — cannot check for updates"
        return 1
    fi

    print_info "Checking for updates..."

    # Fetch latest tags and refs
    if ! git -C "$install_dir" fetch origin --tags --quiet 2>/dev/null; then
        print_warning "Could not reach remote repository"
        return 1
    fi

    _record_update_check

    local latest_tag
    latest_tag=$(_get_latest_tag "$install_dir")

    if [[ -z "$latest_tag" ]]; then
        print_info "No published releases found"
        json_output "$(to_json_kv "up_to_date" "true" "version" "$WSLMOLE_VERSION" "latest_tag" "none")"
        return 0
    fi

    if ! _validate_tag "$latest_tag"; then
        print_error "Remote tag has invalid format: $latest_tag"
        return 1
    fi

    local latest_version="${latest_tag#v}"

    if [[ "$latest_version" == "$WSLMOLE_VERSION" ]]; then
        print_success "WSLMole is up to date (v${WSLMOLE_VERSION})"
        json_output "$(to_json_kv "up_to_date" "true" "version" "$WSLMOLE_VERSION" "latest_tag" "$latest_tag")"
        return 0
    fi

    if _version_gt "$latest_version" "$WSLMOLE_VERSION"; then
        print_warning "Update available: v${WSLMOLE_VERSION} → ${latest_tag}"
        json_output "$(to_json_kv "up_to_date" "false" "current" "$WSLMOLE_VERSION" "latest" "$latest_version" "latest_tag" "$latest_tag")"
    else
        print_success "WSLMole is up to date (v${WSLMOLE_VERSION})"
        json_output "$(to_json_kv "up_to_date" "true" "version" "$WSLMOLE_VERSION" "latest_tag" "$latest_tag")"
    fi
    return 0
}

perform_update() {
    local install_dir
    install_dir="$(_get_install_dir)" || return 1

    if ! _is_git_repo "$install_dir"; then
        print_warning "WSLMole is not installed from Git — cannot update"
        print_info "Re-install with: git clone ${WSLMOLE_REPO_URL}"
        return 1
    fi

    print_header "WSLMole Update"
    print_info "Current version: v${WSLMOLE_VERSION}"

    # Fetch latest tags and refs
    print_info "Fetching latest releases..."
    if ! git -C "$install_dir" fetch origin --tags --quiet 2>/dev/null; then
        print_error "Could not reach remote repository"
        return 1
    fi

    local latest_tag
    latest_tag=$(_get_latest_tag "$install_dir")

    if [[ -z "$latest_tag" ]]; then
        print_info "No published releases found — nothing to update"
        _record_update_check
        return 0
    fi

    if ! _validate_tag "$latest_tag"; then
        print_error "Remote tag has invalid format: $latest_tag"
        return 1
    fi

    local latest_version="${latest_tag#v}"

    if ! _version_gt "$latest_version" "$WSLMOLE_VERSION"; then
        print_success "Already on latest release (v${WSLMOLE_VERSION})"
        _record_update_check
        return 0
    fi

    print_info "New release: ${latest_tag}"

    # Show changes between current version tag and latest tag
    local current_tag="v${WSLMOLE_VERSION}"
    echo ""
    print_info "Changes since ${current_tag}:"
    if git -C "$install_dir" tag -l "$current_tag" | grep -q .; then
        git -C "$install_dir" log --oneline "${current_tag}..${latest_tag}" 2>/dev/null | while IFS= read -r line; do
            print_item "$line"
        done
    else
        git -C "$install_dir" log --oneline HEAD.."${latest_tag}" 2>/dev/null | head -20 | while IFS= read -r line; do
            print_item "$line"
        done
    fi
    echo ""

    if [[ "${DRY_RUN:-false}" == true ]]; then
        print_info "[DRY RUN] Would update to ${latest_tag}"
        _record_update_check
        return 0
    fi

    # Verify the remote is still the official repository
    local origin_url
    origin_url=$(git -C "$install_dir" remote get-url origin 2>/dev/null || echo "")
    if [[ "$origin_url" != "$WSLMOLE_REPO_URL" && "$origin_url" != "${WSLMOLE_REPO_URL%.git}" ]]; then
        print_warning "Git remote 'origin' is not the official WSLMole repository:"
        print_item "$origin_url"
        if ! confirm "Update from this remote anyway?"; then
            print_info "Update cancelled"
            return 1
        fi
    fi

    # Verify the tag signature when one exists; warn loudly when it doesn't.
    # Checked-out code is sourced on the next run, so this is code execution.
    if git -C "$install_dir" verify-tag "$latest_tag" &>/dev/null; then
        print_success "Tag ${latest_tag} has a valid GPG signature"
    else
        print_warning "Tag ${latest_tag} is not GPG-signed; its contents cannot be verified"
    fi

    # Check for local modifications
    local stashed=false
    if ! git -C "$install_dir" diff --quiet 2>/dev/null; then
        print_warning "You have local modifications"
        if ! confirm "Stash local changes and update?"; then
            print_info "Update cancelled"
            return 0
        fi
        if git -C "$install_dir" stash --quiet 2>/dev/null; then
            stashed=true
        else
            print_warning "Could not stash local changes; continuing without stash"
        fi
    fi

    if ! confirm "Update to ${latest_tag}?"; then
        print_info "Update cancelled"
        return 0
    fi

    # Checkout the tagged release
    if git -C "$install_dir" checkout "$latest_tag" --quiet 2>/dev/null; then
        local new_version
        new_version=$(sed -n 's/^WSLMOLE_VERSION="\([^"]*\)".*/\1/p' "$install_dir/lib/common.sh" 2>/dev/null | head -1)
        new_version="${new_version//[^0-9.]/}"
        [[ -n "$new_version" ]] || new_version="$latest_version"
        print_success "Updated to v${new_version}"
        print_info "Note: repo is now at tag ${latest_tag} (detached HEAD)"
        print_info "To return to a branch: cd $install_dir && git checkout master"
        log_info "Updated from v${WSLMOLE_VERSION} to ${latest_tag}"
    else
        print_error "Could not checkout ${latest_tag}"
        print_info "Try: cd $install_dir && git checkout $latest_tag"
        return 1
    fi

    # Restore stashed changes
    if [[ "$stashed" == true ]]; then
        if git -C "$install_dir" stash pop --quiet 2>/dev/null; then
            print_info "Restored local modifications"
        else
            print_warning "Could not restore local modifications (check 'git stash list')"
        fi
    fi

    _record_update_check
}

# ── Periodic Check (called at startup) ────────────────────────────
maybe_check_for_updates() {
    # Skip in non-interactive or JSON mode
    [[ "${FORMAT:-text}" == "json" ]] && return 0
    [[ ! -t 1 ]] && return 0

    local install_dir
    install_dir="$(_get_install_dir 2>/dev/null)" || return 0

    _is_git_repo "$install_dir" || return 0

    local interval="${WSLMOLE_UPDATE_INTERVAL:-86400}"
    local now
    now=$(date +%s)

    if [[ -f "$WSLMOLE_UPDATE_CHECK_FILE" ]]; then
        local last_check
        last_check=$(cat "$WSLMOLE_UPDATE_CHECK_FILE" 2>/dev/null || echo 0)
        if (( now - last_check < interval )); then
            return 0
        fi
    fi

    # Run check in background to avoid slowing down startup
    (
        if git -C "$install_dir" fetch origin --tags --quiet 2>/dev/null; then
            local latest_tag
            latest_tag=$(_get_latest_tag "$install_dir")
            if [[ -n "$latest_tag" ]] && _validate_tag "$latest_tag"; then
                local latest_version="${latest_tag#v}"
                if _version_gt "$latest_version" "$WSLMOLE_VERSION"; then
                    echo -e "  ${YELLOW}⚠${NC} WSLMole ${latest_tag} available (current: v${WSLMOLE_VERSION}). Run ${BOLD}wslmole update${NC} to install." >&2
                fi
            fi
        fi
        mkdir -p "$(dirname "$WSLMOLE_UPDATE_CHECK_FILE")" 2>/dev/null
        echo "$now" > "$WSLMOLE_UPDATE_CHECK_FILE"
    ) &
    disown 2>/dev/null
}

# ── Internal Helpers ──────────────────────────────────────────────

# Validate a tag matches strict semver: v1.2.3
_validate_tag() {
    [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# Get the latest semver tag (e.g. v1.2.3) sorted by version
_get_latest_tag() {
    local dir="$1"
    git -C "$dir" tag -l 'v[0-9]*' --sort=-version:refname 2>/dev/null | head -1
}

# Compare two semver strings: returns 0 (true) if $1 > $2
_version_gt() {
    local v1="$1" v2="$2"
    local -a parts1 parts2
    IFS='.' read -ra parts1 <<< "$v1"
    IFS='.' read -ra parts2 <<< "$v2"
    local i
    for i in 0 1 2; do
        local a="${parts1[$i]:-0}" b="${parts2[$i]:-0}"
        if (( a > b )); then return 0; fi
        if (( a < b )); then return 1; fi
    done
    return 1  # equal
}

_get_install_dir() {
    # SCRIPT_DIR is set by the main wslmole script
    if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -d "$SCRIPT_DIR" ]]; then
        echo "$SCRIPT_DIR"
        return 0
    fi
    print_error "Cannot determine WSLMole install directory"
    return 1
}

_is_git_repo() {
    local dir="$1"
    [[ -d "$dir/.git" ]] || git -C "$dir" rev-parse --git-dir &>/dev/null
}

_record_update_check() {
    mkdir -p "$(dirname "$WSLMOLE_UPDATE_CHECK_FILE")" 2>/dev/null
    date +%s > "$WSLMOLE_UPDATE_CHECK_FILE" 2>/dev/null || true
}
