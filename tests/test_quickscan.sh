#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/quickscan.sh"

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
    [[ $# -ge 3 ]] && { echo "  Expected: $2"; echo "  Got: $3"; }
}

echo "Running WSLMole QuickScan Tests"
echo "==============================="
echo ""

# Helper: run the pure scorer and report the resulting score.
# Args: mem% disk% failed has_wslconfig in_wsl upgradable
score() {
    _quickscan_compute_score "$1" "$2" "$3" "$4" "$5" "$6"
    echo "$QS_HEALTH_SCORE"
}

# ── Healthy baseline ──────────────────────────────────────────────
result=$(score 30 30 0 true true 0)
[[ "$result" == "100" ]] && pass "healthy system scores 100" \
    || fail "healthy system scores 100" "100" "$result"

_quickscan_compute_score 30 30 0 true true 0
[[ ${#QS_RECOMMENDATIONS[@]} -eq 0 ]] && pass "healthy system has no recommendations" \
    || fail "healthy system has no recommendations" "0" "${#QS_RECOMMENDATIONS[@]}"

# ── Memory thresholds ─────────────────────────────────────────────
result=$(score 65 30 0 true true 0)
[[ "$result" == "95" ]] && pass "elevated memory (>=60) costs 5 points" \
    || fail "elevated memory (>=60) costs 5 points" "95" "$result"

result=$(score 85 30 0 true true 0)
[[ "$result" == "85" ]] && pass "critical memory (>=80) costs 15 points" \
    || fail "critical memory (>=80) costs 15 points" "85" "$result"

result=$(score 59 30 0 true true 0)
[[ "$result" == "100" ]] && pass "memory just under 60 costs nothing" \
    || fail "memory just under 60 costs nothing" "100" "$result"

# ── Disk thresholds ───────────────────────────────────────────────
result=$(score 30 80 0 true true 0)
[[ "$result" == "90" ]] && pass "high disk (>=75) costs 10 points" \
    || fail "high disk (>=75) costs 10 points" "90" "$result"

result=$(score 30 95 0 true true 0)
[[ "$result" == "80" ]] && pass "critical disk (>=90) costs 20 points" \
    || fail "critical disk (>=90) costs 20 points" "80" "$result"

# ── Failed services (scaled penalty) ──────────────────────────────
result=$(score 30 30 3 true true 0)
[[ "$result" == "85" ]] && pass "3 failed services cost 15 points (5 each)" \
    || fail "3 failed services cost 15 points (5 each)" "85" "$result"

# ── WSL config ────────────────────────────────────────────────────
result=$(score 30 30 0 false true 0)
[[ "$result" == "95" ]] && pass "missing .wslconfig in WSL costs 5 points" \
    || fail "missing .wslconfig in WSL costs 5 points" "95" "$result"

result=$(score 30 30 0 false false 0)
[[ "$result" == "100" ]] && pass "missing .wslconfig outside WSL costs nothing" \
    || fail "missing .wslconfig outside WSL costs nothing" "100" "$result"

# ── Upgradable packages ───────────────────────────────────────────
result=$(score 30 30 0 true true 15)
[[ "$result" == "95" ]] && pass "many upgradable packages (>10) cost 5 points" \
    || fail "many upgradable packages (>10) cost 5 points" "95" "$result"

result=$(score 30 30 0 true true 10)
[[ "$result" == "100" ]] && pass "exactly 10 upgradable packages cost nothing" \
    || fail "exactly 10 upgradable packages cost nothing" "100" "$result"

# ── Clamping ──────────────────────────────────────────────────────
# 85% mem (-15), 95% disk (-20), 20 failed services (-100) => -35, clamps to 0
result=$(score 85 95 20 false true 50)
[[ "$result" == "0" ]] && pass "score clamps to 0 instead of going negative" \
    || fail "score clamps to 0 instead of going negative" "0" "$result"

# ── Recommendation accumulation ───────────────────────────────────
_quickscan_compute_score 85 95 2 false true 12
if [[ ${#QS_RECOMMENDATIONS[@]} -eq 5 ]]; then
    pass "every penalty contributes one recommendation"
else
    fail "every penalty contributes one recommendation" "5" "${#QS_RECOMMENDATIONS[@]}"
fi

# ── JSON serialization smoke test ─────────────────────────────────
# Exercise the real run_quick_scan JSON path end to end and assert the
# envelope is well-formed (values vary with the host, structure must not).
out=$(FORMAT=json run_quick_scan 2>/dev/null) || true
if [[ "$out" == "{"*"}" ]]; then
    pass "JSON output is a single well-formed object"
else
    fail "JSON output is a single well-formed object" "{...}" "$out"
fi
if [[ "$out" == *'"health_score":'* && "$out" == *'"recommendations":['* && "$out" == *'"cleanable":{'* ]]; then
    pass "JSON output contains health_score, recommendations and cleanable keys"
else
    fail "JSON output contains expected keys" "health_score/recommendations/cleanable" "$out"
fi

echo ""
echo "==============================="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All quickscan tests passed!"
    exit 0
else
    echo "✗ Some quickscan tests failed"
    exit 1
fi
