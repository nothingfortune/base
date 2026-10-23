#!/usr/bin/env bash
#
# Post a summary comment on a PR once all AI-review feedback has been processed.
#
# Run this at the END of the review loop — after await-codex-review.sh and
# await-copilot-review.sh have been fetched, every finding addressed, and each
# thread replied to. It posts one issue-comment signalling reviewers that the
# Codex + Copilot feedback is handled, and reports the live CI state so the
# "good to merge" claim is honest (it won't say ready if checks fail/run).
#
# Usage:
#   bin/pr-reviews-done.sh [PR_NUMBER] [extra note] [--ack-suppressed] [--lessons "<takeaway>"]
#   SUPPRESSED_ACK=1 LESSONS="..." bin/pr-reviews-done.sh 285
#
# With no PR number, uses the PR for the current branch (gh pr view).
# --ack-suppressed asserts you have read and handled the findings Copilot filed inside collapsed
# "Suppressed comments" blocks; without it this refuses to post when any exist (exit 3).
# --lessons is REQUIRED whenever the reviews produced any finding at all: the loop's last step is
# deciding what testing-strategy or test change keeps that bug class from recurring — posted as a
# "Testing takeaways" section. "None new" is a valid takeaway, but it must be said explicitly
# (e.g. --lessons "none new: both findings are the counts-vs-records class CLAUDE.md already owns").
# Otherwise it must cite the L-NNNN that the lessons MCP add_lesson/add_origin returned (checked on the lessons repo's main).
set -euo pipefail

# Flags are stripped before positional parsing so `--ack-suppressed` / `--lessons` can be passed
# with or without a PR number and are never mistaken for one.
ACK="${SUPPRESSED_ACK:-}"
LESSONS="${LESSONS:-}"
ARGS=()
expect_lessons=""
for arg in "$@"; do
  if [ -n "$expect_lessons" ]; then LESSONS="$arg"; expect_lessons=""; continue; fi
  case "$arg" in
    --ack-suppressed) ACK=1 ;;
    --lessons=*)      LESSONS="${arg#--lessons=}" ;;
    --lessons)        expect_lessons=1 ;;
    *)                ARGS+=( "$arg" ) ;;
  esac
done

NOTE="${ARGS[1]:-}"

# shellcheck source=bin/lib/pr-review-lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/pr-review-lib.sh"
read -r REPO PR < <(pr_resolve_repo_and_number "pr-reviews-done" "${ARGS[0]:-}") || exit 2

# Unaddressed bot review threads — every bot inline comment should have our reply before
# this claims the review is done. Reuses the tested pure helper (bin/lib/pr-review-lib.sh).
# Fail CLOSED: a failed comment fetch (auth/rate-limit/network) must NOT read as
# "0 unaddressed" — that would let the gate pass without ever verifying threads.
if reviewcomments="$(gh api "repos/$REPO/pulls/$PR/comments" --paginate 2>/dev/null)"; then
  unaddressed_n="$(printf '%s' "$reviewcomments" | jq -s 'add // []' | unaddressed_bot_threads | grep -c . || true)"
else
  unaddressed_n="?"   # fetch failed → unknown; treated as not-ready in the verdict below
fi

# Findings filed inside a collapsed "Suppressed comments" block. These live in the review BODY and
# are NEVER returned by the comments API, so the thread check above cannot see them and they have no
# id to reply to. On #284/#285 that meant this script posted "Reviews processed and CI is green —
# good to merge" over six unread findings, two of which were genuine bugs.
#
# They can't be auto-verified as addressed — there is no thread to look for a reply in — so the gate
# is an explicit acknowledgement: pass --ack-suppressed (or SUPPRESSED_ACK=1) once you have actually
# read and handled them. Fail CLOSED on a fetch error, same as the thread check.
if reviewsjson="$(gh api "repos/$REPO/pulls/$PR/reviews" --paginate 2>/dev/null)"; then
  suppressed="$(printf '%s' "$reviewsjson" | jq -s 'add // []' | suppressed_findings || true)"
  suppressed_n="$(printf '%s' "$suppressed" | grep -c . || true)"
