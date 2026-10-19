#!/usr/bin/env bash
# bin/comment-density.sh: a fixture workspace (packages/foo) mutated step by step against its baseline.
source "$(dirname "$0")/_harness.sh"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/bin/comment-density.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/t.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT

FIXTURE="$TMP/fixture"
BASELINE="$FIXTURE/comment-density-baseline.json"
SRC="$FIXTURE/packages/foo/src"
mkdir -p "$SRC"

run() { bash "$SCRIPT" --root "$FIXTURE" --baseline "$BASELINE" "$@"; }

# One 2-line `//` block: the initial, intentional baseline state.
cat >"$SRC/index.ts" <<'EOF'
// Step one of setup.
// Two-line explanation of why this exists.
export const value = 1;
EOF
run --update-baseline >/dev/null
assert_contains "$BASELINE" '"packages/foo": 1' "baseline generated from the initial fixture"

# (a) unchanged fixture, at baseline → exit 0, table prints the workspace.
OUT="$TMP/out.txt"
run >"$OUT" 2>&1; CODE=$?
assert_eq "0" "$CODE" "(a) at baseline exits 0"
assert_contains "$OUT" "packages/foo" "(a) the table prints the workspace"

# (b) a NEW two-line `//` block rises above baseline → exit 1, naming the workspace.
cat >>"$SRC/index.ts" <<'EOF'

// A brand new
// two-line comment block.
export const another = 2;
EOF
run >"$OUT" 2>&1; CODE=$?
assert_eq "1" "$CODE" "(b) a new // block fails"
assert_contains "$OUT" "packages/foo rose to 2" "(b) names the workspace and the new count"
assert_contains "$OUT" "new multi-line comments: keep a comment to one WHY line" "(b) explains the rule"
run --update-baseline >/dev/null

# (c) a NEW multi-line `/** */` block, same as (b) but for block comments.
cat >>"$SRC/index.ts" <<'EOF'

/**
 * Some non-exempt rationale for a design choice.
 */
export const third = 3;
EOF
run >"$OUT" 2>&1; CODE=$?
assert_eq "1" "$CODE" "(c) a new /** */ block fails"
assert_contains "$OUT" "packages/foo rose to 3" "(c) names the workspace and the new count"
run --update-baseline >/dev/null

# (d) a multi-line block carrying @public-api is EXEMPT: still at baseline, exit 0.
cat >>"$SRC/index.ts" <<'EOF'

/**
 * @public-api this stays stable across versions.
 * Second line of the same exempt block.
 */
export const fourth = 4;
EOF
run >"$OUT" 2>&1; CODE=$?
assert_eq "0" "$CODE" "(d) an @public-api block is exempt from the ratchet"

# (e) a `/*` inside a template literal is not a comment: the scanner must not count it.
cat >>"$SRC/index.ts" <<'EOF'

export const template = `text /* pretend
multi-line comment */ more text`;
EOF
run >"$OUT" 2>&1; CODE=$?
assert_eq "0" "$CODE" "(e) a /* inside a template literal is not counted"

# (f) removing a block falls BELOW baseline → exit 1, asking to lower the baseline.
cat >"$SRC/index.ts" <<'EOF'
// Step one of setup.
// Two-line explanation of why this exists.
export const value = 1;

/**
 * Some non-exempt rationale for a design choice.
 */
export const third = 3;

/**
 * @public-api this stays stable across versions.
 * Second line of the same exempt block.
 */
export const fourth = 4;

export const template = `text /* pretend
multi-line comment */ more text`;
EOF
run >"$OUT" 2>&1; CODE=$?
assert_eq "1" "$CODE" "(f) a removed block fails"
assert_contains "$OUT" "packages/foo fell to 2" "(f) names the workspace and the lower count"
assert_contains "$OUT" "lower comment-density-baseline.json packages/foo to 2" "(f) tells you how to fix it"

# (g) a workspace missing from the baseline fails, never silently skipped.
echo '{}' >"$BASELINE"
run >"$OUT" 2>&1; CODE=$?
assert_eq "1" "$CODE" "(g) a workspace missing from the baseline fails"
assert_contains "$OUT" "packages/foo is missing from comment-density-baseline.json" "(g) names the missing workspace"

# (h) blocks before a closing delimiter and at end of file are counted: no token owns them as node trivia.
rm -rf "$FIXTURE/packages/foo"
BAR="$FIXTURE/packages/bar/src"
mkdir -p "$BAR"
cat >"$BAR/index.ts" <<'EOF'
export function f(): number {
  return 1;
  // Trailing rationale, first line.
  // Trailing rationale, second line.
}
// End-of-file note, first line.
// End-of-file note, second line.
EOF
echo '{ "packages/bar": 0 }' >"$BASELINE"
run >"$OUT" 2>&1; CODE=$?
assert_eq "1" "$CODE" "(h) blocks before } and at EOF raise the count"
assert_contains "$OUT" "packages/bar rose to 2" "(h) both blocks are counted"

# (i) a single-package repo: root src/ is workspace `.`, alongside any apps/*/src.
SINGLE="$TMP/single"
mkdir -p "$SINGLE/src/lib" "$SINGLE/apps/web/src"
cat >"$SINGLE/src/lib/util.ts" <<'EOF'
// Nested files under root src/ count too,
// so this two-line block is one.
export const util = 1;
EOF
echo 'export const web = 1;' >"$SINGLE/apps/web/src/main.ts"
echo '{ ".": 0, "apps/web": 0 }' >"$SINGLE/baseline.json"
bash "$SCRIPT" --root "$SINGLE" --baseline "$SINGLE/baseline.json" >"$OUT" 2>&1; CODE=$?
assert_eq "1" "$CODE" "(i) a block under root src/ fails against a zero baseline"
assert_contains "$OUT" "comment-density: . rose to 1" "(i) root src/ reports as workspace ."
assert_not_contains "$OUT" "apps/web rose" "(i) apps/web stays at its baseline"

# (j) an unreadable baseline fails closed: every workspace reports missing.
echo 'not json' >"$SINGLE/baseline.json"
bash "$SCRIPT" --root "$SINGLE" --baseline "$SINGLE/baseline.json" >"$OUT" 2>&1; CODE=$?
assert_eq "1" "$CODE" "(j) an unparseable baseline fails"
assert_contains "$OUT" "apps/web is missing from comment-density-baseline.json" "(j) fails closed, not open"

# (k) no src/ anywhere is an error, not a vacuous pass.
mkdir -p "$TMP/empty"
bash "$SCRIPT" --root "$TMP/empty" --baseline "$TMP/empty/b.json" >"$OUT" 2>&1; CODE=$?
assert_eq "1" "$CODE" "(k) no workspaces found fails"
assert_contains "$OUT" "no workspaces with a src/ dir" "(k) says why"

test_summary
