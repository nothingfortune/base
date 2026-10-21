#!/usr/bin/env bash
# Guards .claude/settings.json and keeps bin/ tests runnable inside a Claude Code sandbox.
source "$(dirname "$0")/_harness.sh"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
q() { node -e 'const s=require(process.argv[1]); console.log(JSON.stringify(eval("s"+process.argv[2])))' "$ROOT/.claude/settings.json" "$1"; }

# No sandbox by default: inside it on macOS, gh (which the review loop runs) cannot verify TLS.
assert_eq 'undefined' "$(q '.sandbox')" "the template does not turn the sandbox on"
deny() { assert_eq 'true' "$(q ".permissions?.deny?.includes('$1')")" "deny rule $1"; }
for rule in 'Edit(.claude/settings.json)' 'Edit(.claude/settings.local.json)' 'Edit(.claude/hooks/**)' \
   'Read(**/.env*)' 'Read(!**/.env*.example*)' 'Edit(**/.env*)' 'Edit(!**/.env*.example*)'; do
  deny "$rule"
done
# A ! carve-out only works listed after the rule it narrows.
assert_eq 'true' "$(q '.permissions.deny.indexOf("Read(!**/.env*.example*)") > s.permissions.deny.indexOf("Read(**/.env*)")')" "the .example carve-out follows the .env deny"
assert_eq '"node \"${CLAUDE_PROJECT_DIR}/.claude/hooks/guard-bash.mjs\""' \
  "$(q '.hooks?.PreToolUse?.find(h => h.matcher === "Bash")?.hooks?.[0]?.command')" "Bash commands pass through guard-bash.mjs"
# Claude Code never consults Write(path) rules; Edit(...) already covers the Write tool.
assert_eq 'false' "$(q '.permissions?.deny?.some(r => r.startsWith("Write("))')" "no dead Write(...) rules"
# macOS mktemp ignores $TMPDIR without a template, and the sandbox only allows writes under $TMPDIR.
bare="$(grep -rnE 'mktemp( -d)?\)' "$ROOT/bin" "$ROOT/tests/bin" "$ROOT/.githooks" || true)"
assert_eq '' "$bare" "every mktemp names a template under \$TMPDIR"
# A failed mktemp leaves the path empty, and the test then runs against the real repo.
unguarded="$(grep -rnF '$(mktemp' "$ROOT/bin" "$ROOT/tests/bin" "$ROOT/.githooks" | grep -vF '|| exit 1' || true)"
assert_eq '' "$unguarded" "a failed mktemp exits instead of running in the real repo"
test_summary
