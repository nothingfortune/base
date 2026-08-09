#!/usr/bin/env bash
# Tests for bin/lib/pr-review-lib.sh — the unaddressed-bot-thread logic (pure, no network).
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/_harness.sh"
# shellcheck source=bin/lib/pr-review-lib.sh
. "$DIR/../../bin/lib/pr-review-lib.sh"

echo "pr-review-lib (unaddressed_bot_threads):"

# Fixture — 4 top-level comments + replies:
#   100 codex[bot]   ← reply 200 from us (non-bot)  → ADDRESSED
#   101 Copilot      ← no reply                      → UNADDRESSED
#   102 copilot[bot] ← only reply 201 is a bot       → UNADDRESSED (bot chatter isn't our reply)
#   300 a human      (top-level, not a bot)          → IGNORED
fixture='[
  {"id":100,"in_reply_to_id":null,"user":{"login":"chatgpt-codex-connector[bot]"},"path":"a.php","line":10,"body":"finding A"},
  {"id":200,"in_reply_to_id":100,"user":{"login":"nothingfortune"},"path":"a.php","line":10,"body":"fixed in abc123"},
  {"id":101,"in_reply_to_id":null,"user":{"login":"Copilot"},"path":"b.ts","line":20,"body":"finding B\nsecond line"},
  {"id":102,"in_reply_to_id":null,"user":{"login":"copilot-pull-request-reviewer[bot]"},"path":"c.css","line":null,"original_line":30,"body":"finding C"},
  {"id":201,"in_reply_to_id":102,"user":{"login":"chatgpt-codex-connector[bot]"},"path":"c.css","line":30,"body":"bot chatter"},
  {"id":300,"in_reply_to_id":null,"user":{"login":"somehuman"},"path":"d.md","line":1,"body":"a human note"}
]'

out="$(printf '%s' "$fixture" | unaddressed_bot_threads)"
f="$(mktemp)"; printf '%s\n' "$out" > "$f"

assert_contains     "$f" $'101\t'                 "unaddressed Copilot thread (101) is listed"
assert_contains     "$f" $'102\t'                 "bot-only-reply thread (102) is listed"
assert_not_contains "$f" $'100\t'                 "addressed codex thread (100) is excluded"
assert_not_contains "$f" $'300\t'                 "human top-level comment (300) is ignored"
assert_contains     "$f" "finding B second line"  "multiline body collapsed to one line"
assert_contains     "$f" "c.css:30"               "null line falls back to original_line"
assert_eq "2" "$(printf '%s\n' "$out" | grep -c .)" "exactly 2 unaddressed threads"

empty="$(printf '[]' | unaddressed_bot_threads)"
assert_eq "" "$empty" "empty comment set → no unaddressed threads"

rm -f "$f"

echo
echo "pr_resolve_repo_and_number:"
errfile="$(mktemp)"

# gh stub: repo view resolves; pr view resolves (used when the pr-arg is omitted).
gh() {
  case "$1 $2" in
    "repo view") echo "acme/widgets" ;;
    "pr view")   echo "99" ;;
    *) return 1 ;;
  esac
}

out="$(pr_resolve_repo_and_number "myscript" "42" 2>"$errfile")"
assert_eq "acme/widgets 42" "$out" "explicit pr-arg wins over gh pr view"

out="$(pr_resolve_repo_and_number "myscript" "" 2>"$errfile")"
assert_eq "acme/widgets 99" "$out" "omitted pr-arg falls back to gh pr view"

# gh stub: repo view fails (not in a GitHub repo) -> usage error names the caller, exit 2.
gh() { return 1; }
out="$(pr_resolve_repo_and_number "myscript" "42" 2>"$errfile")"; code=$?
assert_eq "2"  "$code" "exit 2 when gh repo view fails"
assert_eq ""   "$out"  "no stdout when gh repo view fails"
assert_contains "$errfile" "myscript: not in a GitHub repo (gh repo view failed)." "repo-failure error names the caller script"

# gh stub: repo view resolves but both the pr-arg and gh pr view come up empty.
gh() {
  case "$1 $2" in
    "repo view") echo "acme/widgets" ;;
    "pr view")   return 1 ;;
    *) return 1 ;;
  esac
}
out="$(pr_resolve_repo_and_number "myscript" "" 2>"$errfile")"; code=$?
assert_eq "2"  "$code" "exit 2 when no PR can be resolved"
assert_eq ""   "$out"  "no stdout when no PR can be resolved"
assert_contains "$errfile" "usage: myscript.sh <pr-number>  (no PR found for the current branch)" "no-PR error is the usage line"

unset -f gh
rm -f "$errfile"
echo
echo "pr-review-lib (suppressed_findings):"

# Copilot files SOME findings as inline comments and others inside a collapsed
# "Suppressed comments" block in the review BODY. The latter never appear in the
# pull-request comments API, so every tool that reasoned about "the comments" reported
# "nothing to address" on reviews that contained real defects — six of them across
# #284/#285, two genuine bugs. This parser is what closes that hole.
reviews='[
  {"user":{"login":"copilot-pull-request-reviewer[bot]"},"body":"## Overview\n\n<details>\n<summary>Show a summary per file</summary>\n\n| File | Description |\n| decoy.php:1 | a table row, not a finding |\n\n</details>\n\n<details>\n<summary>Suppressed comments (2)</summary>\n\n**web/app/thing.php:148**\n* A real finding about a bug.\n```\ncode fence\n```\n**scripts/other.mts:12**\n* A second real finding.\n```\nmore\n```\n</details>\n"},
  {"user":{"login":"chatgpt-codex-connector[bot]"},"body":"### Codex Review\n\nNothing suppressed here."},
  {"user":{"login":"somehuman"},"body":"<details>\n<summary>Suppressed comments (1)</summary>\n\n**human/file.php:9**\n* a human wrote this\n</details>"}
]'

