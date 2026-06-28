#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/packages.sh"

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

echo "Running WSLMole Packages Tests"
echo "=============================="
echo ""

# Stub the action implementations so dispatch is tested in isolation
# (no real apt/snap calls). Each records that it ran and returns a code.
ACTION_LOG=""
packages_audit()      { ACTION_LOG="${ACTION_LOG}audit,";      return "${AUDIT_RC:-0}"; }
packages_update()     { ACTION_LOG="${ACTION_LOG}update,";     return "${UPDATE_RC:-0}"; }
packages_autoremove() { ACTION_LOG="${ACTION_LOG}autoremove,"; return "${AUTOREMOVE_RC:-0}"; }
packages_clean()      { ACTION_LOG="${ACTION_LOG}clean,";      return "${CLEAN_RC:-0}"; }
packages_list()       { ACTION_LOG="${ACTION_LOG}list,";       return "${LIST_RC:-0}"; }

# ── cmd_packages_action dispatch ──────────────────────────────────
ACTION_LOG=""; cmd_packages_action audit >/dev/null 2>&1
[[ "$ACTION_LOG" == "audit," ]] && pass "cmd_packages_action routes 'audit'" \
    || fail "cmd_packages_action routes 'audit'" "audit," "$ACTION_LOG"

ACTION_LOG=""; cmd_packages_action check >/dev/null 2>&1
[[ "$ACTION_LOG" == "audit," ]] && pass "cmd_packages_action treats 'check' as audit" \
    || fail "cmd_packages_action treats 'check' as audit" "audit," "$ACTION_LOG"

ACTION_LOG=""; cmd_packages_action list >/dev/null 2>&1
[[ "$ACTION_LOG" == "list," ]] && pass "cmd_packages_action routes 'list'" \
    || fail "cmd_packages_action routes 'list'" "list," "$ACTION_LOG"

# Unknown action returns 1
rc=0; cmd_packages_action bogus >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 1 ]] && pass "cmd_packages_action rejects unknown action with rc=1" \
    || fail "cmd_packages_action rejects unknown action with rc=1" "1" "$rc"

# ── Exit-code propagation ─────────────────────────────────────────
CLEAN_RC=3; rc=0; cmd_packages_action clean >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 3 ]] && pass "cmd_packages_action propagates the action's exit code" \
    || fail "cmd_packages_action propagates the action's exit code" "3" "$rc"
CLEAN_RC=0

UPDATE_RC=2; rc=0; cmd_packages_action update >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] && pass "cmd_packages_action propagates a failing update code" \
    || fail "cmd_packages_action propagates a failing update code" "2" "$rc"
UPDATE_RC=0

# ── cmd_packages argument parsing ─────────────────────────────────
ACTION_LOG=""; cmd_packages >/dev/null 2>&1
[[ "$ACTION_LOG" == "audit," ]] && pass "cmd_packages defaults to audit when no action given" \
    || fail "cmd_packages defaults to audit when no action given" "audit," "$ACTION_LOG"

ACTION_LOG=""; cmd_packages autoremove >/dev/null 2>&1
[[ "$ACTION_LOG" == "autoremove," ]] && pass "cmd_packages forwards a named action" \
    || fail "cmd_packages forwards a named action" "autoremove," "$ACTION_LOG"

rc=0; cmd_packages -h >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 0 ]] && pass "cmd_packages -h exits 0" \
    || fail "cmd_packages -h exits 0" "0" "$rc"

rc=0; cmd_packages --bogus >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 1 ]] && pass "cmd_packages rejects unknown option with rc=1" \
    || fail "cmd_packages rejects unknown option with rc=1" "1" "$rc"

# ── require_root_or_skip gating ───────────────────────────────────
# Drive the gate through a stubbed is_root rather than real EUID.
is_root() { return 1; }
rc=0; require_root_or_skip "apt update/upgrade" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 1 ]] && pass "require_root_or_skip blocks (rc=1) when not root" \
    || fail "require_root_or_skip blocks (rc=1) when not root" "1" "$rc"

# The skip warning must be visible to the user (stderr/stdout), not swallowed
out=$(require_root_or_skip "apt cache clean" 2>&1 || true)
[[ "$out" == *"requires root"* ]] && pass "require_root_or_skip warns about the missing privilege" \
    || fail "require_root_or_skip warns about the missing privilege" "*requires root*" "$out"

is_root() { return 0; }
rc=0; require_root_or_skip "apt update/upgrade" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 0 ]] && pass "require_root_or_skip permits (rc=0) when root" \
    || fail "require_root_or_skip permits (rc=0) when root" "0" "$rc"

# ── Action registry ───────────────────────────────────────────────
expected="audit update autoremove clean list"
[[ "${PACKAGES_ACTIONS[*]}" == "$expected" ]] && pass "PACKAGES_ACTIONS lists all supported actions" \
    || fail "PACKAGES_ACTIONS lists all supported actions" "$expected" "${PACKAGES_ACTIONS[*]}"

echo ""
echo "=============================="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All packages tests passed!"
    exit 0
else
    echo "✗ Some packages tests failed"
    exit 1
fi
