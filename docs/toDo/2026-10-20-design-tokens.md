# Design Tokens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship DTCG design tokens, generated CSS, and generated
`@dsCard` preview cards in the base template, guarded by `npm run check`.

**Architecture:** Three pure libraries live in `src/lib/`:

- `design-tokens.ts` parses and validates tokens.
- `design-css.ts` emits the CSS.
- `design-previews.ts` emits the cards and scans for markers.

A thin `.mjs` CLI (`scripts/design-tokens.mjs`) does the IO and imports
the libraries directly through Node's type stripping. Generated files are
committed; `--check` regenerates them in memory and diffs.

**Tech Stack:** TypeScript (strip-only subset), Node ≥ 22.18 (`.nvmrc`
24), Vitest, no new dependencies.

**Spec:** [`docs/designs/2026-10-20-design-tokens-design.md`](../designs/2026-10-20-design-tokens-design.md)

## Global Constraints

- **Format.** DTCG format 2025.10. Supported `$type`s: `color`,
  `dimension`, `fontFamily`, `fontWeight`, `duration`, `number`. Every
  other `$type` is an error naming the token.
- **Allowed `$` keys:** `$type`, `$value`, `$description`, `$extensions`,
  `$deprecated`. Any other `$` key, including 2025.10's `$root` and
  `$extends`, is an error naming it.
- **Names.** Group and token names match `/^[A-Za-z0-9_-]+$/`. A node
  with `$value` and also non-`$` children is an error.
- **Colors.**
  - Only the object form is accepted:
    `{ colorSpace: "srgb", components: [r,g,b] (each 0–1), alpha? (0–1), hex? }`.
  - A bare string is an error, and its message shows the object form.
  - A `hex` that disagrees with `Math.round(c*255)` of the components is an
    error.
  - Emitted as:
    - `hex` when it's present and alpha is absent or 1
    - else `rgb(R G B)` when alpha is absent or 1
    - else `rgb(R G B / A)`
- **Other types.**
  - `dimension` units are `px` and `rem`. `duration` units are `ms` and
    `s`. `number` is a finite number.
  - `fontWeight` is a number from 1 to 1000, or a keyword from the DTCG
    table:

    | Weight | Keywords                     |
    | ------ | ---------------------------- |
    | 100    | `thin`, `hairline`           |
    | 200    | `extra-light`, `ultra-light` |
    | 300    | `light`                      |
    | 400    | `normal`, `regular`, `book`  |
    | 500    | `medium`                     |
    | 600    | `semi-bold`, `demi-bold`     |
    | 700    | `bold`                       |
    | 800    | `extra-bold`, `ultra-bold`   |
    | 900    | `black`, `heavy`             |
    | 950    | `extra-black`, `ultra-black` |

- **Aliases.** An alias is `{a.b.c}`. It's emitted as `var(--a-b-c)` and
  validated by full resolution (missing target, cycle, type mismatch).
  - A token that aliases must still have a `$type`, its own or inherited.
    That's stricter than DTCG, deliberately.
- **Dark file.**
  - Every dark token must override a path in `tokens.json`.
  - A dark token takes its type from that base token. A dark `$type` that
    differs is an error.
- **CSS.**
  - Light values go under `:root`.
  - Dark values go under
    `@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { … } }`
    and again under `:root[data-theme="dark"]`.
  - Property name = `--` + the path joined by `-`. Two paths that map to
    the same name are an error.
  - Output is in source order (`JSON.parse` puts integer-like keys first),
    starts with a generated header line, and ends with a trailing newline.
  - In CSS strings, `"` and `\` are escaped.
- **Cards.**
  - The CLI owns four generated cards, `colors.html`, `type.html`,
    `spacing.html` and `radius.html`, each starting with
    `<!-- @dsCard group="Colors|Type|Spacing|Radius" -->`.
  - Each links `../tokens.css`, with no `<script>` and no external URL.
  - The marker scan covers every `design/**/*.html`, recursively.
- **TypeScript.** Strip-only TS in `src/lib/design-*.ts`: no `enum`, no
  `namespace`, no parameter properties.
  - `.ts` files import each other with `import type` only. Value imports
    with `.ts` extensions fail tsc (TS5097) without
    `allowImportingTsExtensions`.
  - Runtime wiring between libraries happens in the CLI.
- **Exports.** Export functions, plus `Token` and `Parsed`, and nothing
  else. Exported types that no other file uses fail integrity (DEAD-002).
- **Lint.**
  - Use `readonly T[]`, not `ReadonlyArray<T>` (`array-type`).
  - Wrap numbers in `String(n)` inside template literals
    (`restrict-template-expressions`).
  - In the `.mjs`, only `console` and `process` are globals, so use
    `node:path`, `node:url` and `node:fs` the way `check-docs.mjs` does.
- **House rules.**
  - Named exports; no `any`; no `!`.
  - One-line comments. The comment-density baseline is 0, so no two
    consecutive `//` lines and no multi-line `/** */` in `src/`.
  - Coverage floors stay at 99; run `npm run test:coverage` at the end of
    every task.
