#!/usr/bin/env bash
# Tests for tests/bin/run.sh, driven against throwaway suite dirs (never itself: that recurses).
# A runner that ignores its dir argument would re-enter this file; stop at one level.
[ -n "${_RUN_TEST_NESTED:-}" ] && exit 0
export _RUN_TEST_NESTED=1
source "$(dirname "$0")/_harness.sh"
RUNNER="$(cd "$(dirname "$0")" && pwd)/run.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

suite() { # <dir> <name> <body>
  mkdir -p "$1"; printf '#!/usr/bin/env bash\n%s\n' "$3" >"$1/$2"
}

# Aggregate status: one failing suite fails the run, and every suite still runs.
suite "$TMP/mixed" a.test.sh 'exit 0'
suite "$TMP/mixed" b.test.sh 'exit 1'
suite "$TMP/mixed" c.test.sh 'echo c-ran'
out="$(bash "$RUNNER" "$TMP/mixed" 2>&1)"; rc=$?
printf '%s\n' "$out" >"$TMP/mixed.out"
assert_eq "1" "$rc" "a failing suite fails the run"
assert_contains "$TMP/mixed.out" "c-ran" "...and later suites still run"
assert_contains "$TMP/mixed.out" "FAIL in" "...and the failing suite is reported as FAIL"
assert_contains "$TMP/mixed.out" "3 suites in" "...and the summary counts every suite"

# SHELL_TESTS_SKIP skips by basename.
out="$(SHELL_TESTS_SKIP=b.test.sh bash "$RUNNER" "$TMP/mixed" 2>&1)"; rc=$?
printf '%s\n' "$out" >"$TMP/skip.out"
assert_eq "0" "$rc" "skipping the failing suite passes the run"
assert_contains "$TMP/skip.out" "b.test.sh == (skipped: SHELL_TESTS_SKIP)" "...and says it skipped"

# The heartbeat fires during a suite longer than its interval.
suite "$TMP/slow" slow.test.sh 'sleep 3'
out="$(HEARTBEAT_SECS=1 bash "$RUNNER" "$TMP/slow" 2>&1)"
beats="$(printf '%s\n' "$out" | grep -c 'still running slow.test.sh' || true)"
assert_eq "1" "$([ "$beats" -ge 1 ] && echo 1 || echo 0)" "heartbeat fires during a long suite ($beats beats)"

# A captured run returns promptly: an orphaned heartbeat sleep must not hold stdout open.
suite "$TMP/quick" quick.test.sh 'sleep 1'
start=$(date +%s); out="$(HEARTBEAT_SECS=8 bash "$RUNNER" "$TMP/quick" 2>&1)"; secs=$(( $(date +%s) - start ))
assert_eq "1" "$([ "$secs" -le 4 ] && echo 1 || echo 0)" "a captured run returns within 4s, not the heartbeat interval (${secs}s)"

# A TERM to the runner mid-suite takes the heartbeat with it; an orphan writes, and holds stdout, forever.
suite "$TMP/hang" hang.test.sh 'exec sleep 10'
HEARTBEAT_SECS=1 bash "$RUNNER" "$TMP/hang" >"$TMP/hang.out" 2>&1 & runner=$!
sleep 1.5; kill -TERM "$runner"; wait "$runner" 2>/dev/null
before="$(grep -c 'still running' "$TMP/hang.out" || true)"; sleep 2.5
after="$(grep -c 'still running' "$TMP/hang.out" || true)"
pkill -f "$TMP/hang" 2>/dev/null
assert_eq "$before" "$after" "a TERMed runner leaves no heartbeat writing"

test_summary
