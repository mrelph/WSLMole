#!/usr/bin/env bash
# WSLMole - ShellCheck Linter
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Running ShellCheck on WSLMole..."
echo "================================"
echo ""

if ! command -v shellcheck &>/dev/null; then
    echo "Error: shellcheck is not installed"
    echo ""
    echo "Install with:"
    echo "  Ubuntu/Debian: sudo apt install shellcheck"
    echo "  macOS: brew install shellcheck"
    exit 1
fi

FAILED=0

# Check main script
echo "Checking wslmole..."
if shellcheck "$SCRIPT_DIR/wslmole"; then
    echo "✓ wslmole passed"
else
    echo "✗ wslmole failed"
    FAILED=$((FAILED + 1))
fi
echo ""

# Check all library modules
for lib in "$SCRIPT_DIR"/lib/*.sh; do
    lib_name=$(basename "$lib")
    echo "Checking $lib_name..."
    if shellcheck "$lib"; then
        echo "✓ $lib_name passed"
    else
        echo "✗ $lib_name failed"
        FAILED=$((FAILED + 1))
    fi
    echo ""
done

# Check install script
echo "Checking install.sh..."
if shellcheck "$SCRIPT_DIR/install.sh"; then
    echo "✓ install.sh passed"
else
    echo "✗ install.sh failed"
    FAILED=$((FAILED + 1))
fi
echo ""

echo "================================"
if [[ $FAILED -eq 0 ]]; then
    echo "✓ All files passed ShellCheck!"
    exit 0
else
    echo "✗ $FAILED file(s) failed ShellCheck"
    exit 1
fi
