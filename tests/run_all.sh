#!/usr/bin/env bash
# WSLMole Test Runner - Run all tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔════════════════════════════════════════╗"
echo "║     WSLMole Test Suite Runner          ║"
echo "╚════════════════════════════════════════╝"
echo ""

SUITES_PASSED=0
SUITES_FAILED=0
TOTAL_TESTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0

run_test_suite() {
    local test_file="$1"
    local test_name
    test_name=$(basename "$test_file" .sh)

    echo "Running $test_name..."
    echo "----------------------------------------"

    local output
    if output=$(bash "$test_file" 2>&1); then
        echo "$output"
        SUITES_PASSED=$((SUITES_PASSED + 1))
    else
        echo "$output"
        SUITES_FAILED=$((SUITES_FAILED + 1))
    fi

    # Parse individual test counts from suite output
    local suite_run suite_passed suite_failed
    suite_run=$(echo "$output" | grep -oP 'Tests run: \K[0-9]+' || echo 0)
    suite_passed=$(echo "$output" | grep -oP 'Passed: \K[0-9]+' || echo 0)
    suite_failed=$(echo "$output" | grep -oP 'Failed: \K[0-9]+' || echo 0)
    TOTAL_TESTS=$((TOTAL_TESTS + suite_run))
    TOTAL_PASSED=$((TOTAL_PASSED + suite_passed))
    TOTAL_FAILED=$((TOTAL_FAILED + suite_failed))
    echo ""
}

# Run all test files
for test_file in "$SCRIPT_DIR"/test_*.sh; do
    if [[ -f "$test_file" ]]; then
        run_test_suite "$test_file"
    fi
done

echo "========================================"
echo "Summary"
echo "========================================"
echo "Suites: $((SUITES_PASSED + SUITES_FAILED)) total, $SUITES_PASSED passed, $SUITES_FAILED failed"
echo "Tests:  $TOTAL_TESTS total, $TOTAL_PASSED passed, $TOTAL_FAILED failed"
echo ""

if [[ $SUITES_FAILED -eq 0 ]]; then
    echo "✓ All test suites passed!"
    exit 0
else
    echo "✗ $SUITES_FAILED test suite(s) failed"
    exit 1
fi
