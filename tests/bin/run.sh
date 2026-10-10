#!/usr/bin/env bash
# Run every *.test.sh in a suites dir and aggregate the exit status.
# Usage: tests/bin/run.sh [suites-dir]   (default: this directory)
# HEARTBEAT_SECS   heartbeat interval while one suite runs (default 30)
# SHELL_TESTS_SKIP comma-separated basenames to skip
set -uo pipefail
DIR="${1:-$(cd "$(dirname "$0")" && pwd)}"
HB="${HEARTBEAT_SECS:-30}"
rc=0; t0=$(date +%s); n=0; timings=""
heartbeat() { # <name> <start-epoch>
  local nap
  # Kill the sleep too: an orphaned one holds stdout and stalls anyone capturing the runner.
  trap 'kill "$nap" 2>/dev/null; exit 0' TERM
  while :; do
    sleep "$HB" & nap=$!; wait "$nap" || exit 0
    printf '   … still running %s (%ds)\n' "$1" "$(( $(date +%s) - $2 ))"
  done
}
for t in "$DIR"/*.test.sh; do
  [ -f "$t" ] || continue
  name="$(basename "$t")"
  case ",${SHELL_TESTS_SKIP:-}," in *",$name,"*) echo "== $name == (skipped: SHELL_TESTS_SKIP)"; continue ;; esac
  n=$((n+1)); s=$(date +%s)
  printf '== %s == [%3ds elapsed]\n' "$name" "$(( s - t0 ))"
  heartbeat "$name" "$s" & hb=$!
  if bash "$t"; then verdict="ok"; else verdict="FAIL"; rc=1; fi
  kill "$hb" 2>/dev/null; wait "$hb" 2>/dev/null
  d=$(( $(date +%s) - s )); timings="$timings$d $name"$'\n'
  printf '   %s in %ds\n' "$verdict" "$d"
done
printf '\n%d suites in %ds; slowest:\n' "$n" "$(( $(date +%s) - t0 ))"
printf '%s' "$timings" | sort -rn | head -3 | awk '{printf "   %4ds  %s\n", $1, $2}'
exit "$rc"
