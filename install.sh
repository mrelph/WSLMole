#!/usr/bin/env bash
# WSLMole installer — symlinks `wslmole` into your PATH
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
SOURCE="$SCRIPT_DIR/wslmole"
TARGET="/usr/local/bin/wslmole"

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
    echo "Run 'wslmole' to get started."
else
    echo "Could not write to /usr/local/bin (no write access)."
    echo ""
    echo "Option 1 — install with sudo:"
    echo "  sudo ln -sf \"$SOURCE\" \"$TARGET\""
    echo ""
    echo "Option 2 — add the project directory to your PATH:"
    echo "  echo 'export PATH=\"$SCRIPT_DIR:\$PATH\"' >> ~/.bashrc && source ~/.bashrc"
fi
