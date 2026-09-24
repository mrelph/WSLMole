#!/usr/bin/env bash
# WSLMole - Action Plan Module
# Builds a risk-labeled plan from lightweight system checks.

# Note: Strict mode set in main script

PLAN_TITLES=()
PLAN_RISKS=()
PLAN_DETAILS=()
PLAN_COMMANDS=()
PLAN_AUTOS=()
PLAN_CATEGORIES=()
PLAN_SKIPPED_CHECKS=()
PLAN_FILTER_RISK=""
PLAN_FILTER_AUTO=false
PLAN_FILTER_CATEGORY=""
PLAN_FIX_ONLY=""

_plan_json_escape() {
    json_escape "$1"
}

_plan_reset() {
    PLAN_TITLES=()
    PLAN_RISKS=()
    PLAN_DETAILS=()
    PLAN_COMMANDS=()
    PLAN_AUTOS=()
    PLAN_CATEGORIES=()
    PLAN_SKIPPED_CHECKS=()
}

_plan_add_item() {
    local title="$1" risk="$2" detail="$3" command="$4" auto="$5" category="$6"

    if [[ -n "$PLAN_FILTER_RISK" && "$risk" != "$PLAN_FILTER_RISK" ]]; then
        return 0
    fi

    if [[ "$PLAN_FILTER_AUTO" == true && "$auto" != "true" ]]; then
        return 0
    fi

    if [[ -n "$PLAN_FILTER_CATEGORY" && "$category" != "$PLAN_FILTER_CATEGORY" ]]; then
        return 0
    fi

    if [[ -n "$PLAN_FIX_ONLY" ]] && ! _plan_fix_only_allows "$category"; then
        return 0
    fi

    PLAN_TITLES+=("$title")
    PLAN_RISKS+=("$risk")
    PLAN_DETAILS+=("$detail")
    PLAN_COMMANDS+=("$command")
    PLAN_AUTOS+=("$auto")
    PLAN_CATEGORIES+=("$category")
}

_plan_sum_old_files() {
    sum_files_older_than "$1" 7
}

_plan_sum_rotated_logs() {
    sum_rotated_log_bytes /var/log
}

_plan_collect_dev_artifacts() {
    local count=0
    local capped=false
    local dir
    while IFS= read -r -d '' dir; do
        count=$((count + 1))
        if (( count >= 20 )); then
            capped=true
            break
        fi
    done < <(find "$HOME" -maxdepth 4 -type d \
        \( -name node_modules -o -name target -o -name __pycache__ -o -name .venv -o -name venv \) \
        -prune -print0 2>/dev/null || true)
    printf '%s %s\n' "$count" "$capped"
}

