#!/usr/bin/env bash
# WSLMole Test Runner - Run all tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔════════════════════════════════════════╗"
echo "║     WSLMole Test Suite Runner          ║"
echo "╚════════════════════════════════════════╝"
echo ""

TOTAL_PASSED=0
TOTAL_FAILED=0
SUITE_FAILURES=0

run_test_suite() {
    local test_file="$1"
    local test_name=$(basename "$test_file" .sh)
    
    echo "Running $test_name..."
    echo "----------------------------------------"
    
    if bash "$test_file"; then
        echo "✓ $test_name passed"
        TOTAL_PASSED=$((TOTAL_PASSED + 1))
    else
        echo "✗ $test_name failed"
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        SUITE_FAILURES=$((SUITE_FAILURES + 1))
    fi
    echo ""
}

# Run all test files
for test_file in "$SCRIPT_DIR"/test_*.sh; do
    if [[ -f "$test_file" ]]; then
        run_test_suite "$test_file"
    fi
done

echo "========================================"
echo "Test Suites Summary"
echo "========================================"
echo "Suites passed: $TOTAL_PASSED"
echo "Suites failed: $TOTAL_FAILED"
echo ""

if [[ $SUITE_FAILURES -eq 0 ]]; then
    echo "✓ All test suites passed!"
    exit 0
else
    echo "✗ $SUITE_FAILURES test suite(s) failed"
    exit 1
fi
