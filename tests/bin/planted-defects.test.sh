#!/usr/bin/env bash
# bin/planted-defects.sh: a fixture script whose guards are tested, untested, or named by a stale manifest (L-0040).
source "$(dirname "$0")/_harness.sh"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/bin/planted-defects.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/t.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/tests"

# A gate with two refusals: an empty argument (tested) and a too-long one (not tested).
cat >"$TMP/bin/gate.sh" <<'EOF'
#!/usr/bin/env bash
[ -z "${1:-}" ] && { echo "empty" >&2; exit 3; }
[ "${#1}" -gt 9 ] && { echo "too long" >&2; exit 3; }
echo "ok"
EOF
cat >"$TMP/tests/gate.test.sh" <<'EOF'
#!/usr/bin/env bash
bash bin/gate.sh >/dev/null 2>&1; [ $? -eq 3 ] || exit 1
[ "$(bash bin/gate.sh abc)" = "ok" ] || exit 1
EOF
manifest() { # <auto-skip-json> <defects-json>
  printf '{"copy":["bin","tests"],"suites":{"bin/gate.sh":["tests/gate.test.sh"]},"auto":{"files":["bin/gate.sh"],"skip":%s},"defects":%s}\n' "$1" "$2" >"$TMP/tests/bin-planted.json"
}
run() { bash "$SCRIPT" --root "$TMP" --manifest tests/bin-planted.json --jobs 2 >"$TMP/out" 2>&1; echo $?; }

echo "planted-defects:"

manifest '[]' '[]'
assert_eq "1" "$(run)" "an untested refusal survives and fails the gate"
assert_contains "$TMP/out" "SURVIVED bin/gate.sh:3 refusal removed" "...naming the line of the untested refusal"
assert_contains "$TMP/out" "caught   bin/gate.sh:2 refusal removed" "...while the tested one is caught"

manifest '[{"file":"bin/gate.sh","contains":"too long","why":"fixture: no caller passes long input"}]' '[]'
assert_eq "0" "$(run)" "a refusal skipped with a reason no longer fails the gate"

manifest '[{"file":"bin/gate.sh","contains":"too long","why":"x"}]' '[{"file":"bin/gate.sh","find":"echo \"ok\"","replace":"echo \"OK\"","why":"output changed"}]'
assert_eq "0" "$(run)" "a semantic defect a test catches passes"
assert_contains "$TMP/out" "caught   output changed" "...and is reported caught"

manifest '[{"file":"bin/gate.sh","contains":"too long","why":"x"}]' '[{"file":"bin/gate.sh","find":"no such text","replace":"","why":"stale entry"}]'
assert_eq "1" "$(run)" "a manifest entry whose find text is gone fails the gate"
assert_contains "$TMP/out" "stale manifest" "...and says the manifest is stale"

printf '#!/usr/bin/env bash\nexit 1\n' >"$TMP/tests/gate.test.sh"
manifest '[]' '[]'
assert_eq "1" "$(run)" "a suite that already fails stops the run before any defect"
assert_contains "$TMP/out" "fails before any defect is planted" "...and says so, rather than counting every defect caught"

test_summary
