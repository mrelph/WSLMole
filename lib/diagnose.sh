#!/usr/bin/env bash
# WSLMole - System Diagnostics Module
# 4 diagnostic types: process, memory, service, wsl

# Note: Strict mode set in main script

# Valid diagnostic types
DIAGNOSE_TYPES=(process memory service wsl)

# ── CLI Handler ────────────────────────────────────────────────────
cmd_diagnose() {
    local action="all"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cmd_diagnose_help
                return 0
                ;;
            -*)
                print_error "Unknown option: $1"
                cmd_diagnose_help
                return 1
                ;;
            *)
                action="$1"
                shift
                ;;
        esac
    done

    cmd_diagnose_type "$action"
}

# ── Help ───────────────────────────────────────────────────────────
cmd_diagnose_help() {
    echo -e "${BOLD}Usage:${NC} wslmole diagnose [type] [options]"
    echo ""
    echo "  Run system diagnostics to inspect processes, memory, services, and WSL resources."
    echo ""
    echo -e "${BOLD}Arguments:${NC}"
    echo "  type                 Diagnostic type to run (default: all)"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  -h, --help           Show this help message"
    echo ""
    echo -e "${BOLD}Types:${NC}"
    echo -e "  ${BOLD}all${NC}        Run all diagnostics (WSL only if running in WSL)"
    echo -e "  ${BOLD}process${NC}    Top CPU and memory consuming processes"
    echo -e "  ${BOLD}memory${NC}     Memory usage breakdown with visual progress bar"
    echo -e "  ${BOLD}service${NC}    Systemd service status and resource usage"
    echo -e "  ${BOLD}wsl${NC}        WSL-specific environment and resource info"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo -e "  ${CYAN}wslmole diagnose${NC}                  Run all diagnostics"
    echo -e "  ${CYAN}wslmole diagnose memory${NC}           Show memory breakdown"
    echo -e "  ${CYAN}wslmole diagnose process${NC}          Show top processes"
    echo -e "  ${CYAN}wslmole diagnose service${NC}          Show service status"
    echo -e "  ${CYAN}wslmole diagnose wsl${NC}              Show WSL environment info"
}

# ── Type Dispatcher ────────────────────────────────────────────────
cmd_diagnose_type() {
    local dtype="${1:-all}"

    local rc=0
    case "$dtype" in
        all)
            diagnose_processes || rc=1
            diagnose_memory || rc=1
            diagnose_services || rc=1
            if is_wsl; then
                diagnose_wsl_resources || rc=1
            fi
            ;;
        process|processes)
            diagnose_processes || rc=$?
            ;;
        memory|mem)
            diagnose_memory || rc=$?
            ;;
        service|services)
            diagnose_services || rc=$?
            ;;
        wsl)
            diagnose_wsl_resources || rc=$?
            ;;
        *)
            print_error "Unknown diagnostic type: $dtype"
            print_info "Valid types: all ${DIAGNOSE_TYPES[*]}"
            return 1
            ;;
    esac
    return $rc
}

# ── 1. Process Diagnostics ─────────────────────────────────────────
diagnose_processes() {
    print_header "Process Diagnostics"

    # Top 10 CPU consumers
    print_info "Top 10 CPU consumers:"
    echo ""
    printf "    ${BOLD}%-8s  %-6s  %-6s  %s${NC}\n" "PID" "%CPU" "%MEM" "COMMAND"
    printf "    %-8s  %-6s  %-6s  %s\n" "────────" "──────" "──────" "───────────────────────"

    ps aux --sort=-%cpu 2>/dev/null | head -11 | tail -10 | while read -r user pid cpu mem vsz rss tty stat start time command; do
        printf "    %-8s  %-6s  %-6s  %s\n" "$pid" "$cpu" "$mem" "$command"
    done

    echo ""

    # Top 10 memory consumers
    print_info "Top 10 memory consumers:"
    echo ""
    printf "    ${BOLD}%-8s  %-6s  %-10s  %s${NC}\n" "PID" "%MEM" "RSS" "COMMAND"
    printf "    %-8s  %-6s  %-10s  %s\n" "────────" "──────" "──────────" "───────────────────────"

    ps aux --sort=-%mem 2>/dev/null | head -11 | tail -10 | while read -r user pid cpu mem vsz rss tty stat start time command; do
        # RSS from ps is in KB, convert to bytes for format_size
        local rss_bytes=$((rss * 1024))
        local formatted_rss
        formatted_rss=$(format_size "$rss_bytes")
        printf "    %-8s  %-6s  %-10s  %s\n" "$pid" "$mem" "$formatted_rss" "$command"
    done

    echo ""
}

