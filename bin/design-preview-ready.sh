#!/usr/bin/env bash
# Writes ready=true to $GITHUB_OUTPUT only when both Cloudflare secrets are set, so clones without them skip the deploy.
#
# Usage (in a workflow step, with the secrets mapped into env): bin/design-preview-ready.sh
if [ -n "${CLOUDFLARE_API_TOKEN:-}" ] && [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
  echo "ready=true" >>"${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"
else
  echo "::notice::Cloudflare secrets not set; skipping the design preview deploy."
fi
