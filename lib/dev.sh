#!/usr/bin/env bash
# WSLMole - Developer Artifact Cleanup Module
# Finds and removes build artifacts, dependency dirs, and caches

# Note: Strict mode set in main script

# All recognized developer artifact directory names
DEV_ARTIFACTS=(
    node_modules target __pycache__ .gradle venv .venv
    build dist .next .nuxt .cache vendor .tox
    .pytest_cache coverage .nyc_output
)

# ── CLI Handler ────────────────────────────────────────────────────
cmd_dev() {
    local path="."
    local older_than=""
    local types=()

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
            -t|--types)
                if [[ -z "${2:-}" ]]; then
                    print_error "--types requires a comma-separated list"
                    return 1
                fi
                IFS=',' read -ra types <<< "$2"
                shift 2
                ;;
            --older-than)
                if [[ -z "${2:-}" ]]; then
                    print_error "--older-than requires a number of days"
                    return 1
                fi
                older_than="$2"
                shift 2
                ;;
            -h|--help)
                cmd_dev_help
                return 0
                ;;
            -*)
                print_error "Unknown option: $1"
                cmd_dev_help
                return 1
                ;;
            *)
                path="$1"
                shift
                ;;
        esac
    done

    # Default types to full artifact list if none specified
    if [[ ${#types[@]} -eq 0 ]]; then
        types=("${DEV_ARTIFACTS[@]}")
    fi

    # Expand "all" to full list
    local expanded=()
    for t in "${types[@]}"; do
        if [[ "$t" == "all" ]]; then
            expanded=("${DEV_ARTIFACTS[@]}")
            break
        else
            expanded+=("$t")
        fi
    done
    types=("${expanded[@]}")

    cmd_dev_scan "$path" "$older_than" "${types[@]}"
}

# ── Help ───────────────────────────────────────────────────────────
cmd_dev_help() {
    cat << 'EOF'
Usage: wslmole dev [path] [options]

Scan for and clean developer build artifacts (node_modules, target, etc.).

Arguments:
  path                   Directory to scan (default: .)

Options:
  -n, --dry-run          Preview what would be cleaned without deleting
  -f, --force            Skip all confirmation prompts
  -t, --types LIST       Comma-separated artifact types to target
  --older-than DAYS      Only target artifacts older than DAYS days
  -h, --help             Show this help message

Artifact Types:
  node_modules   Node.js dependencies
  target         Rust/Java build output
  __pycache__    Python bytecode cache
  .gradle        Gradle build cache
  venv, .venv    Python virtual environments
  build          Generic build output
  dist           Distribution output
  .next          Next.js build cache
  .nuxt          Nuxt.js build cache
  .cache         Generic cache directory
  vendor         PHP/Go vendored dependencies
  .tox           Python tox test environments
  .pytest_cache  Pytest cache
  coverage       Code coverage reports
  .nyc_output    NYC/Istanbul coverage output
  all            All of the above

Examples:
  wslmole dev ~/projects --dry-run           Preview all artifacts
  wslmole dev . -t node_modules,target       Clean specific types only
  wslmole dev ~/code --older-than 30 -n      Preview artifacts older than 30 days
  wslmole dev ~/work -f -t all               Force-clean all artifact types
EOF
}

# ── Scanner ────────────────────────────────────────────────────────
cmd_dev_scan() {
    local path="${1:-.}"
    local older_than="${2:-}"
    shift 2 2>/dev/null || true
    local types=("$@")

    # Default types if none passed (supports call from menu_dev with just path)
    if [[ ${#types[@]} -eq 0 ]]; then
        types=("${DEV_ARTIFACTS[@]}")
    fi

    # Validate path exists
    if [[ ! -d "$path" ]]; then
        print_error "Path does not exist or is not a directory: $path"
        return 1
    fi

    # Resolve to absolute path
    path="$(cd "$path" && pwd)"

    print_header "Developer Artifact Scan: $path"

    if [[ "$DRY_RUN" == true ]]; then
        print_warning "DRY RUN mode - no files will be deleted"
        echo ""
    fi

    if [[ -n "$older_than" ]]; then
        print_info "Filtering artifacts older than $older_than days"
        echo ""
    fi

    # Build the find -name arguments for each artifact type
    local find_args=()
    local first=true
    for t in "${types[@]}"; do
        if [[ "$first" == true ]]; then
            find_args+=(-name "$t")
            first=false
        else
            find_args+=(-o -name "$t")
        fi
    done

    # Run find: look for matching directories, prune to avoid descending into them
    local found_artifacts=()
    local find_tmp
    find_tmp=$(mktemp)
    find "$path" -type d \( "${find_args[@]}" \) -prune 2>/dev/null > "$find_tmp" &
    local find_pid=$!
    print_info "Scanning for artifacts..."
    show_progress $find_pid
    wait $find_pid 2>/dev/null || true
    while IFS= read -r dir; do
        [[ -n "$dir" ]] || continue
        found_artifacts+=("$dir")
    done < "$find_tmp"
    rm -f "$find_tmp"

    local count=0
    local total_size=0

    for artifact in "${found_artifacts[@]+${found_artifacts[@]}}"; do
        # If older_than is set, check modification time
        if [[ -n "$older_than" ]]; then
            local mtime_days
            mtime_days=$(( ( $(date +%s) - $(stat -c %Y "$artifact" 2>/dev/null || echo "0") ) / 86400 ))
            if [[ $mtime_days -lt $older_than ]]; then
                continue
            fi
        fi

        # Get size
        local size
        size=$(du -sb "$artifact" 2>/dev/null | cut -f1)
        size="${size:-0}"

        # Compute relative path for display
        local rel_path="${artifact#"$path"/}"

        count=$((count + 1))
        total_size=$((total_size + size))

        if [[ "$DRY_RUN" == true ]]; then
            print_item "$rel_path ($(format_size "$size"))"
        else
            safe_delete "$artifact" "$rel_path"
        fi
    done

    # Summary
    echo ""
    if [[ "${FORMAT:-text}" == "json" ]]; then
        json_output "$(to_json_kv "path" "$path" "count" "$count" "total_bytes" "$total_size" "dry_run" "$DRY_RUN")"
    elif [[ $count -eq 0 ]]; then
        print_success "No developer artifacts found"
    else
        print_info "Found $count artifact(s) totaling $(format_size "$total_size")"
        if [[ "$DRY_RUN" == true ]]; then
            echo ""
            print_info "Run without --dry-run to delete these artifacts"
        fi
    fi
}
