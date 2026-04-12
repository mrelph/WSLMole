#!/usr/bin/env bash
# WSLMole - Disk Analysis Module
# 6 analysis modes: summary, tree, files, folders, types, old

# Note: Strict mode set in main script

# Valid disk analysis modes
DISK_MODES=(summary tree files folders types old)

# ── CLI Handler ────────────────────────────────────────────────────
cmd_disk() {
    local path="/"
    local mode="summary"
    local depth=3
    local top=10
    local path_set=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m|--mode)
                if [[ -z "${2:-}" ]]; then
                    print_error "--mode requires a value"
                    return 1
                fi
                mode="$2"
                shift 2
                ;;
            -d|--depth)
                if [[ -z "${2:-}" ]]; then
                    print_error "--depth requires a value"
                    return 1
                fi
                depth="$2"
                shift 2
                ;;
            -n|--top)
                if [[ -z "${2:-}" ]]; then
                    print_error "--top requires a value"
                    return 1
                fi
                top="$2"
                shift 2
                ;;
            -h|--help)
                cmd_disk_help
                return 0
                ;;
            summary|tree|files|file|large|largest|folders|folder|dirs|types|type|old|usage)
                case "$1" in
                    file|large|largest) mode="files" ;;
                    folder|dirs) mode="folders" ;;
                    type) mode="types" ;;
                    usage) mode="summary" ;;
                    *) mode="$1" ;;
                esac
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                cmd_disk_help
                return 1
                ;;
            *)
                if [[ "$path_set" == true ]]; then
                    print_error "Unexpected argument: $1"
                    cmd_disk_help
                    return 1
                fi
                path="$1"
                path_set=true
                shift
                ;;
        esac
    done

    cmd_disk_mode "$mode" "$path" "$depth" "$top"
}

# ── Help ───────────────────────────────────────────────────────────
cmd_disk_help() {
    echo -e "${BOLD}Usage:${NC} wslmole disk [path] [options]"
    echo ""
    echo "  Analyze disk usage with multiple view modes."
    echo ""
    echo -e "${BOLD}Arguments:${NC}"
    echo "  path                 Directory to analyze (default: /)"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo -e "  ${BOLD}-m, --mode${NC} MODE      Analysis mode (default: summary)"
    echo -e "  ${BOLD}-d, --depth${NC} N        Tree depth for tree mode (default: 3)"
    echo -e "  ${BOLD}-n, --top${NC} N          Number of results to show (default: 10)"
    echo -e "  ${BOLD}-h, --help${NC}           Show this help message"
    echo ""
    echo -e "${BOLD}Modes:${NC}"
    echo -e "  ${BOLD}summary${NC}    Filesystem overview and top-level directory sizes"
    echo -e "  ${BOLD}tree${NC}       Hierarchical directory tree sorted by size"
    echo -e "  ${BOLD}files${NC}      Largest individual files"
    echo -e "  ${BOLD}folders${NC}    Largest directories"
    echo -e "  ${BOLD}types${NC}      Disk usage grouped by file extension"
    echo -e "  ${BOLD}old${NC}        Files not modified in 90+ days"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo -e "  ${CYAN}wslmole disk${NC}                           Summary of /"
    echo -e "  ${CYAN}wslmole disk /home -m tree -d 4${NC}        Tree view of /home, 4 levels deep"
    echo -e "  ${CYAN}wslmole disk ~ -m files -n 20${NC}          Top 20 largest files in home"
    echo -e "  ${CYAN}wslmole disk /var -m types${NC}             File type breakdown of /var"
    echo -e "  ${CYAN}wslmole disk ~ -m old -n 15${NC}            15 oldest large files in home"
}

# ── Mode Dispatcher ────────────────────────────────────────────────
cmd_disk_mode() {
    local mode="${1:-summary}"
    local path="${2:-/}"
    local depth="${3:-3}"
    local top="${4:-10}"

    # Validate path exists
    if [[ ! -d "$path" ]]; then
        print_error "Path does not exist or is not a directory: $path"
        return 1
    fi

    # Resolve to absolute path
    path="$(cd "$path" && pwd)"

    local rc=0
    case "$mode" in
        summary)
            disk_summary "$path" || rc=$?
            ;;
        tree)
            disk_tree "$path" "$depth" || rc=$?
            ;;
        files)
            disk_largest_files "$path" "$top" || rc=$?
            ;;
        folders)
            disk_largest_folders "$path" "$top" || rc=$?
            ;;
        types)
            disk_file_types "$path" || rc=$?
            ;;
        old)
            disk_old_files "$path" "$top" || rc=$?
            ;;
        *)
            print_error "Unknown disk analysis mode: $mode"
            print_info "Valid modes: ${DISK_MODES[*]}"
            return 1
            ;;
    esac
    return $rc
}

