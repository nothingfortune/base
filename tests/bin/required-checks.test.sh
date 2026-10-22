#!/usr/bin/env bash
# Every check the ruleset requires must be reported on every PR, or the PR is blocked forever.
source "$(dirname "$0")/_harness.sh"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKFLOWS="$ROOT/.github/workflows"

# Lines of top-level job <job> in a workflow file (indented two spaces under jobs:).
job_block() { # <file> <job>
  awk -v job="  $2:" '
    /^jobs:/ { injobs = 1; next }
    injobs && $0 == job { inblock = 1; next }
    inblock && /^  [^ #]/ { exit }
    inblock { print }
  ' "$1"
}

# The required checks setup-github.sh applies by default.
checks="$(sed -n "s/^CHECKS=\"\${SETUP_REQUIRED_CHECKS:-\$'\(.*\)'}\"$/\1/p" "$ROOT/bin/setup-github.sh" | sed 's/\\n/\n/g')"

echo "required checks:"
assert_eq "gate
e2e / e2e" "$checks" "setup-github.sh requires gate and e2e / e2e"
while IFS= read -r ctx; do
  case "$ctx" in
    *" / "*)
      # A skipped job that calls a reusable workflow reports as "<job>", never "<job> / <job>".
      caller="${ctx%% / *}"
      file="$(grep -lE "^  $caller:$" "$WORKFLOWS"/*.yml | head -n1)"
      block="$(job_block "$file" "$caller")"
      assert_contains <(printf '%s\n' "$block") "uses: " "'$ctx' comes from a job calling a reusable workflow"
      assert_eq "" "$(printf '%s\n' "$block" | grep -E '^    if:')" "...with no job-level if:, so the check exists even when nothing runs"
      ;;
    *)
      file="$(grep -lE "^  $ctx:$" "$WORKFLOWS"/*.yml | head -n1)"
      assert_eq "1" "$([ -n "$file" ] && echo 1 || echo 0)" "'$ctx' is a job in some workflow"
      ;;
  esac
done <<<"$checks"
test_summary
