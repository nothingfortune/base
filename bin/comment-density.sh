#!/usr/bin/env bash
# The logic lives in scripts/comment-density.mjs; bin/ is where CLAUDE.md names the gate.
set -euo pipefail
exec node "$(dirname "$0")/../scripts/comment-density.mjs" "$@"
