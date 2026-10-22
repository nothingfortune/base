# Design handoff

Drop zone for the developer handoff package exported from the design tool
(Claude Design): build specs and the real asset files behind the design
suite. Nothing here is deployed.

## Why this is separate from `../suite/`

[`../suite/`](../suite/README.md) is the bundle Cloudflare Pages publishes, and
nothing that is not part of that deploy belongs there. Keeping the package
and its sources here leaves the deployed bundle and its links untouched.

## What goes here

- The package's spec README, saved as `design-handoff-v<version>.md` with a
  short repo note on top (import date, what changed). Keep earlier versions
  for the decision trail; the newest is the build reference.
- `assets/`: the production asset files (favicons, PWA icons and
  `site.webmanifest`, OG images, email logo, fallback images, social kit).
- Optionally the `.dc.html` design sources: fine here, never in `../suite/`.

## What does not go here

The package's `design-refs/` HTML pages. They are the deploy bundle, so they
go to `../suite/` and live only there; a second copy here would drift.

## Design tokens

Tokens are a separate path: `design/tokens.json` is the source, and
`npm run tokens` generates `design/tokens.css` and the Design System cards in
`design/previews/`. See [the design tokens guide](../../guides/design-tokens.md).
When a handoff package changes a token, update `design/tokens.json`, not a copy
of it here.
