#!/usr/bin/env bash
# Every bin/**/*.sh must parse: a script that fails `bash -n` only fails when someone runs it.
source "$(dirname "$0")/_harness.sh"
ROOT="${SCRIPT_SYNTAX_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

bad=0; n=0
while IFS= read -r script; do
  n=$((n+1))
  if ! bash -n "$script" 2>/dev/null; then
    printf '  FAIL: %s does not parse\n' "${script#"$ROOT"/}"
    bad=$((bad+1))
  fi
done < <(find "$ROOT/bin" -type f -name '*.sh' | LC_ALL=C sort)

assert_eq "0" "$bad" "every bin/**/*.sh parses under bash -n"
# A glob that matches nothing would pass vacuously.
assert_eq "1" "$([ "$n" -ge 1 ] && echo 1 || echo 0)" "found scripts to check (${n})"

test_summary
