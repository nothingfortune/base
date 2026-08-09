#!/usr/bin/env bash
# Tests for bin/pr-reviews-done.sh's GATES — the conditions under which it refuses to post.
# It stubs `gh` on PATH, so no network and no PR is touched.
#
# This exists because the script's whole job is to make a claim ("reviews processed, good to
# merge") that someone else relies on. Every way it can make that claim WITHOUT having checked
# is a bug of the same shape as the one this file's sibling parser was written to fix.
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/_harness.sh"

SCRIPT="$DIR/../../bin/pr-reviews-done.sh"
STUB_DIR="$(mktemp -d)"

# $1 = how the reviews endpoint behaves: "fail" | a JSON payload
# $2 = (optional) JSON for the inline review-comments endpoint — default none
make_gh_stub() {
  local comments_json="${2:-[]}"
  cat > "$STUB_DIR/gh" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"pulls/"*"/reviews"*)  $1 ;;
  *"repo view"*)          echo "acme/widgets" ;;
  *"pulls/"*"/comments"*) printf '%s' '$comments_json' ;;
  *"pr checks"*)          echo "pass" ;;
  *"pr comment"*)         echo "POSTED: \$*" ;;
  *)                      echo "" ;;
esac
EOF
  chmod +x "$STUB_DIR/gh"
}

run_gate() { PATH="$STUB_DIR:$PATH" bash "$SCRIPT" "$@" >"$STUB_DIR/out" 2>&1; echo $?; }

echo "pr-reviews-done (gates):"

# 1. Reviews fetch FAILS → unknown, not zero. Posting "good to merge" here would be claiming
#    the suppressed findings were checked when the check never ran.
make_gh_stub 'exit 1'
code="$(run_gate 42)"
assert_eq "3" "$code" "a failed reviews fetch refuses to post (exit 3)"
assert_not_contains "$STUB_DIR/out" "POSTED" "...and posts nothing"

# 2. ...an explicit acknowledgement clears the suppressed-unknown gate, but findings are
#    still UNKNOWN — so the lessons gate (fail-closed like the others) demands a takeaway.
code="$(run_gate 42 --ack-suppressed)"
assert_eq "3" "$code" "--ack-suppressed alone still refuses: unknown findings need a takeaway"
assert_contains "$STUB_DIR/out" "lessons" "...and the refusal names the --lessons flag"
code="$(run_gate 42 --ack-suppressed --lessons "read in browser; none new: API outage class")"
assert_eq "0" "$code" "--ack-suppressed plus --lessons posts"
assert_contains "$STUB_DIR/out" "POSTED" "...and the summary is posted"

# 3. Reviews fetch SUCCEEDS with suppressed findings present → refuse and list them.
make_gh_stub "printf '%s' '[{\"user\":{\"login\":\"Copilot\"},\"body\":\"<details>\\n<summary>Suppressed comments (1)</summary>\\n\\n**a/b.php:7**\\n* a hidden finding\\n</details>\"}]'"
code="$(run_gate 42)"
assert_eq "3" "$code" "known suppressed findings refuse to post"
assert_contains "$STUB_DIR/out" "a/b.php:7" "...and name the finding so it can be acted on"

# 4. Reviews fetch succeeds and is CLEAN → the gate must not block a normal merge, and no
#    takeaway is demanded when there was nothing to take away.
make_gh_stub "printf '%s' '[{\"user\":{\"login\":\"Copilot\"},\"body\":\"reviewed, no comments\"}]'"
code="$(run_gate 42)"
assert_eq "0" "$code" "a clean review posts normally (no false positive)"
assert_contains "$STUB_DIR/out" "POSTED" "...and the summary is posted"

# 5. Inline bot findings (replied-to, so threads are addressed) still demand a takeaway:
#    a fixed bug is only half-processed until the testing gap that let it ship is named.
FINDINGS='[{"id":1,"in_reply_to_id":null,"user":{"login":"chatgpt-codex-connector[bot]"},"body":"a bug"},{"id":2,"in_reply_to_id":1,"user":{"login":"acme-dev"},"body":"Fixed in abc123"}]'
make_gh_stub "printf '%s' '[{\"user\":{\"login\":\"Copilot\"},\"body\":\"reviewed, no comments\"}]'" "$FINDINGS"
code="$(run_gate 42)"
assert_eq "3" "$code" "addressed findings without a takeaway refuse to post"
assert_contains "$STUB_DIR/out" "lessons" "...and the refusal names the --lessons flag"

# 6. The same PR posts once the takeaway is supplied, and the summary carries it.
code="$(run_gate 42 --lessons "strict calendar dates are now a Testing Rule")"
assert_eq "0" "$code" "findings + --lessons posts"
assert_contains "$STUB_DIR/out" "Testing takeaways" "...and the comment body carries the takeaways section"
assert_contains "$STUB_DIR/out" "strict calendar dates" "...with the supplied text"

rm -rf "$STUB_DIR"
test_summary
