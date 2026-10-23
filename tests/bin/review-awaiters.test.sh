#!/usr/bin/env bash
# Tests for bin/pr-unaddressed.sh, bin/await-codex-review.sh and bin/await-copilot-review.sh,
# with `gh` stubbed on PATH so no network and no PR is touched.
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/_harness.sh"

BIN="$DIR/../../bin"
STUB_DIR="$(mktemp -d "${TMPDIR:-/tmp}/t.XXXXXX")" || exit 1

# The stub answers from files in $STUB_DIR; a file holding exactly "FAIL" makes that endpoint error.
cat > "$STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
answer() { [ "$(cat "$STUB/$1")" = "FAIL" ] && exit 1; cat "$STUB/$1"; }
case "$*" in
  *"repo view"*)                 echo "acme/widgets" ;;
  *"pr view"*)                   echo "HEAD1" ;;
  *"issues/"*"/comments"*)       answer issue_comments ;;
  *"pulls/"*"/comments"*)        answer pull_comments ;;
  *"pulls/"*"/reviews"*)         answer reviews ;;
  *"requested_reviewers"*)       exit 0 ;;
  *"pulls/"*)                    echo '{"requested_reviewers":[]}' ;;
  *)                             echo "" ;;
esac
EOF
chmod +x "$STUB_DIR/gh"
stub() { printf '%s' "$2" > "$STUB_DIR/$1"; }
run() { STUB="$STUB_DIR" PATH="$STUB_DIR:$PATH" CODEX_WAIT_SECS=0 COPILOT_WAIT_SECS=0 bash "$@" >"$STUB_DIR/out" 2>&1; echo $?; }

STATE_HEAD1='[{"user":{"login":"chatgpt-codex-connector[bot]"},"body":"<!-- codex-review-state:v1 {\"code_review\":{\"commit_sha\":\"HEAD1\",\"status\":\"completed\"}} -->"}]'
STATE_OLD='[{"user":{"login":"chatgpt-codex-connector[bot]"},"body":"<!-- codex-review-state:v1 {\"code_review\":{\"commit_sha\":\"OLD\",\"status\":\"completed\"}} -->"}]'
OLD_FINDING='{"id":1,"in_reply_to_id":null,"user":{"login":"chatgpt-codex-connector[bot]"},"path":"a.ts","line":1,"original_commit_id":"OLD","body":"stale finding"}'
HEAD_FINDING='{"id":2,"in_reply_to_id":null,"user":{"login":"chatgpt-codex-connector[bot]"},"path":"b.ts","line":2,"original_commit_id":"HEAD1","body":"fresh finding"}'

echo "pr-unaddressed:"

# A deleted author's comment beside an unanswered finding must not read as "all replied".
stub pull_comments '[{"id":9,"in_reply_to_id":null,"user":null,"body":"ghost"},{"id":10,"in_reply_to_id":null,"user":{"login":"Copilot"},"path":"c.ts","line":3,"body":"unanswered"}]'
code="$(run "$BIN/pr-unaddressed.sh" 42)"
assert_eq "1" "$code" "a user:null comment does not hide an unanswered thread"
assert_contains "$STUB_DIR/out" "c.ts:3" "...and the unanswered thread is listed"

stub pull_comments 'not json'
code="$(run "$BIN/pr-unaddressed.sh" 42)"
assert_eq "2" "$code" "unparseable comments are an error, not 'all replied'"
assert_not_contains "$STUB_DIR/out" "have a reply" "...and it does not claim every thread has a reply"

echo "await-codex-review:"

# Paired with the next case: only the state marker's commit differs.
stub issue_comments "$STATE_OLD"; stub pull_comments "[$OLD_FINDING]"; stub reviews '[]'
code="$(run "$BIN/await-codex-review.sh" 42)"
assert_eq "0" "$code" "a review of an earlier commit times out cleanly"
assert_contains "$STUB_DIR/out" "No completed Codex review" "...and says the head is not reviewed yet"
assert_not_contains "$STUB_DIR/out" "stale finding" "...and does not pass off the earlier review's findings"

stub issue_comments "$STATE_HEAD1"; stub pull_comments "[$OLD_FINDING,$HEAD_FINDING]"
code="$(run "$BIN/await-codex-review.sh" 42)"
assert_eq "0" "$code" "a completed review of the head returns"
assert_contains "$STUB_DIR/out" "fresh finding" "...and prints the head's findings"
assert_not_contains "$STUB_DIR/out" "stale finding" "...and not an earlier commit's"

stub pull_comments "[$OLD_FINDING]"
code="$(run "$BIN/await-codex-review.sh" 42)"
assert_contains "$STUB_DIR/out" "filed no findings" "a clean review of the head is reported as clean"

stub pull_comments FAIL
code="$(run "$BIN/await-codex-review.sh" 42)"
assert_eq "2" "$code" "a failed comments fetch after a completed review exits 2"
assert_not_contains "$STUB_DIR/out" "filed no findings" "...and does not report the review as clean"

echo "await-copilot-review:"

stub reviews '[{"id":7,"user":{"login":"copilot-pull-request-reviewer[bot]"},"commit_id":"HEAD1","body":"summary"}]'
stub pull_comments '[{"id":3,"in_reply_to_id":null,"pull_request_review_id":7,"user":{"login":"Copilot"},"path":"d.ts","line":4,"body":"copilot finding"}]'
code="$(run "$BIN/await-copilot-review.sh" 42)"
assert_eq "0" "$code" "a Copilot review of the head returns"
assert_contains "$STUB_DIR/out" "copilot finding" "...and prints its inline finding"

stub pull_comments FAIL
code="$(run "$BIN/await-copilot-review.sh" 42)"
assert_eq "2" "$code" "a failed inline-comments fetch exits 2"
assert_not_contains "$STUB_DIR/out" "nothing to address" "...and does not report the review as clean"

rm -rf "$STUB_DIR"
test_summary
