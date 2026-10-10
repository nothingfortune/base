#!/usr/bin/env bash
# No database dump or archive is tracked: one commit puts its data in every clone and fork for good.
source "$(dirname "$0")/_harness.sh"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Intentional fixtures, as repo-relative paths.
ALLOWED=()

EXTS="sql sql.gz dump sqlite sqlite3 db tar tar.gz tgz zip"

dumps() { # <repo> [allowed-path...] — prints tracked dump/archive paths, sorted
  local repo="$1"; shift
  git -C "$repo" ls-files -z | while IFS= read -r -d '' f; do
    shopt -s nocasematch
    for ext in $EXTS; do
      case "$f" in *."$ext")
        local allowed=0 a
        for a in "$@"; do [ "$a" = "$f" ] && allowed=1; done
        [ "$allowed" -eq 1 ] || printf '%s\n' "$f"
        break ;;
      esac
    done
  done | LC_ALL=C sort
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# This repo: nothing tracked.
found="$(dumps "$ROOT" ${ALLOWED[@]+"${ALLOWED[@]}"})"
assert_eq "" "$found" "no dump or archive is tracked (allow intentional fixtures in ALLOWED)"

# .gitignore keeps every guarded extension from being added by accident.
unignored=""
for ext in $EXTS; do
  git -C "$ROOT" check-ignore -q --no-index "probe.$ext" || unignored="$unignored *.$ext"
done
assert_eq "" "$unignored" ".gitignore ignores every guarded extension"

# Planted: force-added dumps in a throwaway repo are found, case-insensitively, minus the allowlist.
PLANT="$TMP/plant"
git init -q "$PLANT"
mkdir -p "$PLANT/data" "$PLANT/fixtures"
for f in dump.sql data/app.sqlite3 backup.tar.gz EXPORT.ZIP fixtures/seed.sql notes.md; do
  : >"$PLANT/$f"
done
git -C "$PLANT" add -f -- .
found="$(dumps "$PLANT" fixtures/seed.sql)"
assert_eq "$(printf '%s\n' EXPORT.ZIP backup.tar.gz data/app.sqlite3 dump.sql)" "$found" \
  "planted dumps are reported, the allowlisted fixture is not"

# Control: names that merely contain a guarded extension are not dumps.
CTRL="$TMP/ctrl"
git init -q "$CTRL"
mkdir -p "$CTRL/sql"
for f in database.ts dump.sql.md sql/README.md zipper.ts; do
  : >"$CTRL/$f"
done
git -C "$CTRL" add -- .
assert_eq "" "$(dumps "$CTRL")" "lookalike names are not reported"

test_summary
