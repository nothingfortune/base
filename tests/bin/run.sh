#!/usr/bin/env bash
# Run every tests/bin/*.test.sh and aggregate the exit status.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
rc=0
for t in "$DIR"/*.test.sh; do
  [ -f "$t" ] || continue
  echo "== $(basename "$t") =="
  bash "$t" || rc=1
done
exit "$rc"
