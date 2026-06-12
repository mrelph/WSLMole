#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/menu.sh"

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

echo "Running WSLMole Menu Tests"
echo "=========================="
echo ""

# Stub out the real cleanup and record the DRY_RUN value of each call
CALL_LOG=""
cmd_clean_category() {
    CALL_LOG="${CALL_LOG}${DRY_RUN},"
}
cmd_dev_scan() {
    CALL_LOG="${CALL_LOG}${DRY_RUN},"
}
press_enter() { :; }
print_header() { :; }

# Test 1: _menu_clean_confirm previews in dry-run, then executes for real on "y"
DRY_RUN=true
CALL_LOG=""
_menu_clean_confirm "apt" <<< "y" >/dev/null 2>&1
if [[ "$CALL_LOG" == "true,false," ]]; then
    pass "confirmed cleanup runs with DRY_RUN=false after preview"
else
    fail "confirmed cleanup runs with DRY_RUN=false after preview (got: $CALL_LOG)"
fi

# Test 2: _menu_clean_confirm restores global DRY_RUN afterwards
if [[ "$DRY_RUN" == "true" ]]; then
    pass "global DRY_RUN restored after confirmed cleanup"
else
    fail "global DRY_RUN restored after confirmed cleanup (got: $DRY_RUN)"
fi

# Test 3: declining the confirmation never runs a non-dry-run cleanup
DRY_RUN=true
CALL_LOG=""
_menu_clean_confirm "apt" <<< "n" >/dev/null 2>&1
if [[ "$CALL_LOG" == "true," ]]; then
    pass "declined cleanup only runs the dry-run preview"
else
    fail "declined cleanup only runs the dry-run preview (got: $CALL_LOG)"
fi

# Test 4: menu_dev confirmed cleanup runs with DRY_RUN=false
DRY_RUN=true
CALL_LOG=""
menu_dev >/dev/null 2>&1 <<EOF

y
EOF
if [[ "$CALL_LOG" == "true,false," ]]; then
    pass "menu_dev confirmed cleanup runs with DRY_RUN=false"
else
    fail "menu_dev confirmed cleanup runs with DRY_RUN=false (got: $CALL_LOG)"
fi

# Test 5: main menu exits cleanly on "0"
DRY_RUN=true
if run_interactive_menu >/dev/null 2>&1 <<< "0"; then
    pass "interactive menu exits on 0"
else
    fail "interactive menu exits on 0"
fi

echo ""
echo "=========================="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All menu tests passed!"
    exit 0
else
    echo "✗ Some menu tests failed"
    exit 1
fi
