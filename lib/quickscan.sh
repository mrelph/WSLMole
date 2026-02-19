#!/usr/bin/env bash
# WSLMole - Quick Scan Module
# Fast system health check with score and recommendations

# Note: Strict mode set in main script

# ── Quick Scan ────────────────────────────────────────────────────
run_quick_scan() {
    # ASCII art mole (text mode only)
    if [[ "${FORMAT:-text}" != "json" ]]; then
        echo -e "${CYAN}"
        cat << 'MOLE'
      /\_/\
     ( o.o )
      > ^ <   WSLMole Quick Scan
     /|   |\
    (_|   |_)
MOLE
        echo -e "${NC}"
    fi

    # ── Cleanable Space Calculation ───────────────────────────────

    local apt_cache_bytes=0
    local old_logs_bytes=0
    local snap_bytes=0
    local tmp_bytes=0
    local cleanable_total=0

    # APT cache
    if [[ -d /var/cache/apt/archives ]]; then
        apt_cache_bytes=$(du -sb /var/cache/apt/archives/ 2>/dev/null | cut -f1) || true
        apt_cache_bytes=${apt_cache_bytes:-0}
    fi

    # Old/rotated logs
    local log_files
    log_files=$(find /var/log -type f \( -name "*.gz" -o -name "*.old" -o -name "*.1" \) 2>/dev/null || true)
    if [[ -n "$log_files" ]]; then
        while IFS= read -r file; do
            local fsize
            fsize=$(stat -c%s "$file" 2>/dev/null || echo 0)
            old_logs_bytes=$((old_logs_bytes + fsize))
        done <<< "$log_files"
    fi

    # Snap disabled revisions
    local snap_disabled_count=0
    if command -v snap &>/dev/null; then
        snap_disabled_count=$(snap list --all 2>/dev/null | awk '/disabled/' | wc -l)
        # Estimate ~100MB per disabled snap revision
        snap_bytes=$((snap_disabled_count * 104857600))
    fi

    # Tmp files
    if [[ -d /tmp ]]; then
        tmp_bytes=$(du -sb /tmp 2>/dev/null | cut -f1) || true
        tmp_bytes=${tmp_bytes:-0}
    fi

    cleanable_total=$((apt_cache_bytes + old_logs_bytes + snap_bytes + tmp_bytes))

    # ── Health Score Calculation ──────────────────────────────────

    local health_score=100
    local -a recommendations=()

    # Memory usage check
    local mem_percentage=0
    if [[ -f /proc/meminfo ]]; then
        local mem_total_kb mem_available_kb
        mem_total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
        mem_available_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
        if [[ $mem_total_kb -gt 0 ]]; then
            local mem_used_kb=$((mem_total_kb - mem_available_kb))
            mem_percentage=$((mem_used_kb * 100 / mem_total_kb))
        fi
    fi

    if [[ $mem_percentage -ge 80 ]]; then
        health_score=$((health_score - 15))
        recommendations+=("Memory usage is critically high (${mem_percentage}%) - close unused applications")
    elif [[ $mem_percentage -ge 60 ]]; then
        health_score=$((health_score - 5))
        recommendations+=("Memory usage is elevated (${mem_percentage}%) - consider freeing some memory")
    fi

    # Disk usage check
    local disk_percentage=0
    disk_percentage=$(df / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
    disk_percentage=${disk_percentage:-0}

    if [[ $disk_percentage -ge 90 ]]; then
        health_score=$((health_score - 20))
        recommendations+=("Disk usage is critical (${disk_percentage}%) - run 'wslmole clean' to free space")
    elif [[ $disk_percentage -ge 75 ]]; then
        health_score=$((health_score - 10))
        recommendations+=("Disk usage is high (${disk_percentage}%) - consider running 'wslmole clean'")
    fi

    # Failed systemd services
    local failed_count=0
    if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null 2>&1; then
        failed_count=$(systemctl --no-pager --no-legend list-units --state=failed 2>/dev/null | wc -l)
        if [[ $failed_count -gt 0 ]]; then
            local penalty=$((failed_count * 5))
            health_score=$((health_score - penalty))
            recommendations+=("${failed_count} failed systemd service(s) - run 'wslmole diagnose service' to investigate")
        fi
    fi

    # .wslconfig check (WSL only)
    if is_wsl; then
        local has_wslconfig=false
        local win_username
        win_username=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' || true)
        if [[ -n "$win_username" ]]; then
            local wslconfig="/mnt/c/Users/${win_username}/.wslconfig"
            if [[ -f "$wslconfig" ]]; then
                has_wslconfig=true
            fi
        fi
        if [[ "$has_wslconfig" == false ]]; then
            health_score=$((health_score - 5))
            recommendations+=("No .wslconfig found - create one to limit WSL2 memory/CPU usage")
        fi
    fi

    # Upgradable packages check
    local upgradable_count=0
    if command -v apt-get &>/dev/null; then
        upgradable_count=$(apt list --upgradable 2>/dev/null | grep -c 'upgradable' || true)
        upgradable_count=${upgradable_count:-0}
        if [[ $upgradable_count -gt 10 ]]; then
            health_score=$((health_score - 5))
            recommendations+=("${upgradable_count} packages can be upgraded - run 'wslmole packages upgrade'")
        fi
    fi

    # Clamp score to 0 minimum
    if [[ $health_score -lt 0 ]]; then
        health_score=0
    fi

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
            rec="${rec//\\/\\\\}"
            rec="${rec//\"/\\\"}"
            rec_json+="\"${rec}\""
        done
        rec_json+="]"

        json_output "{\"health_score\":${health_score},\"grade\":\"${grade}\",\"cleanable\":{\"apt_cache\":${apt_cache_bytes},\"old_logs\":${old_logs_bytes},\"snap\":${snap_bytes},\"tmp\":${tmp_bytes},\"total\":${cleanable_total}},\"recommendations\":${rec_json}}"
        return 0
    fi

    print_header "Health Score"
    echo -e "    ${score_color}${BOLD}${health_score}/100${NC}  ${score_color}${grade}${NC}"
    echo ""

    # Cleanable space breakdown (only non-zero items)
    print_header "Cleanable Space"

    local has_cleanable=false
    if [[ $apt_cache_bytes -gt 0 ]]; then
        print_item "APT cache: $(format_size "$apt_cache_bytes")"
        has_cleanable=true
    fi
    if [[ $old_logs_bytes -gt 0 ]]; then
        print_item "Old logs: $(format_size "$old_logs_bytes")"
        has_cleanable=true
    fi
    if [[ $snap_bytes -gt 0 ]]; then
        print_item "Snap disabled revisions ($snap_disabled_count): $(format_size "$snap_bytes")"
        has_cleanable=true
    fi
    if [[ $tmp_bytes -gt 0 ]]; then
        print_item "Tmp files: $(format_size "$tmp_bytes")"
        has_cleanable=true
    fi
    if [[ "$has_cleanable" == true ]]; then
        echo ""
        print_info "Total cleanable: ${BOLD}$(format_size "$cleanable_total")${NC}"
    else
        print_success "System is clean - nothing to reclaim"
    fi

    # Recommendations (only if there are any)
    if [[ ${#recommendations[@]} -gt 0 ]]; then
        print_header "Recommendations"
        for rec in "${recommendations[@]}"; do
            print_warning "$rec"
        done
    fi

    echo ""
    echo -e "  Run ${BOLD}wslmole${NC} for full interactive menu"
    echo -e "  Run ${BOLD}wslmole clean --dry-run${NC} to preview cleanup"
    echo ""
}