# ── 2. Memory Diagnostics ──────────────────────────────────────────
diagnose_memory() {
    print_header "Memory Diagnostics"

    if [[ ! -f /proc/meminfo ]]; then
        print_error "/proc/meminfo not found - cannot read memory info"
        return 1
    fi

    # Read values from /proc/meminfo (values are in kB)
    local mem_total_kb mem_available_kb mem_free_kb buffers_kb cached_kb
    local swap_total_kb swap_free_kb

    mem_total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
    mem_available_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
    mem_free_kb=$(awk '/^MemFree:/ {print $2}' /proc/meminfo)
    buffers_kb=$(awk '/^Buffers:/ {print $2}' /proc/meminfo)
    cached_kb=$(awk '/^Cached:/ {print $2}' /proc/meminfo)
    swap_total_kb=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
    swap_free_kb=$(awk '/^SwapFree:/ {print $2}' /proc/meminfo)

    # Convert to bytes for format_size
    local mem_total=$((mem_total_kb * 1024))
    local mem_available=$((mem_available_kb * 1024))
    local mem_free=$((mem_free_kb * 1024))
    local buffers=$((buffers_kb * 1024))
    local cached=$((cached_kb * 1024))
    local swap_total=$((swap_total_kb * 1024))
    local swap_free=$((swap_free_kb * 1024))

    # Calculate used and percentage
    local mem_used=$((mem_total - mem_available))
    local mem_percentage=0
    if [[ $mem_total -gt 0 ]]; then
        mem_percentage=$((mem_used * 100 / mem_total))
    fi

    # Visual progress bar (30 chars wide)
    local bar_width=30
    local filled=$((mem_percentage * bar_width / 100))
    local empty=$((bar_width - filled))

    # Color based on usage
    local bar_color
    if [[ $mem_percentage -lt 60 ]]; then
        bar_color="$GREEN"
    elif [[ $mem_percentage -le 80 ]]; then
        bar_color="$YELLOW"
    else
        bar_color="$RED"
    fi

    # Build the bar
    local bar_filled=""
    local bar_empty=""
    local i
    for ((i = 0; i < filled; i++)); do
        bar_filled+="█"
    done
    for ((i = 0; i < empty; i++)); do
        bar_empty+="░"
    done

    print_info "Memory Usage:"
    echo ""
    echo -e "    ${bar_color}${bar_filled}${NC}${DIM}${bar_empty}${NC} ${BOLD}${mem_percentage}%${NC}"
    echo ""

    # Memory details table
    printf "    ${BOLD}%-14s  %s${NC}\n" "METRIC" "VALUE"
    printf "    %-14s  %s\n" "──────────────" "──────────────"
    printf "    %-14s  %s\n" "Total" "$(format_size "$mem_total")"
    printf "    %-14s  %s\n" "Used" "$(format_size "$mem_used")"
    printf "    %-14s  %s\n" "Free" "$(format_size "$mem_free")"
    printf "    %-14s  %s\n" "Buffers" "$(format_size "$buffers")"
    printf "    %-14s  %s\n" "Cached" "$(format_size "$cached")"
    printf "    %-14s  %s\n" "Available" "$(format_size "$mem_available")"

    echo ""

    # Swap info
    print_info "Swap:"
    echo ""
    if [[ $swap_total -gt 0 ]]; then
        local swap_used=$((swap_total - swap_free))
        local swap_percentage=0
        if [[ $swap_total -gt 0 ]]; then
            swap_percentage=$((swap_used * 100 / swap_total))
        fi
        printf "    %-14s  %s\n" "Total" "$(format_size "$swap_total")"
        printf "    %-14s  %s (%d%%)\n" "Used" "$(format_size "$swap_used")" "$swap_percentage"
        printf "    %-14s  %s\n" "Free" "$(format_size "$swap_free")"
    else
        print_info "Swap not configured"
    fi

    if [[ "${FORMAT:-text}" == "json" ]]; then
        json_output "{\"memory\":{\"total\":$mem_total,\"used\":$mem_used,\"available\":$mem_available,\"percentage\":$mem_percentage},\"swap\":{\"total\":$swap_total,\"free\":$swap_free}}"
    fi

    echo ""
}