# ── 1. Summary ─────────────────────────────────────────────────────
disk_summary() {
    local path="$1"

    print_header "Disk Usage Summary: $path"

    # Show filesystem info for the path
    print_info "Filesystem:"
    echo ""
    df -h "$path" 2>/dev/null | while IFS= read -r line; do
        echo "    $line"
    done
    echo ""

    # Show directory sizes
    if [[ "$path" == "/" ]]; then
        print_info "Top-level directory sizes:"
        echo ""
        local dirs=(/home /var /tmp /opt /usr /snap)
        for dir in "${dirs[@]}"; do
            if [[ -d "$dir" ]]; then
                local size
                size=$(du -sh "$dir" 2>/dev/null | cut -f1)
                printf "    %-20s %s\n" "$dir" "${size:-N/A}"
            fi
        done
    else
        print_info "Subdirectory sizes:"
        echo ""
        # Show immediate subdirectories sorted by size
        du -sh "$path"/*/ 2>/dev/null | sort -rh | while IFS=$'\t' read -r size dir; do
            # Trim trailing slash for display
            local name="${dir%/}"
            printf "    %-40s %s\n" "$name" "$size"
        done

        # If no subdirectories found
        if [[ -z "$(ls -d "$path"/*/ 2>/dev/null)" ]]; then
            print_info "No subdirectories found"
        fi
    fi

    if [[ "${FORMAT:-text}" == "json" ]]; then
        local fs_json
        fs_json=$(df -B1 "$path" 2>/dev/null | awk 'NR==2{printf "{\"filesystem\":\"%s\",\"size\":%s,\"used\":%s,\"available\":%s,\"mount\":\"%s\"}", $1,$2,$3,$4,$6}')
        json_output "{\"mode\":\"summary\",\"path\":\"$path\",\"fs\":${fs_json:-{}}}"
    fi

    echo ""
}

# ── 2. Tree View ──────────────────────────────────────────────────
disk_tree() {
    local path="$1"
    local depth="$2"

    print_header "Disk Usage Tree: $path (depth: $depth)"

    # Get the base depth for calculating indentation
    local base_depth
    base_depth=$(echo "$path" | tr -cd '/' | wc -c)

    (du -h --max-depth="$depth" "$path" 2>/dev/null | sort -rh | head -40 || true) | while IFS=$'\t' read -r size dir; do
        # Calculate relative depth for indentation
        local dir_depth
        dir_depth=$(echo "$dir" | tr -cd '/' | wc -c)
        local indent_level=$((dir_depth - base_depth))

        # Build indentation string
        local indent=""
        local i
        for ((i = 0; i < indent_level; i++)); do
            indent+="  "
        done

        printf "    %s%-8s %s\n" "$indent" "$size" "$dir"
    done

    echo ""
}

# ── 3. Largest Files ──────────────────────────────────────────────
disk_largest_files() {
    local path="$1"
    local top="$2"

    print_header "Largest Files: $path (top $top)"

    print_info "Scanning..."
    local results_tmp
    results_tmp=$(mktemp)
    (find "$path" -type f -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -"$top" > "$results_tmp") &
    show_progress $!
    wait $! 2>/dev/null || true
    local results
    results=$(cat "$results_tmp")
    rm -f "$results_tmp"

    if [[ -z "$results" ]]; then
        print_info "No files found in $path"
        return 0
    fi

    echo ""
    local rank=1
    while IFS=$'\t' read -r bytes filepath; do
        local formatted_size
        formatted_size=$(format_size "$bytes")
        printf "    %2d. %-12s %s\n" "$rank" "$formatted_size" "$filepath"
        rank=$((rank + 1))
    done <<< "$results"

    if [[ "${FORMAT:-text}" == "json" ]]; then
        local items="[" jfirst=true
        while IFS=$'\t' read -r bytes filepath; do
            [[ "$jfirst" == true ]] && jfirst=false || items+=","
            items+="$(to_json_kv "bytes" "$bytes" "path" "$filepath")"
        done <<< "$results"
        json_output "{\"mode\":\"files\",\"path\":\"$path\",\"items\":${items}]}"
    fi

    echo ""
}

