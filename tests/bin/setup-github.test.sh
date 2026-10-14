#!/usr/bin/env bash
# Tests for bin/setup-github.sh. `gh` is stubbed on PATH: no network, no repo is touched.
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/_harness.sh"

SCRIPT="$DIR/../../bin/setup-github.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
STUB="$TMP/stub"; mkdir -p "$STUB"

# A fixture checkout whose workflows reference two secrets.
FIX="$TMP/repo"; mkdir -p "$FIX/.github/workflows"
printf 'jobs:\n  x:\n    env:\n      A: ${{ secrets.CLOUDFLARE_API_TOKEN }}\n      B: ${{ secrets.NPM_TOKEN }}\n      C: ${{ secrets.GITHUB_TOKEN }}\n' >"$FIX/.github/workflows/w.yml"

# $1 GET rulesets behaviour (shell), $2 POST/PUT rulesets behaviour (shell), $3 secret names
make_gh_stub() {
  cat >"$STUB/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$TMP/calls"
if [[ " \$* " == *" --input - "* ]]; then n=\$(ls "$TMP"/payload-* 2>/dev/null | wc -l | tr -d ' '); cat >"$TMP/payload-\$n.json"; fi
case "\$*" in
  "repo view"*)                       echo "acme/widgets" ;;
  "api repos/acme/widgets/rulesets")  $1 ;;
  *"repos/acme/widgets/rulesets"*)    $2 ;;
  "secret list"*)                     printf '%s' "$3" ;;
  *)                                  echo '{}' ;;
esac
EOF
  chmod +x "$STUB/gh"
  rm -f "$TMP"/calls "$TMP"/payload-*
}

run() { (cd "$FIX" && PATH="$STUB:$PATH" bash "$SCRIPT" "$@" >"$TMP/out" 2>&1); echo $?; }

echo "setup-github:"

# 1. Fresh repo: creates the ruleset and applies every setting.
make_gh_stub "echo '[]'" "echo '{\"id\":1}'" "CLOUDFLARE_API_TOKEN"
code="$(run)"
assert_eq "0" "$code" "a fresh repo is set up (exit 0)"
assert_contains "$TMP/calls" "api -X POST repos/acme/widgets/rulesets" "...the ruleset is created with POST"
assert_eq "gate|e2e / e2e" "$(jq -r '[.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context] | join("|")' "$TMP/payload-0.json")" "...requiring gate and e2e / e2e"
assert_eq "15368" "$(jq -r '[.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].integration_id] | unique | join(",")' "$TMP/payload-0.json")" "...bound to the GitHub Actions app"
assert_eq "~DEFAULT_BRANCH" "$(jq -r '.conditions.ref_name.include[0]' "$TMP/payload-0.json")" "...on the default branch"
assert_eq "deletion,non_fast_forward,required_status_checks" "$(jq -r '[.rules[].type] | sort | join(",")' "$TMP/payload-0.json")" "...blocking deletion and force-push"
assert_eq "true" "$(jq -r '.rules[] | select(.type=="required_status_checks") | .parameters.strict_required_status_checks_policy' "$TMP/payload-0.json")" "...and requiring an up-to-date branch"
assert_eq "0" "$(jq -r '.bypass_actors | length' "$TMP/payload-0.json")" "...with no bypass actors"
assert_contains "$TMP/calls" "api -X PATCH repos/acme/widgets" "repo settings are patched"
assert_eq "true|true" "$(jq -r '[.allow_auto_merge, .delete_branch_on_merge] | map(tostring) | join("|")' "$TMP/payload-1.json")" "...turning on auto-merge and delete-branch-on-merge"
assert_contains "$TMP/calls" "api -X PUT repos/acme/widgets/vulnerability-alerts" "vulnerability alerts are enabled"
assert_contains "$TMP/calls" "api -X PUT repos/acme/widgets/automated-security-fixes" "Dependabot security updates are enabled"
assert_contains "$TMP/out" "NPM_TOKEN" "a workflow secret the repo lacks is listed"
assert_not_contains "$TMP/out" "missing secret: CLOUDFLARE_API_TOKEN" "...but one it has is not"
assert_not_contains "$TMP/out" "GITHUB_TOKEN" "...and GITHUB_TOKEN is never reported"

# 2. Re-run: an existing ruleset of the same name is updated in place, never duplicated.
make_gh_stub "echo '[{\"id\":7,\"name\":\"default-branch-gate\"}]'" "echo '{\"id\":7}'" ""
code="$(run)"
assert_eq "0" "$code" "a re-run succeeds"
assert_contains "$TMP/calls" "api -X PUT repos/acme/widgets/rulesets/7" "...updating ruleset 7 with PUT"
assert_not_contains "$TMP/calls" "-X POST" "...and creating nothing"

# 3. Private repo on a free plan: rulesets cannot be enforced; say so and exit 3.
make_gh_stub "echo '[]'" "echo 'gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)' >&2; exit 1" ""
code="$(run)"
assert_eq "3" "$code" "an unenforceable ruleset exits 3"
assert_contains "$TMP/out" "NOT enforced" "...and says protection is not enforced"
assert_contains "$TMP/out" "gh pr merge --auto" "...naming the auto-merge consequence"
assert_contains "$TMP/calls" "vulnerability-alerts" "...after still applying the other settings"

# 4. A failed rulesets lookup is unknown, not empty: create nothing, exit 1.
make_gh_stub "echo 'gh: HTTP 502' >&2; exit 1" "echo '{}'" ""
code="$(run)"
assert_eq "1" "$code" "a failed rulesets lookup fails"
assert_not_contains "$TMP/calls" "-X POST" "...without creating a possible duplicate"

# 5. --dry-run makes no mutating call and shows the payload.
make_gh_stub "echo '[]'" "echo '{}'" ""
code="$(run --dry-run)"
assert_eq "0" "$code" "--dry-run succeeds"
assert_not_contains "$TMP/calls" " -X " "...making no mutating call"
assert_contains "$TMP/out" "required_status_checks" "...and prints the ruleset it would send"

# 6. --repo skips the repo lookup; an unknown flag is a usage error.
make_gh_stub "echo '[]'" "echo '{}'" ""
run --repo acme/widgets >/dev/null
assert_not_contains "$TMP/calls" "repo view" "--repo is used as given"
assert_eq "2" "$(run --bogus)" "an unknown flag exits 2"

test_summary
