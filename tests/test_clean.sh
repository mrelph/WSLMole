#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/clean.sh"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

TEST_DIR="/tmp/wslmole_test_clean_$$"
trap 'rm -rf "$TEST_DIR"' EXIT

pass() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "✓ $1"
}

fail() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "✗ $1"
}

echo "Running WSLMole Cleanup Tests"
echo "=============================="
echo ""

# Setup mock directories
mkdir -p "$TEST_DIR/cache" "$TEST_DIR/logs" "$TEST_DIR/tmp"
echo "cached data" > "$TEST_DIR/cache/pkg1.deb"
echo "cached data" > "$TEST_DIR/cache/pkg2.deb"
echo "old log" > "$TEST_DIR/logs/syslog.1"
echo "old log" > "$TEST_DIR/logs/kern.log.gz"
echo "temp" > "$TEST_DIR/tmp/tempfile"

# Test 1: DRY_RUN preserves files
export DRY_RUN=true
safe_delete "$TEST_DIR/cache/pkg1.deb" "test pkg" >/dev/null 2>&1
if [[ -f "$TEST_DIR/cache/pkg1.deb" ]]; then
    pass "dry run preserves cache file"
else
    fail "dry run deleted cache file"
fi

# Test 2: DRY_RUN preserves log files
safe_delete "$TEST_DIR/logs/syslog.1" "test log" >/dev/null 2>&1
if [[ -f "$TEST_DIR/logs/syslog.1" ]]; then
    pass "dry run preserves log file"
else
    fail "dry run deleted log file"
fi

# Test 3: Actual deletion works
export DRY_RUN=false
safe_delete "$TEST_DIR/tmp/tempfile" "test temp" >/dev/null 2>&1
if [[ ! -f "$TEST_DIR/tmp/tempfile" ]]; then
    pass "actual deletion removes temp file"
else
    fail "actual deletion failed for temp file"
fi

# Test 4: Deletion of directory contents
echo "more data" > "$TEST_DIR/cache/pkg3.deb"
safe_delete "$TEST_DIR/cache" "test cache dir" >/dev/null 2>&1
if [[ ! -d "$TEST_DIR/cache" ]]; then
    pass "directory deletion works"
else
    fail "directory deletion failed"
fi

# Test 5: Nonexistent file returns success (0)
if safe_delete "$TEST_DIR/nonexistent" "test" >/dev/null 2>&1; then
    pass "nonexistent file returns success"
else
    fail "nonexistent file should return success"
fi

# Test 6: Category dispatcher handles unknown category
if output=$(cmd_clean_category "invalid_category" 2>&1); then
    fail "dispatcher should return non-zero for unknown category"
elif echo "$output" | grep -q "Unknown cleanup category"; then
    pass "dispatcher rejects unknown category"
else
    fail "dispatcher should reject unknown category"
fi

echo ""
echo "=============================="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All cleanup tests passed!"
    exit 0
else
    echo "✗ Some cleanup tests failed"
    exit 1
fi
