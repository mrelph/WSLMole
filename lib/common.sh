#!/usr/bin/env bash
# WSLMole - Common Utilities
# Shared functions used by all modules

# ── Colors ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# ── Global State ────────────────────────────────────────────────────
WSLMOLE_VERSION="1.0.0"
WSLMOLE_LOG_DIR="${HOME}/.local/share/wslmole"
WSLMOLE_LOG_FILE="${WSLMOLE_LOG_DIR}/wslmole.log"
DRY_RUN=false
FORCE=false
VERBOSE=false

# Protected paths - NEVER delete these
PROTECTED_PATHS=(
    "/" "/bin" "/boot" "/dev" "/etc" "/home" "/lib" "/lib64"
    "/media" "/mnt" "/opt" "/proc" "/root" "/run" "/sbin"
    "/srv" "/sys" "/usr" "/var"
)

# ── Output Helpers ──────────────────────────────────────────────────
print_header() {
    echo -e "\n${BOLD}${BLUE}═══ $1 ═══${NC}\n"
}

print_success() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "  ${RED}✗${NC} $1"
}

print_info() {
    echo -e "  ${CYAN}ℹ${NC} $1"
}

print_item() {
    echo -e "  ${DIM}•${NC} $1"
}

# ── Size Formatting ─────────────────────────────────────────────────
format_size() {
    local bytes=$1
    if [[ $bytes -ge 1073741824 ]]; then
        printf "%.1f GB" "$(echo "scale=1; $bytes / 1073741824" | bc)"
    elif [[ $bytes -ge 1048576 ]]; then
        printf "%.1f MB" "$(echo "scale=1; $bytes / 1048576" | bc)"
    elif [[ $bytes -ge 1024 ]]; then
        printf "%.1f KB" "$(echo "scale=1; $bytes / 1024" | bc)"
    else
        printf "%d B" "$bytes"
    fi
}

# Get directory/file size in bytes
get_size_bytes() {
    local path="$1"
    if [[ -d "$path" ]]; then
        du -sb "$path" 2>/dev/null | cut -f1
    elif [[ -f "$path" ]]; then
        stat -c%s "$path" 2>/dev/null
    else
        echo 0
    fi
}

# ── Safety ──────────────────────────────────────────────────────────
is_protected_path() {
    local path
    path=$(realpath -m "$1" 2>/dev/null || echo "$1")
    for protected in "${PROTECTED_PATHS[@]}"; do
        if [[ "$path" == "$protected" ]]; then
            return 0
        fi
    done
    return 1
}

is_root() {
    [[ $EUID -eq 0 ]]
}

require_root_or_skip() {
    local operation="$1"
    if ! is_root; then
        print_warning "Skipping '$operation' - requires root (run with sudo)"
        return 1
    fi
    return 0
}

confirm() {
    local message="$1"
    if [[ "$FORCE" == true ]]; then
        return 0
    fi
    echo -en "  ${YELLOW}?${NC} ${message} [y/N] "
    read -r response
    [[ "$response" =~ ^[Yy]$ ]]
}

# ── Logging ─────────────────────────────────────────────────────────
init_logging() {
    if [[ "$VERBOSE" == true ]]; then
        mkdir -p "$WSLMOLE_LOG_DIR"
        echo "--- WSLMole session $(date -Iseconds) ---" >> "$WSLMOLE_LOG_FILE"
    fi
}

log() {
    if [[ "$VERBOSE" == true ]]; then
        echo "[$(date -Iseconds)] $1" >> "$WSLMOLE_LOG_FILE"
    fi
}

# ── Safe Deletion ───────────────────────────────────────────────────
safe_delete() {
    local path="$1"
    local description="${2:-$path}"

    if is_protected_path "$path"; then
        print_error "BLOCKED: Refusing to delete protected path: $path"
        log "BLOCKED: protected path $path"
        return 1
    fi

    if [[ ! -e "$path" ]]; then
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        local size
        size=$(get_size_bytes "$path")
        print_info "[DRY RUN] Would delete: $description ($(format_size "$size"))"
        log "DRY RUN: would delete $path ($size bytes)"
        return 0
    fi

    local size
    size=$(get_size_bytes "$path")
    if rm -rf "$path" 2>/dev/null; then
        print_success "Deleted: $description ($(format_size "$size"))"
        log "DELETED: $path ($size bytes)"
    else
        print_warning "Could not delete: $description (permission denied or in use)"
        log "FAILED: could not delete $path"
    fi
}

# ── WSL Detection ───────────────────────────────────────────────────
is_wsl() {
    [[ -f /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null
}

get_wsl_version() {
    if is_wsl; then
        if grep -qi "WSL2" /proc/version 2>/dev/null; then
            echo "2"
        else
            echo "1"
        fi
    else
        echo "0"
    fi
}
