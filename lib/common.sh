#!/usr/bin/env bash
# WSLMole - Common Utilities
# Shared functions used by all modules

# Note: set -euo pipefail is set in main script, not here to allow sourcing

# ── Colors ──────────────────────────────────────────────────────────
# Respect NO_COLOR (https://no-color.org/) and non-TTY output
_init_colors() {
    if [[ -n "${NO_COLOR:-}" ]] || [[ "${WSLMOLE_NO_COLOR:-}" == "1" ]] || [[ ! -t 1 ]]; then
        RED='' GREEN='' YELLOW='' BLUE='' CYAN='' MAGENTA='' WHITE=''
        BOLD='' DIM='' ITALIC='' NC=''
    else
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        CYAN='\033[0;36m'
        MAGENTA='\033[0;35m'
        WHITE='\033[1;37m'
        BOLD='\033[1m'
        DIM='\033[2m'
        ITALIC='\033[3m'
        NC='\033[0m'
    fi
}
_init_colors

# ── Global State ────────────────────────────────────────────────────
WSLMOLE_VERSION="2.0.0"
WSLMOLE_LOG_DIR="${HOME}/.local/share/wslmole"
WSLMOLE_LOG_FILE="${WSLMOLE_LOG_DIR}/wslmole.log"
WSLMOLE_CONFIG_FILE="${HOME}/.config/wslmole/config"
WSLMOLE_LOG_LEVEL="INFO"
WSLMOLE_PROBE_TIMEOUT="${WSLMOLE_PROBE_TIMEOUT:-2}"
DRY_RUN=true
FORCE=false
VERBOSE=false

# Protected paths - NEVER delete these (exact match)
PROTECTED_PATHS=(
    "/" "/bin" "/boot" "/dev" "/etc" "/home" "/lib" "/lib64"
    "/media" "/mnt" "/opt" "/proc" "/root" "/run" "/sbin"
    "/srv" "/sys" "/usr" "/var"
    "/usr/bin" "/usr/lib" "/usr/lib64" "/usr/sbin"
)

# System trees where nothing inside may be deleted either (prefix match).
# /var, /tmp, /home etc. are deliberately absent: the tool legitimately
# deletes children there (/var/log/*.gz, /tmp/*, ~/.cache).
PROTECTED_PREFIXES=(
    "/bin" "/sbin" "/boot" "/dev" "/etc" "/lib" "/lib64"
    "/proc" "/sys" "/usr" "/run"
)

# ── Configuration ───────────────────────────────────────────────────
VALID_CONFIG_KEYS="DRY_RUN FORCE VERBOSE WSLMOLE_LOG_LEVEL WSLMOLE_UPDATE_INTERVAL WSLMOLE_PROBE_TIMEOUT"

# Warn about a config problem on stderr (so users actually see it) and log it.
# stderr keeps stdout/JSON output clean for scripted consumers.
_config_warn() {
    printf '  %b⚠ config:%b %s\n' "$YELLOW" "$NC" "$1" >&2
    log_warn "$1"
}

