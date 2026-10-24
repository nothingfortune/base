#!/usr/bin/env bash
# The logic lives in scripts/git-isolation-check.mjs; bin/ is where CLAUDE.md names the gate.
set -euo pipefail
exec node "$(dirname "$0")/../scripts/git-isolation-check.mjs" "$@"
