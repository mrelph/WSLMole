#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WSLMOLE="$PROJECT_ROOT/wslmole"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

pass() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_PASSED=$((TESTS_PASSED + 1)); echo "✓ $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "✗ $1"; }

echo "Running WSLMole Update Tests"
echo "============================="
echo ""

# Source modules for unit tests
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/update.sh"

# Test 1: update --help exits 0
if "$WSLMOLE" update --help >/dev/null 2>&1; then
    pass "update --help exits 0"
else
    fail "update --help exits 0"
fi

# Test 2: help update exits 0
if "$WSLMOLE" help update >/dev/null 2>&1; then
    pass "help update exits 0"
else
    fail "help update exits 0"
fi

# Test 3: _version_gt compares correctly
if _version_gt "1.1.0" "1.0.0"; then
    pass "_version_gt: 1.1.0 > 1.0.0"
else
    fail "_version_gt: 1.1.0 > 1.0.0"
fi

if _version_gt "2.0.0" "1.9.9"; then
    pass "_version_gt: 2.0.0 > 1.9.9"
else
    fail "_version_gt: 2.0.0 > 1.9.9"
fi

if _version_gt "1.0.0" "1.0.0"; then
    fail "_version_gt: 1.0.0 should not be > 1.0.0"
else
    pass "_version_gt: 1.0.0 == 1.0.0 (not greater)"
fi

if _version_gt "1.0.0" "1.0.1"; then
    fail "_version_gt: 1.0.0 should not be > 1.0.1"
else
    pass "_version_gt: 1.0.0 < 1.0.1"
fi

if _version_gt "1.0.10" "1.0.9"; then
    pass "_version_gt: 1.0.10 > 1.0.9"
else
    fail "_version_gt: 1.0.10 > 1.0.9"
fi

# Test 4: _validate_tag accepts valid semver tags
if _validate_tag "v1.0.0"; then
    pass "_validate_tag: accepts v1.0.0"
else
    fail "_validate_tag: should accept v1.0.0"
fi

if _validate_tag "v12.34.56"; then
    pass "_validate_tag: accepts v12.34.56"
else
    fail "_validate_tag: should accept v12.34.56"
fi

if _validate_tag "v1.0.0-beta"; then
    fail "_validate_tag: should reject v1.0.0-beta"
else
    pass "_validate_tag: rejects v1.0.0-beta"
fi

if _validate_tag "v1.0"; then
    fail "_validate_tag: should reject v1.0"
else
    pass "_validate_tag: rejects v1.0 (incomplete)"
fi

if _validate_tag 'v1.0.0$(evil)'; then
    fail "_validate_tag: should reject injection attempt"
else
    pass "_validate_tag: rejects injection attempt"
fi

# Test 5: _is_git_repo detects the project repo
SCRIPT_DIR="$PROJECT_ROOT"
if _is_git_repo "$PROJECT_ROOT"; then
    pass "_is_git_repo detects project repo"
else
    fail "_is_git_repo detects project repo"
fi

# Test 5: _is_git_repo rejects non-repo
if _is_git_repo "/tmp"; then
    fail "_is_git_repo should reject /tmp"
else
    pass "_is_git_repo rejects /tmp"
fi

# Test 6: update --check runs without crashing
exit_code=0
"$WSLMOLE" update --check >/dev/null 2>&1 || exit_code=$?
if [[ $exit_code -le 1 ]]; then
    pass "update --check exits cleanly (code $exit_code)"
else
    fail "update --check crashed (exit code $exit_code)"
fi

echo ""
echo "============================="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""
if [[ $TESTS_FAILED -eq 0 ]]; then echo "✓ All update tests passed!"; exit 0; else echo "✗ Some update tests failed"; exit 1; fi
