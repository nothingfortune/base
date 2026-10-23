#!/usr/bin/env bash
# bin/git-isolation-check.sh: fixture suites that isolate git, leak into the exported GIT_DIR, or skip the harness (L-0103).
source "$(dirname "$0")/_harness.sh"
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$DIR/../../bin/git-isolation-check.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/t.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
SUITES="$TMP/suites"
mkdir -p "$SUITES"
cp "$DIR/_harness.sh" "$SUITES/_harness.sh"
run() { bash "$SCRIPT" --suites "$SUITES" --jobs 2 >"$TMP/out" 2>&1; echo $?; }

# Builds a throwaway repo the way repo-building suites do; safe only because the harness clears GIT_*.
cat >"$SUITES/clean.test.sh" <<'EOF'
#!/usr/bin/env bash
source "$(dirname "$0")/_harness.sh"
d="$(mktemp -d "${TMPDIR:-/tmp}/t.XXXXXX")" || exit 1; cd "$d" && git init -q && git config user.email t@t && git config user.name t && git add -A
rm -rf "$d"
EOF

echo "git-isolation-check:"

assert_eq "0" "$(run)" "a suite that sources the harness and builds a temp repo passes"

# The shape that set core.bare=true in two real checkouts: git init/config in a temp dir with GIT_DIR inherited.
cat >"$SUITES/leaky.test.sh" <<'EOF'
#!/usr/bin/env bash
d="$(mktemp -d "${TMPDIR:-/tmp}/t.XXXXXX")" || exit 1; cd "$d" && git init -q && git config user.email t@t && git config user.name t
rm -rf "$d"
EOF
assert_eq "1" "$(run)" "a suite that writes through an inherited GIT_DIR fails"
assert_contains "$TMP/out" "leaky.test.sh: changed the repository named by the exported GIT_DIR" "...and names the leak"
assert_contains "$TMP/out" "leaky.test.sh: does not source _harness.sh" "...and the missing harness"
assert_not_contains "$TMP/out" "clean.test.sh" "...without blaming the clean suite"
rm -f "$SUITES/leaky.test.sh"

printf '#!/usr/bin/env bash\necho "no git here"\n' >"$SUITES/plain.test.sh"
assert_eq "1" "$(run)" "a harmless suite that skips the harness still fails the static rule"
assert_contains "$TMP/out" "plain.test.sh: does not source _harness.sh" "...so a later git call cannot leak"
assert_not_contains "$TMP/out" "plain.test.sh: changed the repository" "...without claiming a leak that did not happen"
rm -f "$SUITES/plain.test.sh"

cat >"$SUITES/env-sensitive.test.sh" <<'EOF'
#!/usr/bin/env bash
source "$(dirname "$0")/_harness.sh"
[ -z "${GIT_DIR:-}" ] || exit 1
false
EOF
assert_eq "1" "$(run)" "a suite that fails under the exported GIT_DIR fails the check"
assert_contains "$TMP/out" "env-sensitive.test.sh: fails when GIT_DIR is exported" "...and says so"
rm -f "$SUITES/env-sensitive.test.sh"

assert_eq "0" "$(run)" "the clean suite alone passes again"

test_summary
