# Design Tokens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship DTCG design tokens, generated CSS, and generated
`@dsCard` preview cards in the base template, guarded by `npm run check`.

**Architecture:** There are two pure libraries in `src/lib/`.
`design-tokens.ts` parses, validates and resolves tokens and emits the CSS.
`design-previews.ts` emits the cards and scans for markers. A thin `.mjs`
CLI (`scripts/design-tokens.mjs`) does the IO and imports the libraries
directly through Node 24's type stripping. Generated files are committed;
`--check` regenerates them in memory and diffs.

**Tech Stack:** TypeScript (strip-only subset), Node 24, Vitest, no new
dependencies.

**Spec:** [`docs/designs/2026-10-20-design-tokens-design.md`](../designs/2026-10-20-design-tokens-design.md)

## Global Constraints

- DTCG format 2025.10. Supported `$type`s: `color`, `dimension`,
  `fontFamily`, `fontWeight`, `duration`, `number`. Every other `$type`
  is an error naming the token.
- `color` values:
  - only the object form is accepted: `{ colorSpace: "srgb", components: [r,g,b] (each 0–1), alpha?, hex? }`
  - a bare string is an error, and its message shows the object form
- `dimension` units are `px` and `rem`. `duration` units are `ms` and `s`.
- An alias is `{a.b.c}`. It's emitted as `var(--a-b-c)` and validated by full
  resolution (missing target, cycle, type mismatch).
- CSS:
  - light values go under `:root`
  - dark values go under
    `@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { … } }`
    and again under `:root[data-theme="dark"]`
  - property name = `--` + the path joined by `-`
  - output is in source order, starts with a generated header line, and
    ends with a trailing newline
- Each card's first line is `<!-- @dsCard group="Colors|Type|Spacing|Radius" -->`.
  It links `../tokens.css` and contains no `<script>` and no external URL.
- Strip-only TS in `src/lib/design-*.ts`: no `enum`, no `namespace`, no
  parameter properties. Cross-file imports are `import type` only, so Node
  never resolves them at runtime.
- House rules:
  - named exports; no `any`; no `!`
  - one-line comments
  - comment-density baseline unchanged
  - coverage floors stay at 99
- A missing `design/` means opted out: `design:check` prints
  `design: no design/ directory, skipped` and exits 0.

## Review Focus

1. **A dark override for a path that `tokens.json` lacks.** This is
   usually a typo. Expect an error naming the path, not a silently orphaned
   variable. Test: Task 2.
2. **A token or group name with a character a CSS ident can't hold**, such
   as a space, `{`, `}`, `.` or a leading `$`. Expect an error naming it.
   Names must match `/^[A-Za-z0-9_-]+$/`. Test: Task 1.
3. **A token that has no `$type`, on itself or on any ancestor group.**
   Expect an error naming it, not a guess. Test: Task 1.
4. **A font family containing quotes or `<`**, such as `"Segoe UI"`.
   Expect the preview HTML to escape it and the CSS to quote it correctly.
   Test: Tasks 3 and 4.
5. **A half-deleted `design/`**, where previews exist but `tokens.json` is
   missing. Expect `design:check` to fail, not skip. Test: Task 5.

---

### Task 1: Parse and validate token files

**Files:**

- Create: `src/lib/design-tokens.ts`
- Test: `tests/unit/lib/design-tokens.test.ts`

**Interfaces:**

- Produces:

  ```ts
  export type TokenType =
    'color' | 'dimension' | 'fontFamily' | 'fontWeight' | 'duration' | 'number';
  export interface Color {
    colorSpace: 'srgb';
    components: [number, number, number];
    alpha?: number;
    hex?: string;
  }
  export interface Measure {
    value: number;
    unit: string;
  }
  export type TokenValue = Color | Measure | string | readonly string[] | number;
  export interface Token {
    path: string;
    type: TokenType;
    value: TokenValue | { alias: string };
  }
  export interface Parsed {
    tokens: Token[];
    errors: string[];
  }
  export function parseTokens(doc: unknown): Parsed;
  ```

  - `path` is dotted (`color.bg.surface`). Tokens come out in source order.
  - An alias string `"{a.b}"` becomes `{ alias: 'a.b' }`. Its type check
    happens in Task 2.

