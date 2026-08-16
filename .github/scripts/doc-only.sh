#!/usr/bin/env bash
# Is the change under review doc-only (docs/** and *.md, nothing else)?
# Prints `doc_only=true|false` to $GITHUB_OUTPUT (or stdout outside Actions).
#
# Used by ci.yml and e2e.yml to gate their expensive jobs AT THE JOB LEVEL,
# never via workflow-level path filters. The distinction is load-bearing on
# this repo: branch protection requires `check / check` and `e2e / e2e`, and
# a workflow skipped by path filters never creates a check run — the required
# check sits "Expected" forever and the PR is unmergeable. A job skipped via
# `if:` reports "skipped", which branch protection treats as satisfied
# (GitHub's documented "skipped but required checks" behavior).
#
# FAIL-SAFE DIRECTION: when the base commit cannot be resolved (first push of
# a branch, force-push beyond history, the zero SHA), report doc_only=false so
# the FULL gate runs. Here the expensive lane is the required one, so
# uncertainty must buy more checking, not less. (The inverse of dollyVision's
# docs.yml, where the doc lane is the backstop — same principle, opposite
# topology.)
#
# Usage: BASE_SHA=<sha> bash .github/scripts/doc-only.sh
set -uo pipefail

out="${GITHUB_OUTPUT:-/dev/stdout}"
base="${BASE_SHA:-}"

if [ -z "$base" ] || ! git cat-file -e "${base}^{commit}" 2>/dev/null; then
  echo "scope undetermined (base '${base:-unset}' unresolvable) — running the full gate" >&2
  echo "doc_only=false" >> "$out"
  exit 0
fi

# -z, consumed NUL-aware end to end (read -d '' + case patterns, whose *
# matches embedded newlines): re-splitting on newlines fragmented a
# newline-bearing filename into phantom paths. In this repo's direction
# that only ever OVER-checked (a fragment looks non-docish → full gate),
# but the same construct was a zero-check hole in the inverse-direction
# consumer (Codex, dollyVision#61) — the classifier reports the truth and
# lets the caller pick the fail direction.
# --no-renames: `--name-only` reports only a rename's DESTINATION, so an
# exact `src/a.ts → docs/a.md` rename would list one doc path and classify
# doc-only — letting a change that deletes production code skip the whole
# gate (Codex, base#7). With renames disabled it shows as delete+add and
# the deleted code path classifies the change correctly.
nondoc=""
while IFS= read -r -d '' path; do
  case "$path" in
    docs/* | *.md) ;;
    *)
      nondoc="$path"
      break
      ;;
  esac
done < <(git diff --no-renames --name-only -z "${base}...HEAD")
if [ -n "$nondoc" ]; then
  echo "non-doc changes present — full gate" >&2
  echo "doc_only=false" >> "$out"
else
  echo "doc-only change — expensive jobs may skip" >&2
  echo "doc_only=true" >> "$out"
fi
