#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WSLMOLE="$PROJECT_ROOT/wslmole"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

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

echo "Running WSLMole CLI Tests"
echo "========================="
echo ""

# Test 1: --help exits 0
if "$WSLMOLE" --help >/dev/null 2>&1; then
    pass "--help exits 0"
else
    fail "--help exits 0"
fi

# Test 2: --version exits 0 and contains WSLMole
output=$("$WSLMOLE" --version 2>&1)
if [[ $? -eq 0 ]] && echo "$output" | grep -q "WSLMole"; then
    pass "--version exits 0 and contains WSLMole"
else
    fail "--version exits 0 and contains WSLMole"
fi

# Test 3: clean --help exits 0
if "$WSLMOLE" clean --help >/dev/null 2>&1; then
    pass "clean --help exits 0"
else
    fail "clean --help exits 0"
fi

# Test 4: disk --help exits 0
if "$WSLMOLE" disk --help >/dev/null 2>&1; then
    pass "disk --help exits 0"
else
    fail "disk --help exits 0"
fi

# Test 5: dev --help exits 0
if "$WSLMOLE" dev --help >/dev/null 2>&1; then
    pass "dev --help exits 0"
else
    fail "dev --help exits 0"
fi

# Test 6: diagnose --help exits 0
if "$WSLMOLE" diagnose --help >/dev/null 2>&1; then
    pass "diagnose --help exits 0"
else
    fail "diagnose --help exits 0"
fi

# Test 7: packages --help exits 0
if "$WSLMOLE" packages --help >/dev/null 2>&1; then
    pass "packages --help exits 0"
else
    fail "packages --help exits 0"
fi

# Test 8: invalid command exits non-zero
if "$WSLMOLE" invalidcommand >/dev/null 2>&1; then
    fail "invalid command should exit non-zero"
else
    pass "invalid command exits non-zero"
fi

# Test 9: --format json --version works
if "$WSLMOLE" --format json --version >/dev/null 2>&1; then
    pass "--format json --version works"
else
    fail "--format json --version works"
fi

# Test 10: --format invalid exits non-zero
if "$WSLMOLE" --format invalid --version >/dev/null 2>&1; then
    fail "--format invalid should exit non-zero"
else
    pass "--format invalid exits non-zero"
fi

# Test 11: fix --help exits 0
if "$WSLMOLE" fix --help >/dev/null 2>&1; then
    pass "fix --help exits 0"
else
    fail "fix --help exits 0"
fi

# Test 12: help output mentions fix command
output=$("$WSLMOLE" --help 2>&1)
if echo "$output" | grep -q "fix"; then
    pass "--help mentions fix command"
else
    fail "--help mentions fix command"
fi

# Test 13: help output mentions interactive flag
if echo "$output" | grep -q "\-i"; then
    pass "--help mentions -i flag"
else
    fail "--help mentions -i flag"
fi

echo ""
echo "========================="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All CLI tests passed!"
    exit 0
else
    echo "✗ Some CLI tests failed"
    exit 1
fi
