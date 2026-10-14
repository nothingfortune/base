#!/usr/bin/env bash
# Apply the GitHub settings a template cannot carry to a clone: they are repo settings, not files.
#
# Usage: bin/setup-github.sh [--repo owner/name] [--dry-run]
#   - ruleset on the default branch: required checks, no force-push, no deletion, no bypass
#   - auto-merge + delete-branch-on-merge
#   - vulnerability alerts + Dependabot security updates
#   - lists workflow secrets the repo does not have yet
# Idempotent. Exit: 0 ok, 1 a step failed, 2 usage, 3 ruleset cannot be enforced on this plan.
# SETUP_REQUIRED_CHECKS overrides the required check names (newline-separated).
set -uo pipefail

RULESET_NAME="default-branch-gate"
ACTIONS_APP_ID=15368
CHECKS="${SETUP_REQUIRED_CHECKS:-$'gate\ne2e / e2e'}"

usage() { sed -n '4,10p' "$0" | sed 's/^# \{0,1\}//'; }

REPO=""; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:-}"; [ -n "$REPO" ] || { usage >&2; exit 2; }; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

for bin in gh jq; do
  command -v "$bin" >/dev/null || { echo "setup-github: $bin is required" >&2; exit 1; }
done

if [ -z "$REPO" ]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" \
    || { echo "setup-github: cannot resolve the repo; pass --repo owner/name" >&2; exit 1; }
fi

failed=0; unenforced=0
ok()   { if [ "$DRY" = 1 ]; then printf '  plan  %s\n' "$1"; else printf '  ok    %s\n' "$1"; fi; }
bad()  { printf '  FAIL  %s\n' "$1"; failed=1; }

# Runs a mutating gh call, or prints it under --dry-run. Payload, if any, arrives on stdin.
mutate() {
  if [ "$DRY" = 1 ]; then
    printf '  dry-run: gh %s\n' "$*"
    [[ " $* " == *" --input - "* ]] && jq . | sed 's/^/    /'
    return 0
  fi
  gh "$@" >/dev/null
}

echo "setup-github: $REPO$([ "$DRY" = 1 ] && echo ' (dry run)')"

# --- Ruleset -----------------------------------------------------------------
checks_json="$(printf '%s\n' "$CHECKS" | jq -R . | jq -s --argjson app "$ACTIONS_APP_ID" \
  'map(select(length > 0) | {context: ., integration_id: $app})')"
ruleset="$(jq -n --arg name "$RULESET_NAME" --argjson checks "$checks_json" '{
  name: $name,
  target: "branch",
  enforcement: "active",
  bypass_actors: [],
  conditions: {ref_name: {include: ["~DEFAULT_BRANCH"], exclude: []}},
  rules: [
    {type: "deletion"},
    {type: "non_fast_forward"},
    {type: "required_status_checks", parameters: {
      strict_required_status_checks_policy: true,
      required_status_checks: $checks}}
  ]}')"

errfile="$(mktemp)"; trap 'rm -f "$errfile"' EXIT
if ! existing="$(gh api "repos/$REPO/rulesets" 2>"$errfile")"; then
  # Unknown is not empty: creating here could duplicate a ruleset we failed to see.
  bad "ruleset: could not list rulesets ($(tr -d '\n' <"$errfile"))"
else
  id="$(printf '%s' "$existing" | jq -r --arg n "$RULESET_NAME" '.[]? | select(.name == $n) | .id' | head -n1)"
  if [ -n "$id" ]; then verb=(-X PUT "repos/$REPO/rulesets/$id"); else verb=(-X POST "repos/$REPO/rulesets"); fi
  if err="$(printf '%s' "$ruleset" | mutate api "${verb[@]}" --input - 2>&1)"; then
    [ "$DRY" = 1 ] && printf '%s\n' "$err"
    ok "ruleset '$RULESET_NAME' $([ -n "$id" ] && echo updated || echo created): $(printf '%s' "$CHECKS" | paste -sd, -)"
  elif printf '%s' "$err" | grep -qiE 'upgrade to github pro|make this repository public'; then
    unenforced=1
    printf '  WARN  ruleset: this plan cannot enforce rulesets on a private repo.\n'
  else
    bad "ruleset: $err"
  fi
fi

# --- Repo settings -------------------------------------------------------------
if err="$(jq -n '{allow_auto_merge: true, delete_branch_on_merge: true}' \
  | mutate api -X PATCH "repos/$REPO" --input - 2>&1)"; then
  [ "$DRY" = 1 ] && printf '%s\n' "$err"
  ok "auto-merge and delete-branch-on-merge"
else
  bad "repo settings: $err"
fi

for endpoint in vulnerability-alerts automated-security-fixes; do
  if err="$(mutate api -X PUT "repos/$REPO/$endpoint" 2>&1)"; then
    [ "$DRY" = 1 ] && printf '%s\n' "$err"
    ok "$endpoint"
  else
    bad "$endpoint: $err"
  fi
done

# --- Secrets the workflows reference ---------------------------------------------
wanted="$(grep -ohE 'secrets\.[A-Z0-9_]+' .github/workflows/*.y*ml 2>/dev/null \
  | sed 's/^secrets\.//' | grep -vx GITHUB_TOKEN | sort -u || true)"
if [ -n "$wanted" ]; then
  if have="$(gh secret list --repo "$REPO" --json name --jq '.[].name' 2>/dev/null)"; then
    missing="$(comm -23 <(printf '%s\n' "$wanted") <(printf '%s\n' "$have" | sort -u) | grep . || true)"
    if [ -n "$missing" ]; then
      echo "  todo  workflow secrets not set on the repo (org secrets may cover them;"
      echo "        dormant workflows only need theirs once adopted):"
      printf '%s\n' "$missing" | sed 's/^/          missing secret: /'
    else
      ok "every workflow secret is set"
    fi
  else
    printf '  WARN  could not list secrets; workflows reference:\n'
    printf '%s\n' "$wanted" | sed 's/^/          /'
  fi
fi

if [ "$unenforced" = 1 ]; then
  cat >&2 <<'EOF'

Branch protection is NOT enforced on this repo. Required checks do nothing, so
`gh pr merge --auto` merges immediately without waiting for CI, and the
Dependabot auto-merge workflow will land red updates. Make the repo public,
move it to a paid plan, or merge only after `gh pr checks <pr> --watch` is green.
EOF
  exit 3
fi
exit "$failed"
