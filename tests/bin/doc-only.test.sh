#!/usr/bin/env bash
# .github/scripts/doc-only.sh — the CI scope gate. Its fail-safe direction is
# load-bearing (undetermined scope must run the FULL gate, because the
# expensive lane is the required one), so every classification and the
# fail-safe are pinned here.
source "$(dirname "$0")/_harness.sh"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/.github/scripts/doc-only.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A scratch repo with a base commit to diff against.
REPO="$TMP/repo"
mkdir -p "$REPO/docs" "$REPO/src"
git -C "$REPO" init -q -b main
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
BASE_COMMIT="$(git -C "$REPO" rev-parse HEAD)"

run_scope() { # <expected doc_only=...> <message>  (call after staging a commit)
  local out
  out="$(cd "$REPO" && BASE_SHA="$BASE_COMMIT" GITHUB_OUTPUT=/dev/stdout bash "$SCRIPT" 2>/dev/null)"
  assert_eq "$1" "$out" "$2"
}

commit() { git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m x; }

# doc-only: docs/** and root *.md → skip allowed.
echo body > "$REPO/docs/note.md"; echo readme > "$REPO/README.md"
git -C "$REPO" add -A && commit
run_scope "doc_only=true" "docs/** + *.md classifies doc-only"

# mixed: a code file joins → full gate.
echo 'x' > "$REPO/src/a.ts"
git -C "$REPO" add -A && commit
run_scope "doc_only=false" "mixed doc+code classifies full-gate"

# filename with a SPACE containing .md-like fragment must not confuse the
# classifier (NUL-delimited diff): a code file named 'weird .md name.ts'.
echo 'y' > "$REPO/src/weird .md name.ts"
git -C "$REPO" add -A && commit
run_scope "doc_only=false" "spacey non-doc filename still classifies full-gate"

# fail-safe: unresolvable base → full gate, exit 0 (never blocks CI itself).
out="$(cd "$REPO" && BASE_SHA=0000000000000000000000000000000000000000 GITHUB_OUTPUT=/dev/stdout bash "$SCRIPT" 2>/dev/null)"; code=$?
assert_eq "doc_only=false" "$out" "zero SHA fail-safes to the full gate"
assert_eq "0" "$code" "fail-safe exits 0"

out="$(cd "$REPO" && BASE_SHA= GITHUB_OUTPUT=/dev/stdout bash "$SCRIPT" 2>/dev/null)"
assert_eq "doc_only=false" "$out" "unset base fail-safes to the full gate"

test_summary
