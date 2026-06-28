#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/diagnose.sh"

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

echo "Running WSLMole Diagnose Tests"
echo "=============================="
echo ""

# Stub each diagnostic so dispatch and exit-code handling are tested in
# isolation. Each records that it ran and returns a configurable code.
RUN_LOG=""
diagnose_processes()      { RUN_LOG="${RUN_LOG}process,"; return "${PROC_RC:-0}"; }
diagnose_memory()         { RUN_LOG="${RUN_LOG}memory,";  return "${MEM_RC:-0}"; }
diagnose_services()       { RUN_LOG="${RUN_LOG}service,"; return "${SVC_RC:-0}"; }
diagnose_wsl_resources()  { RUN_LOG="${RUN_LOG}wsl,";     return "${WSL_RC:-0}"; }
is_wsl()                  { return "${IS_WSL_RC:-1}"; }   # default: not WSL

reset_codes() { PROC_RC=0; MEM_RC=0; SVC_RC=0; WSL_RC=0; IS_WSL_RC=1; RUN_LOG=""; }

# ── Single-type routing + exit code propagation ───────────────────
reset_codes; PROC_RC=2; rc=0; cmd_diagnose_type process >/dev/null 2>&1 || rc=$?
[[ "$RUN_LOG" == "process," && "$rc" -eq 2 ]] \
    && pass "type 'process' runs only processes and propagates its code" \
    || fail "type 'process' runs only processes and propagates its code" "process,/2" "$RUN_LOG/$rc"

reset_codes; MEM_RC=5; rc=0; cmd_diagnose_type memory >/dev/null 2>&1 || rc=$?
[[ "$RUN_LOG" == "memory," && "$rc" -eq 5 ]] \
    && pass "type 'memory' runs only memory and propagates its code" \
    || fail "type 'memory' runs only memory and propagates its code" "memory,/5" "$RUN_LOG/$rc"

reset_codes; SVC_RC=4; rc=0; cmd_diagnose_type service >/dev/null 2>&1 || rc=$?
[[ "$RUN_LOG" == "service," && "$rc" -eq 4 ]] \
    && pass "type 'service' runs only services and propagates its code" \
    || fail "type 'service' runs only services and propagates its code" "service,/4" "$RUN_LOG/$rc"

reset_codes; WSL_RC=7; rc=0; cmd_diagnose_type wsl >/dev/null 2>&1 || rc=$?
[[ "$RUN_LOG" == "wsl," && "$rc" -eq 7 ]] \
    && pass "type 'wsl' runs only wsl and propagates its code" \
    || fail "type 'wsl' runs only wsl and propagates its code" "wsl,/7" "$RUN_LOG/$rc"

# Aliases resolve to the same handlers
reset_codes; cmd_diagnose_type processes >/dev/null 2>&1
[[ "$RUN_LOG" == "process," ]] && pass "alias 'processes' maps to process diagnostics" \
    || fail "alias 'processes' maps to process diagnostics" "process," "$RUN_LOG"

reset_codes; cmd_diagnose_type mem >/dev/null 2>&1
[[ "$RUN_LOG" == "memory," ]] && pass "alias 'mem' maps to memory diagnostics" \
    || fail "alias 'mem' maps to memory diagnostics" "memory," "$RUN_LOG"

# ── 'all' aggregation ─────────────────────────────────────────────
reset_codes; rc=0; cmd_diagnose_type all >/dev/null 2>&1 || rc=$?
[[ "$RUN_LOG" == "process,memory,service," && "$rc" -eq 0 ]] \
    && pass "'all' runs the three core diagnostics (no WSL) and succeeds" \
    || fail "'all' runs the three core diagnostics (no WSL) and succeeds" "process,memory,service,/0" "$RUN_LOG/$rc"

reset_codes; IS_WSL_RC=0; rc=0; cmd_diagnose_type all >/dev/null 2>&1 || rc=$?
[[ "$RUN_LOG" == "process,memory,service,wsl," ]] \
    && pass "'all' includes WSL diagnostics when running in WSL" \
    || fail "'all' includes WSL diagnostics when running in WSL" "process,memory,service,wsl," "$RUN_LOG"

# Any single failure makes 'all' report rc=1 (normalized, not the raw code)
reset_codes; MEM_RC=9; rc=0; cmd_diagnose_type all >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 1 ]] && pass "'all' returns rc=1 when any diagnostic fails" \
    || fail "'all' returns rc=1 when any diagnostic fails" "1" "$rc"

# All sub-diagnostics still run even when an earlier one failed
reset_codes; PROC_RC=1; cmd_diagnose_type all >/dev/null 2>&1 || true
[[ "$RUN_LOG" == "process,memory,service," ]] \
    && pass "'all' keeps running later diagnostics after an early failure" \
    || fail "'all' keeps running later diagnostics after an early failure" "process,memory,service," "$RUN_LOG"

# ── Unknown type ──────────────────────────────────────────────────
reset_codes; rc=0; cmd_diagnose_type bogus >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 1 && -z "$RUN_LOG" ]] && pass "unknown type returns rc=1 without running diagnostics" \
    || fail "unknown type returns rc=1 without running diagnostics" "1/empty" "$rc/$RUN_LOG"

# ── cmd_diagnose argument parsing ─────────────────────────────────
reset_codes; cmd_diagnose >/dev/null 2>&1
[[ "$RUN_LOG" == "process,memory,service," ]] && pass "cmd_diagnose defaults to 'all'" \
    || fail "cmd_diagnose defaults to 'all'" "process,memory,service," "$RUN_LOG"

reset_codes; MEM_RC=6; rc=0; cmd_diagnose memory >/dev/null 2>&1 || rc=$?
[[ "$RUN_LOG" == "memory," && "$rc" -eq 6 ]] \
    && pass "cmd_diagnose forwards a named type and its exit code" \
    || fail "cmd_diagnose forwards a named type and its exit code" "memory,/6" "$RUN_LOG/$rc"

rc=0; cmd_diagnose -h >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 0 ]] && pass "cmd_diagnose -h exits 0" \
    || fail "cmd_diagnose -h exits 0" "0" "$rc"

rc=0; cmd_diagnose --bogus >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 1 ]] && pass "cmd_diagnose rejects unknown option with rc=1" \
    || fail "cmd_diagnose rejects unknown option with rc=1" "1" "$rc"

# ── Type registry ─────────────────────────────────────────────────
expected="process memory service wsl"
[[ "${DIAGNOSE_TYPES[*]}" == "$expected" ]] && pass "DIAGNOSE_TYPES lists all diagnostic types" \
    || fail "DIAGNOSE_TYPES lists all diagnostic types" "$expected" "${DIAGNOSE_TYPES[*]}"

echo ""
echo "=============================="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All diagnose tests passed!"
    exit 0
else
    echo "✗ Some diagnose tests failed"
    exit 1
fi
