#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/lib/common.sh"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

TEST_DIR="/tmp/wslmole_test_log_$$"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR"

pass() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_PASSED=$((TESTS_PASSED + 1)); echo "✓ $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "✗ $1"; }

echo "Running WSLMole Logging Tests"
echo "=============================="
echo ""

# Setup
export WSLMOLE_LOG_DIR="$TEST_DIR"
export WSLMOLE_LOG_FILE="$TEST_DIR/test.log"
export VERBOSE=true
export WSLMOLE_LOG_LEVEL="INFO"

# Test 1: log_info writes when VERBOSE=true
log_info "test message"
if [[ -f "$WSLMOLE_LOG_FILE" ]] && grep -q "test message" "$WSLMOLE_LOG_FILE"; then
    pass "log_info writes to file"
else
    fail "log_info writes to file"
fi
rm -f "$WSLMOLE_LOG_FILE"

# Test 2: log_debug skipped at INFO level
log_debug "debug msg"
if [[ -f "$WSLMOLE_LOG_FILE" ]] && grep -q "debug msg" "$WSLMOLE_LOG_FILE"; then
    fail "log_debug should not write at INFO level"
else
    pass "log_debug skipped at INFO level"
fi
rm -f "$WSLMOLE_LOG_FILE"

# Test 3: log_debug writes at DEBUG level
WSLMOLE_LOG_LEVEL="DEBUG"
log_debug "debug visible"
if [[ -f "$WSLMOLE_LOG_FILE" ]] && grep -q "debug visible" "$WSLMOLE_LOG_FILE"; then
    pass "log_debug writes at DEBUG level"
else
    fail "log_debug writes at DEBUG level"
fi
rm -f "$WSLMOLE_LOG_FILE"
WSLMOLE_LOG_LEVEL="INFO"

# Test 4: log_error always writes
log_error "error msg"
if [[ -f "$WSLMOLE_LOG_FILE" ]] && grep -q "error msg" "$WSLMOLE_LOG_FILE"; then
    pass "log_error writes to file"
else
    fail "log_error writes to file"
fi
rm -f "$WSLMOLE_LOG_FILE"

# Test 5: Log rotation
dd if=/dev/zero of="$WSLMOLE_LOG_FILE" bs=1024 count=1100 2>/dev/null
init_logging
if [[ -f "${WSLMOLE_LOG_FILE}.1" ]]; then
    pass "log rotation creates .log.1"
else
    fail "log rotation creates .log.1"
fi

# Test 6: log() is alias for log_info
rm -f "$WSLMOLE_LOG_FILE"
log "alias test"
if [[ -f "$WSLMOLE_LOG_FILE" ]] && grep -q "\[INFO\]" "$WSLMOLE_LOG_FILE"; then
    pass "log() writes with INFO level"
else
    fail "log() writes with INFO level"
fi

echo ""
echo "=============================="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""
if [[ $TESTS_FAILED -eq 0 ]]; then echo "✓ All logging tests passed!"; exit 0; else echo "✗ Some logging tests failed"; exit 1; fi
