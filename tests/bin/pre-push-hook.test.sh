#!/usr/bin/env bash
# The pre-push gate's routing logic: which pushed refs get validated, which
# get warned about, which are ignored. The gated path itself (npm run check)
# is not exercised here — a stub `npm` on PATH records the call instead, so
# these tests stay fast and dependency-free.
source "$(dirname "$0")/_harness.sh"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/.githooks/pre-push"
ZERO="0000000000000000000000000000000000000000"

# Sandbox: a real git repo with one commit, and a stub npm that logs.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
(
  cd "$TMP"
  git init -q -b main
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
)
HEAD_SHA="$(git -C "$TMP" rev-parse HEAD)"
OTHER_SHA="1111111111111111111111111111111111111111"
mkdir -p "$TMP/stub"
printf '#!/usr/bin/env bash\necho "npm $*" >> "%s/npm.log"\nexit 0\n' "$TMP" > "$TMP/stub/npm"
chmod +x "$TMP/stub/npm"

run_hook() { # stdin: push lines; stdout/stderr -> $TMP/out; returns hook rc
  (cd "$TMP" && PATH="$TMP/stub:$PATH" bash "$HOOK") > "$TMP/out" 2>&1
}
reset_log() { rm -f "$TMP/npm.log"; touch "$TMP/npm.log"; }

# 1. Pushing HEAD runs the gate.
reset_log
run_hook <<< "refs/heads/main $HEAD_SHA refs/heads/main $ZERO"
assert_eq "0" "$?" "HEAD push exits 0 via stub check"
assert_contains "$TMP/npm.log" "npm run check" "HEAD push runs the gate"

# 2. Pushing only a non-HEAD ref skips the gate, with a per-ref warning.
reset_log
run_hook <<< "refs/heads/other $OTHER_SHA refs/heads/other $ZERO"
assert_eq "0" "$?" "non-HEAD push exits 0"
assert_contains "$TMP/out" "cannot validate refs/heads/other" "non-HEAD ref is warned about by name"
assert_not_contains "$TMP/npm.log" "npm run check" "non-HEAD push does not run the gate"

# 3. Multi-ref push: gate runs for HEAD, the other ref still gets its warning.
reset_log
run_hook <<EOF
refs/heads/main $HEAD_SHA refs/heads/main $ZERO
refs/heads/other $OTHER_SHA refs/heads/other $ZERO
EOF
assert_contains "$TMP/npm.log" "npm run check" "multi-ref push still gates HEAD"
assert_contains "$TMP/out" "cannot validate refs/heads/other" "multi-ref push warns for the unvalidated ref"

# 4. Ref deletion is ignored: no gate, no warning.
reset_log
run_hook <<< "(delete) $ZERO refs/heads/gone $OTHER_SHA"
assert_eq "0" "$?" "deletion push exits 0"
assert_not_contains "$TMP/out" "cannot validate" "deletion is not warned about"
assert_not_contains "$TMP/npm.log" "npm run check" "deletion does not run the gate"

# 5. Dirty tracked file: gate still runs, drift is surfaced by filename.
reset_log
echo tracked > "$TMP/f.txt"
git -C "$TMP" add f.txt
git -C "$TMP" -c user.email=t@t -c user.name=t commit -q -m f
HEAD_SHA="$(git -C "$TMP" rev-parse HEAD)"
echo drift > "$TMP/f.txt"
run_hook <<< "refs/heads/main $HEAD_SHA refs/heads/main $ZERO"
assert_contains "$TMP/out" "working tree differs" "drift warning appears"
assert_contains "$TMP/out" "f.txt" "drift warning names the drifted file"
assert_contains "$TMP/npm.log" "npm run check" "drifted tree still runs the gate"

test_summary
