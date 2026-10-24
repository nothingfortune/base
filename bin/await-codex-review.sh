#!/usr/bin/env bash
#
# Poll a GitHub PR until Codex has reviewed its CURRENT head, then print that review's findings.
#
# Codex reviews post asynchronously (~1-3 min after a PR is opened, or after an `@codex review`
# comment). Completion is read from the codex-review-state:v1 marker in Codex's summary issue
# comment: the review is done when its commit_sha equals the PR head and its status is completed.
# Only comments Codex made on that head are printed, so findings from an earlier push are not
# mistaken for a fresh review, and a clean review is reported as clean.
#
# Unlike Copilot, Codex CANNOT be requested from here. Posting the connector to
# `pulls/<n>/requested_reviewers` returns HTTP 200 but is silently dropped, so this script
# only polls. For a push after the first review, comment `@codex review` first.
#
# Usage:
#   bin/await-codex-review.sh [PR_NUMBER]
#   CODEX_WAIT_SECS=600 bin/await-codex-review.sh 88
#
# With no PR number, uses the PR for the current branch (gh pr view).
# Exit 0 once the head is reviewed or the wait budget runs out (the message says which);
# exit 2 on usage/lookup failure or a failed fetch of the review's comments.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=bin/lib/pr-review-lib.sh
. "$HERE/lib/pr-review-lib.sh"

WAIT="${CODEX_WAIT_SECS:-240}"
POLL="${CODEX_POLL_SECS:-15}"

read -r REPO PR < <(pr_resolve_repo_and_number "await-codex-review" "${1:-}") || exit 2

HEAD="$(gh pr view "$PR" --repo "$REPO" --json headRefOid -q .headRefOid 2>/dev/null || true)"
if [ -z "$HEAD" ]; then
  echo "await-codex-review: could not read the head commit of PR #$PR." >&2
  exit 2
fi

deadline=$(( $(date +%s) + WAIT ))
while :; do
  # A failed state fetch is "not yet known", so keep polling rather than claim a result.
  state="$(gh api --paginate "repos/$REPO/issues/$PR/comments" 2>/dev/null \
    | jq -s 'add // []' 2>/dev/null | codex_review_state "$HEAD" 2>/dev/null || echo pending)"
  if [ "$state" = "completed" ]; then break; fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "No completed Codex review of $REPO PR #$PR head ${HEAD:0:7} after ${WAIT}s."
    echo "(This means 'not reviewed yet', NOT 'reviewed and found nothing'. For a push after the"
    echo " first review, comment '@codex review', then re-run.)"
    exit 0
  fi
  sleep "$POLL"
done

# The review is done, so a failed fetch here would hide its findings: fail instead of printing none.
if ! raw="$(gh api --paginate "repos/$REPO/pulls/$PR/comments" 2>/dev/null)" \
  || ! comments="$(printf '%s' "$raw" | jq -s --arg head "$HEAD" \
    'add // [] | [.[] | select(((.user.login // "") | test("codex"; "i")) and (.in_reply_to_id == null) and ((.original_commit_id // .commit_id) == $head))]')"; then
  echo "await-codex-review: Codex reviewed ${HEAD:0:7}, but its comments could not be fetched or parsed. Retry." >&2
  exit 2
fi
count="$(printf '%s' "$comments" | jq 'length')"

# Review bodies too: a finding in a collapsed "Suppressed comments" block never reaches the comments API.
if ! rawreviews="$(gh api --paginate "repos/$REPO/pulls/$PR/reviews" 2>/dev/null)" \
  || ! headreviews="$(printf '%s' "$rawreviews" | jq -s --arg head "$HEAD" 'add // [] | [.[] | select(.commit_id == $head)]')"; then
  echo "await-codex-review: Codex reviewed ${HEAD:0:7}, but its reviews could not be fetched or parsed. Retry." >&2
  exit 2
fi
suppressed="$(printf '%s' "$headreviews" | suppressed_findings "codex")"
s_count="$(printf '%s' "$suppressed" | grep -c . || true)"

echo "=== Codex on $REPO PR #$PR head ${HEAD:0:7} — ${count} inline, ${s_count} suppressed ==="
if [ "$count" -gt 0 ]; then
  printf '%s' "$comments" | jq -r '.[] |
    "-- id=\(.id) | \(.path):\(.line // .original_line // "?")\n\(.body)\n"'
  echo "Reply in-thread: gh api repos/$REPO/pulls/$PR/comments/<id>/replies -f body=..."
fi
if [ "$s_count" -gt 0 ]; then
  echo
  echo "!! ${s_count} SUPPRESSED finding(s) — collapsed in the review body, NOT in the comments API:"
  printf '%s\n' "$suppressed" | sed 's/^/   /'
fi
if [ "$count" -eq 0 ] && [ "$s_count" -eq 0 ]; then
  echo "(Codex reviewed this head and filed no findings.)"
fi
exit 0
