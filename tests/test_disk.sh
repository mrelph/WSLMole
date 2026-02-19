#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/lib/common.sh"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

TEST_DIR="/tmp/wslmole_test_disk_$$"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR"

pass() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "✓ $1"
}

fail() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "✗ $1"
    echo "  Expected: $2"
    echo "  Got: $3"
}

echo "Running WSLMole Disk Tests"
echo "=========================="
echo ""

# format_size tests
result=$(format_size 0)
[[ "$result" == "0 B" ]] && pass "format_size: 0 bytes" || fail "format_size: 0 bytes" "0 B" "$result"

result=$(format_size 1)
[[ "$result" == "1 B" ]] && pass "format_size: 1 byte" || fail "format_size: 1 byte" "1 B" "$result"

result=$(format_size 1023)
[[ "$result" == "1023 B" ]] && pass "format_size: 1023 bytes" || fail "format_size: 1023 bytes" "1023 B" "$result"

result=$(format_size 1024)
[[ "$result" == "1.0 KB" ]] && pass "format_size: 1024 bytes = 1.0 KB" || fail "format_size: 1024" "1.0 KB" "$result"

result=$(format_size 1048576)
[[ "$result" == "1.0 MB" ]] && pass "format_size: 1MB boundary" || fail "format_size: 1MB" "1.0 MB" "$result"

result=$(format_size 1073741824)
[[ "$result" == "1.0 GB" ]] && pass "format_size: 1GB boundary" || fail "format_size: 1GB" "1.0 GB" "$result"

result=$(format_size 5368709120)
[[ "$result" == "5.0 GB" ]] && pass "format_size: 5GB" || fail "format_size: 5GB" "5.0 GB" "$result"

# get_size_bytes tests
echo -n "hello" > "$TEST_DIR/testfile"
result=$(get_size_bytes "$TEST_DIR/testfile")
[[ "$result" == "5" ]] && pass "get_size_bytes: 5-byte file" || fail "get_size_bytes: file" "5" "$result"

result=$(get_size_bytes "$TEST_DIR/nonexistent")
[[ "$result" == "0" ]] && pass "get_size_bytes: nonexistent returns 0" || fail "get_size_bytes: nonexistent" "0" "$result"

result=$(get_size_bytes "$TEST_DIR")
[[ "$result" -ge 0 ]] && pass "get_size_bytes: directory returns >= 0" || fail "get_size_bytes: dir" ">= 0" "$result"

echo ""
echo "=========================="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All disk tests passed!"
    exit 0
else
    echo "✗ Some disk tests failed"
    exit 1
fi
