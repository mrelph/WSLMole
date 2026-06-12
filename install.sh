#!/usr/bin/env bash
# WSLMole installer — symlinks `wslmole` into your PATH and installs man page
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
SOURCE="$SCRIPT_DIR/wslmole"
TARGET="/usr/local/bin/wslmole"
MAN_SOURCE="$SCRIPT_DIR/docs/wslmole.1"
MAN_TARGET="/usr/local/share/man/man1/wslmole.1"

echo "WSLMole installer"
echo "================="
echo ""

if [[ ! -f "$SOURCE" ]]; then
    echo "Error: wslmole not found at $SOURCE"
    exit 1
fi

# Ensure the main script is executable
chmod +x "$SOURCE"

# Try to create the symlink directly
if ln -sf "$SOURCE" "$TARGET" 2>/dev/null; then
    echo "Installed: $TARGET -> $SOURCE"

    # Install man page
    if [[ -f "$MAN_SOURCE" ]]; then
        mkdir -p "$(dirname "$MAN_TARGET")" 2>/dev/null || true
        if cp "$MAN_SOURCE" "$MAN_TARGET" 2>/dev/null; then
            echo "Man page: $MAN_TARGET"
        else
            echo "Note: Could not install man page (try: sudo cp \"$MAN_SOURCE\" \"$MAN_TARGET\")"
        fi
    fi

    echo ""
    echo "Run 'wslmole' to get started."
else
    echo "Could not write to /usr/local/bin (no write access)."
    echo ""
    echo "Option 1 — install with sudo:"
    echo "  sudo ln -sf \"$SOURCE\" \"$TARGET\""
    if [[ -f "$MAN_SOURCE" ]]; then
        echo "  sudo mkdir -p $(dirname "$MAN_TARGET")"
        echo "  sudo cp \"$MAN_SOURCE\" \"$MAN_TARGET\""
    fi
    echo ""
    echo "Option 2 — add the project directory to your PATH:"
    echo "  echo 'export PATH=\"$SCRIPT_DIR:\$PATH\"' >> ~/.bashrc && source ~/.bashrc"
fi
