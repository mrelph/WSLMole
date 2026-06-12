#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/lib/common.sh"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

pass() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_PASSED=$((TESTS_PASSED + 1)); echo "✓ $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "✗ $1 (got: $2)"; }

echo "Running WSLMole JSON Tests"
echo "=========================="
echo ""

# Test 1: String values
result=$(to_json_kv "name" "test")
[[ "$result" == '{"name":"test"}' ]] && pass "string value" || fail "string value" "$result"

# Test 2: Numeric values
result=$(to_json_kv "score" "42")
[[ "$result" == '{"score":42}' ]] && pass "numeric value" || fail "numeric value" "$result"

# Test 3: Boolean values
result=$(to_json_kv "ok" "true")
[[ "$result" == '{"ok":true}' ]] && pass "boolean value" || fail "boolean value" "$result"

# Test 4: Mixed types
result=$(to_json_kv "name" "test" "score" "100" "active" "true")
[[ "$result" == '{"name":"test","score":100,"active":true}' ]] && pass "mixed types" || fail "mixed types" "$result"

# Test 5: Empty object
result=$(to_json_kv)
[[ "$result" == '{}' ]] && pass "empty object" || fail "empty object" "$result"

echo ""
echo "=========================="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""
if [[ $TESTS_FAILED -eq 0 ]]; then echo "✓ All JSON tests passed!"; exit 0; else echo "✗ Some JSON tests failed"; exit 1; fi