- **Opting out.** A missing `design/` means opted out: `design:check`
  prints `design: no design/ directory, skipped` and exits 0.
- **No dated-doc links from the guide.** Living docs never link
  `docs/designs/` or `docs/toDo/`: `bin/init.sh` deletes them in clones.

## Review Focus

1. **A dark override for a path that `tokens.json` lacks**, usually a
   typo. Expect an error naming the path. Test: Task 2.
2. **A name a CSS ident can't hold**, or two paths that collide on one CSS
   name (`a.b-c` and `a-b.c`). Expect an error naming them. Test: Tasks 1
   and 3.
3. **A token with no `$type` anywhere.** Expect an error naming it. Test:
   Task 1.
4. **A font family containing quotes, `\` or `<`.** Expect the HTML to be
   escaped and the CSS to be quoted correctly. Test: Tasks 3 and 4.
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
  export interface Token {
    path: string;
    type: TokenType;
    value: TokenValue | { alias: string };
  }
  export interface Parsed {
    tokens: Token[];
    errors: string[];
  }
  export function parseTokens(doc: unknown, typeOf?: (path: string) => string | undefined): Parsed;
  ```

  - `TokenType`, `Color`, `Measure` and `TokenValue` are module-private.
    Their shapes are as in Global Constraints. Measures are
    `{ value: number; unit: string }`.
  - `typeOf` supplies a fallback type per path. It's used for the dark
    file, which takes its types from the base tokens.
  - `path` is dotted. Tokens come out in source order.
  - An alias string `"{a.b}"` becomes `{ alias: 'a.b' }`.
  - An error is formatted `<path>: <reason>`.

- [ ] **Step 1: Write the failing tests.** Each asserts one result.
  - `parses a color token with group-inherited $type`: input
    `{color:{$type:'color', accent:{$value:{colorSpace:'srgb',components:[0,0.4,1],hex:'#0066ff'}}}}`
    gives exactly
    `{tokens:[{path:'color.accent',type:'color',value:{colorSpace:'srgb',components:[0,0.4,1],hex:'#0066ff'}}],errors:[]}`.
  - `rejects a bare hex color and shows the object form`: the error
    matches `/^color\.accent: .*colorSpace/`.
  - `rejects a hex that disagrees with components`.
  - `rejects components outside 0–1, or not three numbers`, and
    `rejects alpha outside 0–1`.
  - `rejects an unsupported $type naming the token`: `fx.drop` with
    `shadow` gives an error matching `/^fx\.drop: unsupported \$type "shadow"/`.
  - `rejects a bad $type on a group`.
  - `rejects a token with no $type anywhere` (Review Focus 3): the error
    matches `/^space\.sm: no \$type/`.
  - `takes the type from typeOf when the doc has none`.
  - `rejects names a CSS ident cannot hold` (Review Focus 2):
    `'bad name'` and `'a{b'` each give an error naming the key.
  - `rejects $ keys outside the allowlist`: `$root` and `$x` each give an
    error naming them.
  - `rejects a token that also has children`: the error matches
    `/^color\.accent: a token cannot have child tokens/`.
  - `rejects a non-object group node`.
  - Per type, one accept and one reject:
    - dimension, rejecting `em`
    - duration, rejecting `min`
    - fontFamily as a string and as a list, rejecting a non-string item
    - fontWeight `700`, `'bold'` and `'extra-black'`, rejecting `'heavyish'`
      and `1001`
    - number, rejecting `'3'`
  - `turns "{color.accent}" into an alias`: the result is
    `{ alias: 'color.accent' }`.
  - `rejects a non-object document`: `parseTokens(42).errors` equals
    `['tokens: document must be an object']`.
- [ ] **Step 2: Run the tests and see them fail.**
      `npx vitest run tests/unit/lib/design-tokens.test.ts` should fail with
      "Failed to resolve import".
