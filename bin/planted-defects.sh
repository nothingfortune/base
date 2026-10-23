#!/usr/bin/env bash
# The logic lives in scripts/planted-defects.mjs; bin/ is where CLAUDE.md names the gate.
set -euo pipefail
exec node "$(dirname "$0")/../scripts/planted-defects.mjs" "$@"
