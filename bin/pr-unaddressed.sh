#!/usr/bin/env bash
#
# List the bot review-comment threads on a PR that we have NOT replied to.
#
# Complements await-codex-review.sh / await-copilot-review.sh (which surface the
# findings) and gates pr-reviews-done.sh: every bot inline comment should get an
# in-thread reply before "good to merge". Prints the open threads (with a ready-to-run
# reply command each) and exits:
#   0 — every bot thread has a reply from us (or there are no bot comments)
#   1 — one or more bot threads still lack our reply
#   2 — usage / not in a GitHub repo
# The non-zero exit makes it usable as a gate in scripts or CI.
#
# Usage:
#   bin/pr-unaddressed.sh [PR_NUMBER]     # no number → the PR for the current branch
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=bin/lib/pr-review-lib.sh
. "$HERE/lib/pr-review-lib.sh"

read -r REPO PR < <(pr_resolve_repo_and_number "pr-unaddressed" "${1:-}") || exit 2

# All inline review comments (paginated → one merged array). Fail CLOSED: a failed
# fetch must not be reported as "all addressed" (exit 0) — it's an error (exit 2).
if ! reviewcomments="$(gh api "repos/$REPO/pulls/$PR/comments" --paginate 2>/dev/null)"; then
  echo "pr-unaddressed: failed to fetch review comments for PR #$PR (gh api error)." >&2
  exit 2
fi
open="$(printf '%s' "$reviewcomments" | jq -s 'add // []' | unaddressed_bot_threads || true)"

if [ -z "$open" ]; then
  echo "✅ All bot review threads on PR #$PR have a reply."
  exit 0
fi

n="$(printf '%s\n' "$open" | grep -c . || true)"
echo "⚠️  $n unaddressed bot review thread(s) on PR #$PR (no reply from us):"
echo
printf '%s\n' "$open" | while IFS=$'\t' read -r id loc who snip; do
  printf '  • %s  %s\n      %s\n      reply: gh api repos/%s/pulls/%s/comments/%s/replies -f body=...\n\n' \
    "$who" "$loc" "$snip" "$REPO" "$PR" "$id"
done
exit 1
