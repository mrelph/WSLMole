#!/usr/bin/env bash
# WSLMole - WSL-Specific Tools Module
# WSL info, memory, disk compact guide, interop status

# Note: Strict mode set in main script

# Valid WSL actions
WSL_ACTIONS=(info memory compact interop)

# ── CLI Handler ────────────────────────────────────────────────────
cmd_wsl() {
    local action="info"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cmd_wsl_help
                return 0
                ;;
            -*)
                print_error "Unknown option: $1"
                cmd_wsl_help
                return 1
                ;;
            *)
                action="$1"
                shift
                ;;
        esac
    done

    cmd_wsl_action "$action"
}

# ── Help ───────────────────────────────────────────────────────────
cmd_wsl_help() {
    echo -e "${BOLD}Usage:${NC} wslmole wsl [action] [options]"
    echo ""
    echo "  WSL-specific tools and information."
    echo ""
    echo -e "${BOLD}Arguments:${NC}"
    echo "  action               WSL action to perform (default: info)"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo -e "  ${BOLD}-h, --help${NC}           Show this help message"
    echo ""
    echo -e "${BOLD}Actions:${NC}"
    echo -e "  ${BOLD}info${NC}       WSL environment info, .wslconfig, /etc/wsl.conf"
    echo -e "  ${BOLD}memory${NC}     Memory allocation, usage, and .wslconfig limits"
    echo -e "  ${BOLD}compact${NC}    Guide to compacting the WSL2 virtual disk (vhdx)"
    echo -e "  ${BOLD}interop${NC}    Windows/Linux interop status and PATH integration"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo -e "  ${CYAN}wslmole wsl${NC}                       Show WSL info (default)"
    echo -e "  ${CYAN}wslmole wsl info${NC}                  Show WSL environment info"
    echo -e "  ${CYAN}wslmole wsl memory${NC}                Show memory allocation and limits"
    echo -e "  ${CYAN}wslmole wsl compact${NC}               Show vhdx compact guide"
    echo -e "  ${CYAN}wslmole wsl interop${NC}               Show interop status"
}

# ── Action Dispatcher ─────────────────────────────────────────────
cmd_wsl_action() {
    local action="${1:-info}"

    if ! is_wsl; then
        print_error "Not running in WSL - WSL tools require a WSL environment"
        return 1
    fi

    local rc=0
    case "$action" in
        info)
            wsl_info || rc=$?
            ;;
        memory|mem)
            wsl_memory || rc=$?
            ;;
        compact|compact-guide)
            wsl_compact_guide || rc=$?
            ;;
        interop)
            wsl_interop || rc=$?
            ;;
        *)
            print_error "Unknown WSL action: $action"
            print_info "Valid actions: ${WSL_ACTIONS[*]}"
            return 1
            ;;
    esac
    return $rc
}

# ── Helper: Get Windows Username ──────────────────────────────────
_get_win_username() {
    cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' || true
}

# ── Helper: Get Distro Name ──────────────────────────────────────
_get_distro_name() {
    if [[ -f /etc/os-release ]]; then
        (. /etc/os-release && echo "${PRETTY_NAME:-${NAME:-unknown}}")
    else
        echo "unknown"
    fi
}

# ── Helper: Get WSL Distro ID ─────────────────────────────────────
_get_wsl_distro_id() {
    # WSL_DISTRO_NAME is set by WSL at runtime
    if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
        echo "$WSL_DISTRO_NAME"
    elif [[ -f /etc/os-release ]]; then
        (. /etc/os-release && echo "${ID:-Ubuntu}")
    else
        echo "Ubuntu"
    fi
}

