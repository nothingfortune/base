# Design tokens

The template ships one design-token source, CSS generated from it, and
preview cards that the claude.ai/design Design System pane can index. Tokens
use the open [DTCG format (2025.10)](https://www.designtokens.org/tr/2025.10/format/),
so they stay useful whatever tool reads them next.

| File                      | What it is                                                  | Edit it?  |
| ------------------------- | ----------------------------------------------------------- | --------- |
| `design/tokens.json`      | Every token: base values plus light-theme aliases           | Yes       |
| `design/tokens.dark.json` | Dark-theme overrides of tokens in `tokens.json`             | Yes       |
| `design/tokens.css`       | One CSS custom property per token, light and dark           | Generated |
| `design/previews/*.html`  | One `@dsCard` card per group: colors, type, spacing, radius | Generated |

After editing either JSON file, run `npm run tokens`. `npm run check` ends
with `npm run design:check`, which fails when the generated files are out of
date, a token file is invalid, or any `design/**/*.html` lacks its `@dsCard`
first line.

## Editing tokens

A token is an object with `$value`; a group is any other object. `$type`
set on a group applies to everything under it. Names may use letters,
digits, `_` and `-`; the path joined by `-` becomes the property name, so
`color.bg.surface` is `--color-bg-surface`.

Supported types are `color`, `dimension` (`px`, `rem`), `fontFamily`,
`fontWeight` (1–1000 or a DTCG keyword such as `bold`), `duration`
(`ms`, `s`) and `number`. Composite types such as `typography` and `shadow`
are rejected; extend `src/lib/design-tokens.ts` if a project needs them.

Colors use the DTCG object form. Keep `hex` beside the components: it is
what the CSS emits, and `design:check` fails if the two disagree.

```json
"accent": {
  "default": {
    "$value": { "colorSpace": "srgb", "components": [0.1451, 0.3882, 0.9216], "hex": "#2563eb" }
  }
}
```

An alias is `"{color.neutral.0}"`. It becomes `var(--color-neutral-0)` in
the CSS, so a dark override of the target carries to every alias of it.
Missing targets, cycles and type mismatches fail the check.

The dark file holds only overrides. Each must name a token in
`tokens.json`, and takes its type from it.

Integer-like keys (`"0"`, `"50"`, `"100"`) always sort first and ascending
when JSON is parsed, so a ramp keyed by numbers comes out in numeric order
whatever order the file uses.

## Using the CSS

Link or import `design/tokens.css` and use the properties:

```css
body {
  background: var(--color-bg-surface);
  color: var(--color-fg-default);
  font-family: var(--font-family-sans);
}
```

The page follows the OS theme. Set `data-theme="light"` or
`data-theme="dark"` on `<html>` to force one.

## Previewing

Open any file in `design/previews/` in a browser. Each card links
`../tokens.css`, so it shows the current values. The cards use system colors
for their own chrome and render in both themes.

## Syncing with claude.ai/design

The cards' first line, `<!-- @dsCard group="…" -->`, is what the Design
System pane indexes. To push them to a design-system project, start a Claude
Code session in the repo and run `/design-sync`.

- Run it in the main session. The sync tool is not available to subagents.
- If every call fails with "needs design-system authorization", run
  `/design-login` and continue.
- The sync is incremental, one component at a time, and shows its plan
  before writing.
- Standalone Claude Design (claude.ai/design) closes by 2026-12-14 as design
  moves into Claude. The tokens and CSS do not depend on it, and the marker is
  one HTML comment.

## The Cloudflare preview

The cards are not deployed: the Design System pane reads them through the
sync above. The Cloudflare preview publishes the design tool's exported pages
from `docs/designs/suite/`, and the handoff package goes in
`docs/designs/handoff/`; each folder's README says what belongs there and how
to turn the deploy on. When a handoff changes a token, update
`design/tokens.json` and run `npm run tokens`.

## Opting out

A project without a UI deletes all of the following, and `npm run check`
stays green:

- `design/`
- the three `src/lib/design-*.ts` libraries and their tests in
  `tests/unit/lib/`
- the CLI test in `tests/unit/scripts/` and the CLI in `scripts/`
- the `tokens` and `design:check` scripts in `package.json`, and
  `&& npm run design:check` at the end of `check`
- the two `design/` lines in `.prettierignore`
- the design rows in `CLAUDE.md` and `README.md`, and the "Design tokens"
  section of [quality gates](quality-gates.md)
- this guide