- [ ] **Step 1: Write the failing tests.** Each test asserts one result.
  - `parses a color token with group-inherited $type`: input
    `{color:{$type:'color', accent:{$value:{colorSpace:'srgb',components:[0,0.4,1],hex:'#0066ff'}}}}`
    gives `tokens` equal to
    `[{path:'color.accent',type:'color',value:{colorSpace:'srgb',components:[0,0.4,1],hex:'#0066ff'}}]`
    and `errors` equal to `[]`.
  - `rejects a bare hex color and shows the object form`: the error
    matches `/color\.accent.*colorSpace/`.
  - `rejects an unsupported $type naming the token`: a `shadow` gives an
    error matching `/^fx\.drop: unsupported \$type "shadow"/`.
  - `rejects a token with no $type anywhere`: the error matches
    `/^space\.sm: no \$type/` (Review Focus 3).
  - `rejects names a CSS ident cannot hold`: the keys `'bad name'`, `'$x'`
    (as a token, not a `$`-property) and `'a{b'` each give an error naming
    the key (Review Focus 2).
  - `parses dimension, duration, fontFamily (string and list), fontWeight
(number and keyword), number`: one test per type, with exact `value`
    equality.
  - `rejects a dimension unit other than px/rem` and
    `rejects a duration unit other than ms/s`.
  - `rejects color components outside 0–1 or not three numbers`.
  - `turns "{color.accent}" into an alias`: the result is
    `{ alias: 'color.accent' }`.
  - `rejects a non-object document`: `parseTokens(42).errors` equals
    `['tokens: document must be an object']`.
- [ ] **Step 2: Run the tests and see them fail.**
      `npx vitest run tests/unit/lib/design-tokens.test.ts` should fail with
      "Failed to resolve import".
- [ ] **Step 3: Implement `parseTokens`.** Walk the object depth-first in
      key order:
  - keys starting with `$` are properties
  - a node with `$value` is a token
  - `$type` inherits from the nearest ancestor that has one

  Collect every error rather than stopping at the first. Each error is
  formatted `<path>: <reason>`.

- [ ] **Step 4: Run the tests and see them pass.** Run the same command;
      everything should pass.
- [ ] **Step 5: Commit.** Run `git add` on both files, then
      `git commit -m "feat(design): parse and validate DTCG token files"`.

### Task 2: Resolve aliases and validate overrides

**Files:**

- Modify: `src/lib/design-tokens.ts`
- Test: `tests/unit/lib/design-tokens.test.ts`

**Interfaces:**

- Consumes: `Token` from Task 1.
- Produces: `export function validateTokens(base: Token[], dark: Token[]): string[]`.
  It returns errors, and an empty list means valid.
  - Aliases in either set resolve against `base`, with `dark` overriding
    by path.

- [ ] **Step 1: Write the failing tests.**
  - `accepts a transitive alias chain`: `a → b → c(color)` gives `[]`.
  - `reports a missing alias target naming both paths`: the error matches
    `/^color\.fg: alias \{color\.nope\} has no target/`.
  - `reports a cycle with its path`: `a → b → a` gives an error matching
    `/cycle: a → b → a/`.
  - `reports a type mismatch`: a `dimension` token aliasing a `color` token
    gives an error matching `/^space\.x: alias \{color\.a\} is color, expected dimension/`.
  - `reports a dark override for a path base lacks` (Review Focus 1): the
    error equals `'dark: color.bg.surfce: no such token in tokens.json'`.
  - `checks dark aliases too`: a dark token aliasing a missing path gives
    an error.
- [ ] **Step 2: Run the tests and see them fail.** Running
      `npx vitest run tests/unit/lib/design-tokens.test.ts` should fail with
      "validateTokens is not a function".
- [ ] **Step 3: Implement `validateTokens`.** Use a `Map` of path to token.
      Detect cycles with a visited list per walk.
- [ ] **Step 4: Run the tests and see them pass.**
- [ ] **Step 5: Commit.**
      `git commit -m "feat(design): resolve aliases and validate dark overrides"`.

### Task 3: Emit CSS

**Files:**

- Modify: `src/lib/design-tokens.ts`
- Test: `tests/unit/lib/design-tokens.test.ts`

**Interfaces:**

- Consumes: `Token`.
- Produces:
  - `export function cssName(path: string): string`, which turns
    `'color.bg.surface'` into `'--color-bg-surface'`
  - `export function emitCss(base: Token[], dark: Token[]): string`