out="$(printf '%s' "$reviews" | suppressed_findings)"
f="$(mktemp)"; printf '%s\n' "$out" > "$f"

assert_contains     "$f" "web/app/thing.php:148"   "a suppressed finding is extracted with its location"
assert_contains     "$f" "A real finding about"    "...and its text"
assert_contains     "$f" "scripts/other.mts:12"    "a SECOND finding in the same block is extracted (not just the first)"
assert_not_contains "$f" "decoy.php"               "the per-file summary table is not mistaken for findings"
assert_not_contains "$f" "human/file.php"          "a non-bot review is ignored"
assert_eq "2" "$(grep -c . "$f")"                  "exactly the two bot findings, no more"

# A clean review must produce NOTHING — the gate below keys off emptiness, so a false
# positive here would block every merge.
clean='[{"user":{"login":"Copilot"},"body":"## Overview\n\nCopilot reviewed 6 files and generated no comments."}]'
empty="$(printf '%s' "$clean" | suppressed_findings | grep -c . || true)"
assert_eq "0" "$empty" "a review with no suppressed block yields no findings"

# Malformed/absent input must not explode — these run in a merge gate.
assert_eq "0" "$(printf '[]' | suppressed_findings | grep -c . || true)"        "an empty review list is handled"
assert_eq "0" "$(printf 'not json' | suppressed_findings | grep -c . || true)"  "non-JSON input is handled without failing"


echo
echo "pr-review-lib (review_request_needed):"

# The bug this guards: the awaiter scripts polled for a review nobody had requested,
# so they timed out forever. On #302 the review only arrived AFTER an explicit request.
none='{"requested_reviewers":[],"reviews":[]}'
assert_eq "request" "$(printf '%s' "$none" | review_request_needed "copilot" "abc123")" \
  "no pending request and no review → request"

pending='{"requested_reviewers":[{"login":"Copilot"}],"reviews":[]}'
assert_eq "skip" "$(printf '%s' "$pending" | review_request_needed "copilot" "abc123")" \
  "already in the pending queue → skip (re-requesting resets it)"

reviewed_head='{"requested_reviewers":[],"reviews":[{"user":{"login":"copilot-pull-request-reviewer[bot]"},"commit_id":"abc123"}]}'
assert_eq "skip" "$(printf '%s' "$reviewed_head" | review_request_needed "copilot" "abc123")" \
  "already reviewed THIS head → skip"

# The re-review case: a review exists, but of an older commit — so a fresh push must re-request.
reviewed_old='{"requested_reviewers":[],"reviews":[{"user":{"login":"copilot-pull-request-reviewer[bot]"},"commit_id":"OLDSHA"}]}'
assert_eq "request" "$(printf '%s' "$reviewed_old" | review_request_needed "copilot" "abc123")" \
  "reviewed an EARLIER commit → request again for the new head"

# A different bot's activity must not satisfy our reviewer's request.
other_bot='{"requested_reviewers":[{"login":"chatgpt-codex-connector[bot]"}],"reviews":[{"user":{"login":"chatgpt-codex-connector[bot]"},"commit_id":"abc123"}]}'
assert_eq "request" "$(printf '%s' "$other_bot" | review_request_needed "copilot" "abc123")" \
  "another bot's request/review does not count as ours"

# With no head sha known, a prior review can't be matched to a commit — ask again rather
# than skip, since a missed review is worse than a redundant request.
assert_eq "request" "$(printf '%s' "$reviewed_head" | review_request_needed "copilot" "")" \
  "unknown head → request rather than silently skip"

assert_eq "request" "$(printf '%s' '{}' | review_request_needed "copilot" "abc123")" \
  "missing keys degrade to request"

# REGRESSION (Codex P2 on #306): GitHub returns `user: null` for a review whose author
# account was deleted. `test()` on null makes jq ABORT (exit 5, no output), and the
# caller used to read that empty output as "skip" — silently reinstating the
# never-request bug on any PR carrying one such historical review.
null_user='{"requested_reviewers":[],"reviews":[{"user":null,"commit_id":"abc123"}]}'
assert_eq "request" "$(printf '%s' "$null_user" | review_request_needed "copilot" "abc123")" \
  "a review with user:null is a non-match, not a jq abort"

null_login='{"requested_reviewers":[{"login":null}],"reviews":[]}'
assert_eq "request" "$(printf '%s' "$null_login" | review_request_needed "copilot" "abc123")" \
  "a requested reviewer with login:null is a non-match, not a jq abort"

# A null author must not mask a REAL match sitting beside it in the same list.
null_plus_real='{"requested_reviewers":[],"reviews":[{"user":null,"commit_id":"abc123"},{"user":{"login":"Copilot"},"commit_id":"abc123"}]}'
assert_eq "skip" "$(printf '%s' "$null_plus_real" | review_request_needed "copilot" "abc123")" \
  "a null author alongside a genuine review still resolves to skip"

test_summary