# ── 1. WSL Info ───────────────────────────────────────────────────
wsl_info() {
    print_header "WSL Environment Info"

    # WSL version
    local wsl_ver
    wsl_ver=$(get_wsl_version)
    print_info "WSL Version: ${BOLD}${wsl_ver}${NC}"

    # Kernel
    local kernel
    kernel=$(uname -r 2>/dev/null || echo "unknown")
    print_info "Kernel: ${BOLD}${kernel}${NC}"

    # Distro
    local distro
    distro=$(_get_distro_name)
    print_info "Distro: ${BOLD}${distro}${NC}"

    # Hostname
    local hname
    hname=$(hostname 2>/dev/null || echo "unknown")
    print_info "Hostname: ${BOLD}${hname}${NC}"

    # User
    print_info "User: ${BOLD}${USER:-$(whoami 2>/dev/null || echo unknown)}${NC}"

    # Shell
    print_info "Shell: ${BOLD}${SHELL:-unknown}${NC}"

    echo ""

    # .wslconfig
    print_info "Windows .wslconfig:"
    echo ""

    local win_username
    win_username=$(_get_win_username)

    if [[ -n "$win_username" ]]; then
        local wslconfig="/mnt/c/Users/${win_username}/.wslconfig"
        if [[ -f "$wslconfig" ]]; then
            while IFS= read -r line; do
                echo "    $line"
            done < "$wslconfig"
        else
            print_warning "No .wslconfig found at $wslconfig"
            echo ""
            print_info "Example .wslconfig to limit resources:"
            echo ""
            echo "    [wsl2]"
            echo "    memory=4GB"
            echo "    processors=2"
            echo "    swap=2GB"
            echo "    localhostForwarding=true"
        fi
    else
        print_warning "Could not determine Windows username"
    fi

    echo ""

    # /etc/wsl.conf
    print_info "Linux /etc/wsl.conf:"
    echo ""

    if [[ -f /etc/wsl.conf ]]; then
        while IFS= read -r line; do
            echo "    $line"
        done < /etc/wsl.conf
    else
        print_info "No /etc/wsl.conf found"
    fi

    if [[ "${FORMAT:-text}" == "json" ]]; then
        local wsl_ver; wsl_ver=$(get_wsl_version)
        local kernel; kernel=$(uname -r 2>/dev/null || echo "unknown")
        local distro; distro=$(_get_distro_name)
        json_output "$(to_json_kv "wsl_version" "$wsl_ver" "kernel" "$kernel" "distro" "$distro" "hostname" "$(hostname 2>/dev/null || echo unknown)")"
    fi

    echo ""
}

# ── 2. WSL Memory ────────────────────────────────────────────────
wsl_memory() {
    print_header "WSL Memory Status"

    if [[ ! -f /proc/meminfo ]]; then
        print_error "/proc/meminfo not found - cannot read memory info"
        return 1
    fi

    # Read values from /proc/meminfo (values are in kB)
    local mem_total_kb mem_available_kb swap_total_kb swap_free_kb

    mem_total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
    mem_available_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
    swap_total_kb=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
    swap_free_kb=$(awk '/^SwapFree:/ {print $2}' /proc/meminfo)

    # Convert to bytes for format_size
    local mem_total=$((mem_total_kb * 1024))
    local mem_available=$((mem_available_kb * 1024))
    local mem_used=$((mem_total - mem_available))
    local swap_total=$((swap_total_kb * 1024))
    local swap_free=$((swap_free_kb * 1024))

    # Calculate percentage
    local mem_percentage=0
    if [[ $mem_total -gt 0 ]]; then
        mem_percentage=$((mem_used * 100 / mem_total))
    fi

    # Display allocated / used / available
    print_info "Allocated (total): ${BOLD}$(format_size "$mem_total")${NC}"
    print_info "Used:              ${BOLD}$(format_size "$mem_used")${NC} (${mem_percentage}%)"
    print_info "Available:         ${BOLD}$(format_size "$mem_available")${NC}"

    echo ""

    # Check .wslconfig for memory= setting
    print_info "Memory Configuration:"
    echo ""

    local win_username
    win_username=$(_get_win_username)
    local configured_limit=""

    if [[ -n "$win_username" ]]; then
        local wslconfig="/mnt/c/Users/${win_username}/.wslconfig"
        if [[ -f "$wslconfig" ]]; then
            configured_limit=$(grep -i '^\s*memory\s*=' "$wslconfig" 2>/dev/null | head -1 | sed 's/.*=\s*//' | tr -d '[:space:]' || true)
        fi
    fi

    if [[ -n "$configured_limit" ]]; then
        print_success "Configured memory limit: ${BOLD}${configured_limit}${NC} (from .wslconfig)"
    else
        print_warning "No memory limit configured in .wslconfig"
        print_info "WSL2 defaults to 50% of host RAM or 8GB (whichever is less)"
        print_info "Add 'memory=4GB' under [wsl2] in .wslconfig to set a limit"
    fi

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
        print_info "Add 'swap=2GB' under [wsl2] in .wslconfig to enable swap"
    fi

    echo ""
}