else
  suppressed="" ; suppressed_n="?"
fi

# Unknown (fetch failed) is NOT the same as zero. Without this the script skipped the refusal
# below, skipped every verdict branch, and posted "good to merge" having inspected nothing —
# the exact shape of the bug this whole change is about, in the code fixing it (Codex, #286).
# An explicit acknowledgement still overrides, because the operator may have read the reviews
# in the browser when the API was down.
if [ "$suppressed_n" = "?" ] && [ -z "$ACK" ]; then
  echo "Refusing to post: could not fetch reviews for $REPO PR #$PR, so suppressed findings are UNKNOWN." >&2
  echo "Copilot files some findings in collapsed blocks that never reach the comments API, so an" >&2
  echo "unverified fetch cannot be reported as 'no findings'. Retry, or pass --ack-suppressed if" >&2
  echo "you have read the reviews yourself." >&2
  exit 3
fi

if [ "${suppressed_n:-0}" -gt 0 ] && [ -z "$ACK" ]; then
  echo "Refusing to post: ${suppressed_n} suppressed finding(s) on $REPO PR #$PR have not been acknowledged." >&2
  echo >&2
  printf '%s\n' "$suppressed" | sed 's/^/  /' >&2
  echo >&2
  echo "These are collapsed in the review body and never appear in the comments API, so nothing" >&2
  echo "else in this loop can see them. Address them, then re-run with --ack-suppressed." >&2
  exit 3
fi

# Refuse before the lessons gate: a takeaway cannot honestly be written for an unread finding.
if [ "$unaddressed_n" = "?" ]; then
  echo "Refusing to post: could not fetch review comments for $REPO PR #$PR, so unaddressed" >&2
  echo "threads are UNKNOWN. A failed fetch is never 'nothing to address'. Retry once the API answers." >&2
  exit 3
fi

if [ "$unaddressed_n" -gt 0 ]; then
  echo "Refusing to post: ${unaddressed_n} bot review thread(s) on $REPO PR #$PR have no reply from us." >&2
  echo >&2
  echo "List them with:  bin/pr-unaddressed.sh $PR" >&2
  echo "address each one, reply in-thread, then re-run this." >&2
  exit 3
fi

# Findings demand a takeaway. A review that surfaced bugs is only half-processed once the code is
# fixed — the class of bug is still open until the testing strategy (or a test) closes it, so this
# refuses to declare the loop done without one. Counts every top-level bot finding (inline threads
# + suppressed); unknown counts (failed fetches) require a takeaway too, same fail-closed posture
# as the other gates. "None new" is acceptable but must be stated, with the reason.
if [ "$unaddressed_n" = "?" ] || [ "$suppressed_n" = "?" ]; then
  findings_n="?"
else
  findings_n="$(printf '%s' "$reviewcomments" | jq -s 'add // [] | [.[] | select(.in_reply_to_id == null) | select((.user.login // "") | test("copilot|codex"; "i"))] | length')"
  findings_n=$(( findings_n + suppressed_n ))
fi
if { [ "$findings_n" = "?" ] || [ "${findings_n:-0}" -gt 0 ]; } && [ -z "$LESSONS" ]; then
  echo "Refusing to post: the reviews on $REPO PR #$PR produced ${findings_n} finding(s), and no testing" >&2
  echo "takeaway was given. Every finding is a bug some test layer failed to catch — decide what" >&2
  echo "testing-strategy or test change prevents that class from recurring (or state why existing" >&2
  echo "coverage already owns it) and re-run with:" >&2
  echo "  bin/pr-reviews-done.sh $PR --lessons \"<what changes in the tests/strategy, or 'none new: <why>'>\"" >&2
  exit 3
fi

