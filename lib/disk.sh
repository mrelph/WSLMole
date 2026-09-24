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

    validate_integer_option "$depth" "--depth" 0 20 || return 1
    validate_integer_option "$top" "--top" 1 1000 || return 1

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
    echo -e "  ${BOLD}-d, --depth${NC} N        Tree depth, 0-20 (default: 3)"
    echo -e "  ${BOLD}-n, --top${NC} N          Number of results, 1-1000 (default: 10)"
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

    validate_integer_option "$depth" "--depth" 0 20 || return 1
    validate_integer_option "$top" "--top" 1 1000 || return 1

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
        local filesystem="" size=0 used=0 available=0 capacity="" mount=""
        read -r filesystem size used available capacity mount \
            < <(df -P -B1 "$path" 2>/dev/null | awk 'NR==2 {print $1, $2, $3, $4, $5, $6}')
        json_output "{\"mode\":\"summary\",\"path\":$(json_quote "$path"),\"fs\":{\"filesystem\":$(json_quote "$filesystem"),\"size\":${size:-0},\"used\":${used:-0},\"available\":${available:-0},\"mount\":$(json_quote "$mount")}}"
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

    local results_tmp
    results_tmp=$(mktemp)
    (du -B1 --null --max-depth="$depth" "$path" 2>/dev/null | sort -z -rn > "$results_tmp" || true) &
    local scan_pid=$!
    show_progress "$scan_pid"
    wait "$scan_pid" 2>/dev/null || true

    local -a sizes=()
    local -a paths=()
    local record bytes dir
    while IFS= read -r -d '' record; do
        bytes="${record%%$'\t'*}"
        dir="${record#*$'\t'}"
        sizes+=("$bytes")
        paths+=("$dir")
        (( ${#paths[@]} >= 40 )) && break
    done < "$results_tmp"
    rm -f "$results_tmp"

    local i
    for i in "${!paths[@]}"; do
        bytes="${sizes[$i]}"
        dir="${paths[$i]}"
        # Calculate relative depth for indentation
        local dir_depth
        dir_depth=$(echo "$dir" | tr -cd '/' | wc -c)
        local indent_level=$((dir_depth - base_depth))

        # Build indentation string
        local indent=""
        local indent_i
        for ((indent_i = 0; indent_i < indent_level; indent_i++)); do
            indent+="  "
        done

        printf "    %s%-12s %s\n" "$indent" "$(format_size "$bytes")" "$dir"
    done

    if [[ "${FORMAT:-text}" == "json" ]]; then
        local items="[" first=true
        for i in "${!paths[@]}"; do
            [[ "$first" == true ]] && first=false || items+=","
            items+="$(to_json_kv "bytes" "${sizes[$i]}" "path" "${paths[$i]}")"
        done
        items+="]"
        json_output "{\"mode\":\"tree\",\"path\":$(json_quote "$path"),\"depth\":${depth},\"items\":${items}}"
    fi

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
    (find "$path" -type f -printf '%s\t%p\0' 2>/dev/null | sort -z -rn > "$results_tmp" || true) &
    local scan_pid=$!
    show_progress "$scan_pid"
    wait "$scan_pid" 2>/dev/null || true

    local -a sizes=()
    local -a paths=()
    local record bytes filepath
    while IFS= read -r -d '' record; do
        bytes="${record%%$'\t'*}"
        filepath="${record#*$'\t'}"
        sizes+=("$bytes")
        paths+=("$filepath")
        (( ${#paths[@]} >= top )) && break
    done < "$results_tmp"
    rm -f "$results_tmp"

    if [[ ${#paths[@]} -eq 0 ]]; then
        print_info "No files found in $path"
    else
        echo ""
    fi

    local i
    for i in "${!paths[@]}"; do
        bytes="${sizes[$i]}"
        filepath="${paths[$i]}"
        local formatted_size
        formatted_size=$(format_size "$bytes")
        printf "    %2d. %-12s %s\n" "$((i + 1))" "$formatted_size" "$filepath"
    done

    if [[ "${FORMAT:-text}" == "json" ]]; then
        local items="[" jfirst=true
        for i in "${!paths[@]}"; do
            [[ "$jfirst" == true ]] && jfirst=false || items+=","
            items+="$(to_json_kv "bytes" "${sizes[$i]}" "path" "${paths[$i]}")"
        done
        items+="]"
        json_output "{\"mode\":\"files\",\"path\":$(json_quote "$path"),\"items\":${items}}"
    fi

    echo ""
}

# ── 4. Largest Folders ────────────────────────────────────────────
disk_largest_folders() {
    local path="$1"
    local top="$2"

    print_header "Largest Folders: $path (top $top)"

    local results_tmp
    results_tmp=$(mktemp)
    while IFS= read -r -d '' dirpath; do
        printf '%s\t%s\0' "$(get_size_bytes "$dirpath")" "$dirpath"
    done < <(find "$path" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null || true) \
        | sort -z -rn > "$results_tmp"

    local -a sizes=()
    local -a paths=()
    local record bytes dirpath
    while IFS= read -r -d '' record; do
        bytes="${record%%$'\t'*}"
        dirpath="${record#*$'\t'}"
        sizes+=("$bytes")
        paths+=("$dirpath")
        (( ${#paths[@]} >= top )) && break
    done < "$results_tmp"
    rm -f "$results_tmp"

    if [[ ${#paths[@]} -eq 0 ]]; then
        print_info "No subdirectories found in $path"
    else
        echo ""
    fi

    local i
    for i in "${!paths[@]}"; do
        bytes="${sizes[$i]}"
        dirpath="${paths[$i]}"
        local formatted_size
        formatted_size=$(format_size "$bytes")
        local name="${dirpath%/}"
        printf "    %2d. %-12s %s\n" "$((i + 1))" "$formatted_size" "$name"
    done

    if [[ "${FORMAT:-text}" == "json" ]]; then
        local items="[" first=true
        for i in "${!paths[@]}"; do
            [[ "$first" == true ]] && first=false || items+=","
            items+="$(to_json_kv "bytes" "${sizes[$i]}" "path" "${paths[$i]}")"
        done
        items+="]"
        json_output "{\"mode\":\"folders\",\"path\":$(json_quote "$path"),\"items\":${items}}"
    fi

    echo ""
}

# ── 5. File Types ─────────────────────────────────────────────────
disk_file_types() {
    local path="$1"

    print_header "Disk Usage by File Type: $path"

    local -A totals=()
    local -A counts=()
    local record bytes filename ext
    while IFS= read -r -d '' record; do
        bytes="${record%%$'\t'*}"
        filename="${record#*$'\t'}"
        ext="(no ext)"
        if [[ "$filename" == *.* ]]; then
            local candidate="${filename##*.}"
            if [[ -n "$candidate" && ${#candidate} -le 10 && "$candidate" =~ ^[[:alnum:]_+-]+$ ]]; then
                ext="${candidate,,}"
            fi
        fi
        totals["$ext"]=$(( ${totals["$ext"]:-0} + bytes ))
        counts["$ext"]=$(( ${counts["$ext"]:-0} + 1 ))
    done < <(find "$path" -type f -printf '%s\t%f\0' 2>/dev/null || true)

    local results_tmp
    results_tmp=$(mktemp)
    for ext in "${!totals[@]}"; do
        printf '%s\t%s\t%s\0' "${totals[$ext]}" "${counts[$ext]}" "$ext"
    done | sort -z -rn > "$results_tmp"

    if [[ ${#totals[@]} -eq 0 ]]; then
        print_info "No files found in $path"
    else
        echo ""
        printf "    %-12s  %8s  %s\n" "SIZE" "COUNT" "EXTENSION"
        printf "    %-12s  %8s  %s\n" "────────────" "────────" "─────────"
    fi

    local -a result_bytes=()
    local -a result_counts=()
    local -a result_exts=()
    local count display_ext
    while IFS= read -r -d '' record; do
        bytes="${record%%$'\t'*}"
        local remainder="${record#*$'\t'}"
        count="${remainder%%$'\t'*}"
        ext="${remainder#*$'\t'}"
        result_bytes+=("$bytes")
        result_counts+=("$count")
        result_exts+=("$ext")
        display_ext="$ext"
        [[ "$ext" != "(no ext)" ]] && display_ext=".$ext"
        printf "    %-12s  %8d  %s\n" "$(format_size "$bytes")" "$count" "$display_ext"
    done < "$results_tmp"
    rm -f "$results_tmp"

    if [[ "${FORMAT:-text}" == "json" ]]; then
        local items="[" first=true i
        for i in "${!result_exts[@]}"; do
            [[ "$first" == true ]] && first=false || items+=","
            items+="$(to_json_kv "bytes" "${result_bytes[$i]}" "count" "${result_counts[$i]}" "extension" "${result_exts[$i]}")"
        done
        items+="]"
        json_output "{\"mode\":\"types\",\"path\":$(json_quote "$path"),\"items\":${items}}"
    fi

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
    (find "$path" -type f -mtime +90 -printf '%s\t%T+\t%p\0' 2>/dev/null | sort -z -rn > "$results_tmp" || true) &
    local scan_pid=$!
    show_progress "$scan_pid"
    wait "$scan_pid" 2>/dev/null || true

    local -a sizes=()
    local -a mtimes=()
    local -a paths=()
    local record bytes remainder mtime filepath
    while IFS= read -r -d '' record; do
        bytes="${record%%$'\t'*}"
        remainder="${record#*$'\t'}"
        mtime="${remainder%%$'\t'*}"
        filepath="${remainder#*$'\t'}"
        sizes+=("$bytes")
        mtimes+=("$mtime")
        paths+=("$filepath")
        (( ${#paths[@]} >= top )) && break
    done < "$results_tmp"
    rm -f "$results_tmp"

    if [[ ${#paths[@]} -eq 0 ]]; then
        print_info "No files older than 90 days found in $path"
    else
        echo ""
        printf "    %-12s  %-20s  %s\n" "SIZE" "LAST MODIFIED" "PATH"
        printf "    %-12s  %-20s  %s\n" "────────────" "────────────────────" "────"
    fi

    local i
    for i in "${!paths[@]}"; do
        bytes="${sizes[$i]}"
        mtime="${mtimes[$i]}"
        filepath="${paths[$i]}"
        local formatted_size
        formatted_size=$(format_size "$bytes")
        # Trim the fractional seconds from the timestamp for cleaner display
        local date_display="${mtime%%.*}"
        # Replace the T with a space for readability
        date_display="${date_display//T/ }"
        printf "    %-12s  %-20s  %s\n" "$formatted_size" "$date_display" "$filepath"
    done

    if [[ "${FORMAT:-text}" == "json" ]]; then
        local items="[" jfirst=true
        for i in "${!paths[@]}"; do
            [[ "$jfirst" == true ]] && jfirst=false || items+=","
            items+="$(to_json_kv "bytes" "${sizes[$i]}" "modified" "${mtimes[$i]}" "path" "${paths[$i]}")"
        done
        items+="]"
        json_output "{\"mode\":\"old\",\"path\":$(json_quote "$path"),\"items\":${items}}"
    fi

    echo ""
}
