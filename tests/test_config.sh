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

# Test 3: Config rejects unsafe values
WSLMOLE_CONFIG_FILE="$TEST_DIR/config2"
echo 'DRY_RUN=$(rm -rf /)' > "$WSLMOLE_CONFIG_FILE"
DRY_RUN=true
load_config 2>/dev/null
[[ "$DRY_RUN" == "true" ]] && pass "config rejects unsafe values" || fail "config rejects unsafe values"

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

# Test 6: Unknown config key warns on stderr (visible to the user)
WSLMOLE_CONFIG_FILE="$TEST_DIR/config_warn"
echo 'DRYRUN=true' > "$WSLMOLE_CONFIG_FILE"   # typo of DRY_RUN
warn_out=$(load_config 2>&1 >/dev/null)
[[ "$warn_out" == *"Unknown config key 'DRYRUN'"* ]] \
    && pass "unknown key warns on stderr" || fail "unknown key warns on stderr"

# Test 7: Warnings go to stderr, not stdout (keeps JSON/scripts clean)
WSLMOLE_CONFIG_FILE="$TEST_DIR/config_warn2"
echo 'UNKNOWN_KEY=bad' > "$WSLMOLE_CONFIG_FILE"
stdout_out=$(load_config 2>/dev/null)
[[ -z "$stdout_out" ]] && pass "warnings stay off stdout" || fail "warnings stay off stdout"

echo ""
echo "============================="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""
if [[ $TESTS_FAILED -eq 0 ]]; then echo "✓ All config tests passed!"; exit 0; else echo "✗ Some config tests failed"; exit 1; fi
