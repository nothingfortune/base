#!/usr/bin/env bash
# The design suite deploys to Cloudflare Pages as a private preview; the handoff package never does.
source "$(dirname "$0")/_harness.sh"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SUITE="$ROOT/docs/designs/suite"
WF="$ROOT/.github/workflows/deploy-design-preview.yml"

echo "design suite:"
assert_eq "1" "$([ -f "$SUITE/index.html" ] && echo 1 || echo 0)" "the suite has an index.html entry point"
assert_contains "$SUITE/index.html" 'name="robots"' "...with a robots meta tag"
assert_contains "$SUITE/index.html" 'content="noindex, nofollow' "...that asks not to be indexed"
# The header covers images and assets too, which a <meta robots> cannot.
assert_contains "$SUITE/_headers" "/*" "_headers applies to every path"
assert_contains "$SUITE/_headers" "X-Robots-Tag: noindex, nofollow" "...sending X-Robots-Tag noindex"
assert_contains "$SUITE/robots.txt" "User-agent: *" "robots.txt addresses every crawler"
assert_contains "$SUITE/robots.txt" "User-agent: ClaudeBot" "...and AI crawlers by name"
assert_eq "" "$(grep -vE '^(User-agent: .+|Disallow: /|#.*|)$' "$SUITE/robots.txt")" "...and only ever disallows everything"
# A .dc.html source in the deployed folder once caused a redirect loop (outerReach #111).
assert_eq "" "$(find "$SUITE" -name '*.dc.html')" "no design-tool sources in the deployed suite"
assert_eq "1" "$([ -f "$ROOT/docs/designs/handoff/README.md" ] && echo 1 || echo 0)" "the handoff drop zone exists"

echo "deploy workflow:"
assert_contains "$WF" "- 'docs/designs/suite/**'" "the deploy runs when the suite changes"
assert_contains "$WF" "path: docs/designs/suite" "...and deploys that same folder"
assert_not_contains "$WF" "handoff" "...never the handoff package"
assert_contains "$WF" "github.actor != 'dependabot[bot]'" "Dependabot pushes, which carry no secrets, are skipped"
assert_contains "$WF" "needs.configured.outputs.ready == 'true'" "the deploy waits until the Cloudflare secrets are set"
test_summary
