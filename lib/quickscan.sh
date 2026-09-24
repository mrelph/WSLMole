#!/usr/bin/env bash
# WSLMole - Quick Scan Module
# Fast system health check with score and recommendations

# Note: Strict mode set in main script

# ── Health Score (pure) ───────────────────────────────────────────
# Compute the health score and recommendations from already-collected
# metrics. Kept free of system calls so the scoring arithmetic, clamping,
# and thresholds are unit-testable in isolation.
#
# Results are returned via two globals (bash arrays can't be returned):
#   QS_HEALTH_SCORE        - integer score, clamped to a 0 minimum
#   QS_RECOMMENDATIONS      - array of recommendation strings
QS_HEALTH_SCORE=100
QS_RECOMMENDATIONS=()
_quickscan_compute_score() {
    local mem_percentage="$1" disk_percentage="$2" failed_count="$3" \
          has_wslconfig="$4" in_wsl="$5" upgradable_count="$6"

    QS_HEALTH_SCORE=100
    QS_RECOMMENDATIONS=()

    if [[ $mem_percentage -ge 80 ]]; then
        QS_HEALTH_SCORE=$((QS_HEALTH_SCORE - 15))
        QS_RECOMMENDATIONS+=("Memory usage is critically high (${mem_percentage}%) - close unused applications")
    elif [[ $mem_percentage -ge 60 ]]; then
        QS_HEALTH_SCORE=$((QS_HEALTH_SCORE - 5))
        QS_RECOMMENDATIONS+=("Memory usage is elevated (${mem_percentage}%) - consider freeing some memory")
    fi

    if [[ $disk_percentage -ge 90 ]]; then
        QS_HEALTH_SCORE=$((QS_HEALTH_SCORE - 20))
        QS_RECOMMENDATIONS+=("Disk usage is critical (${disk_percentage}%) - run 'wslmole clean' to free space")
    elif [[ $disk_percentage -ge 75 ]]; then
        QS_HEALTH_SCORE=$((QS_HEALTH_SCORE - 10))
        QS_RECOMMENDATIONS+=("Disk usage is high (${disk_percentage}%) - consider running 'wslmole clean'")
    fi

    if [[ $failed_count -gt 0 ]]; then
        QS_HEALTH_SCORE=$((QS_HEALTH_SCORE - failed_count * 5))
        QS_RECOMMENDATIONS+=("${failed_count} failed systemd service(s) - run 'wslmole diagnose service' to investigate")
    fi

    if [[ "$in_wsl" == true && "$has_wslconfig" == false ]]; then
        QS_HEALTH_SCORE=$((QS_HEALTH_SCORE - 5))
        QS_RECOMMENDATIONS+=("No .wslconfig found - create one to limit WSL2 memory/CPU usage")
    fi

    if [[ $upgradable_count -gt 10 ]]; then
        QS_HEALTH_SCORE=$((QS_HEALTH_SCORE - 5))
        QS_RECOMMENDATIONS+=("${upgradable_count} packages can be upgraded - run 'wslmole packages update'")
    fi

    # Clamp score to 0 minimum
    if [[ $QS_HEALTH_SCORE -lt 0 ]]; then
        QS_HEALTH_SCORE=0
    fi
}