# ── 3. WSL Compact Guide ─────────────────────────────────────────
wsl_compact_guide() {
    print_header "WSL2 Virtual Disk Compact Guide"

    print_info "The WSL2 virtual disk (vhdx) grows as you use it but does"
    print_info "NOT automatically shrink when you delete files. Over time,"
    print_info "the vhdx file can become much larger than the actual data"
    print_info "stored inside it. Compacting reclaims this wasted space."

    echo ""

    # Current disk usage
    print_info "Current WSL Disk Usage:"
    echo ""
    df -h / 2>/dev/null | while IFS= read -r line; do
        echo "    $line"
    done

    echo ""

    # Get actual values for the commands
    local win_username
    win_username=$(_get_win_username)
    local distro_id
    distro_id=$(_get_wsl_distro_id)

    local vhdx_path
    if [[ -n "$win_username" ]]; then
        vhdx_path="C:\\Users\\${win_username}\\AppData\\Local\\Packages\\CanonicalGroupLimited.*\\LocalState\\ext4.vhdx"
    else
        vhdx_path="C:\\Users\\<USERNAME>\\AppData\\Local\\Packages\\CanonicalGroupLimited.*\\LocalState\\ext4.vhdx"
    fi

    print_info "Step-by-step guide to compact the vhdx:"
    echo ""

    # Step 1
    echo -e "    ${BOLD}Step 1:${NC} Shut down WSL (run in PowerShell as Administrator):"
    echo ""
    echo "      wsl --shutdown"
    echo ""

    # Step 2
    echo -e "    ${BOLD}Step 2:${NC} Find the vhdx file (run in PowerShell):"
    echo ""
    if [[ -n "$win_username" ]]; then
        printf '      Get-ChildItem -Path "C:\\Users\\%s\\AppData\\Local\\Packages\\" -Recurse -Filter "ext4.vhdx" -ErrorAction SilentlyContinue | Select-Object FullName\n' "$win_username"
    else
        printf '      Get-ChildItem -Path "C:\\Users\\<USERNAME>\\AppData\\Local\\Packages\\" -Recurse -Filter "ext4.vhdx" -ErrorAction SilentlyContinue | Select-Object FullName\n'
    fi
    echo ""

    # Step 3
    echo -e "    ${BOLD}Step 3:${NC} Compact using WSL (preferred, run in PowerShell):"
    echo ""
    echo "      wsl --manage ${distro_id} --compact"
    echo ""

    # Step 4
    echo -e "    ${BOLD}Step 4:${NC} Alternative: diskpart method (for older WSL versions):"
    echo ""
    echo "      # Run in PowerShell as Administrator:"
    echo "      wsl --shutdown"
    echo "      diskpart"
    echo "      # In diskpart:"
    echo "      select vdisk file=\"<full path to ext4.vhdx from Step 2>\""
    echo "      attach vdisk readonly"
    echo "      compact vdisk"
    echo "      detach vdisk"
    echo "      exit"

    echo ""

    print_warning "Always back up important data before compacting."
    print_info "After compacting, start WSL normally to verify everything works."

    echo ""
}

# ── 4. WSL Interop ───────────────────────────────────────────────
wsl_interop() {
    print_header "WSL Interop Status"

    # Check WSLInterop binfmt_misc
    print_info "Interop Registration:"
    echo ""

    local interop_file="/proc/sys/fs/binfmt_misc/WSLInterop"
    if [[ -f "$interop_file" ]]; then
        local interop_status
        interop_status=$(head -1 "$interop_file" 2>/dev/null || echo "unknown")
        if [[ "$interop_status" == "enabled" ]]; then
            print_success "WSLInterop is ${BOLD}enabled${NC} (Windows executables can run from Linux)"
        else
            print_warning "WSLInterop status: ${BOLD}${interop_status}${NC}"
        fi
    else
        print_warning "WSLInterop binfmt_misc entry not found"
        print_info "Windows/Linux interop may be disabled"
    fi

    echo ""

    # Check PATH for Windows entries
    print_info "Windows PATH Integration:"
    echo ""

    local win_path_entries
    win_path_entries=$(echo "$PATH" | tr ':' '\n' | grep -i '/mnt/c/' || true)

    if [[ -n "$win_path_entries" ]]; then
        local win_path_count
        win_path_count=$(echo "$win_path_entries" | wc -l)
        print_success "${win_path_count} Windows PATH entries found:"
        echo ""
        echo "$win_path_entries" | while IFS= read -r entry; do
            print_item "$entry"
        done
    else
        print_warning "No Windows PATH entries found (/mnt/c/ not in PATH)"
        print_info "Windows PATH integration may be disabled"
    fi

    echo ""

    # Check /etc/wsl.conf interop settings
    print_info "Interop Configuration (/etc/wsl.conf):"
    echo ""

    if [[ -f /etc/wsl.conf ]]; then
        local interop_section
        interop_section=$(awk '/^\[interop\]/,/^\[/' /etc/wsl.conf 2>/dev/null | grep -v '^\[' | grep -v '^$' || true)

        if [[ -n "$interop_section" ]]; then
            echo "$interop_section" | while IFS= read -r line; do
                echo "    $line"
            done
        else
            print_info "No [interop] section in /etc/wsl.conf (using defaults)"
        fi
    else
        print_info "No /etc/wsl.conf found (using defaults)"
    fi

    echo ""

    # Check for Windows executables
    print_info "Windows Executables Accessibility:"
    echo ""

    local -a win_exes=("cmd.exe" "powershell.exe" "explorer.exe" "code")
    for exe in "${win_exes[@]}"; do
        if command -v "$exe" &>/dev/null; then
            local exe_path
            exe_path=$(command -v "$exe" 2>/dev/null)
            print_success "${exe} found at ${DIM}${exe_path}${NC}"
        else
            print_warning "${exe} not found in PATH"
        fi
    done

    echo ""
}