- [ ] **Step 1: Write the failing tests.**
  - `emits the exact stylesheet`: a fixture of one color with `hex`, one
    color with alpha 0.5 and no hex, one alias, one dimension, one
    fontFamily list `['Segoe UI', 'system-ui']`, and one dark override of
    the color. Compare against the full expected string, in this order:
    - the header `/* Generated by npm run tokens from design/tokens*.json. Do not edit. */`
    - `:root {` holding `  --color-accent: #0066ff;`,
      `  --color-scrim: rgb(0 0 0 / 0.5);`,
      `  --color-focus: var(--color-accent);`, `  --space-sm: 8px;` and
      `  --font-family-sans: "Segoe UI", system-ui;`
    - the media block, then the `[data-theme="dark"]` block, each holding
      only the dark override
    - a trailing `\n`
  - `quotes a family with spaces or quotes and escapes embedded quotes`
    (Review Focus 4): `He said "hi"` gives `"He said \"hi\""`. Generic
    keywords such as `system-ui`, `sans-serif` and `monospace` stay
    unquoted.
  - `emits no dark blocks when dark is empty`.
  - `emits a fontWeight keyword as its numeric CSS weight`: `bold` gives
    `700`. Use the DTCG keyword table.
- [ ] **Step 2: Run the tests and see them fail.**
- [ ] **Step 3: Implement `cssName` and `emitCss`.**
  - A color with `hex` and alpha absent or 1 is emitted as the `hex`
    string. Otherwise it's emitted as `rgb(R G B / A)`, with R, G and B as
    0–255 integers.
- [ ] **Step 4: Run the tests and see them pass.**
- [ ] **Step 5: Commit.** `git commit -m "feat(design): emit token CSS with dark theme"`.

### Task 4: Emit preview cards and scan for markers

**Files:**

- Create: `src/lib/design-previews.ts`
- Test: `tests/unit/lib/design-previews.test.ts`

**Interfaces:**

- Consumes: `import type { Token } from './design-tokens'` and
  `cssName`. The library must not import `cssName` at runtime, because
  the strip-only rule doesn't allow it. Instead the caller passes
  `name: (path: string) => string`.
- Produces:
  - `export function emitPreviews(tokens: Token[], name: (path: string) => string): Map<string, string>`,
    keyed `colors.html`, `type.html`, `spacing.html` and `radius.html`.
    A card whose group has no tokens is omitted.
  - `export function missingDsCard(files: ReadonlyArray<{ path: string; content: string }>): string[]`,
    which returns the paths whose first line doesn't match
    `/^<!-- @dsCard group="[^"]+" -->$/`.

- [ ] **Step 1: Write the failing tests.**
  - `every card starts with its @dsCard line`: `colors.html` starts with
    `<!-- @dsCard group="Colors" -->\n`, and likewise for Type, Spacing
    and Radius.
  - `the colors card has one swatch per color token`: count the
    `data-token=` attributes and compare against the fixture's color
    tokens.
  - `cards link ../tokens.css and contain no script or external URL`:
    assert no `<script`, and no `http` outside the doctype.
  - `escapes token values in HTML` (Review Focus 4): the family
    `A<b"c` appears as `A&lt;b&quot;c`.
  - `omits a card whose group has no tokens`.
  - `missingDsCard flags a blank first line, a marker on line 2, and a
marker without a group`, and returns `[]` for a correct file.
- [ ] **Step 2: Run the tests and see them fail.**
- [ ] **Step 3: Implement the two functions.** Map tokens to cards by the
      first path segment:
  - `color` → Colors
  - `font` → Type
  - `space` → Spacing
  - `radius` → Radius

  Each card's markup uses `var(<name(path)>)` so the preview shows the
  live CSS, and prints the path as a label.

- [ ] **Step 4: Run the tests and see them pass.** Then run
      `npm run test:coverage`. The floors should hold at 99.
- [ ] **Step 5: Commit.** `git commit -m "feat(design): generate @dsCard preview cards"`.

### Task 5: CLI, starter tokens, and the gate

**Files:**

- Create:
  - `scripts/design-tokens.mjs`
  - `design/tokens.json`
  - `design/tokens.dark.json`
  - generated: `design/tokens.css` and `design/previews/*.html`
