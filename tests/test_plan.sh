#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/plan.sh"

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

echo "Running WSLMole Plan Tests"
echo "=========================="
echo ""

# Reset all filters to a known state before each group
reset_filters() {
    PLAN_FILTER_RISK=""
    PLAN_FILTER_AUTO=false
    PLAN_FILTER_CATEGORY=""
    PLAN_FIX_ONLY=""
}

# ── _plan_reset ───────────────────────────────────────────────────
reset_filters
_plan_add_item "T" "low" "d" "c" "true" "apt"
_plan_reset
if [[ ${#PLAN_TITLES[@]} -eq 0 && ${#PLAN_AUTOS[@]} -eq 0 ]]; then
    pass "_plan_reset clears all plan arrays"
else
    fail "_plan_reset clears all plan arrays" "0 items" "${#PLAN_TITLES[@]}"
fi

# ── _plan_fix_only_allows ─────────────────────────────────────────
PLAN_FIX_ONLY=""
if _plan_fix_only_allows "anything"; then
    pass "_plan_fix_only_allows: empty filter allows any category"
else
    fail "_plan_fix_only_allows: empty filter allows any category"
fi

PLAN_FIX_ONLY="apt,logs"
if _plan_fix_only_allows "apt"; then
    pass "_plan_fix_only_allows: listed category (apt) allowed"
else
    fail "_plan_fix_only_allows: listed category (apt) allowed"
fi

if ! _plan_fix_only_allows "tmp"; then
    pass "_plan_fix_only_allows: unlisted category (tmp) denied"
else
    fail "_plan_fix_only_allows: unlisted category (tmp) denied"
fi

PLAN_FIX_ONLY="apt, logs , tmp"
if _plan_fix_only_allows "logs" && _plan_fix_only_allows "tmp"; then
    pass "_plan_fix_only_allows: tolerates whitespace around items"
else
    fail "_plan_fix_only_allows: tolerates whitespace around items"
fi
PLAN_FIX_ONLY=""

# ── _plan_add_item filters ────────────────────────────────────────
reset_filters
PLAN_FILTER_RISK="low"
_plan_reset
_plan_add_item "Low item"    "low"    "d" "c" "true"  "apt"
_plan_add_item "Medium item" "medium" "d" "c" "false" "disk"
if [[ ${#PLAN_TITLES[@]} -eq 1 && "${PLAN_TITLES[0]}" == "Low item" ]]; then
    pass "_plan_add_item: PLAN_FILTER_RISK keeps only matching risk"
else
    fail "_plan_add_item: PLAN_FILTER_RISK keeps only matching risk" "1 (Low item)" "${#PLAN_TITLES[@]}"
fi

reset_filters
PLAN_FILTER_AUTO=true
_plan_reset
_plan_add_item "Auto item"   "low" "d" "c" "true"  "apt"
_plan_add_item "Manual item" "low" "d" "c" "false" "snap"
if [[ ${#PLAN_TITLES[@]} -eq 1 && "${PLAN_TITLES[0]}" == "Auto item" ]]; then
    pass "_plan_add_item: PLAN_FILTER_AUTO keeps only auto=true items"
else
    fail "_plan_add_item: PLAN_FILTER_AUTO keeps only auto=true items" "1 (Auto item)" "${#PLAN_TITLES[@]}"
fi

reset_filters
PLAN_FILTER_CATEGORY="logs"
_plan_reset
_plan_add_item "Apt item"  "low" "d" "c" "true" "apt"
_plan_add_item "Logs item" "low" "d" "c" "true" "logs"
if [[ ${#PLAN_TITLES[@]} -eq 1 && "${PLAN_TITLES[0]}" == "Logs item" ]]; then
    pass "_plan_add_item: PLAN_FILTER_CATEGORY keeps only matching category"
else
    fail "_plan_add_item: PLAN_FILTER_CATEGORY keeps only matching category" "1 (Logs item)" "${#PLAN_TITLES[@]}"
fi

reset_filters
PLAN_FIX_ONLY="apt"
_plan_reset
_plan_add_item "Apt item" "low" "d" "c" "true" "apt"
_plan_add_item "Tmp item" "low" "d" "c" "true" "tmp"
if [[ ${#PLAN_TITLES[@]} -eq 1 && "${PLAN_TITLES[0]}" == "Apt item" ]]; then
    pass "_plan_add_item: PLAN_FIX_ONLY restricts added items by category"
else
    fail "_plan_add_item: PLAN_FIX_ONLY restricts added items by category" "1 (Apt item)" "${#PLAN_TITLES[@]}"
fi
reset_filters

# ── _plan_json_escape ─────────────────────────────────────────────
result=$(_plan_json_escape 'say "hi"')
[[ "$result" == 'say \"hi\"' ]] && pass "_plan_json_escape: escapes double quotes" \
    || fail "_plan_json_escape: escapes double quotes" 'say \"hi\"' "$result"

result=$(_plan_json_escape 'a\b')
[[ "$result" == 'a\\b' ]] && pass "_plan_json_escape: escapes backslashes" \
    || fail "_plan_json_escape: escapes backslashes" 'a\\b' "$result"

result=$(_plan_json_escape $'line1\nline2')
[[ "$result" == 'line1\nline2' ]] && pass "_plan_json_escape: escapes newlines" \
    || fail "_plan_json_escape: escapes newlines" 'line1\nline2' "$result"

# ── plan_print_json ───────────────────────────────────────────────
reset_filters
_plan_reset
_plan_add_item "Clean APT" "low" "Reclaim space" "sudo wslmole clean apt" "true" "apt"
json=$(FORMAT=text plan_print_json)   # FORMAT!=json => json_output prints to stdout
if [[ "$json" == '{"items":['*']}' ]]; then
    pass "plan_print_json: wraps items in a JSON envelope"
else
    fail "plan_print_json: wraps items in a JSON envelope" '{"items":[...]}' "$json"
fi
if [[ "$json" == *'"auto":true'* && "$json" == *'"category":"apt"'* ]]; then
    pass "plan_print_json: emits raw boolean auto and category fields"
else
    fail "plan_print_json: emits raw boolean auto and category fields" 'auto:true, category:apt' "$json"
fi

_plan_reset
json=$(FORMAT=text plan_print_json)
[[ "$json" == '{"items":[]}' ]] && pass "plan_print_json: empty plan yields empty items array" \
    || fail "plan_print_json: empty plan yields empty items array" '{"items":[]}' "$json"

# ── plan_has_auto_actions ─────────────────────────────────────────
reset_filters
_plan_reset
_plan_add_item "Manual" "medium" "d" "c" "false" "disk"
if ! plan_has_auto_actions; then
    pass "plan_has_auto_actions: false when no auto items exist"
else
    fail "plan_has_auto_actions: false when no auto items exist"
fi

_plan_add_item "Auto" "low" "d" "c" "true" "apt"
if plan_has_auto_actions; then
    pass "plan_has_auto_actions: true when an allowed auto item exists"
else
    fail "plan_has_auto_actions: true when an allowed auto item exists"
fi

# An auto item whose category is excluded by PLAN_FIX_ONLY does not count
PLAN_FIX_ONLY="logs"
if ! plan_has_auto_actions; then
    pass "plan_has_auto_actions: respects PLAN_FIX_ONLY exclusion"
else
    fail "plan_has_auto_actions: respects PLAN_FIX_ONLY exclusion"
fi
PLAN_FIX_ONLY=""

# ── plan_apply_auto_actions ───────────────────────────────────────
# Stub the real cleanup so we only record which categories were applied.
APPLY_LOG=""
cmd_clean_category() { APPLY_LOG="${APPLY_LOG}${1},"; }
print_section() { :; }
print_info() { :; }

reset_filters
_plan_reset
_plan_add_item "Apt"    "low"    "d" "c" "true"  "apt"     # auto + known category
_plan_add_item "Logs"   "low"    "d" "c" "true"  "logs"    # auto + known category
_plan_add_item "Manual" "medium" "d" "c" "false" "disk"    # not auto -> skipped
_plan_add_item "Snap"   "low"    "d" "c" "true"  "snap"    # auto but no registered action
APPLY_LOG=""
plan_apply_auto_actions
if [[ "$APPLY_LOG" == "apt,logs," ]]; then
    pass "plan_apply_auto_actions: runs only auto items with registered cleanups"
else
    fail "plan_apply_auto_actions: runs only auto items with registered cleanups" "apt,logs," "$APPLY_LOG"
fi

# PLAN_FIX_ONLY narrows which auto actions actually run
PLAN_FIX_ONLY="logs"
APPLY_LOG=""
plan_apply_auto_actions
if [[ "$APPLY_LOG" == "logs," ]]; then
    pass "plan_apply_auto_actions: honors PLAN_FIX_ONLY whitelist"
else
    fail "plan_apply_auto_actions: honors PLAN_FIX_ONLY whitelist" "logs," "$APPLY_LOG"
fi
PLAN_FIX_ONLY=""

echo ""
echo "=========================="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All plan tests passed!"
    exit 0
else
    echo "✗ Some plan tests failed"
    exit 1
fi
