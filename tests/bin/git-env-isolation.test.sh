#!/usr/bin/env bash
# Tripwire: a hook-exported GIT_DIR overrides `git -C`, so repo-building tests must not see it.
source "$(dirname "$0")/_harness.sh"
DIR="$(cd "$(dirname "$0")" && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SENTINEL="$TMP/sentinel"
git init -q -b main "$SENTINEL"
git -C "$SENTINEL" -c user.email=s@s -c user.name=s commit -q --allow-empty -m sentinel

state() {
  git -C "$SENTINEL" rev-parse HEAD
  git -C "$SENTINEL" for-each-ref --format='%(refname) %(objectname)'
  git -C "$SENTINEL" config --local --list | sort
}
before="$(state)"

# What git exports to a hook run from a linked worktree: absolute paths.
GIT_DIR="$SENTINEL/.git" GIT_WORK_TREE="$SENTINEL" GIT_INDEX_FILE="$SENTINEL/.git/index" \
  bash "$DIR/tracked-dumps.test.sh" >"$TMP/out" 2>&1
rc=$?

assert_eq "0" "$rc" "a repo-building test still passes under an exported GIT_DIR"
assert_eq "$before" "$(state)" "the ambient repository keeps its HEAD, refs and config"

test_summary