- [ ] **Step 3: Implement `parseTokens`.**
  - Walk depth-first in key order.
  - A node with `$value` is a token.
  - `$type` inherits from the nearest ancestor; failing that, use
    `typeOf(path)`.
  - Collect all errors rather than stopping at the first.
- [ ] **Step 4: Run the tests and see them pass.** Then
      `npm run test:coverage` should keep the floors.
- [ ] **Step 5: Commit.**
      `git commit -m "feat(design): parse and validate DTCG token files"`.

### Task 2: Resolve aliases and validate overrides

**Files:**

- Modify: `src/lib/design-tokens.ts`
- Test: `tests/unit/lib/design-tokens.test.ts`

**Interfaces:**

- Consumes: `Token`.
- Produces: `export function validateTokens(base: Token[], dark: Token[]): string[]`.
  It returns errors, and an empty list means valid.
  - Aliases in both sets resolve against `base`.
  - Dark paths must exist in `base`, with the same type.

- [ ] **Step 1: Write the failing tests.**
  - `accepts a transitive alias chain`: `a → b → c(color)` gives `[]`.
  - `reports a missing alias target`: the error matches
    `/^color\.fg: alias \{color\.nope\} has no target/`.
  - `reports a self-alias and a longer cycle`: the error matches
    `/cycle: a → b → a/`.
  - `reports a type mismatch`: the error matches
    `/^space\.x: alias \{color\.a\} is color, expected dimension/`.
  - `reports a dark override for a missing path` (Review Focus 1): the
    error equals `'dark: color.bg.surfce: no such token in tokens.json'`.
  - `reports a dark override that changes the type`.
  - `checks dark aliases too`.
- [ ] **Step 2: Run the tests and see them fail.** Expect
      "validateTokens is not a function".
- [ ] **Step 3: Implement `validateTokens`.** Use a path map and a
      visited list per walk.
- [ ] **Step 4: Run the tests and see them pass.** Then
      `npm run test:coverage`.
- [ ] **Step 5: Commit.**
      `git commit -m "feat(design): resolve aliases and validate dark overrides"`.

### Task 3: Emit CSS

**Files:**

- Create: `src/lib/design-css.ts`, which imports only `import type { Token } from './design-tokens'`
- Test: `tests/unit/lib/design-css.test.ts`

**Interfaces:**

- Produces:
  - `export function cssName(path: string): string`, which turns
    `'color.bg.surface'` into `'--color-bg-surface'`
  - `export function cssCollisions(tokens: readonly Token[]): string[]`
  - `export function emitCss(base: readonly Token[], dark: readonly Token[]): string`

- [ ] **Step 1: Write the failing tests.**
  - `emits the exact stylesheet`: a fixture of a color with `hex`, a color
    with alpha 0.5 and no hex, a color with no hex and no alpha, an alias,
    a dimension `{value:8,unit:'px'}`, a fontFamily
    `['Segoe UI','system-ui']`, and a dark override of the first color.
    Compare against the full expected string, in this order:
    - the header `/* Generated by npm run tokens from design/tokens*.json. Do not edit. */`
    - `:root {` holding `  --color-accent: #0066ff;`,
      `  --color-scrim: rgb(0 0 0 / 0.5);`, `  --color-ink: rgb(17 17 17);`,
      `  --color-focus: var(--color-accent);`, `  --space-sm: 8px;` and
      `  --font-family-sans: "Segoe UI", system-ui;`
    - the media block, then the `[data-theme="dark"]` block, each holding
      only the override
    - a trailing `\n`
  - `quotes families and escapes " and \` (Review Focus 4): `He said "hi"`
    gives `"He said \"hi\""`, and `a\b` gives `"a\\b"`. Generic keywords
    (`serif`, `sans-serif`, `monospace`, `cursive`, `fantasy`,
    `system-ui`, `ui-sans-serif`, `ui-serif`, `ui-monospace`,
    `ui-rounded`, `math`, `emoji`, `fangsong`) stay unquoted.
  - `emits fontWeight keywords as numbers`: `extra-black` gives `950`.
  - `emits durations and numbers`: `{value:200,unit:'ms'}` gives `200ms`,
    and `1.5` gives `1.5`.
  - `emits no dark blocks when dark is empty`.
  - `cssCollisions reports a.b-c vs a-b.c` (Review Focus 2): the result
    equals `['--a-b-c: a.b-c and a-b.c']`.
- [ ] **Step 2: Run the tests and see them fail.**
- [ ] **Step 3: Implement the three functions.**
- [ ] **Step 4: Run the tests and see them pass.** Then
      `npm run test:coverage`.
- [ ] **Step 5: Commit.** `git commit -m "feat(design): emit token CSS with dark theme"`.

### Task 4: Emit preview cards and scan for markers

**Files:**

- Create: `src/lib/design-previews.ts`, which imports only `import type { Token } from './design-tokens'`
- Test: `tests/unit/lib/design-previews.test.ts`

**Interfaces:**

- Produces:
  - `export const CARD_FILES: readonly string[]`, holding `colors.html`,
    `type.html`, `spacing.html` and `radius.html`
  - `export function emitPreviews(tokens: readonly Token[], name: (path: string) => string): Map<string, string>`,
    keyed by the names in `CARD_FILES`. A card whose group has no tokens
    is omitted.
  - `export function missingDsCard(files: readonly { path: string; content: string }[]): string[]`,
    which returns the paths whose first line doesn't match
    `/^<!-- @dsCard group="[^"]+" -->$/`.

