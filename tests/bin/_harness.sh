#!/usr/bin/env bash
# Minimal dependency-free test helpers for bin/ scripts.
# Usage in a *.test.sh file:  source "$(dirname "$0")/_harness.sh"
set -uo pipefail

_T_PASS=0; _T_FAIL=0

assert_eq() { # <expected> <actual> <message>
  if [ "$1" = "$2" ]; then _T_PASS=$((_T_PASS+1));
  else _T_FAIL=$((_T_FAIL+1)); printf '  FAIL: %s\n    expected: %q\n    actual:   %q\n' "$3" "$1" "$2"; fi
}
assert_contains() { # <haystack-file> <needle> <message>
  if grep -qF -- "$2" "$1"; then _T_PASS=$((_T_PASS+1));
  else _T_FAIL=$((_T_FAIL+1)); printf '  FAIL: %s\n    %q not found in %s\n' "$3" "$2" "$1"; fi
}
assert_not_contains() { # <haystack-file> <needle> <message>
  if grep -qF -- "$2" "$1"; then _T_FAIL=$((_T_FAIL+1)); printf '  FAIL: %s\n    %q unexpectedly found in %s\n' "$3" "$2" "$1";
  else _T_PASS=$((_T_PASS+1)); fi
}
test_summary() { printf '  %d passed, %d failed\n' "$_T_PASS" "$_T_FAIL"; [ "$_T_FAIL" -eq 0 ]; }