# ── Quick Scan ────────────────────────────────────────────────────
run_quick_scan() {
    # ASCII art mole (text mode only)
    if [[ "${FORMAT:-text}" != "json" ]]; then
        echo ""
        echo -e "${CYAN}${BOLD}"
        cat << 'MOLE'
        ╭─────────────────────────╮
        │      /\_/\              │
        │     ( o.o )  WSLMole    │
        │      > ^ <   Quick Scan │
        │     /|   |\             │
        │    (_|   |_)            │
        ╰─────────────────────────╯
MOLE
        echo -e "${NC}"
    fi

    # ── Cleanable Space Calculation ───────────────────────────────

    local apt_cache_bytes=0
    local old_logs_bytes=0
    local snap_bytes=0
    local tmp_bytes=0
    local cleanable_total=0
    local -a skipped_checks=()

    # APT cache
    if [[ -d /var/cache/apt/archives ]]; then
        apt_cache_bytes=$(get_size_bytes /var/cache/apt/archives)
    fi

    # Old/rotated logs
    old_logs_bytes=$(sum_rotated_log_bytes /var/log)

    # Snap disabled revisions
    local snap_disabled_count=0
    if command -v snap &>/dev/null; then
        local snap_output
        if snap_output=$(run_probe "$WSLMOLE_PROBE_TIMEOUT" snap list --all 2>/dev/null); then
            read -r snap_disabled_count snap_bytes < <(snap_disabled_stats "$snap_output")
        else
            skipped_checks+=("snap")
        fi
    fi

    # Match the cleanup command exactly: files older than seven days in the
    # two temp trees and the user's cache.
    tmp_bytes=$(( $(sum_files_older_than /tmp 7) + \
        $(sum_files_older_than /var/tmp 7) + \
        $(sum_files_older_than "$HOME/.cache" 7) ))

    cleanable_total=$((apt_cache_bytes + old_logs_bytes + snap_bytes + tmp_bytes))

    # ── System Info Gathering ─────────────────────────────────────

    local mem_percentage=0
    local mem_total_kb=0 mem_available_kb=0 mem_used_kb=0
    if [[ -f /proc/meminfo ]]; then
        mem_total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
        mem_available_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
        if [[ $mem_total_kb -gt 0 ]]; then
            mem_used_kb=$((mem_total_kb - mem_available_kb))
            mem_percentage=$((mem_used_kb * 100 / mem_total_kb))
        fi
    fi

    local disk_percentage=0
    local disk_used="" disk_total="" disk_avail=""
    disk_percentage=$(df / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
    disk_percentage=${disk_percentage:-0}
    disk_total=$(df -h / 2>/dev/null | awk 'NR==2 {print $2}')
    disk_used=$(df -h / 2>/dev/null | awk 'NR==2 {print $3}')
    disk_avail=$(df -h / 2>/dev/null | awk 'NR==2 {print $4}')

    # ── Health Score Calculation ──────────────────────────────────
    # Gather the remaining metrics, then delegate the scoring arithmetic
    # to the pure _quickscan_compute_score helper (see above).

    local failed_count=0
    if command -v systemctl &>/dev/null; then
        if run_probe "$WSLMOLE_PROBE_TIMEOUT" systemctl is-system-running &>/dev/null; then
            local failed_output
            if failed_output=$(run_probe "$WSLMOLE_PROBE_TIMEOUT" systemctl --no-pager --no-legend list-units --state=failed 2>/dev/null); then
                failed_count=$(printf '%s\n' "$failed_output" | sed '/^[[:space:]]*$/d' | wc -l)
            else
                skipped_checks+=("systemd")
            fi
        fi
    fi

    local has_wslconfig=false
    local in_wsl=false
    if is_wsl; then
        in_wsl=true
        local win_username
        win_username=$(get_windows_username)
        if [[ -n "$win_username" ]]; then
            local wslconfig="/mnt/c/Users/${win_username}/.wslconfig"
            if [[ -f "$wslconfig" ]]; then
                has_wslconfig=true
            fi
        fi
    fi

    local upgradable_count=0
    if command -v apt &>/dev/null; then
        local apt_output
        if apt_output=$(run_probe "$WSLMOLE_PROBE_TIMEOUT" apt list --upgradable 2>/dev/null); then
            upgradable_count=$(printf '%s\n' "$apt_output" | grep -c 'upgradable' || true)
        else
            skipped_checks+=("apt")
        fi
    fi

    _quickscan_compute_score "$mem_percentage" "$disk_percentage" "$failed_count" \
        "$has_wslconfig" "$in_wsl" "$upgradable_count"

    local health_score="$QS_HEALTH_SCORE"
    local -a recommendations=(${QS_RECOMMENDATIONS[@]+"${QS_RECOMMENDATIONS[@]}"})

    # ── Output ────────────────────────────────────────────────────

    # Health score with color and grade
    local score_color grade
    if [[ $health_score -ge 90 ]]; then
        score_color="$GREEN"
        grade="Excellent"
    elif [[ $health_score -ge 70 ]]; then
        score_color="$YELLOW"
        grade="Good"
    elif [[ $health_score -ge 50 ]]; then
        score_color="$YELLOW"
        grade="Fair"
    else
        score_color="$RED"
        grade="Poor"
    fi

    # JSON output mode
    if [[ "${FORMAT:-text}" == "json" ]]; then
        local rec_json="["
        local rfirst=true
        for rec in "${recommendations[@]+"${recommendations[@]}"}"; do
            if [[ "$rfirst" == true ]]; then rfirst=false; else rec_json+=","; fi
            rec_json+="$(json_quote "$rec")"
        done
        rec_json+="]"

        local skipped_json="["
        local sfirst=true skipped
        for skipped in "${skipped_checks[@]+"${skipped_checks[@]}"}"; do
            if [[ "$sfirst" == true ]]; then sfirst=false; else skipped_json+=","; fi
            skipped_json+="$(json_quote "$skipped")"
        done
        skipped_json+="]"

        json_output "{\"health_score\":${health_score},\"grade\":$(json_quote "$grade"),\"memory_percent\":${mem_percentage},\"disk_percent\":${disk_percentage},\"cleanable\":{\"apt_cache\":${apt_cache_bytes},\"old_logs\":${old_logs_bytes},\"snap\":${snap_bytes},\"tmp\":${tmp_bytes},\"total\":${cleanable_total}},\"recommendations\":${rec_json},\"skipped_checks\":${skipped_json}}"
        return 0
    fi

    # ── Visual Health Score ───────────────────────────────────────

    echo -e "  ${BOLD}HEALTH SCORE${NC}"
    echo ""

    # Large score display with visual bar
    local bar_width=40
    local filled=$((health_score * bar_width / 100))
    local empty=$((bar_width - filled))
    local bar_filled="" bar_empty=""
    local i
    for ((i = 0; i < filled; i++)); do bar_filled+="█"; done
    for ((i = 0; i < empty; i++)); do bar_empty+="░"; done

    echo -e "    ${score_color}${BOLD}${health_score}${NC}/100  ${score_color}${grade}${NC}"
    echo -e "    ${score_color}${bar_filled}${NC}${DIM}${bar_empty}${NC}"
    echo ""

    # ── Two-Column System Overview ────────────────────────────────

    echo -e "  ${BOLD}SYSTEM OVERVIEW${NC}"
    echo -e "  ${DIM}─────────────────────────────────────────────${NC}"
    echo ""

    # Memory bar
    local mem_bar_w=20
    local mem_filled=$((mem_percentage * mem_bar_w / 100))
    local mem_empty=$((mem_bar_w - mem_filled))
    local mem_bar_f="" mem_bar_e=""
    local mem_color
    if [[ $mem_percentage -lt 60 ]]; then mem_color="$GREEN"
    elif [[ $mem_percentage -le 80 ]]; then mem_color="$YELLOW"
    else mem_color="$RED"; fi
    for ((i = 0; i < mem_filled; i++)); do mem_bar_f+="█"; done
    for ((i = 0; i < mem_empty; i++)); do mem_bar_e+="░"; done

    # Disk bar
    local disk_bar_w=20
    local disk_filled=$((disk_percentage * disk_bar_w / 100))
    local disk_empty=$((disk_bar_w - disk_filled))
    local disk_bar_f="" disk_bar_e=""
    local disk_color
    if [[ $disk_percentage -lt 75 ]]; then disk_color="$GREEN"
    elif [[ $disk_percentage -le 90 ]]; then disk_color="$YELLOW"
    else disk_color="$RED"; fi
    for ((i = 0; i < disk_filled; i++)); do disk_bar_f+="█"; done
    for ((i = 0; i < disk_empty; i++)); do disk_bar_e+="░"; done

    printf "    ${BOLD}%-12s${NC} ${mem_color}%s${NC}${DIM}%s${NC}  ${BOLD}%d%%${NC}  %s / %s\n" \
        "Memory" "$mem_bar_f" "$mem_bar_e" "$mem_percentage" \
        "$(format_size $((mem_used_kb * 1024)))" "$(format_size $((mem_total_kb * 1024)))"
    printf "    ${BOLD}%-12s${NC} ${disk_color}%s${NC}${DIM}%s${NC}  ${BOLD}%d%%${NC}  %s / %s\n" \
        "Disk" "$disk_bar_f" "$disk_bar_e" "$disk_percentage" \
        "${disk_used:-?}" "${disk_total:-?}"

    echo ""

    # ── Cleanable Space ───────────────────────────────────────────

    echo -e "  ${BOLD}CLEANABLE SPACE${NC}"
    echo -e "  ${DIM}─────────────────────────────────────────────${NC}"
    echo ""

    local has_cleanable=false

    # Show items with proportional bar indicators
    _show_cleanable_item() {
        local label="$1" bytes="$2"
        if [[ $bytes -gt 0 ]]; then
            has_cleanable=true
            local item_bar=""
            # Mini bar proportional to size (max 10 chars for 1GB+)
            local bar_len=1
            if [[ $bytes -ge 1073741824 ]]; then bar_len=10
            elif [[ $bytes -ge 524288000 ]]; then bar_len=8
            elif [[ $bytes -ge 104857600 ]]; then bar_len=6
            elif [[ $bytes -ge 10485760 ]]; then bar_len=4
            elif [[ $bytes -ge 1048576 ]]; then bar_len=2
            fi
            for ((i = 0; i < bar_len; i++)); do item_bar+="▪"; done

            printf "    ${YELLOW}%-8s${NC} %-24s %s\n" "$item_bar" "$label" "$(format_size "$bytes")"
        fi
    }

    _show_cleanable_item "APT cache" "$apt_cache_bytes"
    _show_cleanable_item "Old logs" "$old_logs_bytes"
    if [[ $snap_bytes -gt 0 ]]; then
        _show_cleanable_item "Snap ($snap_disabled_count revs)" "$snap_bytes"
    fi
    _show_cleanable_item "Old temp/cache files" "$tmp_bytes"

    if [[ "$has_cleanable" == true ]]; then
        echo ""
        echo -e "    ${BOLD}Total reclaimable:  $(format_size "$cleanable_total")${NC}"
    else
        print_success "System is clean - nothing to reclaim"
    fi

    echo ""

    if [[ ${#skipped_checks[@]} -gt 0 ]]; then
        print_warning "Some checks were unavailable or exceeded ${WSLMOLE_PROBE_TIMEOUT}s: ${skipped_checks[*]}"
        echo ""
    fi

    # ── Recommendations ───────────────────────────────────────────

    if [[ ${#recommendations[@]} -gt 0 ]]; then
        echo -e "  ${BOLD}RECOMMENDATIONS${NC}"
        echo -e "  ${DIM}─────────────────────────────────────────────${NC}"
        echo ""
        for rec in "${recommendations[@]}"; do
            echo -e "    ${YELLOW}▸${NC} $rec"
        done
        echo ""
    fi

    # ── Footer ────────────────────────────────────────────────────

    echo -e "  ${DIM}─────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}wslmole plan${NC}        Risk-labeled action plan"
    echo -e "  ${BOLD}wslmole fix${NC}         Auto-fix recommendations"
    echo -e "  ${BOLD}wslmole clean${NC}       Full system cleanup"
    echo -e "  ${BOLD}wslmole -i${NC}          Interactive menu"
    echo -e "  ${DIM}─────────────────────────────────────────────${NC}"
    echo ""
}
