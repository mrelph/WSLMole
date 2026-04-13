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

# Test 12: plan --help exits 0
if "$WSLMOLE" plan --help >/dev/null 2>&1; then
    pass "plan --help exits 0"
else
    fail "plan --help exits 0"
fi

# Test 13: scan --help exits 0
if "$WSLMOLE" scan --help >/dev/null 2>&1; then
    pass "scan --help exits 0"
else
    fail "scan --help exits 0"
fi

# Test 14: help output mentions fix command
output=$("$WSLMOLE" --help 2>&1)
if echo "$output" | grep -q "fix"; then
    pass "--help mentions fix command"
else
    fail "--help mentions fix command"
fi

# Test 15: help output mentions plan command
if echo "$output" | grep -q "plan"; then
    pass "--help mentions plan command"
else
    fail "--help mentions plan command"
fi

# Test 16: help output mentions scan command
if echo "$output" | grep -q "scan"; then
    pass "--help mentions scan command"
else
    fail "--help mentions scan command"
fi

# Test 17: help output mentions interactive flag
if echo "$output" | grep -q "\-i"; then
    pass "--help mentions -i flag"
else
    fail "--help mentions -i flag"
fi

# Test 18: scan command exits 0
if "$WSLMOLE" scan >/dev/null 2>&1; then
    pass "scan command exits 0"
else
    fail "scan command exits 0"
fi

# Test 19: scan command works in JSON mode
scan_json=$("$WSLMOLE" --format json scan 2>/dev/null)
if command -v python3 >/dev/null 2>&1; then
    if printf '%s\n' "$scan_json" | python3 -m json.tool >/dev/null 2>&1; then
        pass "scan JSON stdout is parseable"
    else
        fail "scan JSON stdout is parseable"
    fi
elif [[ "$scan_json" == \{* ]]; then
    pass "scan JSON stdout starts with JSON"
else
    fail "scan JSON stdout starts with JSON"
fi

# Test 20: positional clean category works
if "$WSLMOLE" clean apt --dry-run >/dev/null 2>&1; then
    pass "clean positional category works"
else
    fail "clean positional category works"
fi

# Test 21: positional disk mode works
if "$WSLMOLE" disk large /tmp -n 1 >/dev/null 2>&1; then
    pass "disk positional mode works"
else
    fail "disk positional mode works"
fi

# Test 22: positional dev artifact type works
if "$WSLMOLE" dev node /tmp --dry-run >/dev/null 2>&1; then
    pass "dev positional type works"
else
    fail "dev positional type works"
fi

# Test 23: JSON mode emits parseable stdout for subcommands
json_output=$("$WSLMOLE" --format json dev /tmp --dry-run 2>/dev/null)
if command -v python3 >/dev/null 2>&1; then
    if printf '%s\n' "$json_output" | python3 -m json.tool >/dev/null 2>&1; then
        pass "--format json subcommand stdout is parseable"
    else
        fail "--format json subcommand stdout is parseable"
    fi
elif [[ "$json_output" == \{* ]]; then
    pass "--format json subcommand stdout starts with JSON"
else
    fail "--format json subcommand stdout starts with JSON"
fi

# Test 24: plan command works in JSON mode
plan_json=$("$WSLMOLE" --format json plan 2>/dev/null)
if command -v python3 >/dev/null 2>&1; then
    if printf '%s\n' "$plan_json" | python3 -m json.tool >/dev/null 2>&1; then
        pass "plan JSON stdout is parseable"
    else
        fail "plan JSON stdout is parseable"
    fi
elif [[ "$plan_json" == \{* ]]; then
    pass "plan JSON stdout starts with JSON"
else
    fail "plan JSON stdout starts with JSON"
fi

# Test 25: plan filters work
if "$WSLMOLE" plan --risk low >/dev/null 2>&1 && "$WSLMOLE" plan --auto >/dev/null 2>&1 && "$WSLMOLE" plan --category logs >/dev/null 2>&1; then
    pass "plan filters exit 0"
else
    fail "plan filters exit 0"
fi

# Test 26: invalid plan risk exits non-zero
if "$WSLMOLE" plan --risk banana >/dev/null 2>&1; then
    fail "invalid plan risk should exit non-zero"
else
    pass "invalid plan risk exits non-zero"
fi

# Test 27: fix dry-run exits 0
if "$WSLMOLE" fix --dry-run >/dev/null 2>&1; then
    pass "fix --dry-run exits 0"
else
    fail "fix --dry-run exits 0"
fi

# Test 28: fix --only dry-run exits 0
if "$WSLMOLE" fix --dry-run --only logs,tmp >/dev/null 2>&1; then
    pass "fix --only dry-run exits 0"
else
    fail "fix --only dry-run exits 0"
fi

# Test 29: fix dry-run works in JSON mode
fix_json=$("$WSLMOLE" --format json fix --dry-run 2>/dev/null)
if command -v python3 >/dev/null 2>&1; then
    if printf '%s\n' "$fix_json" | python3 -m json.tool >/dev/null 2>&1; then
        pass "fix JSON stdout is parseable"
    else
        fail "fix JSON stdout is parseable"
    fi
elif [[ "$fix_json" == \{* ]]; then
    pass "fix JSON stdout starts with JSON"
else
    fail "fix JSON stdout starts with JSON"
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