load_config() {
    [[ -f "$WSLMOLE_CONFIG_FILE" ]] || return 0
    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        # Require strict KEY=VALUE format (no shell commands, no spaces in key)
        if [[ ! "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            _config_warn "Malformed config line $line_num in $WSLMOLE_CONFIG_FILE (skipped)"
            continue
        fi
        local key="${BASH_REMATCH[1]}"
        local val="${BASH_REMATCH[2]}"
        # Strip surrounding quotes from value
        val="${val#\"}" ; val="${val%\"}"
        val="${val#\'}" ; val="${val%\'}"
        if [[ ! " $VALID_CONFIG_KEYS " =~ [[:space:]]${key}[[:space:]] ]]; then
            _config_warn "Unknown config key '$key' at line $line_num in $WSLMOLE_CONFIG_FILE"
            continue
        fi
        # Validate value contains no command substitution or semicolons
        if [[ "$val" =~ [\$\;\`\|] ]]; then
            _config_warn "Unsafe characters in value for '$key' at line $line_num (skipped)"
            continue
        fi
        # Assign only known keys
        case "$key" in
            DRY_RUN)       [[ "$val" =~ ^(true|false)$ ]] && DRY_RUN="$val" ;;
            FORCE)         [[ "$val" =~ ^(true|false)$ ]] && FORCE="$val" ;;
            VERBOSE)       [[ "$val" =~ ^(true|false)$ ]] && VERBOSE="$val" ;;
            WSLMOLE_LOG_LEVEL) [[ "$val" =~ ^(DEBUG|INFO|WARN|ERROR)$ ]] && WSLMOLE_LOG_LEVEL="$val" ;;
            WSLMOLE_UPDATE_INTERVAL) [[ "$val" =~ ^[0-9]+$ ]] && WSLMOLE_UPDATE_INTERVAL="$val" ;;
            WSLMOLE_PROBE_TIMEOUT)
                [[ "$val" =~ ^[0-9]+$ ]] && (( val >= 1 && val <= 30 )) && WSLMOLE_PROBE_TIMEOUT="$val"
                ;;
        esac
        # Invalid values are ignored. Keep load_config successful under `set -e`.
        true
    done < "$WSLMOLE_CONFIG_FILE"
}

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

print_section() {
    echo -e "\n${BOLD}$1${NC}"
}

# ── Progress Display ────────────────────────────────────────────────
show_progress() {
    local pid=$1
    local chars="/-\|"
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r\033[K  %s " "${chars:$i:1}"
        i=$(( (i + 1) % 4 ))
        sleep 0.1
    done
    printf "\r\033[K"
}

# ── JSON Output ─────────────────────────────────────────────────────
json_output() {
    if [[ "${FORMAT:-text}" == "json" && "${JSON_STDOUT_FD:-}" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$1" >&"$JSON_STDOUT_FD"
    else
        printf '%s\n' "$1"
    fi
}

json_escape() {
    local value="${1-}"
    local escaped=""
    local char code encoded
    local i
    local LC_ALL=C
    for ((i = 0; i < ${#value}; i++)); do
        char="${value:i:1}"
        case "$char" in
            '"') escaped+='\"' ;;
            \\) escaped+=$'\\\\' ;;
            $'\b') escaped+='\b' ;;
            $'\f') escaped+='\f' ;;
            $'\n') escaped+='\n' ;;
            $'\r') escaped+='\r' ;;
            $'\t') escaped+='\t' ;;
            *)
                printf -v code '%d' "'$char"
                if (( code < 32 )); then
                    printf -v encoded '\\u%04x' "$code"
                    escaped+="$encoded"
                else
                    escaped+="$char"
                fi
                ;;
        esac
    done
    printf '%s' "$escaped"
}

json_quote() {
    printf '"%s"' "$(json_escape "${1-}")"
}

# Build JSON object from key=value arguments
# Usage: to_json_kv "key1" "val1" "key2" "val2" ...
to_json_kv() {
    local json="{"
    local first=true
    while [[ $# -ge 2 ]]; do
        local key="$1" val="$2"
        shift 2
        if [[ "$first" == true ]]; then
            first=false
        else
            json+=","
        fi
        # Pass numbers/booleans/null raw, quote everything else
        if [[ "$val" =~ ^-?[0-9]+\.?[0-9]*$ ]] || [[ "$val" =~ ^(true|false|null)$ ]]; then
            json+="\"${key}\":${val}"
        else
            json+="\"${key}\":$(json_quote "$val")"
        fi
    done
    json+="}"
    echo "$json"
}

# ── Size Formatting ─────────────────────────────────────────────────
# Pure integer arithmetic (no 'bc' dependency). One decimal, truncated.
format_size() {
    local bytes=${1:-0}
    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
    local div unit
    if (( bytes >= 1073741824 )); then div=1073741824; unit="GB"
    elif (( bytes >= 1048576 )); then div=1048576; unit="MB"
    elif (( bytes >= 1024 )); then div=1024; unit="KB"
    else
        printf "%d B" "$bytes"
        return
    fi
    printf "%d.%d %s" "$(( bytes / div ))" "$(( bytes % div * 10 / div ))" "$unit"
}

# Get directory/file size in bytes
get_size_bytes() {
    local path="$1"
    local size=""
    if [[ -d "$path" ]]; then
        size=$(du -sb "$path" 2>/dev/null | awk 'NR==1 {print $1}' || true)
    elif [[ -f "$path" ]]; then
        # Try Linux stat first, then macOS stat
        size=$(stat -c%s "$path" 2>/dev/null || stat -f%z "$path" 2>/dev/null || true)
    else
        size=0
    fi
    [[ "$size" =~ ^[0-9]+$ ]] && echo "$size" || echo 0
}

# Run a read-only system probe with a hard deadline. GNU timeout is available
# in the target WSL/Ubuntu environment; gtimeout supports macOS development.
run_probe() {
    local seconds="${1:-$WSLMOLE_PROBE_TIMEOUT}"
    shift

    if ! [[ "$seconds" =~ ^[0-9]+$ ]] || (( seconds < 1 )); then
        return 2
    fi

    if command -v timeout >/dev/null 2>&1; then
        timeout --signal=TERM --kill-after=1s "${seconds}s" "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout --signal=TERM --kill-after=1s "${seconds}s" "$@"
    else
        # Portable fallback for development environments without coreutils.
        "$@" &
        local command_pid=$!
        (
            sleep "$seconds"
            kill -TERM "$command_pid" 2>/dev/null || exit 0
            sleep 1
            kill -KILL "$command_pid" 2>/dev/null || true
        ) &
        local timer_pid=$!
        local rc=0
        wait "$command_pid" || rc=$?
        if kill -0 "$timer_pid" 2>/dev/null; then
            kill "$timer_pid" 2>/dev/null || true
            wait "$timer_pid" 2>/dev/null || true
        else
            wait "$timer_pid" 2>/dev/null || true
            if [[ $rc -eq 137 || $rc -eq 143 ]]; then
                return 124
            fi
        fi
        return "$rc"
    fi
}

validate_integer_option() {
    local value="$1"
    local option_name="$2"
    local minimum="${3:-0}"
    local maximum="${4:-2147483647}"

    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        print_error "$option_name requires an integer"
        return 1
    fi
    if (( value < minimum || value > maximum )); then
        print_error "$option_name must be between $minimum and $maximum"
        return 1
    fi
}

sum_files_older_than() {
    local dir="$1"
    local days="${2:-7}"
    local total=0
    local size
    [[ -d "$dir" ]] || { printf '0\n'; return 0; }
    while IFS= read -r -d '' size; do
        [[ "$size" =~ ^[0-9]+$ ]] || continue
        total=$((total + size))
    done < <(find "$dir" -type f -mtime "+$days" -printf '%s\0' 2>/dev/null || true)
    printf '%s\n' "$total"
}

sum_rotated_log_bytes() {
    local log_dir="${1:-/var/log}"
    local total=0
    local size
    [[ -d "$log_dir" ]] || { printf '0\n'; return 0; }
    while IFS= read -r -d '' size; do
        [[ "$size" =~ ^[0-9]+$ ]] || continue
        total=$((total + size))
    done < <(find "$log_dir" -type f \
        \( -name "*.gz" -o -name "*.old" -o -name "*.1" -o -name "*.2" -o -name "*.3" \) \
        -printf '%s\0' 2>/dev/null || true)
    printf '%s\n' "$total"
}

# Print "<count> <bytes>" for disabled revisions in snap-list output.
snap_disabled_stats() {
    local snap_output="${1-}"
    local snap_dir="${2:-/var/lib/snapd/snaps}"
    local count=0
    local bytes=0
    local snap_name snap_rev snap_file

    while read -r snap_name snap_rev; do
        [[ "$snap_name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || continue
        [[ "$snap_rev" =~ ^[0-9]+$ ]] || continue
        count=$((count + 1))
        snap_file="$snap_dir/${snap_name}_${snap_rev}.snap"
        bytes=$((bytes + $(get_size_bytes "$snap_file")))
    done < <(printf '%s\n' "$snap_output" | awk '$NF == "disabled" {print $1, $3}')

    printf '%s %s\n' "$count" "$bytes"
}

# ── Safety ──────────────────────────────────────────────────────────
validate_path() {
    local path="$1"
    local allow_nonexistent="${2:-false}"
    
    # Resolve to absolute path
    if ! path=$(realpath -m "$path" 2>/dev/null); then
        print_error "Invalid path: $1"
        return 1
    fi
    
    # Check for suspicious patterns
    if [[ "$path" =~ \.\./\.\. ]] || [[ "$path" == "/" ]]; then
        print_error "Suspicious path pattern: $path"
        return 1
    fi
    
    # Check if protected
    if is_protected_path "$path"; then
        print_error "Path is protected: $path"
        return 1
    fi
    
    # Check existence if required
    if [[ "$allow_nonexistent" != "true" ]] && [[ ! -e "$path" ]]; then
        print_error "Path does not exist: $path"
        return 1
    fi
    
    echo "$path"
}

is_protected_path() {
    local input_path resolved_path protected resolved_protected prefix
    input_path=$(realpath -m "$1" 2>/dev/null || echo "$1")
    resolved_path=$(realpath "$input_path" 2>/dev/null || echo "$input_path")
    for protected in "${PROTECTED_PATHS[@]}"; do
        resolved_protected=$(realpath "$protected" 2>/dev/null || echo "$protected")
        if [[ "$input_path" == "$protected" || "$resolved_path" == "$resolved_protected" ]]; then
            return 0
        fi
    done
    for prefix in "${PROTECTED_PREFIXES[@]}"; do
        if [[ "$input_path" == "$prefix/"* || "$resolved_path" == "$prefix/"* ]]; then
            return 0
        fi
    done
    return 1
}

# Windows username via interop, validated before use in path construction.
# Returns empty if interop is unavailable or the name contains unsafe chars.
get_windows_username() {
    local name
    if ! command -v cmd.exe >/dev/null 2>&1; then
        return 0
    fi
    name=$(run_probe "$WSLMOLE_PROBE_TIMEOUT" cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' || true)
    if [[ -n "$name" && ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9\ ._-]*$ ]]; then
        log_warn "Ignoring Windows username with unexpected characters"
        name=""
    fi
    printf '%s' "$name"
}

is_root() {
    [[ $EUID -eq 0 ]]
}

has_sudo() {
    [[ $EUID -eq 0 ]] || sudo -n true 2>/dev/null
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
    if [[ "${FORCE:-false}" == true ]]; then
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
        # Rotate log if > 1MB
        if [[ -f "$WSLMOLE_LOG_FILE" ]] && [[ $(get_size_bytes "$WSLMOLE_LOG_FILE") -gt 1048576 ]]; then
            mv "$WSLMOLE_LOG_FILE" "${WSLMOLE_LOG_FILE}.1"
        fi
        echo "--- WSLMole session $(date -Iseconds) ---" >> "$WSLMOLE_LOG_FILE"
    fi
}

_log() {
    if [[ "${VERBOSE:-false}" == true ]]; then
        echo "[$(date -Iseconds)] [$1] $2" >> "$WSLMOLE_LOG_FILE"
    fi
}

log_debug() {
    [[ "$WSLMOLE_LOG_LEVEL" == "DEBUG" ]] && _log "DEBUG" "$1"
    return 0
}

log_info() {
    [[ "$WSLMOLE_LOG_LEVEL" =~ ^(DEBUG|INFO)$ ]] && _log "INFO" "$1"
    return 0
}

log_warn() {
    [[ "$WSLMOLE_LOG_LEVEL" =~ ^(DEBUG|INFO|WARN)$ ]] && _log "WARN" "$1"
    return 0
}

log_error() {
    _log "ERROR" "$1"
    return 0
}

# Backward-compatible alias
log() {
    log_info "$1"
}

# ── Suggestion Helpers ──────────────────────────────────────────────

# Find closest match from a list using simple character overlap
# Usage: suggest_match "typo" "valid1 valid2 valid3"
suggest_match() {
    local input="$1"
    shift
    local best="" best_score=0
    for candidate in "$@"; do
        local score=0 i=0
        # Count matching characters in order (simple subsequence score)
        local ci=0
        while (( i < ${#input} && ci < ${#candidate} )); do
            if [[ "${input:$i:1}" == "${candidate:$ci:1}" ]]; then
                score=$((score + 1))
                i=$((i + 1))
            fi
            ci=$((ci + 1))
        done
        # Bonus for matching prefix
        local prefix_len=0
        while (( prefix_len < ${#input} && prefix_len < ${#candidate} )) && \
              [[ "${input:$prefix_len:1}" == "${candidate:$prefix_len:1}" ]]; do
            prefix_len=$((prefix_len + 1))
            score=$((score + 2))
        done
        if (( score > best_score )); then
            best_score=$score
            best="$candidate"
        fi
    done
    # Only suggest if reasonably close (at least half the chars match)
    local threshold=$(( ${#input} / 2 ))
    (( threshold < 2 )) && threshold=2
    if (( best_score >= threshold )) && [[ -n "$best" ]]; then
        echo "$best"
    fi
}

# Print "did you mean?" suggestion and list valid values
# Usage: suggest_correction "typo" "context" valid1 valid2 valid3
suggest_correction() {
    local input="$1"
    local context="$2"
    shift 2
    local match
    match=$(suggest_match "$input" "$@")
    if [[ -n "$match" ]]; then
        print_info "Did you mean '${match}'?"
    fi
    print_info "Valid ${context}: $*"
}

# ── Safe Deletion ───────────────────────────────────────────────────
# Returns: 0=success, 1=blocked, 2=not found, 3=permission denied
safe_delete() {
    local path="$1"
    local description="${2:-$path}"

    # Validate path is absolute
    case "$path" in
        /*) ;; # absolute path - OK
        *)
            print_error "safe_delete requires absolute path, got: $path"
            log_error "BLOCKED: relative path $path"
            return 1
            ;;
    esac

    # Block path traversal. Match ".." only as a whole path component
    # ("/../", trailing "/..") so legitimate names like "foo..bar" are allowed.
    if [[ "$path" =~ (^|/)\.\.(/|$) ]] || [[ "$path" == "/" ]]; then
        print_error "BLOCKED: Suspicious path pattern: $path"
        log_error "BLOCKED: suspicious pattern $path"
        return 1
    fi

    if is_protected_path "$path"; then
        print_error "BLOCKED: Refusing to delete protected path: $path"
        log_error "BLOCKED: protected path $path"
        return 1
    fi

    if [[ ! -e "$path" ]]; then
        return 0
    fi

    if [[ "${DRY_RUN:-false}" == true ]]; then
        local size
        size=$(get_size_bytes "$path")
        print_info "[DRY RUN] Would delete: $description ($(format_size "$size"))"
        log_info "DRY RUN: would delete $path ($size bytes)"
        return 0
    fi

    local size
    size=$(get_size_bytes "$path")
    if rm -rf "$path" 2>/dev/null; then
        print_success "Deleted: $description ($(format_size "$size"))"
        log_info "DELETED: $path ($size bytes)"
        return 0
    else
        print_warning "Could not delete: $description (permission denied or in use)"
        log_warn "FAILED: could not delete $path"
        return 3
    fi
}

# Consume NUL-delimited absolute paths and route every deletion through the
# same validation and audit path as a single safe_delete call.
safe_delete_nul_stream() {
    local description="${1:-item}"
    local path
    local rc=0
    while IFS= read -r -d '' path; do
        [[ -n "$path" ]] || continue
        safe_delete "$path" "$description: $(basename "$path")" || rc=1
    done
    return "$rc"
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