# Uncited takeaways die in this PR comment; ids are looked up (fail closed) because a regex accepts unwritten ones.
LESSONS_REPO="${LESSONS_REPO:-hestiamediagroup/engineering-lessons}"
LESSONS_PATH="plugins/engineering-lessons/skills/lessons/lessons"
lesson_links=""
if [ -n "$LESSONS" ]; then
  # Whole tokens at a word boundary: a typo like L-0082oops must refuse, not verify as L-0082; CALL-410 is a ticket.
  cited="$(printf '%s' "$LESSONS" | grep -oE '(^|[^[:alnum:]_-])L-[[:alnum:]_-]+' | sed -E 's/^[^L]//' | sort -u || true)"
  malformed="$(printf '%s\n' "$cited" | grep -vE '^(L-[0-9]{4})?$' || true)"
  if [ -n "$malformed" ]; then
    echo "Refusing to post: malformed lesson id(s): $(printf '%s' "$malformed" | tr '\n' ' ')- ids are exactly L- plus four digits." >&2
    exit 3
  fi
  if [ -z "$cited" ]; then
    if ! printf '%s' "$LESSONS" | grep -qiE 'none new: *[^ ]'; then
      echo "Refusing to post: the takeaway cites no lesson id and is not 'none new: <why>'." >&2
      echo "Record it in the shared lessons first, with the lessons MCP server's tools (plugin" >&2
      echo "engineering-lessons): search_lessons for an existing rule, then add_origin (it happened again)" >&2
      echo "or add_lesson (new bug class). Re-run citing the id they return:" >&2
      echo "  bin/pr-reviews-done.sh $PR --lessons \"L-NNNN: <what changes in the tests/strategy>\"" >&2
      exit 3
    fi
  else
    if ! names="$(gh api "repos/$LESSONS_REPO/contents/$LESSONS_PATH?ref=main" --jq '.[].name' 2>/dev/null)" || [ -z "$names" ]; then
      echo "Refusing to post: could not list lessons on $LESSONS_REPO main, so the cited ids are UNVERIFIED." >&2
      echo "A failed lookup is not proof they exist. Retry once the API answers (this needs gh access to" >&2
      echo "$LESSONS_REPO)." >&2
      exit 3
    fi
    for id in $cited; do
      file="$(printf '%s\n' "$names" | grep -E "^${id}-.*\.md$" | head -1 || true)"
      if [ -z "$file" ]; then
        echo "Refusing to post: $id is not on $LESSONS_REPO main. Cite the id add_lesson / add_origin returned" >&2
        echo "after it merged, not one you expect it to get." >&2
        exit 3
      fi
      lesson_links="${lesson_links}${lesson_links:+, }[${id}](https://github.com/${LESSONS_REPO}/blob/main/${LESSONS_PATH}/${file})"
    done
  fi
fi

