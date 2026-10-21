# Design tokens and Claude Design previews

Status: approved for planning, 2026-10-20.

## Intent

Every project cloned from this template should start with a design-token
setup that Claude can work with end to end: one source file of tokens, CSS
generated from it, and preview pages that the claude.ai/design Design System
pane can index. Today the template has none of this; the only design surface
is the dormant `deploy-design-preview.yml`, which waits for
`docs/designs/handoff/`.

Why now: the user asked for the base to "support Claude design tokens and
such", and every UI project built from it otherwise invents its own token
layout, which Claude then has to rediscover per repo.

## Goals

1. **One source of truth.** `design/tokens.json` in the W3C Design Tokens
   Community Group (DTCG) format, stable spec 2025.10
   (<https://www.designtokens.org/tr/2025.10/format/>).
2. **Generated CSS.** `design/tokens.css` exposes every token as a CSS custom
   property, with a dark theme. Generated, committed, and never hand-edited.
3. **Claude Design previews.** `design/previews/*.html`, one card per
   foundation (colors, type, spacing, radius), generated from the tokens like
   the CSS, so a clone that replaces the starter tokens gets matching cards. Each file's first line is
   `<!-- @dsCard group="…" -->`, the marker the Design System pane indexes
   cards from.
4. **A gate.** `check` fails when:
   - `tokens.css` or a preview is out of date with the token files
   - `tokens.json` is not valid DTCG for the types we support
   - an alias doesn't resolve, or forms a cycle
   - a preview lacks its first-line `@dsCard` marker
5. **A guide.** `docs/guides/design-tokens.md` covers editing tokens,
   regenerating, previewing locally, syncing with claude.ai/design through
   `/design-sync`, and how app code consumes the CSS.

## Non-goals

- No component library. The template has no UI framework; previews show
  foundations only.
- No Style Dictionary or other token toolchain dependency. The subset we
  support is small enough to own (see Constraints).
- No automated sync to claude.ai/design. DesignSync runs only in a user-started
  `/design-sync` session; CI cannot call it.
- No Figma or Tokens Studio integration.

## Anti-goals (a failure even if it works)

- Tokens locked to claude.ai/design. Standalone Claude Design closes by
  2026-12-14 (DesignSync's own tool description), with design moving into
  Claude. DTCG JSON and CSS custom properties stay useful either way. The
  `@dsCard` marker is one HTML comment and costs nothing if the pane goes away.
- A clone without a UI paying for this. Deleting `design/` must leave `check`
  green. The design check treats a missing `design/` as opted out.
- A red CI run on the template, or on any clone that hasn't set up
  Cloudflare, caused by this change (see Deploy).
- Hand-edited generated CSS drifting from the JSON.

## Constraints

- House rules apply (`CLAUDE.md`):
  - Strict TypeScript, named exports, no `any`, no `!`.
  - Logic lives in `src/lib/` with unit tests that mirror its path.
  - The coverage floors are 99%.
  - Comments are one line each, and the comment-density ratchet must hold.
  - Every behavior ships with a test that was seen failing first.
- Node 24 (`.nvmrc`) runs `.ts` directly, so a CLI can import `src/lib` with
  no build step.
- The token types supported, matching DTCG names:
  - `color`: DTCG 2025.10's object form only, with `colorSpace: "srgb"`,
    `components`, and optional `alpha` and `hex`. Emitted as `hex` when that
    field is present and alpha is 1, else as `rgb()`. A bare hex string is
    rejected with a message showing the object form. The starter file
    includes `hex` on every color so it stays easy to edit by hand. My call:
    the file must stay readable by other DTCG tools.
  - `dimension`: `{ value, unit: "px" | "rem" }`
  - `fontFamily`: a string or a list of strings
  - `fontWeight`: a number or a DTCG keyword
  - `duration`: `{ value, unit: "ms" | "s" }`
  - `number`
  - Composite types (`typography`, `shadow`, …) are rejected with a clear
    error naming the token. Projects that need them extend the library.
- Aliases use DTCG `{group.token}` syntax, resolved transitively. A cycle or a
  missing target is an error naming the path.
- `$type` inherits from the nearest group, as the spec says.

## The how, as decided

- **Layout.** The `design/` tree:

  | Path                      | Contents                                                       |
  | ------------------------- | -------------------------------------------------------------- |
  | `design/tokens.json`      | Base tokens plus semantic light-theme tokens                   |
  | `design/tokens.dark.json` | Overrides for semantic tokens only; aliases into `tokens.json` |
  | `design/tokens.css`       | Generated                                                      |
  | `design/previews/*.html`  | Cards; each links `../tokens.css`                              |

  Dark mode as a second file is my call. DTCG's own theming (the Resolver
  module) is newer than the format spec and heavier than the template needs.

- **CSS shape.**
  - Light values go under `:root`.
  - Dark overrides go twice:
    - under `@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { … } }`
    - again under `:root[data-theme="dark"]`

    This follows the same convention as Claude artifacts, so a preview or
    app can follow the OS or force a theme.

  - A token whose value is an alias is emitted as `var(--target)`, not the
    resolved value, so a dark override of the target carries to every token
    that aliases it. Validation still resolves every alias fully, to catch
    missing targets, cycles and type mismatches. My call.
  - Property names are the token path joined by `-` and prefixed `--`. For
    example, `color.bg.surface` becomes `--color-bg-surface`.
  - Output is deterministic: source order, a generated-file header, and a
    trailing newline.
- **Code.**
  - `src/lib/design-tokens.ts` holds the pure functions: parse/validate,
    resolve aliases, flatten, and emit CSS. It has no IO.
  - A thin CLI reads the files and writes, or with `--check` compares.
  - New scripts: `npm run tokens` generates. `npm run design:check` runs the
    CLI with `--check` plus the `@dsCard` scan, and joins `check`.
- **Starter tokens.** A small neutral set:
  - colors: a neutral ramp, one accent, and semantic `bg` / `fg` / `border`
    / `accent`
  - a 4px-based space scale
  - three radii
  - system font stacks
  - a type scale of five sizes
  - two weights

  Enough to show the shape, and small enough that every clone replaces it.

- **Previews.**
  - Generated by the same library: `colors.html` (a swatch per color
    token), `type.html` (a sample per font size, plus the families and
    weights), `spacing.html` (a bar per space token), and `radius.html` (a
    box per radius).
  - Each starts with `<!-- @dsCard group="…" -->` and links
    `../tokens.css`.
  - Static HTML, no scripts, no external resources: the pane and any static
    host render it as is.
  - Which tokens go on which card is decided by the top-level group name
    (`color`, `font`, `space`, `radius`). A clone that adds groups extends
    the mapping in the library.
  - Groups: `Colors`, `Type`, `Spacing`, `Radius`.
  - The `@dsCard` scan still runs over every `design/**/*.html`, so a
    hand-added card can't miss its marker.
- **Deploy.** `deploy-design-preview.yml` stays pointed at
  `docs/designs/handoff/`, which this change does not create. Previews live in
  `design/previews/`, so nothing wakes the Cloudflare deploy.
  - The guide explains how a project opts in: set `path` to
    `design/previews` (with `design/tokens.css` reachable), add the secrets,
    and widen the trigger paths.
  - Decided by the user (2026-10-20): deploy stays opt-in, so CI stays green
    on the template and on fresh clones.

- **Opting out.** The guide lists what a clone without a UI deletes:
  - `design/`
  - `src/lib/design-tokens.ts` and its test
  - the CLI
  - the `tokens` and `design:check` scripts, and `design:check` in `check`

  No `bin/init.sh` flag. My call: one documented list is cheaper than a flag
  and its tests, and the code is small.

- **CI lane.** The builder confirms that a change under `design/` (JSON,
  CSS, HTML) takes the full `check` lane, not the doc-only lane, in the
  shared `scope.yml` classifier.

## Left to the builder

- How the CLI imports `src/lib` (a `.ts` script with explicit extensions, or
  `.mjs` plus Node type stripping), within the tsconfig rules. Any tsconfig
  change must tighten or stay neutral, never loosen.
- The validation error format, as long as every error names the token path.
- Preview page styling, within the tokens it shows.
- The test split between the CLI and the library. The library carries the
  coverage.
