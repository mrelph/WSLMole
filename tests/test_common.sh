#!/usr/bin/env bash
# WSLMole Test Suite - Common Utilities Tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the module to test
source "$PROJECT_ROOT/lib/common.sh"

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

assert_true() {
    local test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "✓ $test_name"
}

assert_false() {
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
        assert_true "get_size_bytes: emits one numeric value"
    else
        assert_false "get_size_bytes: should emit one numeric value"
    fi
}

test_is_protected_path() {
    if is_protected_path "/bin"; then
        assert_true "is_protected_path: /bin is protected"
    else
        assert_false "is_protected_path: /bin should be protected"
    fi

    local resolved_bin
    resolved_bin=$(realpath /bin 2>/dev/null || echo /bin)
    if is_protected_path "$resolved_bin"; then
        assert_true "is_protected_path: resolved /bin is protected"
    else
        assert_false "is_protected_path: resolved /bin should be protected"
    fi
    
    if is_protected_path "/tmp/test"; then
        assert_false "is_protected_path: /tmp/test should not be protected"
    else
        assert_true "is_protected_path: /tmp/test is not protected"
    fi
    
    if is_protected_path "/"; then
        assert_true "is_protected_path: / is protected"
    else
        assert_false "is_protected_path: / should be protected"
    fi
}

test_validate_path() {
    # Test suspicious patterns
    if validate_path "../../etc/passwd" 2>/dev/null; then
        assert_false "validate_path: should reject ../.."
    else
        assert_true "validate_path: rejects ../.."
    fi
    
    # Test root path
    if validate_path "/" 2>/dev/null; then
        assert_false "validate_path: should reject /"
    else
        assert_true "validate_path: rejects /"
    fi
    
    # Test protected path
    if validate_path "/bin" 2>/dev/null; then
        assert_false "validate_path: should reject /bin"
    else
        assert_true "validate_path: rejects /bin"
    fi
}

test_safe_delete() {
    # Test protected path blocking
    DRY_RUN=false
    if safe_delete "/bin" 2>/dev/null; then
        assert_false "safe_delete: should block /bin"
    else
        assert_true "safe_delete: blocks /bin"
    fi
    
    # Test relative path blocking
    if safe_delete "relative/path" 2>/dev/null; then
        assert_false "safe_delete: should block relative paths"
    else
        assert_true "safe_delete: blocks relative paths"
    fi
    
    # Test suspicious pattern blocking
    if safe_delete "/tmp/../etc/passwd" 2>/dev/null; then
        assert_false "safe_delete: should block .. patterns"
    else
        assert_true "safe_delete: blocks .. patterns"
    fi
}

# Run all tests
echo "Running WSLMole Common Utilities Tests"
echo "======================================="
echo ""

test_format_size
test_is_protected_path
test_validate_path
test_safe_delete

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
