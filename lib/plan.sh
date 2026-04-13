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
PLAN_FILTER_RISK=""
PLAN_FILTER_AUTO=false
PLAN_FILTER_CATEGORY=""
PLAN_FIX_ONLY=""

_plan_json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    printf '%s' "$value"
}

_plan_reset() {
    PLAN_TITLES=()
    PLAN_RISKS=()
    PLAN_DETAILS=()
    PLAN_COMMANDS=()
    PLAN_AUTOS=()
    PLAN_CATEGORIES=()
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
    local dir="$1"
    local total=0
    local file size
    [[ -d "$dir" ]] || { echo 0; return 0; }
    while IFS= read -r -d '' file; do
        size=$(get_size_bytes "$file")
        total=$((total + size))
    done < <(find "$dir" -type f -mtime +7 -print0 2>/dev/null || true)
    echo "$total"
}

_plan_sum_rotated_logs() {
    local total=0
    local file size
    [[ -d /var/log ]] || { echo 0; return 0; }
    while IFS= read -r -d '' file; do
        size=$(get_size_bytes "$file")
        total=$((total + size))
    done < <(find /var/log -type f \( -name "*.gz" -o -name "*.old" -o -name "*.1" \) -print0 2>/dev/null || true)
    echo "$total"
}

_plan_collect_dev_artifacts() {
    local count=0
    local total=0
    local dir size
    while IFS= read -r dir; do
        [[ -n "$dir" ]] || continue
        count=$((count + 1))
        size=$(get_size_bytes "$dir")
        total=$((total + size))
    done < <(find "$HOME" -maxdepth 4 -type d \( -name node_modules -o -name target -o -name __pycache__ -o -name .venv -o -name venv \) -prune 2>/dev/null | head -20)
    printf '%s %s\n' "$count" "$total"
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

    local tmp_bytes var_tmp_bytes tmp_total
    tmp_bytes=$(_plan_sum_old_files /tmp)
    var_tmp_bytes=$(_plan_sum_old_files /var/tmp)
    tmp_total=$((tmp_bytes + var_tmp_bytes))
    if [[ $tmp_total -gt 0 ]]; then
        _plan_add_item "Remove old temp files" "low" "Temp files older than 7 days can reclaim $(format_size "$tmp_total")." "wslmole clean tmp" "true" "tmp"
    fi

    local snap_disabled_count=0
    if command -v snap &>/dev/null; then
        snap_disabled_count=$(snap list --all 2>/dev/null | awk '/disabled/' | wc -l)
        snap_disabled_count=${snap_disabled_count:-0}
    fi
    if [[ $snap_disabled_count -gt 0 ]]; then
        _plan_add_item "Review disabled Snap revisions" "medium" "${snap_disabled_count} disabled Snap revision(s) found; review before removal." "wslmole clean snap --dry-run" "false" "snap"
    fi

    local disk_pct=0
    disk_pct=$(df / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
    disk_pct=${disk_pct:-0}
    if [[ $disk_pct -ge 75 ]]; then
        _plan_add_item "Investigate disk pressure" "medium" "Root filesystem is ${disk_pct}% full." "wslmole disk / -m summary" "false" "disk"
    fi

    local upgradable_count=0
    if command -v apt &>/dev/null; then
        upgradable_count=$(apt list --upgradable 2>/dev/null | grep -c 'upgradable' || true)
        upgradable_count=${upgradable_count:-0}
    fi
    if [[ $upgradable_count -gt 10 ]]; then
        _plan_add_item "Review package updates" "medium" "${upgradable_count} package(s) can be upgraded." "wslmole packages audit" "false" "packages"
    fi

    local failed_count=0
    if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null 2>&1; then
        failed_count=$(systemctl --no-pager --no-legend list-units --state=failed 2>/dev/null | wc -l)
        failed_count=${failed_count:-0}
    fi
    if [[ $failed_count -gt 0 ]]; then
        _plan_add_item "Investigate failed services" "review" "${failed_count} failed systemd service(s) detected." "wslmole diagnose service" "false" "services"
    fi

    if is_wsl; then
        local win_user
        win_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' || true)
        if [[ -n "$win_user" ]] && [[ ! -f "/mnt/c/Users/${win_user}/.wslconfig" ]]; then
            _plan_add_item "Add a WSL memory limit" "review" "No .wslconfig found; WSL2 may use more memory than expected." "wslmole wsl info" "false" "wslconfig"
        fi
    fi

    local dev_count dev_bytes
    read -r dev_count dev_bytes < <(_plan_collect_dev_artifacts)
    if [[ ${dev_count:-0} -gt 0 ]]; then
        _plan_add_item "Review developer artifacts" "review" "Found ${dev_count} artifact(s) in your home directory, up to $(format_size "$dev_bytes") across the first 20 matches." "wslmole dev ~ --dry-run" "false" "dev"
    fi
}

plan_print_text() {
    print_header "WSLMole Action Plan"

    if [[ ${#PLAN_TITLES[@]} -eq 0 ]]; then
        print_success "No recommended actions right now."
        return 0
    fi

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
}

plan_print_json() {
    local json='{"items":['
    local i first=true
    for i in "${!PLAN_TITLES[@]}"; do
        [[ "$first" == true ]] && first=false || json+=","
        json+="{\"title\":\"$(_plan_json_escape "${PLAN_TITLES[$i]}")\","
        json+="\"risk\":\"$(_plan_json_escape "${PLAN_RISKS[$i]}")\","
        json+="\"detail\":\"$(_plan_json_escape "${PLAN_DETAILS[$i]}")\","
        json+="\"command\":\"$(_plan_json_escape "${PLAN_COMMANDS[$i]}")\","
        json+="\"auto\":${PLAN_AUTOS[$i]},"
        json+="\"category\":\"$(_plan_json_escape "${PLAN_CATEGORIES[$i]}")\"}"
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