# ── 4. Largest Folders ────────────────────────────────────────────
disk_largest_folders() {
    local path="$1"
    local top="$2"

    print_header "Largest Folders: $path (top $top)"

    local results
    results=$(du -sb "$path"/*/ 2>/dev/null | sort -rn | head -"$top" || true)

    if [[ -z "$results" ]]; then
        print_info "No subdirectories found in $path"
        return 0
    fi

    echo ""
    local rank=1
    while IFS=$'\t' read -r bytes dirpath; do
        local formatted_size
        formatted_size=$(format_size "$bytes")
        local name="${dirpath%/}"
        printf "    %2d. %-12s %s\n" "$rank" "$formatted_size" "$name"
        rank=$((rank + 1))
    done <<< "$results"

    echo ""
}

# ── 5. File Types ─────────────────────────────────────────────────
disk_file_types() {
    local path="$1"

    print_header "Disk Usage by File Type: $path"

    local results
    results=$(find "$path" -type f -printf '%s %f\n' 2>/dev/null | awk '
    {
        size = $1
        filename = $2
        # Extract extension
        n = split(filename, parts, ".")
        if (n > 1 && length(parts[n]) <= 10) {
            ext = tolower(parts[n])
        } else {
            ext = "(no ext)"
        }
        total[ext] += size
        count[ext]++
    }
    END {
        for (ext in total) {
            printf "%d\t%d\t%s\n", total[ext], count[ext], ext
        }
    }
    ' | sort -rn || true)

    if [[ -z "$results" ]]; then
        print_info "No files found in $path"
        return 0
    fi

    echo ""
    printf "    %-12s  %8s  %s\n" "SIZE" "COUNT" "EXTENSION"
    printf "    %-12s  %8s  %s\n" "────────────" "────────" "─────────"

    while IFS=$'\t' read -r bytes count ext; do
        local formatted_size
        formatted_size=$(format_size "$bytes")
        printf "    %-12s  %8d  .%s\n" "$formatted_size" "$count" "$ext"
    done <<< "$results"

    echo ""
}

# ── 6. Old Files ──────────────────────────────────────────────────
disk_old_files() {
    local path="$1"
    local top="$2"

    print_header "Old Files (90+ days): $path (top $top by size)"

    print_info "Scanning..."
    local results_tmp
    results_tmp=$(mktemp)
    (find "$path" -type f -mtime +90 -printf '%s\t%T+\t%p\n' 2>/dev/null | sort -rn | head -"$top" > "$results_tmp") &
    show_progress $!
    wait $! 2>/dev/null || true
    local results
    results=$(cat "$results_tmp")
    rm -f "$results_tmp"

    if [[ -z "$results" ]]; then
        print_info "No files older than 90 days found in $path"
        return 0
    fi

    echo ""
    printf "    %-12s  %-20s  %s\n" "SIZE" "LAST MODIFIED" "PATH"
    printf "    %-12s  %-20s  %s\n" "────────────" "────────────────────" "────"

    while IFS=$'\t' read -r bytes mtime filepath; do
        local formatted_size
        formatted_size=$(format_size "$bytes")
        # Trim the fractional seconds from the timestamp for cleaner display
        local date_display="${mtime%%.*}"
        # Replace the T with a space for readability
        date_display="${date_display//T/ }"
        printf "    %-12s  %-20s  %s\n" "$formatted_size" "$date_display" "$filepath"
    done <<< "$results"

    if [[ "${FORMAT:-text}" == "json" ]]; then
        local items="[" jfirst=true
        while IFS=$'\t' read -r bytes mtime filepath; do
            [[ "$jfirst" == true ]] && jfirst=false || items+=","
            items+="$(to_json_kv "bytes" "$bytes" "modified" "$mtime" "path" "$filepath")"
        done <<< "$results"
        json_output "{\"mode\":\"old\",\"path\":\"$path\",\"items\":${items}]}"
    fi

    echo ""
}
