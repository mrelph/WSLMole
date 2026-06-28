#!/usr/bin/env bash
# WSLMole Test Suite - Safety Tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the module to test
source "$PROJECT_ROOT/lib/common.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

echo "Running WSLMole Safety Tests"
echo "============================="
echo ""

# These tests deliberately call safe_delete with DRY_RUN=false against real
# system paths to prove the guard blocks them. Never run them as root: a
# guard regression must not be able to delete anything that matters.
if [[ $EUID -eq 0 ]]; then
    echo "✗ Refusing to run safety tests as root"
    exit 1
fi

# Test 1: Protected paths cannot be deleted
echo "Test 1: Protected paths are blocked"
TESTS_RUN=$((TESTS_RUN + 1))
export DRY_RUN=false
if safe_delete "/bin" "test" 2>/dev/null; then
    echo "✗ CRITICAL: /bin was not blocked!"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    echo "✓ /bin is protected"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Test 2: Root path cannot be deleted
echo "Test 2: Root path is blocked"
TESTS_RUN=$((TESTS_RUN + 1))
if safe_delete "/" "test" 2>/dev/null; then
    echo "✗ CRITICAL: / was not blocked!"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    echo "✓ / is protected"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Test 3: Relative paths are blocked
echo "Test 3: Relative paths are blocked"
TESTS_RUN=$((TESTS_RUN + 1))
if safe_delete "relative/path" "test" 2>/dev/null; then
    echo "✗ CRITICAL: relative path was not blocked!"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    echo "✓ Relative paths are blocked"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Test 4: Path traversal is blocked
echo "Test 4: Path traversal is blocked"
TESTS_RUN=$((TESTS_RUN + 1))
if safe_delete "/tmp/../etc/passwd" "test" 2>/dev/null; then
    echo "✗ CRITICAL: path traversal was not blocked!"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    echo "✓ Path traversal is blocked"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Test 5: Dry run doesn't delete
echo "Test 5: Dry run mode works"
TESTS_RUN=$((TESTS_RUN + 1))
TEST_FILE="/tmp/wslmole_test_$$"
touch "$TEST_FILE"
export DRY_RUN=true
safe_delete "$TEST_FILE" "test" >/dev/null 2>&1
if [[ -f "$TEST_FILE" ]]; then
    echo "✓ Dry run preserved file"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    rm -f "$TEST_FILE"
else
    echo "✗ Dry run deleted file!"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 6: Actual deletion works for safe paths
echo "Test 6: Safe paths can be deleted"
TESTS_RUN=$((TESTS_RUN + 1))
TEST_FILE="/tmp/wslmole_test_$$"
touch "$TEST_FILE"
export DRY_RUN=false
safe_delete "$TEST_FILE" "test" >/dev/null 2>&1
if [[ ! -f "$TEST_FILE" ]]; then
    echo "✓ Safe file was deleted"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "✗ Safe file was not deleted"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    rm -f "$TEST_FILE"
fi

# Test 7: Children of protected system trees are blocked (prefix protection)
echo "Test 7: Children of protected system trees are blocked"
for sys_child in "/usr/local/bin" "/etc/passwd" "/usr/bin/env" "/boot/grub"; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if safe_delete "$sys_child" "test" 2>/dev/null; then
        echo "✗ CRITICAL: $sys_child was not blocked!"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        echo "✓ $sys_child is protected"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
done

# Test 8: Children of /tmp and /var/log remain deletable (no over-blocking)
echo "Test 8: /tmp children are still deletable"
TESTS_RUN=$((TESTS_RUN + 1))
TEST_FILE="/tmp/wslmole_test_prefix_$$"
touch "$TEST_FILE"
export DRY_RUN=false
safe_delete "$TEST_FILE" "test" >/dev/null 2>&1
if [[ ! -f "$TEST_FILE" ]]; then
    echo "✓ /tmp child deleted (prefix rules do not over-block)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "✗ /tmp child was over-blocked"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    rm -f "$TEST_FILE"
fi

# Test 9: Real path traversal is still blocked
echo "Test 9: Path traversal components are blocked"
for trav in "/tmp/../etc" "/var/log/.." "/home/user/../../etc/passwd"; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if safe_delete "$trav" "test" 2>/dev/null; then
        echo "✗ CRITICAL: $trav was not blocked!"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        echo "✓ $trav is blocked"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
done

# Test 10: Legitimate filenames containing ".." are NOT over-blocked
echo "Test 10: Filenames with embedded dots are deletable"
export DRY_RUN=false
for name in "wslmole_foo..bar" "wslmole_..hidden" "wslmole_trailing.."; do
    TESTS_RUN=$((TESTS_RUN + 1))
    TEST_FILE="/tmp/${name}_$$"
    touch "$TEST_FILE"
    safe_delete "$TEST_FILE" "test" >/dev/null 2>&1
    if [[ ! -f "$TEST_FILE" ]]; then
        echo "✓ '$name' deleted (not over-blocked)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "✗ '$name' was over-blocked as traversal"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        rm -f "$TEST_FILE"
    fi
done

echo ""
echo "============================="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All safety tests passed!"
    exit 0
else
    echo "✗ CRITICAL: Some safety tests failed!"
    exit 1
fi