- Modify:
  - `package.json` (scripts `tokens` and `design:check`; append
    `&& npm run design:check` to `check` after `docs:check`)
  - `.prettierignore` (add `design/tokens.css` and `design/previews/`)
- Test: `tests/unit/scripts/design-tokens.test.ts`, which spawns the CLI
  against a temp root, following `check-docs.test.ts`

**Interfaces:**

- Consumes:
  - `parseTokens`, `validateTokens`, `emitCss` and `cssName` from
    `../src/lib/design-tokens.ts`
  - `emitPreviews` and `missingDsCard` from
    `../src/lib/design-previews.ts`
  - both imports carry explicit `.ts` extensions
- Produces:
  - `node scripts/design-tokens.mjs [--check] [--root <dir>]`
  - exit 0 when it writes or the check passes, exit 1 on any error or
    drift

- [ ] **Step 1: Write the failing tests.**
  - `writes tokens.css and previews from tokens.json`.
  - `--check passes right after a write`.
  - `--check fails naming tokens.css when it was hand-edited`.
  - `--check fails naming a hand-added previews/x.html without a marker`.
  - `--check fails on a validation error, printing it`.
  - `--check with no design/ skips`: exit 0, and stdout matches
    `/no design\/ directory, skipped/`.
  - `--check fails when previews exist but tokens.json is missing`
    (Review Focus 5).
  - `tokens.dark.json is optional`.
- [ ] **Step 2: Run the tests and see them fail.**
- [ ] **Step 3: Implement the CLI.**
  - Write the starter tokens to the spec's "Starter tokens" list:
    - a neutral ramp `color.neutral.0…900`, `color.accent`, and semantic
      `color.bg.surface`, `color.bg.raised`, `color.fg.default`,
      `color.fg.muted`, `color.border.default` and `color.accent.fg`,
      each with `hex`
    - `space.1…8` on a 4px base
    - `radius.sm`, `radius.md` and `radius.lg`
    - `font.family.sans` and `font.family.mono`
    - `font.size.xs…xl` (five sizes)
    - `font.weight.regular` and `font.weight.bold`
  - The dark file overrides only the semantic `color.*` tokens.
  - Run `npm run tokens`.
- [ ] **Step 4: Verify.**
  - The tests pass.
  - `npm run design:check` passes.
  - `npm run check` passes.
  - Open `design/previews/colors.html` in a browser and check that light
    and dark both render. Record what you saw in the commit body.
  - Confirm that the shared `scope.yml` (pinned in
    `.github/workflows/ci.yml`) sends `design/**` to the full lane, not
    the doc-only lane. If it doesn't, stop and report.
- [ ] **Step 5: Commit.**
      `git commit -m "feat(design): token CLI, starter tokens, design:check in the gate"`.

### Task 6: Guide and living docs

**Files:**

- Create: `docs/guides/design-tokens.md`
- Modify:
  - `CLAUDE.md`: a Commands row each for `npm run tokens` and
    `npm run design:check`, a Layout row for `design/`, and `design:check`
    in the `check` row's description
  - `scripts/check-docs.mjs`: add `design` to `REPO_ROOTS`
  - `tests/unit/scripts/check-docs.test.ts`: a test that a missing
    `design/x` path in a living doc fails
  - `docs/guides/quality-gates.md`: a `design:check` section in the
    house format, with **Why:** and **Updating:**

- [ ] **Step 1: Write the failing check-docs test, and watch it fail.**
- [ ] **Step 2: Extend `REPO_ROOTS` so the test passes.**
- [ ] **Step 3: Write the guide.** It covers:
  - editing tokens (the DTCG object form for colors, aliases, and the dark
    file)
  - `npm run tokens`
  - previewing locally
  - consuming the CSS from app code
  - syncing to claude.ai/design: run `/design-sync`; the main session
    only; `/design-login` on auth errors; the `@dsCard` first line; a note
    that standalone Claude Design closes by 2026-12-14
  - turning on the Cloudflare deploy (point `path` at `design/previews`,
    copy or serve `design/tokens.css` beside it, add the two secrets,
    widen the trigger paths)
  - the opt-out removal list from the spec
- [ ] **Step 4: Verify.** `npm run docs:check` and `npm run check` both
      pass.
- [ ] **Step 5: Commit.** `git commit -m "docs(design): tokens guide, CLAUDE.md rows, gate docs"`.
