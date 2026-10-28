#!/usr/bin/env bash
# bin/fail-open-lint.sh: fixture scripts with and without silent network-read fallbacks (L-0029).
source "$(dirname "$0")/_harness.sh"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/bin/fail-open-lint.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/t.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin/lib"
run() { bash "$SCRIPT" --root "$TMP" >"$TMP/out" 2>&1; echo $?; }
fixture() { printf '%s\n' "$2" >"$TMP/bin/$1"; }

echo "fail-open-lint:"

fixture ok.sh 'if ! x="$(gh api repos/a/b 2>/dev/null)"; then echo "unreadable" >&2; exit 2; fi'
assert_eq "0" "$(run)" "a read whose failure exits is clean"

fixture bad.sh 'x="$(gh api repos/a/b 2>/dev/null || echo "[]")"'
assert_eq "1" "$(run)" "a gh api read falling back to [] fails"
assert_contains "$TMP/out" "bin/bad.sh:1" "...and names the file and line"

fixture bad.sh 'x="$(curl -s https://example.com/x || true)"'
assert_eq "1" "$(run)" "a curl read falling back to true fails"

fixture bad.sh 'buckets="$(gh pr checks 1 --json bucket 2>/dev/null || :)"'
assert_eq "1" "$(run)" "a CI rollup read falling back to : fails"

printf '%s\n' 'x="$(gh api --paginate repos/a/b 2>/dev/null \' '  | jq -s add || echo null)"' >"$TMP/bin/bad.sh"
assert_eq "1" "$(run)" "a fallback on a backslash-continued line is still found"
assert_contains "$TMP/out" "bin/bad.sh:1" "...and reported at the line the read starts on"

printf '%s\n' '# fail-open-ok: polling, unknown means not yet' 'x="$(gh api repos/a/b 2>/dev/null || echo null)"' >"$TMP/bin/bad.sh"
assert_eq "0" "$(run)" "a marker on the line before accepts the fallback"

fixture bad.sh 'x="$(gh api repos/a/b 2>/dev/null || echo null)"  # fail-open-ok: polling'
assert_eq "0" "$(run)" "a marker on the same line accepts the fallback"

fixture bad.sh 'x="$(gh api repos/a/b 2>/dev/null || echo null)"  # fail-open-ok:'
assert_eq "1" "$(run)" "a marker with no reason does not count"

fixture bad.sh '# x="$(gh api repos/a/b || echo null)"'
assert_eq "0" "$(run)" "a commented-out read is not a finding"

fixture bad.sh 'n="$(printf "%s" "$x" | grep -c . || true)"'
assert_eq "0" "$(run)" "a local count with || true is not a network read"
rm -f "$TMP/bin/bad.sh"

printf '%s\n' 'x="$(gh api repos/a/b || echo "[]")"' >"$TMP/bin/lib/helper.sh"
assert_eq "1" "$(run)" "bin/lib scripts are linted too"

test_summary
