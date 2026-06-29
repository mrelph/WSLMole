#!/usr/bin/env bash
# WSLMole installer — symlinks `wslmole` into your PATH, installs the man page
# and shell completions, checks dependencies, and reports self-update status.
#
# Safe to re-run: every step is idempotent. Missing optional dependencies are
# reported as warnings and never fail the core install.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
SOURCE="$SCRIPT_DIR/wslmole"
TARGET="/usr/local/bin/wslmole"
MAN_SOURCE="$SCRIPT_DIR/docs/wslmole.1"
MAN_TARGET="/usr/local/share/man/man1/wslmole.1"
BASH_COMP_SOURCE="$SCRIPT_DIR/completions/wslmole.bash"
ZSH_COMP_SOURCE="$SCRIPT_DIR/completions/_wslmole"
BASH_COMP_SYS="/usr/local/share/bash-completion/completions/wslmole"
ZSH_COMP_SYS="/usr/local/share/zsh/site-functions/_wslmole"
USER_DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
BASH_COMP_USER="$USER_DATA/bash-completion/completions/wslmole"
ZSH_COMP_USER="$USER_DATA/zsh/site-functions/_wslmole"

# ── Output helpers ─────────────────────────────────────────────────
info() { printf '  %s\n' "$1"; }
ok()   { printf '  \xe2\x9c\x93 %s\n' "$1"; }
warn() { printf '  \xe2\x9a\xa0 %s\n' "$1"; }

WARNINGS=0
note_warning() { warn "$1"; WARNINGS=$((WARNINGS + 1)); }

# Read the declared version without sourcing the whole project.
read_version() {
    sed -n 's/^WSLMOLE_VERSION="\([^"]*\)".*/\1/p' "$SCRIPT_DIR/lib/common.sh" 2>/dev/null | head -1
}

echo "WSLMole installer"
echo "================="
echo ""

if [[ ! -f "$SOURCE" ]]; then
    echo "Error: wslmole not found at $SOURCE"
    exit 1
fi

VERSION="$(read_version)"
info "Installing WSLMole ${VERSION:+v$VERSION}"
echo ""

# ── 1. Dependency checks ───────────────────────────────────────────
echo "Checking dependencies..."

# Required: Bash 4+ and core coreutils/findutils tools.
missing_required=()
if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
    missing_required+=("bash >= 4 (found ${BASH_VERSION:-unknown})")
fi
for tool in find du stat df awk sed grep; do
    command -v "$tool" &>/dev/null || missing_required+=("$tool")
done

if [[ ${#missing_required[@]} -gt 0 ]]; then
    echo ""
    echo "Error: missing required dependencies:"
    for dep in "${missing_required[@]}"; do
        echo "  - $dep"
    done
    echo "Install coreutils/findutils and a modern Bash, then re-run."
    exit 1
fi
ok "Bash ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]} and coreutils/findutils present"

# Optional: git (self-update) and mandoc (man page rendering).
if command -v git &>/dev/null; then
    ok "git present (required for 'wslmole update')"
else
    note_warning "git not found — 'wslmole update' self-update will be unavailable"
fi
if command -v mandoc &>/dev/null || command -v man &>/dev/null; then
    ok "man/mandoc present (for 'man wslmole')"
else
    note_warning "mandoc/man not found — the man page will be installed but unreadable until you install one"
fi
echo ""

# ── 2. Install the executable symlink ──────────────────────────────
echo "Installing executable..."
chmod +x "$SOURCE"

installed_system=false
if ln -sf "$SOURCE" "$TARGET" 2>/dev/null; then
    ok "$TARGET -> $SOURCE"
    installed_system=true
else
    note_warning "Could not write to $(dirname "$TARGET") (no write access)"
    echo ""
    echo "  Install with sudo:"
    echo "    sudo ln -sf \"$SOURCE\" \"$TARGET\""
    echo ""
    echo "  ...or add the project directory to your PATH:"
    echo "    echo 'export PATH=\"$SCRIPT_DIR:\$PATH\"' >> ~/.bashrc && source ~/.bashrc"
fi
echo ""

# ── 3. Install the man page (best-effort) ──────────────────────────
if [[ -f "$MAN_SOURCE" ]]; then
    echo "Installing man page..."
    if mkdir -p "$(dirname "$MAN_TARGET")" 2>/dev/null && cp "$MAN_SOURCE" "$MAN_TARGET" 2>/dev/null; then
        ok "$MAN_TARGET"
        # Refresh the man-page database so `man wslmole` resolves immediately.
        if command -v mandb &>/dev/null; then
            mandb -q "$(dirname "$(dirname "$MAN_TARGET")")" &>/dev/null || true
        elif command -v makewhatis &>/dev/null; then
            makewhatis "$(dirname "$(dirname "$MAN_TARGET")")" &>/dev/null || true
        fi
    else
        note_warning "Could not install man page (try: sudo cp \"$MAN_SOURCE\" \"$MAN_TARGET\")"
    fi
    echo ""
fi

# ── 4. Install shell completions (best-effort) ─────────────────────
# Try a system-wide location first, then fall back to the per-user XDG path.
install_completion() {
    local src="$1" sys="$2" user="$3" shell="$4"
    [[ -f "$src" ]] || return 0
    if mkdir -p "$(dirname "$sys")" 2>/dev/null && cp "$src" "$sys" 2>/dev/null; then
        ok "$shell completion -> $sys"
    elif mkdir -p "$(dirname "$user")" 2>/dev/null && cp "$src" "$user" 2>/dev/null; then
        ok "$shell completion -> $user"
    else
        note_warning "Could not install $shell completion"
    fi
}

echo "Installing shell completions..."
install_completion "$BASH_COMP_SOURCE" "$BASH_COMP_SYS" "$BASH_COMP_USER" "bash"
install_completion "$ZSH_COMP_SOURCE" "$ZSH_COMP_SYS" "$ZSH_COMP_USER" "zsh"
info "Start a new shell (or 'source' your rc file) to pick up completions."
echo ""

# ── 5. Self-update awareness ───────────────────────────────────────
echo "Self-update status..."
if git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
    ok "Installed from a git checkout — 'wslmole update' is available"
else
    note_warning "Not a git checkout — 'wslmole update' will not work"
    info "To enable self-update, reinstall from a clone:"
    info "  git clone https://github.com/mrelph/WSLMole.git && cd WSLMole && ./install.sh"
fi
echo ""

# ── Summary ────────────────────────────────────────────────────────
echo "================="
if [[ "$installed_system" == true ]]; then
    echo "WSLMole ${VERSION:+v$VERSION} installed. Run 'wslmole' to get started."
else
    echo "WSLMole ${VERSION:+v$VERSION} set up (executable not symlinked — see above)."
fi
if [[ "$WARNINGS" -gt 0 ]]; then
    echo "Completed with $WARNINGS warning(s); the core install is in place."
fi
echo "Uninstall any time with: ./uninstall.sh"
exit 0
