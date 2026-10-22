#!/usr/bin/env bash
# Tests for bin/init.sh, run against a copy of this repo's real tracked tree.
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/_harness.sh"
ROOT="$(cd "$DIR/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/t.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT

fresh_clone() { # <dest> — the working tree as a clone would get it, minus node_modules
  mkdir -p "$1"
  (cd "$ROOT" && git ls-files -z --cached --others --exclude-standard | tar --null -T - -cf -) | tar -xf - -C "$1"
  git -C "$1" init -q -b main
  # Committed like a real clone, so init's deletions are tracked-but-missing files.
  git -C "$1" add -A && git -C "$1" -c user.email=t@t -c user.name=t commit -q --no-verify -m clone
}

echo "init:"

# 1. The residue check fires on the untouched template.
fresh_clone "$TMP/a"
(cd "$TMP/a" && bash bin/init.sh --check >"$TMP/out" 2>&1); code=$?
assert_eq "1" "$code" "--check fails on the untouched template"
assert_contains "$TMP/out" "package.json" "...naming the package name"
assert_contains "$TMP/out" "README.md" "...and the README"

# 2. init renames, strips the template's docs, passes its own check, and removes itself.
(cd "$TMP/a" && bash bin/init.sh my-app --title "My App" >"$TMP/out" 2>&1); code=$?
assert_eq "0" "$code" "init my-app succeeds"
assert_eq "my-app" "$(node -p 'require(process.argv[1]).name' "$TMP/a/package.json")" "package.json is renamed"
assert_eq "my-app|my-app" "$(node -p 'const l=require(process.argv[1]);l.name+"|"+l.packages[""].name' "$TMP/a/package-lock.json")" "...and both lockfile names"
assert_eq "# My App" "$(head -n1 "$TMP/a/README.md")" "README title uses --title verbatim"
assert_not_contains "$TMP/a/README.md" "Using this template" "README loses the template how-to"
assert_not_contains "$TMP/a/README.md" "Template repository" "...and the template description"
assert_contains "$TMP/a/README.md" "## Quickstart" "...but keeps the project sections"
assert_not_contains "$TMP/a/CLAUDE.md" "template base repo" "CLAUDE.md loses the template banner"
assert_contains "$TMP/a/CLAUDE.md" "npm run check" "...but keeps the conventions"
assert_eq "0" "$(find "$TMP/a/docs/toDo" "$TMP/a/docs/designs" -maxdepth 1 -name '*.md' | grep -c . || true)" "the template's plans and designs are gone"
assert_eq "0" "$(find "$TMP/a/docs/toDo/completed" -name '*.md' | grep -c . || true)" "...including completed plans"
assert_eq "11" "$([ -f "$TMP/a/docs/designs/suite/README.md" ] && echo 1)$([ -f "$TMP/a/docs/designs/handoff/README.md" ] && echo 1)" "...but the suite and handoff READMEs stay"
assert_eq "1" "$([ -f "$TMP/a/docs/guides/ci-budget.md" ] && echo 1 || echo 0)" "...but the guides stay"
assert_eq "1" "$([ -f "$TMP/a/docs/toDo/completed/.gitkeep" ] && echo 1 || echo 0)" "...and the empty folders stay"
assert_eq "0" "$([ -e "$TMP/a/bin/init.sh" ] || [ -e "$TMP/a/tests/bin/init.test.sh" ] && echo 1 || echo 0)" "init.sh and its test remove themselves"
assert_eq "1" "$([ -f "$TMP/a/bin/setup-github.sh" ] && echo 1 || echo 0)" "...leaving setup-github.sh for re-runs"
assert_not_contains "$TMP/out" "residue" "...after its residue check came back clean"
(cd "$TMP/a" && node scripts/check-docs.mjs >"$TMP/docs.out" 2>&1); code=$?
assert_eq "0" "$code" "docs:check passes straight after init, before anything is staged"

# 3. Title defaults to the name exactly as given.
fresh_clone "$TMP/b"
(cd "$TMP/b" && bash bin/init.sh widgets >/dev/null 2>&1)
assert_eq "# widgets" "$(head -n1 "$TMP/b/README.md")" "title defaults to the name as given"

# 4. An invalid npm name is a usage error and changes nothing.
fresh_clone "$TMP/c"
(cd "$TMP/c" && bash bin/init.sh "My App" >"$TMP/out" 2>&1); code=$?
assert_eq "2" "$code" "an invalid package name exits 2"
assert_eq "base" "$(node -p 'require(process.argv[1]).name' "$TMP/c/package.json")" "...leaving package.json alone"

# 5. A repo that is no longer the template is refused: init deletes docs, so it must run once.
fresh_clone "$TMP/d"
node -e 'const f=process.argv[1],p=require(f);p.name="already";require("fs").writeFileSync(f,JSON.stringify(p,null,2)+"\n")' "$TMP/d/package.json"
(cd "$TMP/d" && bash bin/init.sh other >"$TMP/out" 2>&1); code=$?
assert_eq "1" "$code" "init refuses a repo that is not the untouched template"
assert_eq "1" "$(find "$TMP/d/docs/toDo" -name '*.md' | grep -c . >/dev/null && echo 1 || echo 0)" "...deleting nothing"

# 6. --github hands off to setup-github.sh (stubbed here).
fresh_clone "$TMP/e"
printf '#!/usr/bin/env bash\necho "setup-github called: $*" >"%s/gh-called"\n' "$TMP" >"$TMP/e/bin/setup-github.sh"
(cd "$TMP/e" && bash bin/init.sh my-app --github >/dev/null 2>&1); code=$?
assert_eq "0" "$code" "init --github succeeds"
assert_eq "1" "$([ -f "$TMP/gh-called" ] && echo 1 || echo 0)" "...and runs setup-github.sh"

test_summary
