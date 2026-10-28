#!/usr/bin/env bash
# The logic lives in scripts/fail-open-lint.mjs; bin/ is where CLAUDE.md names the gate.
set -euo pipefail
exec node "$(dirname "$0")/../scripts/fail-open-lint.mjs" "$@"
