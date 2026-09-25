#!/usr/bin/env bash
# WSLMole uninstaller — removes the symlink, man page, and shell completions
# installed by install.sh. Safe to re-run; removing something that is already
# gone is reported and skipped, never an error.
#
# Usage: ./uninstall.sh [--purge] [-h|--help]
#   --purge   Also remove user config (~/.config/wslmole) and data
#             (~/.local/share/wslmole), including the log file.
set -euo pipefail

TARGET="/usr/local/bin/wslmole"
MAN_TARGET="/usr/local/share/man/man1/wslmole.1"
BASH_COMP_SYS="/usr/local/share/bash-completion/completions/wslmole"
ZSH_COMP_SYS="/usr/local/share/zsh/site-functions/_wslmole"
USER_DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
USER_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
BASH_COMP_USER="$USER_DATA/bash-completion/completions/wslmole"
ZSH_COMP_USER="$USER_DATA/zsh/site-functions/_wslmole"
CONFIG_DIR="$USER_CONFIG/wslmole"
DATA_DIR="$USER_DATA/wslmole"

PURGE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --purge) PURGE=true; shift ;;
        -h|--help)
            sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: ./uninstall.sh [--purge] [-h|--help]" >&2
            exit 1
            ;;
    esac
done

info() { printf '  %s\n' "$1"; }
ok()   { printf '  \xe2\x9c\x93 %s\n' "$1"; }
skip() { printf '  \xc2\xb7 %s\n' "$1"; }
warn() { printf '  \xe2\x9a\xa0 %s\n' "$1"; }

echo "WSLMole uninstaller"
echo "==================="
echo ""

REMOVED=0

# Remove a file/symlink if present; report what happened.
remove_path() {
    local path="$1" label="$2"
    if [[ -e "$path" || -L "$path" ]]; then
        if rm -f "$path" 2>/dev/null; then
            ok "Removed $label ($path)"
            REMOVED=$((REMOVED + 1))
        else
            warn "Could not remove $label — try: sudo rm -f \"$path\""
        fi
    else
        skip "$label not present ($path)"
    fi
}

# Remove a directory tree if present; report what happened.
remove_dir() {
    local path="$1" label="$2"
    if [[ -d "$path" ]]; then
        if rm -rf "$path" 2>/dev/null; then
            ok "Removed $label ($path)"
            REMOVED=$((REMOVED + 1))
        else
            warn "Could not remove $label — try: sudo rm -rf \"$path\""
        fi
    else
        skip "$label not present ($path)"
    fi
}

echo "Removing executable and man page..."
remove_path "$TARGET" "executable symlink"
remove_path "$MAN_TARGET" "man page"
echo ""

echo "Removing shell completions..."
remove_path "$BASH_COMP_SYS" "bash completion (system)"
remove_path "$BASH_COMP_USER" "bash completion (user)"
remove_path "$ZSH_COMP_SYS" "zsh completion (system)"
remove_path "$ZSH_COMP_USER" "zsh completion (user)"
echo ""

if [[ "$PURGE" == true ]]; then
    echo "Purging user config and data..."
    remove_dir "$CONFIG_DIR" "config directory"
    remove_dir "$DATA_DIR" "data directory"
    echo ""
else
    echo "Keeping user config and data:"
    info "$CONFIG_DIR"
    info "$DATA_DIR"
    info "Re-run with --purge to remove them too."
    echo ""
fi

echo "==================="
if [[ "$REMOVED" -gt 0 ]]; then
    echo "WSLMole uninstalled ($REMOVED item(s) removed)."
else
    echo "Nothing to remove — WSLMole was not installed in the standard locations."
fi
exit 0
