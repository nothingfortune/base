#!/usr/bin/env bash
#
# Poll a GitHub PR for GitHub Copilot's code review and print it.
#
# Copilot's review posts asynchronously (~1-3 min after it is REQUESTED), so an
# immediate fetch usually finds nothing. Unlike inline-only bots, Copilot ALWAYS
# posts a review summary — even when it finds nothing — so completion is detected by
# the presence of a Copilot review of the current head commit, and its inline
# comments (if any) are printed for triage. Mirror of await-codex-review.sh.
#
# It REQUESTS the review first. Copilot does not review on PR-open or on
# ready-for-review in this repo; it reviews when asked. On #302 the order was: PR
# opened 05:43 → Copilot requested 06:24 → review 06:27. This script used to poll
# only, so on a PR nobody had requested it waited out its whole budget and reported
# "may still be running or isn't enabled" — which reads as a bot problem and is not.
# Five 240s windows were spent that way on #303/#304 before the cause was found.
# The request is skipped when one is already pending or Copilot has already reviewed
# this exact head (see review_request_needed in lib/pr-review-lib.sh).
#
# Usage:
#   bin/await-copilot-review.sh [PR_NUMBER]
#   COPILOT_WAIT_SECS=300 bin/await-copilot-review.sh 88
#
# With no PR number, uses the PR for the current branch (gh pr view).
# Exit 0 whether or not comments were found (a clean review is not an error);
# exit 2 on usage/lookup failure.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=bin/lib/pr-review-lib.sh
. "$HERE/lib/pr-review-lib.sh"

WAIT="${COPILOT_WAIT_SECS:-240}"
POLL="${COPILOT_POLL_SECS:-15}"

read -r REPO PR < <(pr_resolve_repo_and_number "await-copilot-review" "${1:-}") || exit 2

# Ask before waiting. Set COPILOT_NO_REQUEST=1 to poll only (e.g. when a human already
# requested it and you just want the result).
if [ -z "${COPILOT_NO_REQUEST:-}" ]; then
  pr_request_review "$REPO" "$PR" 'copilot-pull-request-reviewer[bot]' 'copilot'
fi

# Copilot's login is "Copilot" on the comments API and "copilot-pull-request-reviewer[bot]"
# on the reviews API — a case-insensitive substring match catches both.
MATCH='.user.login | test("copilot"; "i")'

# Prefer a review OF THE CURRENT HEAD, so a re-run after a push waits for the fresh review
# rather than returning a stale earlier one. Fall back to "any Copilot review" if the head
# lookup fails.
HEAD="$(gh pr view "$PR" --json headRefOid -q .headRefOid 2>/dev/null || true)"
if [ -n "$HEAD" ]; then
  SELECT="($MATCH) and (.commit_id == \"$HEAD\")"
else
  SELECT="$MATCH"
fi

print_review() {
  # $1 = a Copilot review JSON object; prints its summary + the inline comments that belong to
  # THIS review (by pull_request_review_id) — not every Copilot comment ever posted, so a stale
  # earlier review's comments don't surface under a fresh, clean summary. --paginate: the reviews
  # /comments lists default to 30 per page.
  local review="$1" review_id comments count
  review_id="$(printf '%s' "$review" | jq -r '.id // 0')"
  comments="$(gh api --paginate "repos/$REPO/pulls/$PR/comments" 2>/dev/null \
    | jq -s "add // [] | [.[] | select(($MATCH) and (.pull_request_review_id == $review_id))]" 2>/dev/null || echo '[]')"
  count="$(printf '%s' "$comments" | jq 'length' 2>/dev/null || echo 0)"

  # Findings Copilot filed inside a collapsed "Suppressed comments" block. These are in the review
  # BODY only — the comments API never returns them — so a tool that counts inline comments reports
  # "nothing to address" while real defects sit unread. That happened on #284/#285: six findings,
  # two of them genuine bugs, under a summary saying the feedback was handled.
  local suppressed s_count
  suppressed="$(printf '%s' "[$review]" | suppressed_findings 2>/dev/null || true)"
  s_count="$(printf '%s' "$suppressed" | grep -c . || true)"

  echo "=== Copilot review on $REPO PR #$PR — ${count:-0} inline, ${s_count:-0} suppressed ==="
  printf '%s' "$review" | jq -r '.body // "(no summary body)"'
  echo
  if [ "${count:-0}" -gt 0 ]; then
    printf '%s' "$comments" | jq -r '.[] |
      "-- id=\(.id) | \(.path):\(.line // .original_line // "?")\n\(.body)\n"'
    echo "Reply in-thread: gh api repos/$REPO/pulls/$PR/comments/<id>/replies -f body=..."
  fi
  if [ "${s_count:-0}" -gt 0 ]; then
    echo
    echo "!! ${s_count} SUPPRESSED finding(s) — collapsed in the review body, NOT in the comments API:"
    printf '%s\n' "$suppressed" | sed 's/^/   /'
    echo "   These have no comment id, so they cannot be replied to in-thread — address them and"
    echo "   say so in a PR comment. bin/pr-reviews-done.sh will refuse until you acknowledge them."
  fi
  if [ "${count:-0}" -eq 0 ] && [ "${s_count:-0}" -eq 0 ]; then
    echo "(Copilot generated no inline or suppressed comments — nothing to address.)"
  fi
}

deadline=$(( $(date +%s) + WAIT ))
while :; do
  # --paginate + `jq -s add`: reviews default to 30/page, so a newer review of the current head
  # can land on a later page on long-lived PRs. Merge all pages before selecting the latest.
  review="$(gh api --paginate "repos/$REPO/pulls/$PR/reviews" 2>/dev/null \
    | jq -s "add // [] | [.[] | select($SELECT)] | last" 2>/dev/null || echo 'null')"

  if [ -n "$review" ] && [ "$review" != "null" ]; then
    print_review "$review"
    exit 0
  fi

  if [ "$(date +%s)" -ge "$deadline" ]; then
    # Timed out waiting for a review of the current head — fall back to the latest Copilot
    # review of ANY commit, so a re-review that targeted an earlier push isn't hidden.
    review="$(gh api --paginate "repos/$REPO/pulls/$PR/reviews" 2>/dev/null \
      | jq -s "add // [] | [.[] | select($MATCH)] | last" 2>/dev/null || echo 'null')"
    if [ -n "$review" ] && [ "$review" != "null" ]; then
      echo "(No Copilot review of the current commit after ${WAIT}s — showing the most recent one.)"
      print_review "$review"
    else
      echo "No Copilot review on $REPO PR #$PR after ${WAIT}s."
      echo "(Copilot may still be running or isn't enabled — re-run this script, or check the PR page.)"
    fi
    exit 0
  fi
  sleep "$POLL"
done