- [ ] **Step 1: Write the failing tests.**
  - `every card starts with its @dsCard line`: `colors.html` starts with
    `<!-- @dsCard group="Colors" -->\n`, and likewise for Type, Spacing
    and Radius.
  - `every card links ../tokens.css`.
  - `the colors card has one swatch per color token`: count the
    `data-token=` attributes and compare against the fixture.
  - `cards contain no script and no external URL`.
  - `escapes token values in HTML` (Review Focus 4): `A<b"c` appears as
    `A&lt;b&quot;c`.
  - `omits a card whose group has no tokens`.
  - `missingDsCard flags a blank first line, a marker on line 2, and a
marker without a group`, and returns `[]` for a correct file.
- [ ] **Step 2: Run the tests and see them fail.**
- [ ] **Step 3: Implement the two functions.**
  - Map tokens to cards by the first path segment:
    - `color` → Colors
    - `font` → Type
    - `space` → Spacing
    - `radius` → Radius
  - Card markup uses `var(<name(path)>)` and prints the path as a label.
- [ ] **Step 4: Run the tests and see them pass.** Then
      `npm run test:coverage`.
- [ ] **Step 5: Commit.** `git commit -m "feat(design): generate @dsCard preview cards"`.

### Task 5: CLI, starter tokens, and the gate

**Files:**

- Create:
  - `scripts/design-tokens.mjs`
  - `design/tokens.json`
  - `design/tokens.dark.json`
  - generated: `design/tokens.css` and `design/previews/*.html`
- Modify:
  - `package.json`:
    - add the scripts `"tokens": "node scripts/design-tokens.mjs"` and
      `"design:check": "node scripts/design-tokens.mjs --check"`
    - append `&& npm run design:check` to `check`
    - set `engines.node` to `>=22.18`
  - `.prettierignore`: add `design/tokens.css` and `design/previews/`
  - `knip.json`: `entry` becomes `["src/index.ts!", "scripts/*.mjs!"]`
    and `project` becomes `["src/**/*.ts!", "scripts/**/*.mjs!", "tests/**/*.ts"]`.
    Without this, the libraries fail DEAD-004. The glob still holds when
    the CLI is opted out.
- Test: `tests/unit/scripts/design-tokens.test.ts`, which spawns the CLI
  against a temp root via `--root`, as in `check-docs.test.ts`, and
  asserts on stdout or a regex, never exact stderr (Node may print an
  ExperimentalWarning)

**Interfaces:**

- Consumes:
  - `parseTokens` and `validateTokens` from `../src/lib/design-tokens.ts`
  - `cssName`, `cssCollisions` and `emitCss` from `../src/lib/design-css.ts`
  - `CARD_FILES`, `emitPreviews` and `missingDsCard` from
    `../src/lib/design-previews.ts`
- Produces: `node scripts/design-tokens.mjs [--check] [--root <dir>]`.
  It exits 0 when it writes or the check passes, and 1 on any error or
  drift, naming each file.

