#!/usr/bin/env bash
# WSLMole Test Suite - Common Utilities Tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the module to test
source "$PROJECT_ROOT/lib/common.sh"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helpers
assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$expected" == "$actual" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "✓ $test_name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "✗ $test_name"
        echo "  Expected: $expected"
        echo "  Got: $actual"
    fi
}

record_pass() {
    local test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "✓ $test_name"
}

record_fail() {
    local test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "✗ $test_name"
}

# Tests
test_format_size() {
    local result
    result=$(format_size 500)
    assert_equals "500 B" "$result" "format_size: bytes"
    
    result=$(format_size 2048)
    assert_equals "2.0 KB" "$result" "format_size: kilobytes"
    
    result=$(format_size 2097152)
    assert_equals "2.0 MB" "$result" "format_size: megabytes"
    
    result=$(format_size 2147483648)
    assert_equals "2.0 GB" "$result" "format_size: gigabytes"

    local size_test_file="/tmp/wslmole_common_size_$$"
    printf 'x' > "$size_test_file"
    result=$(get_size_bytes "$size_test_file")
    rm -f "$size_test_file"
    if [[ "$result" =~ ^[0-9]+$ ]]; then
        record_pass "get_size_bytes: emits one numeric value"
    else
        record_fail "get_size_bytes: should emit one numeric value"
    fi
}

test_is_protected_path() {
    if is_protected_path "/bin"; then
        record_pass "is_protected_path: /bin is protected"
    else
        record_fail "is_protected_path: /bin should be protected"
    fi

    local resolved_bin
    resolved_bin=$(realpath /bin 2>/dev/null || echo /bin)
    if is_protected_path "$resolved_bin"; then
        record_pass "is_protected_path: resolved /bin is protected"
    else
        record_fail "is_protected_path: resolved /bin should be protected"
    fi
    
    if is_protected_path "/tmp/test"; then
        record_fail "is_protected_path: /tmp/test should not be protected"
    else
        record_pass "is_protected_path: /tmp/test is not protected"
    fi
    
    if is_protected_path "/"; then
        record_pass "is_protected_path: / is protected"
    else
        record_fail "is_protected_path: / should be protected"
    fi
}

test_validate_path() {
    # Test suspicious patterns
    if validate_path "../../etc/passwd" 2>/dev/null; then
        record_fail "validate_path: should reject ../.."
    else
        record_pass "validate_path: rejects ../.."
    fi
    
    # Test root path
    if validate_path "/" 2>/dev/null; then
        record_fail "validate_path: should reject /"
    else
        record_pass "validate_path: rejects /"
    fi
    
    # Test protected path
    if validate_path "/bin" 2>/dev/null; then
        record_fail "validate_path: should reject /bin"
    else
        record_pass "validate_path: rejects /bin"
    fi
}

test_safe_delete() {
    # Test protected path blocking
    DRY_RUN=false
    if safe_delete "/bin" 2>/dev/null; then
        record_fail "safe_delete: should block /bin"
    else
        record_pass "safe_delete: blocks /bin"
    fi
    
    # Test relative path blocking
    if safe_delete "relative/path" 2>/dev/null; then
        record_fail "safe_delete: should block relative paths"
    else
        record_pass "safe_delete: blocks relative paths"
    fi
    
    # Test suspicious pattern blocking
    if safe_delete "/tmp/../etc/passwd" 2>/dev/null; then
        record_fail "safe_delete: should block .. patterns"
    else
        record_pass "safe_delete: blocks .. patterns"
    fi
}

test_json_helpers() {
    local value=$'quote" slash\\ tab\t newline\n return\r'
    local escaped
    escaped=$(json_escape "$value")
    assert_equals 'quote\" slash\\ tab\t newline\n return\r' "$escaped" "json_escape: escapes JSON control characters"

    local quoted
    quoted=$(json_quote "$value")
    if [[ "$quoted" == '"quote\" slash\\ tab\t newline\n return\r"' ]]; then
        record_pass "json_quote: wraps escaped content"
    else
        record_fail "json_quote: wraps escaped content"
    fi
}

test_integer_validation() {
    if validate_integer_option 10 "--test" 1 20 >/dev/null 2>&1; then
        record_pass "validate_integer_option: accepts in-range integer"
    else
        record_fail "validate_integer_option: accepts in-range integer"
    fi

    if validate_integer_option nope "--test" 1 20 >/dev/null 2>&1; then
        record_fail "validate_integer_option: rejects non-integer"
    else
        record_pass "validate_integer_option: rejects non-integer"
    fi

    if validate_integer_option 21 "--test" 1 20 >/dev/null 2>&1; then
        record_fail "validate_integer_option: rejects out-of-range integer"
    else
        record_pass "validate_integer_option: rejects out-of-range integer"
    fi
}

test_probe_timeout() {
    local started elapsed rc=0
    started=$(date +%s)
    run_probe 1 bash -c 'sleep 5' >/dev/null 2>&1 || rc=$?
    elapsed=$(( $(date +%s) - started ))
    if [[ $rc -eq 124 && $elapsed -lt 4 ]]; then
        record_pass "run_probe: terminates a hanging command"
    else
        record_fail "run_probe: terminates a hanging command"
    fi
}

test_collectors() {
    local old_dir="$TEST_DIR/old"
    local snap_dir="$TEST_DIR/snaps"
    mkdir -p "$old_dir" "$snap_dir"
    printf 'old-data' > "$old_dir/old file"
    printf 'new' > "$old_dir/new-file"
    touch -d '10 days ago' "$old_dir/old file"

    local total
    total=$(sum_files_older_than "$old_dir" 7)
    assert_equals "8" "$total" "sum_files_older_than: counts only eligible files"

    mkdir -p "$TEST_DIR/logs"
    printf '12345' > "$TEST_DIR/logs/app.log.1"
    printf '123' > "$TEST_DIR/logs/current.log"
    total=$(sum_rotated_log_bytes "$TEST_DIR/logs")
    assert_equals "5" "$total" "sum_rotated_log_bytes: matches cleanup patterns"

    printf 'snapdata' > "$snap_dir/demo_42.snap"
    local snap_output stats
    snap_output=$'Name Version Rev Tracking Publisher Notes\ndemo 1.0 42 latest/test publisher disabled\nactive 1.0 7 latest/test publisher -'
    stats=$(snap_disabled_stats "$snap_output" "$snap_dir")
    assert_equals "1 8" "$stats" "snap_disabled_stats: returns exact revision bytes"
}

# Run all tests
echo "Running WSLMole Common Utilities Tests"
echo "======================================="
echo ""

test_format_size
test_is_protected_path
test_validate_path
test_safe_delete
test_json_helpers
test_integer_validation
test_probe_timeout
test_collectors

echo ""
echo "======================================="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
