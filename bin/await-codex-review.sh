#!/usr/bin/env bash
#
# Poll a GitHub PR for Codex review comments and print them.
#
# Codex reviews post asynchronously (~1-3 min after a PR is created/updated),
# so an immediate fetch usually finds nothing. This polls until Codex comments
# appear or the wait budget is exhausted, then prints them for triage.
#
# Unlike Copilot, Codex CANNOT be requested from here. Posting the connector to
# `pulls/<n>/requested_reviewers` returns HTTP 200 but is silently dropped —
# `requested_reviewers` stays empty — so this script can only poll. That means a
# timeout here is genuinely ambiguous: Codex may be slow, or may not be running at
# all. Check the PR page before concluding the code is clean; a silent Codex is not
# an approving Codex. (await-copilot-review.sh does request, since Copilot can be.)
#
# Usage:
#   bin/await-codex-review.sh [PR_NUMBER]
#   CODEX_WAIT_SECS=300 bin/await-codex-review.sh 88
#
# With no PR number, uses the PR for the current branch (gh pr view).
# Exit 0 whether or not comments were found (a clean "none yet" is not an error);
# exit 2 on usage/lookup failure.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=bin/lib/pr-review-lib.sh
. "$HERE/lib/pr-review-lib.sh"

WAIT="${CODEX_WAIT_SECS:-240}"
POLL="${CODEX_POLL_SECS:-15}"

read -r REPO PR < <(pr_resolve_repo_and_number "await-codex-review" "${1:-}") || exit 2

deadline=$(( $(date +%s) + WAIT ))
while :; do
  # --paginate + `jq -s add`: the comments endpoint defaults to 30/page, so a
  # long-lived PR's older comments would silently drop without merging every page.
  comments="$(gh api --paginate "repos/$REPO/pulls/$PR/comments" 2>/dev/null \
    | jq -s 'add // [] | [.[] | select(.user.login | test("codex"; "i"))]' 2>/dev/null || echo '[]')"
  count="$(printf '%s' "$comments" | jq 'length' 2>/dev/null || echo 0)"

  # Also check review BODIES for collapsed "Suppressed comments" findings. Codex files inline
  # today, but the comments API is the wrong place to look for a bot that doesn't — which is
  # exactly how six Copilot findings were missed on #284/#285 — so this checks both.
  suppressed="$(gh api --paginate "repos/$REPO/pulls/$PR/reviews" 2>/dev/null \
    | jq -s 'add // []' 2>/dev/null | suppressed_findings "codex" 2>/dev/null || true)"
  s_count="$(printf '%s' "$suppressed" | grep -c . || true)"

  if [ "${count:-0}" -gt 0 ] || [ "${s_count:-0}" -gt 0 ]; then
    echo "=== Codex on $REPO PR #$PR — ${count:-0} inline, ${s_count:-0} suppressed ==="
    if [ "${count:-0}" -gt 0 ]; then
      printf '%s' "$comments" | jq -r '.[] |
        "-- id=\(.id) | \(.path):\(.line // .original_line // "?")\n\(.body)\n"'
      echo "Reply in-thread: gh api repos/$REPO/pulls/$PR/comments/<id>/replies -f body=..."
    fi
    if [ "${s_count:-0}" -gt 0 ]; then
      echo
      echo "!! ${s_count} SUPPRESSED finding(s) — collapsed in the review body, NOT in the comments API:"
      printf '%s\n' "$suppressed" | sed 's/^/   /'
    fi
    exit 0
  fi

  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "No Codex comments on $REPO PR #$PR after ${WAIT}s."
    echo "(Codex cannot be requested via the API — it reviews on its own schedule, so this"
    echo " means 'no review yet', NOT 'reviewed and found nothing'. Re-run, or check the PR.)"
    exit 0
  fi
  sleep "$POLL"
done