# ── 3. Service Diagnostics ─────────────────────────────────────────
diagnose_services() {
    print_header "Service Diagnostics"

    # Check if systemctl is available
    if ! command -v systemctl &>/dev/null; then
        print_warning "systemctl not available (common in WSL without systemd)"
        print_info "Service diagnostics require systemd to be running."
        return 0
    fi

    # Verify systemd is actually running (PID 1)
    if ! systemctl is-system-running &>/dev/null 2>&1; then
        print_warning "systemd is not running as init system"
        print_info "Service diagnostics require systemd to be the init system."
        print_info "For WSL2, enable systemd in /etc/wsl.conf under [boot] with systemd=true"
        return 0
    fi

    # Failed services
    print_info "Failed services:"
    echo ""

    local failed_services
    failed_services=$(systemctl --no-pager --no-legend list-units --state=failed 2>/dev/null || true)

    if [[ -n "$failed_services" ]]; then
        while IFS= read -r line; do
            local unit_name
            unit_name=$(echo "$line" | awk '{print $1}')
            echo -e "    ${RED}●${NC} $unit_name"
        done <<< "$failed_services"
    else
        print_success "No failed services"
    fi

    echo ""

    # Count running services
    local running_count
    running_count=$(systemctl --no-pager --no-legend list-units --type=service --state=running 2>/dev/null | wc -l)
    print_info "Running services: ${BOLD}${running_count}${NC}"

    echo ""

    # Top 5 services by memory
    print_info "Top 5 services by memory usage:"
    echo ""
    printf "    ${BOLD}%-40s  %s${NC}\n" "SERVICE" "MEMORY"
    printf "    %-40s  %s\n" "────────────────────────────────────────" "──────────"

    local services_list
    services_list=$(systemctl --no-pager --no-legend list-units --type=service --state=running 2>/dev/null | awk '{print $1}')

    if [[ -n "$services_list" ]]; then
        local -a service_mem_pairs=()

        while IFS= read -r svc; do
            [[ -n "$svc" ]] || continue
            local mem_current
            mem_current=$(systemctl show "$svc" --property=MemoryCurrent 2>/dev/null | cut -d= -f2)

            # Skip if not available or infinity
            if [[ -z "$mem_current" || "$mem_current" == "[not set]" || "$mem_current" == "infinity" ]]; then
                continue
            fi

            # mem_current is in bytes
            if [[ "$mem_current" =~ ^[0-9]+$ && "$mem_current" -gt 0 ]]; then
                service_mem_pairs+=("${mem_current}:${svc}")
            fi
        done <<< "$services_list"

        # Sort by memory (descending) and take top 5
        if [[ ${#service_mem_pairs[@]} -gt 0 ]]; then
            printf '%s\n' "${service_mem_pairs[@]}" | sort -t: -k1 -rn | head -5 | while IFS=: read -r mem_bytes svc_name; do
                local formatted_mem
                formatted_mem=$(format_size "$mem_bytes")
                printf "    %-40s  %s\n" "$svc_name" "$formatted_mem"
            done
        else
            print_info "No memory data available for running services"
        fi
    fi

    echo ""
}

# ── 4. WSL Resources ──────────────────────────────────────────────
diagnose_wsl_resources() {
    print_header "WSL Resources"

    if ! is_wsl; then
        print_warning "Not running in WSL - skipping WSL diagnostics"
        return 0
    fi

    # WSL version
    local wsl_ver
    wsl_ver=$(get_wsl_version)
    print_info "WSL Version: ${BOLD}${wsl_ver}${NC}"

    # Kernel
    local kernel
    kernel=$(uname -r 2>/dev/null || echo "unknown")
    print_info "Kernel: ${BOLD}${kernel}${NC}"

    # Distro info from /etc/os-release
    if [[ -f /etc/os-release ]]; then
        local distro_name distro_version
        distro_name=$(. /etc/os-release && echo "${PRETTY_NAME:-${NAME:-unknown}}")
        print_info "Distro: ${BOLD}${distro_name}${NC}"
    fi

    # Hostname
    local hname
    hname=$(hostname 2>/dev/null || echo "unknown")
    print_info "Hostname: ${BOLD}${hname}${NC}"

    echo ""

    # .wslconfig
    print_info "WSL Configuration (.wslconfig):"
    echo ""

    local win_username
    # Get Windows username via cmd.exe
    win_username=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' || true)

    if [[ -n "$win_username" ]]; then
        local wslconfig="/mnt/c/Users/${win_username}/.wslconfig"
        if [[ -f "$wslconfig" ]]; then
            while IFS= read -r line; do
                echo "    $line"
            done < "$wslconfig"
        else
            print_info "No .wslconfig found at $wslconfig"
            print_info "Create one to limit WSL2 memory/CPU usage."
        fi
    else
        print_warning "Could not determine Windows username"
    fi

    echo ""

    # WSL filesystem usage
    print_info "WSL Filesystem Usage:"
    echo ""
    df -h / 2>/dev/null | while IFS= read -r line; do
        echo "    $line"
    done

    echo ""
}
