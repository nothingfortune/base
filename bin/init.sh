#!/usr/bin/env bash
# Turn a fresh copy of the template into its own project, then delete this script.
#
# Usage: bin/init.sh <package-name> [--title "Title"] [--github]
#        bin/init.sh --check
#   <package-name>  npm name for package.json and the lockfile (lowercase)
#   --title         README title, used verbatim (default: the package name as given)
#   --github        also run bin/setup-github.sh (ruleset, auto-merge, security updates)
#   --check         only report template residue; exit 1 if any remains
# Runs once: it deletes the template's own docs, so it refuses a repo already renamed.
set -uo pipefail

usage() { sed -n '4,11p' "$0" | sed 's/^# \{0,1\}//'; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "init: not inside a git repo" >&2; exit 1; }
cd "$ROOT" || exit 1

residue() {
  local hits rc
  hits="$(git grep -nI --untracked -E \
    -e '^# base$' -e 'Template repository' -e '## Using this template' \
    -e 'template base repo' -e 'nothingfortune/base([^a-zA-Z0-9_.-]|$)' \
    -- . ':!bin/init.sh' ':!tests/bin/init.test.sh')"; rc=$?
  # git grep exits 1 for "no match" and >1 for an error; an error must not read as clean.
  [ "$rc" -le 1 ] || { echo "init: residue scan failed (git grep exit $rc)" >&2; return 2; }
  for f in package.json package-lock.json; do
    [ -f "$f" ] && [ "$(node -p 'require(process.argv[1]).name' "$ROOT/$f")" = "base" ] \
      && hits="${hits:+$hits$'\n'}$f: name is still \"base\""
  done
  if [ -n "$hits" ]; then
    echo "template residue:"
    printf '%s\n' "$hits" | sed 's/^/  /'
    return 1
  fi
}

NAME=""; TITLE=""; GITHUB=0; CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --title) TITLE="${2:-}"; [ -n "$TITLE" ] || { usage >&2; exit 2; }; shift 2 ;;
    --github) GITHUB=1; shift ;;
    --check) CHECK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; exit 2 ;;
    *) [ -z "$NAME" ] || { usage >&2; exit 2; }; NAME="$1"; shift ;;
  esac
done

if [ "$CHECK" = 1 ]; then residue; exit $?; fi

[ -n "$NAME" ] || { usage >&2; exit 2; }
if ! [[ "$NAME" =~ ^(@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*$ ]]; then
  echo "init: '$NAME' is not a valid npm package name (lowercase, digits, . _ -)" >&2
  exit 2
fi
TITLE="${TITLE:-$NAME}"

if [ "$(node -p 'require("./package.json").name')" != "base" ]; then
  echo "init: package.json is no longer named \"base\"; this repo was already initialized." >&2
  exit 1
fi

echo "init: $NAME ($TITLE)"

node -e '
  const fs = require("fs"), name = process.argv[1];
  for (const f of ["package.json", "package-lock.json"]) {
    if (!fs.existsSync(f)) continue;
    const j = JSON.parse(fs.readFileSync(f, "utf8"));
    j.name = name;
    if (j.packages && j.packages[""]) j.packages[""].name = name;
    fs.writeFileSync(f, JSON.stringify(j, null, 2) + "\n");
  }' "$NAME"
echo "  renamed package.json and package-lock.json"

# README: new title; drop the template description and its how-to section.
awk -v title="# $TITLE" '
  NR == 1 { print title; next }
  /^Template repository:/ { skipblank = 1; next }
  skipblank && /^$/ { skipblank = 0; next }
  { skipblank = 0 }
  /^## Using this template$/ { insection = 1; next }
  insection && /^## / { insection = 0 }
  !insection { print }
' README.md >README.md.tmp && mv README.md.tmp README.md
echo "  README: title set, template how-to removed"

awk '/template base repo/ { skipblank = 1; next } skipblank && /^$/ { skipblank = 0; next } { skipblank = 0; print }' \
  CLAUDE.md >CLAUDE.md.tmp && mv CLAUDE.md.tmp CLAUDE.md
echo "  CLAUDE.md: template banner removed"

# Only dated designs at the top level go; the suite and handoff READMEs describe the project's own folders.
find docs/toDo -name '*.md' -type f -print -delete 2>/dev/null | sed 's/^/  removed /'
find docs/designs -maxdepth 1 -name '*.md' -type f -print -delete 2>/dev/null | sed 's/^/  removed /'

rc=0
if ! residue; then rc=1; fi

if [ "$GITHUB" = 1 ]; then
  bash bin/setup-github.sh || { rc=$?; echo "init: setup-github.sh failed; re-run it directly once fixed." >&2; }
fi

rm -f bin/init.sh tests/bin/init.test.sh
echo "  removed bin/init.sh and its test (one-shot)"

cat <<EOF

Next:
  - fill in the Project section of CLAUDE.md and the README description
  - update the holder and year in LICENSE
  - $([ "$GITHUB" = 1 ] && echo "review the setup-github output above" || echo "run bin/setup-github.sh to apply the ruleset and repo settings")
  - adjust tsconfig.json for the project type (last section of CLAUDE.md)
  - keep .github/workflows/e2e.yml: the ruleset requires its check (or set
    SETUP_REQUIRED_CHECKS=gate when running bin/setup-github.sh without it)
  - npm run check, then commit
  - with the first real code: delete src/index.ts and its test, and set the
    coverage floors in vitest.config.ts ~1 point under measured, once
    (docs/guides/quality-gates.md)
EOF
exit "$rc"