# A check that skips on draft PRs must actually have RUN on a PR that is ready to merge. GitHub
# counts a skipped job as satisfying a required check — so a PR marked ready right after its final
# push can carry a draft-era SKIP straight through branch protection with the check never having
# run on the merging commit. (Found the hard way in the repo this script came from.)
#
# Set DRAFT_SKIPPED_CHECK to the caller's job name (here `e2e`). A reusable-workflow job reports as
# "<job> / <inner>" when it runs but as plain "<job>" when skipped, so both names are matched.
#
# Fail CLOSED, like the other two gates: a lookup failure is not permission to proceed.
# Sorted by startedAt, NOT array order: the rollup lists a draft-era SKIP alongside a newer run, and
# taking `last` picked the older of the two — reporting SKIPPED while the real run was in progress.
# A run not yet started (startedAt null, or gh's zero time 0001-01-01) is the newest, so it sorts last.
DRAFT_SKIPPED_CHECK="${DRAFT_SKIPPED_CHECK:-}"
if [ -n "$DRAFT_SKIPPED_CHECK" ]; then
  if e2e_state="$(gh pr view "$PR" --json isDraft,statusCheckRollup \
    --jq "[.isDraft, ([.statusCheckRollup[]? | select(.name == \"$DRAFT_SKIPPED_CHECK\" or ((.name // \"\") | startswith(\"$DRAFT_SKIPPED_CHECK / \")))] | sort_by(.startedAt // \"\" | if . == \"\" or startswith(\"0001-\") then \"9999\" else . end) | last | if . == null then \"MISSING\" else (.conclusion // .status // \"RUNNING\") end)] | @tsv" 2>/dev/null)"; then
    is_draft="$(printf '%s' "$e2e_state" | cut -f1)"
    e2e_conclusion="$(printf '%s' "$e2e_state" | cut -f2)"
  else
    is_draft="?" ; e2e_conclusion="?"
  fi

  # Only SKIPPED/absent is refused here. A run still in flight is not a hazard — the CI rollup below
  # already reports "checks still running", so double-refusing it would just be noise.
  if [ "$is_draft" = "false" ] && { [ "$e2e_conclusion" = "SKIPPED" ] || [ "$e2e_conclusion" = "MISSING" ]; }; then
    echo "Refusing to post: '${DRAFT_SKIPPED_CHECK}' is '${e2e_conclusion}' on a PR that is no longer a draft." >&2
    echo >&2
    echo "Drafts skip that job on purpose, and GitHub treats a skipped job as satisfying a required" >&2
    echo "check — so this would merge without it ever running on the merging commit. Re-trigger" >&2
    echo "it (push a commit, or 'gh pr ready --undo' then 'gh pr ready') and wait for it to pass." >&2
    exit 3
  fi
fi

# Live CI rollup from the machine-readable buckets (pass|fail|pending|skipping|cancel). Claim
# "green" only when at least one check is reported AND none are failing/cancelled/pending —
# an empty or errored rollup ("no checks reported yet", API/auth failure) must NOT read as
# merge-ready. skipping counts as ok (e.g. real-WP e2e skips on docs-only PRs).
buckets="$(gh pr checks "$PR" --json bucket -q '.[].bucket' 2>/dev/null || true)"
total="$(  printf '%s\n' "$buckets" | grep -c .          || true)"
blocked="$(printf '%s\n' "$buckets" | grep -cxE 'fail|cancel' || true)"
pending="$(printf '%s\n' "$buckets" | grep -cx  'pending'     || true)"

# Every thread is answered past the gates above, so the verdict is about CI only.
if [ "${total:-0}" -eq 0 ]; then
  verdict="Reviews processed. **No CI checks reported yet** — verify CI is green before merging."
elif [ "${blocked:-0}" -gt 0 ]; then
  verdict="Reviews processed, but **${blocked} CI check(s) failing/cancelled** — not ready to merge yet."
elif [ "${pending:-0}" -gt 0 ]; then
  verdict="Reviews processed. **${pending} check(s) still running** — mergeable once CI is green."
else
  verdict="Reviews processed and **CI is green — good to merge.** ✅"
fi

body="🤖 ${verdict}

All Codex & GitHub Copilot review feedback has been addressed and replied to in-thread."
if [ "$suppressed_n" != "?" ] && [ "${suppressed_n:-0}" -gt 0 ]; then
  # Say so explicitly: these were handled without a thread, so the claim above would otherwise
  # be resting on evidence a reader cannot check.
  body="${body}
Includes ${suppressed_n} finding(s) filed in collapsed \"Suppressed comments\" blocks, which have no
thread to reply in — those are answered in a PR comment instead."
fi
if [ -n "$LESSONS" ]; then
  body="${body}

**Testing takeaways:** ${LESSONS}"
  if [ -n "$lesson_links" ]; then
    body="${body}
Recorded in engineering-lessons: ${lesson_links}"
  fi
fi
if [ -n "$NOTE" ]; then
  body="${body}

${NOTE}"
fi

gh pr comment "$PR" --body "$body"
echo "Posted reviews-done summary to $REPO PR #$PR."