plan_collect() {
    _plan_reset

    local apt_cache_bytes=0
    [[ -d /var/cache/apt/archives ]] && apt_cache_bytes=$(get_size_bytes /var/cache/apt/archives)
    if [[ $apt_cache_bytes -gt 0 ]]; then
        if is_root; then
            _plan_add_item "Clean APT package cache" "low" "APT cache can reclaim $(format_size "$apt_cache_bytes")." "sudo wslmole clean apt" "true" "apt"
        else
            _plan_add_item "Clean APT package cache" "low" "APT cache can reclaim $(format_size "$apt_cache_bytes"), but this requires sudo." "sudo wslmole clean apt" "false" "apt"
        fi
    fi

    local old_logs_bytes
    old_logs_bytes=$(_plan_sum_rotated_logs)
    if [[ $old_logs_bytes -gt 0 ]]; then
        _plan_add_item "Remove rotated logs" "low" "Rotated logs can reclaim $(format_size "$old_logs_bytes")." "wslmole clean logs" "true" "logs"
    fi

    local tmp_bytes var_tmp_bytes cache_bytes tmp_total
    tmp_bytes=$(_plan_sum_old_files /tmp)
    var_tmp_bytes=$(_plan_sum_old_files /var/tmp)
    cache_bytes=$(_plan_sum_old_files "$HOME/.cache")
    tmp_total=$((tmp_bytes + var_tmp_bytes + cache_bytes))
    if [[ $tmp_total -gt 0 ]]; then
        _plan_add_item "Remove old temp files" "low" "Temp files older than 7 days can reclaim $(format_size "$tmp_total")." "wslmole clean tmp" "true" "tmp"
    fi

    local snap_disabled_count=0
    local snap_disabled_bytes=0
    if command -v snap &>/dev/null; then
        local snap_output
        if snap_output=$(run_probe "$WSLMOLE_PROBE_TIMEOUT" snap list --all 2>/dev/null); then
            read -r snap_disabled_count snap_disabled_bytes < <(snap_disabled_stats "$snap_output")
        else
            PLAN_SKIPPED_CHECKS+=("snap")
        fi
    fi
    if [[ $snap_disabled_count -gt 0 ]]; then
        local snap_detail="${snap_disabled_count} disabled Snap revision(s) found"
        if [[ $snap_disabled_bytes -gt 0 ]]; then
            snap_detail+=" ($(format_size "$snap_disabled_bytes"))"
        fi
        _plan_add_item "Review disabled Snap revisions" "medium" "${snap_detail}; review before removal." "wslmole clean snap --dry-run" "false" "snap"
    fi

    local disk_pct=0
    disk_pct=$(df / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
    disk_pct=${disk_pct:-0}
    if [[ $disk_pct -ge 75 ]]; then
        _plan_add_item "Investigate disk pressure" "medium" "Root filesystem is ${disk_pct}% full." "wslmole disk / -m summary" "false" "disk"
    fi

    local upgradable_count=0
    if command -v apt &>/dev/null; then
        local apt_output
        if apt_output=$(run_probe "$WSLMOLE_PROBE_TIMEOUT" apt list --upgradable 2>/dev/null); then
            upgradable_count=$(printf '%s\n' "$apt_output" | grep -c 'upgradable' || true)
        else
            PLAN_SKIPPED_CHECKS+=("apt")
        fi
    fi
    if [[ $upgradable_count -gt 10 ]]; then
        _plan_add_item "Review package updates" "medium" "${upgradable_count} package(s) can be upgraded." "wslmole packages audit" "false" "packages"
    fi

    local failed_count=0
    if command -v systemctl &>/dev/null && run_probe "$WSLMOLE_PROBE_TIMEOUT" systemctl is-system-running &>/dev/null; then
        local failed_output
        if failed_output=$(run_probe "$WSLMOLE_PROBE_TIMEOUT" systemctl --no-pager --no-legend list-units --state=failed 2>/dev/null); then
            failed_count=$(printf '%s\n' "$failed_output" | sed '/^[[:space:]]*$/d' | wc -l)
        else
            PLAN_SKIPPED_CHECKS+=("systemd")
        fi
    fi
    if [[ $failed_count -gt 0 ]]; then
        _plan_add_item "Investigate failed services" "review" "${failed_count} failed systemd service(s) detected." "wslmole diagnose service" "false" "services"
    fi

    if is_wsl; then
        local win_user
        win_user=$(get_windows_username)
        if [[ -n "$win_user" ]] && [[ ! -f "/mnt/c/Users/${win_user}/.wslconfig" ]]; then
            _plan_add_item "Add a WSL memory limit" "review" "No .wslconfig found; WSL2 may use more memory than expected." "wslmole wsl info" "false" "wslconfig"
        fi
    fi

    local dev_count dev_capped
    read -r dev_count dev_capped < <(_plan_collect_dev_artifacts)
    if [[ ${dev_count:-0} -gt 0 ]]; then
        local dev_detail="Found ${dev_count} developer artifact director"
        [[ "$dev_count" -eq 1 ]] && dev_detail+="y" || dev_detail+="ies"
        [[ "$dev_capped" == true ]] && dev_detail+=" in the first 20 matches"
        _plan_add_item "Review developer artifacts" "review" "${dev_detail}; run a dedicated scan for exact sizes." "wslmole dev ~ --dry-run" "false" "dev"
    fi
}

plan_print_text() {
    print_header "WSLMole Action Plan"

    if [[ ${#PLAN_TITLES[@]} -eq 0 ]]; then
        print_success "No recommended actions right now."
    else
        echo "  Recommended actions:"
        echo ""
        local i display_idx
        for i in "${!PLAN_TITLES[@]}"; do
            display_idx=$((i + 1))
            printf "  %s) %s\n" "$display_idx" "${PLAN_TITLES[$i]}"
            printf "     Risk:    %s\n" "${PLAN_RISKS[$i]}"
            printf "     Detail:  %s\n" "${PLAN_DETAILS[$i]}"
            printf "     Command: %s\n" "${PLAN_COMMANDS[$i]}"
            echo ""
        done

        print_info "Run ${BOLD}wslmole fix --dry-run${NC} to preview low-risk cleanup actions."
        print_info "Run ${BOLD}wslmole fix --yes${NC} to apply low-risk cleanup actions without prompts."
    fi

    if [[ ${#PLAN_SKIPPED_CHECKS[@]} -gt 0 ]]; then
        echo ""
        print_warning "Some checks were unavailable or exceeded ${WSLMOLE_PROBE_TIMEOUT}s: ${PLAN_SKIPPED_CHECKS[*]}"
    fi
}

plan_print_json() {
    local json='{"items":['
    local i first=true
    for i in "${!PLAN_TITLES[@]}"; do
        [[ "$first" == true ]] && first=false || json+=","
        json+="{\"title\":$(json_quote "${PLAN_TITLES[$i]}"),"
        json+="\"risk\":$(json_quote "${PLAN_RISKS[$i]}"),"
        json+="\"detail\":$(json_quote "${PLAN_DETAILS[$i]}"),"
        json+="\"command\":$(json_quote "${PLAN_COMMANDS[$i]}"),"
        json+="\"auto\":${PLAN_AUTOS[$i]},"
        json+="\"category\":$(json_quote "${PLAN_CATEGORIES[$i]}")}"
    done
    json+="],\"skipped_checks\":["
    local skipped sfirst=true
    for skipped in "${PLAN_SKIPPED_CHECKS[@]+"${PLAN_SKIPPED_CHECKS[@]}"}"; do
        [[ "$sfirst" == true ]] && sfirst=false || json+=","
        json+="$(json_quote "$skipped")"
    done
    json+="]}"
    json_output "$json"
}

cmd_plan_help() {
    echo -e "${BOLD}Usage:${NC} wslmole plan [options]"
    echo ""
    echo "  Show a risk-labeled action plan without changing the system."
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  --risk RISK          Show only items with risk: low, medium, review"
    echo "  --auto               Show only low-risk automatic actions"
    echo "  --category CATEGORY  Show only one category (logs, tmp, snap, etc.)"
    echo "  -h, --help           Show this help"
}

cmd_plan() {
    PLAN_FILTER_RISK=""
    PLAN_FILTER_AUTO=false
    PLAN_FILTER_CATEGORY=""
    PLAN_FIX_ONLY=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --risk)
                if [[ -z "${2:-}" ]]; then
                    print_error "--risk requires a value"
                    return 1
                fi
                case "$2" in
                    low|medium|review)
                        PLAN_FILTER_RISK="$2"
                        ;;
                    *)
                        print_error "Invalid risk: $2. Use low, medium, or review"
                        return 1
                        ;;
                esac
                shift 2
                ;;
            --auto)
                PLAN_FILTER_AUTO=true
                shift
                ;;
            --category)
                if [[ -z "${2:-}" ]]; then
                    print_error "--category requires a value"
                    return 1
                fi
                PLAN_FILTER_CATEGORY="$2"
                shift 2
                ;;
            -h|--help)
                cmd_plan_help
                return 0
                ;;
            *)
                print_error "Unknown option: $1"
                cmd_plan_help
                return 1
                ;;
        esac
    done

    plan_collect
    if [[ "${FORMAT:-text}" == "json" ]]; then
        plan_print_json
    else
        plan_print_text
    fi
}

