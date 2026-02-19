#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/lib/common.sh"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

TEST_DIR="/tmp/wslmole_test_config_$$"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR"

pass() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_PASSED=$((TESTS_PASSED + 1)); echo "✓ $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "✗ $1"; }

echo "Running WSLMole Config Tests"
echo "============================="
echo ""

# Test 1: No config file doesn't error
WSLMOLE_CONFIG_FILE="$TEST_DIR/nonexistent"
load_config 2>/dev/null && pass "load_config with no file" || fail "load_config with no file"

# Test 2: Config sets DRY_RUN
WSLMOLE_CONFIG_FILE="$TEST_DIR/config1"
echo 'DRY_RUN=true' > "$WSLMOLE_CONFIG_FILE"
DRY_RUN=false
load_config
[[ "$DRY_RUN" == "true" ]] && pass "config sets DRY_RUN" || fail "config sets DRY_RUN"
DRY_RUN=false

# Test 3: Config adds protected paths
WSLMOLE_CONFIG_FILE="$TEST_DIR/config2"
echo 'WSLMOLE_PROTECTED_PATHS_EXTRA=("/my/custom/path")' > "$WSLMOLE_CONFIG_FILE"
load_config
found=false
for p in "${PROTECTED_PATHS[@]}"; do
    [[ "$p" == "/my/custom/path" ]] && found=true
done
[[ "$found" == "true" ]] && pass "config adds protected paths" || fail "config adds protected paths"

# Test 4: Config sets log level
WSLMOLE_CONFIG_FILE="$TEST_DIR/config3"
echo 'WSLMOLE_LOG_LEVEL=DEBUG' > "$WSLMOLE_CONFIG_FILE"
WSLMOLE_LOG_LEVEL=INFO
load_config
[[ "$WSLMOLE_LOG_LEVEL" == "DEBUG" ]] && pass "config sets log level" || fail "config sets log level"

# Test 5: Unknown config key doesn't crash
WSLMOLE_CONFIG_FILE="$TEST_DIR/config_bad"
echo 'UNKNOWN_KEY=bad' > "$WSLMOLE_CONFIG_FILE"
load_config 2>/dev/null && pass "unknown config key doesn't crash" || fail "unknown config key doesn't crash"

echo ""
echo "============================="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""
if [[ $TESTS_FAILED -eq 0 ]]; then echo "✓ All config tests passed!"; exit 0; else echo "✗ Some config tests failed"; exit 1; fi