- [ ] **Step 1: Write the failing tests.**
  - `writes tokens.css and the previews`.
  - `--check passes right after a write`.
  - `--check fails naming tokens.css when it was hand-edited`.
  - `--check fails naming colors.html when it was hand-edited`.
  - `--check fails naming a deleted generated card`.
  - `--check fails naming a stale generated card whose group is now
empty`. A write deletes it.
  - `--check fails naming a hand-added previews/extra/x.html without a
marker`, which checks that the scan is recursive.
  - `--check fails on a validation error, printing it`.
  - `--check with no design/ skips`: exit 0, and stdout matches
    `/no design\/ directory, skipped/`.
  - `--check fails when previews exist but tokens.json is missing`
    (Review Focus 5).
  - `tokens.dark.json is optional`.
- [ ] **Step 2: Run the tests and see them fail.**
- [ ] **Step 3: Implement the CLI.**
  - Write the starter tokens:
    - `color.neutral.0`, `50`, `100`, `200`, `300`, `400`, `500`, `600`,
      `700`, `800`, `900`
    - `color.accent.default` and `color.accent.fg`
    - semantic aliases `color.bg.surface`, `color.bg.raised`,
      `color.fg.default`, `color.fg.muted` and `color.border.default`
    - `space.1`, `2`, `3`, `4`, `6` and `8` on a 4px base
    - `radius.sm`, `radius.md` and `radius.lg`
    - `font.family.sans` and `font.family.mono` (system stacks)
    - `font.size.xs`, `sm`, `md`, `lg` and `xl` (rem)
    - `font.weight.regular` and `font.weight.bold`
  - Every color carries `hex`.
  - The dark file overrides only the `color.bg.*`, `color.fg.*`,
    `color.border.*` and `color.accent.*` tokens.
  - Run `npm run tokens`, then `npx prettier --write design/tokens*.json`.
- [ ] **Step 4: Verify.**
  - The tests pass, and `npm run design:check` and `npm run check` both
    pass.
  - Render `design/previews/colors.html` in light and dark with the
    Playwright tools if they're available. Otherwise, list it for the user
    to eyeball.
  - The scope lane is already confirmed: the pinned `scope.yml` treats
    only `docs/*` and `*.md` as doc-only, so `design/**` takes the full
    lane.
- [ ] **Step 5: Commit.**
      `git commit -m "feat(design): token CLI, starter tokens, design:check in the gate"`.

### Task 6: Guide, living docs, and the opt-out proof

**Files:**

- Create: `docs/guides/design-tokens.md`
- Modify:
  - `CLAUDE.md`: Commands rows for `tokens` and `design:check`, a Layout
    row for `design/`, and `design:check` in the `check` row
  - `README.md`: the commands-table rows, and step 6 "Delete what you do
    not need" points to the guide's opt-out list
  - `docs/guides/quality-gates.md`: a `design:check` section with **Why:**
    and **Updating:**
- `REPO_ROOTS` in `check-docs.mjs` is not extended, so `design/…` spans in
  living docs stay unchecked and opting out can't break `docs:check`.

- [ ] **Step 1: Write the guide.** It covers:
  - editing tokens: the color object form with `hex`, aliases, the dark
    file, and integer-like keys sorting first
  - `npm run tokens`
  - previewing locally
  - consuming `design/tokens.css` from app code
  - syncing to claude.ai/design: `/design-sync`; main session only;
    `/design-login` on auth errors; the `@dsCard` first line; a note that
    standalone Claude Design closes by 2026-12-14
  - turning on the Cloudflare deploy: set the caller's `path: design`, so
    cards serve at `/previews/*.html` and `../tokens.css` resolves; add
    `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`; set the trigger
    paths to `design/**`
  - the opt-out list:
    - `design/`
    - `src/lib/design-tokens.ts`, `design-css.ts` and `design-previews.ts`
      and their tests
    - `tests/unit/scripts/design-tokens.test.ts`
    - `scripts/design-tokens.mjs`
    - the two `package.json` scripts and `design:check` in `check`
    - the `.prettierignore` lines
    - the CLAUDE.md and README rows
    - the quality-gates section
    - this guide

  The guide links nothing under `docs/designs/` or `docs/toDo/`.

- [ ] **Step 2: Update CLAUDE.md, the README and quality-gates.**
- [ ] **Step 3: Prove the opt-out.** Copy the tracked tree to `$TMPDIR`
      with `node_modules` symlinked, apply the opt-out list, and run
      `npm run check` there. It should exit 0. Record the result in the commit
      body.
- [ ] **Step 4: Verify.** `npm run check` passes in the repo.
- [ ] **Step 5: Commit.**
      `git commit -m "docs(design): tokens guide, living-doc rows, opt-out proof"`.
