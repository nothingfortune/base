# Design suite

The deployed design bundle. `.github/workflows/deploy-design-preview.yml`
publishes this folder, exactly as committed, to Cloudflare Pages whenever it
changes: `main` goes to the production URL, every other branch to its own
preview URL.

## What goes here

- The design tool's exported HTML pages (from a Claude Design handoff
  package, its `design-refs/`), plus any scripts they reference. Each page is
  self-contained, and the pages cross-link by relative filename, so keep them
  together in this folder.
- `index.html`, the entry point. Until an export lands it is a placeholder;
  afterwards make it redirect to the suite's own index page.
- `_headers` and `robots.txt`, which keep the preview out of search engines and
  AI crawlers. Keep both.

## What never goes here

Anything that is not part of the deploy. The handoff package (specs, asset
files, `.dc.html` sources) lives in [`../handoff/`](../handoff/README.md).
A `.dc.html` source in this folder once caused a redirect loop on Cloudflare
(`.dc.html` → `.html`), and `npm run test:bin` fails if one appears.

## Editing

Exported pages are compiled output. Change them in the design tool and
re-export; do not hand-edit the bundled HTML.

## Turning the deploy on

1. Add the repository secrets `CLOUDFLARE_API_TOKEN` (permission: Account ▸
   Cloudflare Pages ▸ Edit) and `CLOUDFLARE_ACCOUNT_ID`. Until both exist the
   workflow runs, finds no secrets, and skips the deploy.
2. Optionally name the Pages project with the reusable workflow's
   `project_name` input; it defaults to `<repo>-design` and is created on the
   first run.