plan_has_auto_actions() {
    local i
    for i in "${!PLAN_AUTOS[@]}"; do
        [[ "${PLAN_AUTOS[$i]}" == "true" ]] || continue
        _plan_fix_only_allows "${PLAN_CATEGORIES[$i]}" && return 0
    done
    return 1
}

_plan_fix_only_allows() {
    local category="$1"
    local item
    local -a only_items
    [[ -n "$PLAN_FIX_ONLY" ]] || return 0
    IFS=',' read -ra only_items <<< "$PLAN_FIX_ONLY"
    for item in "${only_items[@]}"; do
        item="${item//[[:space:]]/}"
        [[ "$item" == "$category" ]] && return 0
    done
    return 1
}

plan_apply_auto_actions() {
    local i category
    for i in "${!PLAN_AUTOS[@]}"; do
        [[ "${PLAN_AUTOS[$i]}" == "true" ]] || continue
        category="${PLAN_CATEGORIES[$i]}"
        if ! _plan_fix_only_allows "$category"; then
            continue
        fi
        print_section "Applying: ${PLAN_TITLES[$i]}"
        case "$category" in
            apt|logs|tmp)
                cmd_clean_category "$category"
                ;;
            *)
                print_info "Skipping ${PLAN_TITLES[$i]} - no automatic action registered"
                ;;
        esac
    done
}
