# Universal Template Repo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn this repo into a GitHub template carrying strict TypeScript tooling, a standard folder structure, one quality gate, CI, and agent conventions.

**Architecture:** A single npm package at the repo root. Four quality legs — typecheck, lint, format, test — each independently runnable and composed into one `npm run check` script. CI runs that script verbatim so nothing CI enforces is unavailable locally.

**Tech Stack:** TypeScript 5.x (strict), ESLint 9 flat config + typescript-eslint (type-aware), Prettier, Vitest, npm, Node 24, GitHub Actions.

**Spec:** `docs/designs/2026-08-08-universal-template-design.md`

## Global Constraints

- Node pinned to `24` in `.nvmrc`; `engines.node` is `>=22`. These differ on purpose — `engines` is the breakage floor, `.nvmrc` is the exact dev/CI version.
- ESM only: `"type": "module"` in `package.json`.
- `package-lock.json` is committed. CI uses `npm ci`, never `npm install`.
- Exactly 8 dev dependencies: `typescript`, `eslint`, `@eslint/js`, `typescript-eslint`, `eslint-config-prettier`, `prettier`, `vitest`, `@types/node`. Do not add others.
- Prettier: semicolons, single quotes, trailing commas `all`, print width 100, tab width 2.
- No Husky, lint-staged, commitlint, Changesets, Dockerfile, or Playwright dependency.
- Never append Claude Code attribution footers to commits or files.
- Empty directories carry `.gitkeep` so git preserves them.

---

## File Structure

| File                                        | Responsibility                                              |
| ------------------------------------------- | ----------------------------------------------------------- |
| `.nvmrc`                                    | Single source of truth for Node version                     |
| `package.json`                              | Scripts, deps, ESM declaration                              |
| `tsconfig.json`                             | Strict type checking, bundler-friendly module resolution    |
| `vitest.config.ts`                          | Scopes Vitest to `tests/unit/**` so `tests/e2e/` stays free |
| `eslint.config.js`                          | Flat config, type-aware rules, Prettier conflict disable    |
| `.prettierrc` / `.prettierignore`           | Formatting rules and exclusions                             |
| `.editorconfig`                             | Editor-agnostic whitespace baseline                         |
| `.gitignore`                                | Rewritten: deduped, `.vscode` negation, generic `build/`    |
| `.vscode/settings.json` / `extensions.json` | Shared editor behavior and recommendations                  |
| `.github/workflows/ci.yml`                  | Runs `npm run check`                                        |
| `.github/pull_request_template.md`          | PR checklist                                                |
| `src/index.ts`                              | Placeholder entry point, deleted per project                |
| `tests/unit/index.test.ts`                  | Proves the test leg is wired                                |
| `CLAUDE.md`                                 | Agent conventions: layout, TS rules, testing, CI            |
| `README.md`                                 | Template usage checklist                                    |
| `LICENSE`                                   | MIT                                                         |

---

### Task 1: Node pin and package manifest

**Files:**

- Create: `.nvmrc`
- Create: `package.json`
- Create: `package-lock.json` (generated)

**Interfaces:**

- Consumes: nothing
- Produces: npm scripts `typecheck`, `lint`, `lint:fix`, `format`, `format:check`, `test`, `test:watch`, `check`. All later tasks rely on these exact names. Installed binaries `tsc`, `eslint`, `prettier`, `vitest` become available to later tasks.

- [ ] **Step 1: Create `.nvmrc`**

```
24
```

- [ ] **Step 2: Create `package.json`**

```json
{
  "name": "base",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "engines": {
    "node": ">=22"
  },
  "scripts": {
    "typecheck": "tsc --noEmit",
    "lint": "eslint .",
    "lint:fix": "eslint . --fix",
    "format": "prettier --write .",
    "format:check": "prettier --check .",
    "test": "vitest run",
    "test:watch": "vitest",
    "check": "npm run typecheck && npm run lint && npm run format:check && npm run test"
  }
}
```

- [ ] **Step 3: Install the eight dev dependencies**

Run:

```bash
npm install --save-dev typescript eslint @eslint/js typescript-eslint eslint-config-prettier prettier vitest @types/node
```

Expected: exits 0, creates `node_modules/` and `package-lock.json`.

- [ ] **Step 4: Verify the toolchain binaries resolve**

Run: `npx tsc --version && npx eslint --version && npx prettier --version && npx vitest --version`
Expected: four version strings, exit 0.

- [ ] **Step 5: Verify exactly eight dev dependencies**

Run: `node --input-type=commonjs -p "Object.keys(require('./package.json').devDependencies).length"`
Expected: `8`

(`--input-type=commonjs` is required because `package.json` declares `"type": "module"`.)

- [ ] **Step 6: Commit**

```bash
git add .nvmrc package.json package-lock.json
git commit -m "Add Node pin, package manifest, and dev toolchain"
```

---

### Task 2: Strict TypeScript config, entry point, and first test

**Files:**

- Create: `tsconfig.json`
- Create: `vitest.config.ts`
- Create: `src/index.ts`
- Test: `tests/unit/index.test.ts`

**Interfaces:**

- Consumes: `npm run typecheck`, `npm test` from Task 1
- Produces: `greet(name: string): string` exported from `src/index.ts`. Task 10 deletes it; nothing else depends on it.

- [ ] **Step 1: Create `tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2023"],
    "module": "preserve",
    "moduleResolution": "bundler",
    "types": ["node"],

    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "noImplicitOverride": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,

    "verbatimModuleSyntax": true,
    "isolatedModules": true,
    "esModuleInterop": true,
    "resolveJsonModule": true,
    "forceConsistentCasingInFileNames": true,
    "skipLibCheck": true,
    "noEmit": true
  },
  "include": ["src/**/*", "tests/**/*", "scripts/**/*", "*.config.ts"],
  "exclude": ["node_modules", "dist", "build"]
}
```

Note: `noUnusedLocals` and `noUnusedParameters` are deliberately absent — they live in ESLint (Task 4).

- [ ] **Step 2: Create `vitest.config.ts`**

```ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['tests/unit/**/*.test.ts'],
    environment: 'node',
  },
});
```

- [ ] **Step 3: Write the failing test**

Create `tests/unit/index.test.ts`:

```ts
import { describe, expect, it } from 'vitest';

import { greet } from '../../src/index';

describe('greet', () => {
  it('addresses the given name', () => {
    expect(greet('world')).toBe('Hello, world!');
  });
});
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `npm test`
Expected: FAIL — cannot resolve `../../src/index`.

(Extensionless is correct here because `moduleResolution` is `bundler`. If you later switch the project to `nodenext` per `CLAUDE.md`, relative imports gain `.js` extensions.)

- [ ] **Step 5: Write the minimal implementation**

Create `src/index.ts`:

```ts
/** Placeholder entry point. Delete once this project has real code. */
export function greet(name: string): string {
  return `Hello, ${name}!`;
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `npm test`
Expected: PASS, 1 test.

- [ ] **Step 7: Verify typecheck passes**

Run: `npm run typecheck`
Expected: exit 0, no output.

- [ ] **Step 8: Prove the strict flags are actually engaged**

Temporarily append to `src/index.ts`:

```ts
const sample: string[] = [];
export const first: string = sample[0];
```

Run: `npm run typecheck`
Expected: FAIL with `Type 'string | undefined' is not assignable to type 'string'` — this confirms `noUncheckedIndexedAccess` is live, not merely present in the file.

Then delete those two lines and re-run `npm run typecheck`. Expected: exit 0.

- [ ] **Step 9: Commit**

```bash
git add tsconfig.json vitest.config.ts src/index.ts tests/unit/index.test.ts
git commit -m "Add strict TypeScript config, entry point, and unit test setup"
```

---

### Task 3: Prettier and editor whitespace baseline

**Files:**

- Create: `.prettierrc`
- Create: `.prettierignore`
- Create: `.editorconfig`

**Interfaces:**

- Consumes: `npm run format`, `npm run format:check` from Task 1
- Produces: a formatted working tree that `format:check` passes on

- [ ] **Step 1: Create `.prettierrc`**

```json
{
  "semi": true,
  "singleQuote": true,
  "trailingComma": "all",
  "printWidth": 100,
  "tabWidth": 2
}
```

- [ ] **Step 2: Create `.prettierignore`**

```
dist/
build/
coverage/
node_modules/
package-lock.json
.gitkeep
```

- [ ] **Step 3: Create `.editorconfig`**

```ini
root = true

[*]
charset = utf-8
end_of_line = lf
indent_style = space
indent_size = 2
insert_final_newline = true
trim_trailing_whitespace = true

[*.md]
trim_trailing_whitespace = false
```

- [ ] **Step 4: Format the tree, then verify the check passes**

Run: `npm run format && npm run format:check`
Expected: format rewrites any non-conforming files; `format:check` then exits 0 with "All matched files use Prettier code style!".

- [ ] **Step 5: Prove the format leg actually fails on bad input**

Run:

```bash
printf 'export const x   =    1\n' > src/scratch.ts
npm run format:check
```

Expected: FAIL, listing `src/scratch.ts`.

Then run `rm src/scratch.ts && npm run format:check`. Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add .prettierrc .prettierignore .editorconfig
git commit -m "Add Prettier config and editor whitespace baseline"
```

---

### Task 4: ESLint flat config with type-aware rules

**Files:**

- Create: `eslint.config.js`

**Interfaces:**

- Consumes: `npm run lint` from Task 1, `tsconfig.json` from Task 2 (via `projectService`)
- Produces: a lint-clean tree

- [ ] **Step 1: Create `eslint.config.js`**

```js
import js from '@eslint/js';
import prettier from 'eslint-config-prettier';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  { ignores: ['dist/**', 'build/**', 'coverage/**', 'node_modules/**'] },
  js.configs.recommended,
  ...tseslint.configs.strictTypeChecked,
  ...tseslint.configs.stylisticTypeChecked,
  {
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],
      'no-console': ['warn', { allow: ['warn', 'error'] }],
    },
  },
  { files: ['**/*.js'], ...tseslint.configs.disableTypeChecked },
  prettier,
);
```

- [ ] **Step 2: Run lint to verify a clean tree**

Run: `npm run lint`
Expected: exit 0, no output.

- [ ] **Step 3: Prove type-aware linting is actually running**

A floating promise is invisible to plain syntactic linting — it can only be caught with type information. Create `src/scratch.ts`:

```ts
export function leak(): void {
  Promise.resolve(1);
}
```

Run: `npm run lint`
Expected: FAIL with `@typescript-eslint/no-floating-promises`. This confirms `projectService` resolved the tsconfig.

- [ ] **Step 4: Prove unused-variable enforcement lives in ESLint**

Replace `src/scratch.ts` with:

```ts
export function unused(): number {
  const dead = 5;
  return 1;
}
```

Run: `npm run lint`
Expected: FAIL with `@typescript-eslint/no-unused-vars` for `dead`.

Then run `npm run typecheck`. Expected: exit 0 — proving unused variables fail lint but do not block typecheck, which is the intended split.

- [ ] **Step 5: Clean up and re-verify**

Run: `rm src/scratch.ts && npm run lint`
Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add eslint.config.js
git commit -m "Add ESLint flat config with type-aware rules"
```

---

### Task 5: Verify the composite gate

**Files:**

- Modify: none (verification only)

**Interfaces:**

- Consumes: all four legs from Tasks 2–4
- Produces: confidence that `npm run check` fails for each distinct failure class

- [ ] **Step 1: Verify the gate passes clean**

Run: `npm run check`
Expected: exit 0, all four legs run in order.

- [ ] **Step 2: Verify the typecheck leg blocks the gate**

Run:

```bash
printf 'export const bad: number = "string";\n' > src/scratch.ts
npm run check
```

Expected: FAIL at the typecheck leg; lint/format/test never run.

- [ ] **Step 3: Verify the lint leg blocks the gate**

Run:

```bash
printf 'export function leak(): void {\n  Promise.resolve(1);\n}\n' > src/scratch.ts
npm run check
```

Expected: typecheck passes, FAIL at the lint leg.

- [ ] **Step 4: Verify the format leg blocks the gate**

Run:

```bash
printf 'export const x   =    1;\n' > src/scratch.ts
npm run check
```

Expected: typecheck and lint pass, FAIL at the format leg.

- [ ] **Step 5: Verify the test leg blocks the gate**

Run:

```bash
rm src/scratch.ts
printf "import { expect, it } from 'vitest';\n\nit('fails on purpose', () => {\n  expect(1).toBe(2);\n});\n" > tests/unit/scratch.test.ts
npm run format
npm run check
```

Expected: typecheck, lint, and format pass; FAIL at the test leg.

- [ ] **Step 6: Clean up and confirm green**

Run:

```bash
rm tests/unit/scratch.test.ts
npm run check
git status --porcelain
```

Expected: `check` exits 0 and `git status --porcelain` prints nothing (no stray scratch files left behind).

---

### Task 6: Standard folder structure

**Files:**

- Create: `src/lib/.gitkeep`, `src/types/.gitkeep`, `src/config/.gitkeep`
- Create: `tests/e2e/.gitkeep`
- Create: `bin/.gitkeep`, `scripts/.gitkeep`
- Create: `docs/guides/.gitkeep`, `docs/toDo/completed/.gitkeep`

**Interfaces:**

- Consumes: nothing
- Produces: the directory contract documented in `CLAUDE.md` (Task 8)

- [ ] **Step 1: Create every directory with a `.gitkeep`**

Run:

```bash
for d in src/lib src/types src/config tests/e2e bin scripts docs/guides docs/toDo/completed; do
  mkdir -p "$d" && touch "$d/.gitkeep"
done
```

- [ ] **Step 2: Verify git will actually track them**

Run:

```bash
git add -A
git status --porcelain | grep -c '\.gitkeep'
```

Expected: `8`

- [ ] **Step 3: Verify the gate still passes**

Run: `npm run check`
Expected: exit 0. (`.gitkeep` is in `.prettierignore`, so the format leg ignores the empty files.)

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Add standard folder structure"
```

---

### Task 7: Git ignore rewrite and shared editor settings

**Files:**

- Modify: `.gitignore` (full rewrite)
- Create: `.vscode/settings.json`
- Create: `.vscode/extensions.json`

**Interfaces:**

- Consumes: nothing
- Produces: a `.gitignore` that ignores `.vscode/*` except the two shared files

- [ ] **Step 1: Replace `.gitignore` entirely**

The current file ignores `.vscode/` wholesale, duplicates the OS block, and carries a WP Engine-specific comment. Replace all contents with:

```
# === Environment & secrets ===
.env
.env.local
.env.*.local
.env.deploy

# === OS ===
.DS_Store
Thumbs.db

# === Editors ===
*.swp
*.swo
.idea/
*.code-workspace
.vscode/*
!.vscode/settings.json
!.vscode/extensions.json

# === Dependencies & build artifacts ===
node_modules/
dist/
build/
coverage/

# === Test output ===
/playwright-report/
/test-results/
/blob-report/

# === Logs ===
*.log
```

- [ ] **Step 2: Create `.vscode/settings.json`**

```json
{
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": "explicit"
  },
  "typescript.tsdk": "node_modules/typescript/lib",
  "files.insertFinalNewline": true
}
```

- [ ] **Step 3: Create `.vscode/extensions.json`**

```json
{
  "recommendations": [
    "dbaeumer.vscode-eslint",
    "esbenp.prettier-vscode",
    "editorconfig.editorconfig"
  ]
}
```

- [ ] **Step 4: Verify the negation works**

Run:

```bash
git check-ignore -v .vscode/settings.json .vscode/extensions.json
```

Expected: exit code 1 and no output — neither file is ignored.

Run:

```bash
git check-ignore -v .DS_Store node_modules
```

Expected: both reported as ignored.

- [ ] **Step 5: Delete the stray `.DS_Store` files**

Run: `rm -f .DS_Store docs/.DS_Store`

These are untracked and already ignored, so this is local housekeeping only.

- [ ] **Step 6: Verify the gate still passes, then commit**

```bash
npm run check
git add .gitignore .vscode/settings.json .vscode/extensions.json
git commit -m "Rewrite gitignore and add shared editor settings"
```

Expected: `check` exits 0 before committing.

---

### Task 8: Agent conventions in CLAUDE.md

**Files:**

- Create: `CLAUDE.md`

**Interfaces:**

- Consumes: script names from Task 1, folder structure from Task 6
- Produces: the testing and CI rules every derived project inherits

- [ ] **Step 1: Create `CLAUDE.md`**

```markdown
# CLAUDE.md

Conventions for this repository. Read before making changes.

## Project

<!-- One line: what this project is. Fill in when you start from this template. -->

## Commands

`npm run check` is the gate. It must pass before you claim work is done.

| Command                                   | Purpose                                 |
| ----------------------------------------- | --------------------------------------- |
| `npm run check`                           | typecheck + lint + format check + tests |
| `npm run typecheck`                       | `tsc --noEmit`                          |
| `npm run lint` / `npm run lint:fix`       | ESLint                                  |
| `npm run format` / `npm run format:check` | Prettier                                |
| `npm test` / `npm run test:watch`         | Vitest                                  |

## Layout

| Path            | Contents                                                                   |
| --------------- | -------------------------------------------------------------------------- |
| `src/`          | Application code. Entry point is `src/index.ts`.                           |
| `src/lib/`      | Reusable logic with no framework or IO coupling.                           |
| `src/types/`    | Types shared across modules. Types used in one module stay in that module. |
| `src/config/`   | Configuration loading and environment parsing.                             |
| `tests/unit/`   | Vitest specs, mirroring `src/` paths.                                      |
| `tests/e2e/`    | Playwright specs. Not installed by default.                                |
| `bin/`          | Shell scripts (deploy, build helpers).                                     |
| `scripts/`      | Repo-local Node/TS tooling.                                                |
| `docs/designs/` | Design docs, named `YYYY-MM-DD-topic-design.md`.                           |
| `docs/guides/`  | How-to documentation.                                                      |
| `docs/toDo/`    | Active plans. Move to `docs/toDo/completed/` when finished.                |

## TypeScript

- Strict mode with `noUncheckedIndexedAccess` and `exactOptionalPropertyTypes`. Do not weaken `tsconfig.json` to make code compile.
- No `any`. Use `unknown` and narrow.
- No non-null assertions (`!`). Handle the null case.
- Named exports, not default exports.
- Use `import type` for type-only imports — `verbatimModuleSyntax` requires it.

## Testing

- Every behavior change ships with a test in the same commit.
- Unit tests live in `tests/unit/` and mirror `src/` paths: `src/lib/parse.ts` becomes `tests/unit/lib/parse.test.ts`.
- End-to-end tests live in `tests/e2e/` and are Playwright. Vitest does not run them. Add Playwright per project; the template does not install it.
- Test observable behavior through public interfaces. If a test needs access to something private, the boundary is wrong — fix the boundary, do not export the internal.
- Every bug fix starts with a failing test that reproduces the bug. Watch it fail, then fix it.
- Never make a suite green by deleting a test, adding `.skip`, or loosening an assertion. If a test is genuinely wrong, say so and explain why before changing it.
- Mock only what crosses the network, filesystem, or clock. Prefer real objects.
- A test asserts one expected result. No conditionals or `try`/`catch` that let it pass either way.

## CI

- CI runs exactly `npm run check`. Anything CI enforces must be reproducible locally with that command — to add a check, add it to the `check` script, not as a bare workflow step.
- One workflow file (`.github/workflows/ci.yml`) until there is a concrete reason for a second.
- `.nvmrc` is the single source of truth for the Node version, read via `node-version-file`. Never hardcode a version in the workflow.
- Install with `npm ci`, never `npm install`, in CI. `package-lock.json` is committed.
- Secrets come from GitHub repository secrets. Never commit `.env*` files.
- Do not claim work passes because it looks correct. Run `npm run check` and read the output.

## Adjusting for project type

`tsconfig.json` ships bundler-friendly (`module: "preserve"`, `noEmit: true`). Other project shapes need one change:

- **Pure Node ESM (CLI, server):** set `"module": "nodenext"` and `"moduleResolution": "nodenext"`. Relative imports then require `.js` extensions.
- **Package that ships JS:** set `"noEmit": false`, add `"outDir": "dist"`, and add a `"build": "tsc"` script.
- **Browser / DOM code:** set `"lib": ["ES2023", "DOM", "DOM.Iterable"]`.
```

- [ ] **Step 2: Verify the gate still passes**

Run: `npm run check`
Expected: exit 0. If the format leg rewrites `CLAUDE.md` table spacing, run `npm run format` and re-run.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "Add agent conventions covering layout, testing, and CI"
```

---

### Task 9: CI workflow and PR template

**Files:**

- Create: `.github/workflows/ci.yml`
- Create: `.github/pull_request_template.md`

**Interfaces:**

- Consumes: `npm run check` from Task 1, `.nvmrc` from Task 1, `package-lock.json` from Task 1
- Produces: the CI contract described in `CLAUDE.md`

- [ ] **Step 1: Create `.github/workflows/ci.yml`**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version-file: '.nvmrc'
          cache: 'npm'

      - run: npm ci

      - run: npm run check
```

- [ ] **Step 2: Create `.github/pull_request_template.md`**

```markdown
## Summary

<!-- What does this change and why? -->

## Changes

-

## Testing

<!-- How was this verified? Paste relevant output. -->

## Checklist

- [ ] `npm run check` passes locally
- [ ] Tests cover the behavior change
- [ ] Docs updated if behavior or setup changed
```

- [ ] **Step 3: Verify the workflow YAML parses**

Run:

```bash
node --input-type=commonjs -e "const f=require('fs').readFileSync('.github/workflows/ci.yml','utf8'); if(!/npm run check/.test(f)) throw new Error('missing gate'); if(!/node-version-file/.test(f)) throw new Error('hardcoded node version'); if(/npm install/.test(f)) throw new Error('must use npm ci'); console.log('ci.yml contract OK');"
```

Expected: `ci.yml contract OK`

- [ ] **Step 4: Verify `npm ci` works from the committed lockfile**

Run: `npm ci`
Expected: exit 0. This is the exact command CI runs; if the lockfile is missing or stale it fails here rather than in CI.

- [ ] **Step 5: Verify the gate still passes, then commit**

```bash
npm run check
git add .github/workflows/ci.yml .github/pull_request_template.md
git commit -m "Add CI workflow and pull request template"
```

---

### Task 10: README, LICENSE, and final verification

**Files:**

- Modify: `README.md` (full rewrite — currently reads `# dollyVision`)
- Create: `LICENSE`

**Interfaces:**

- Consumes: everything above
- Produces: the finished template

- [ ] **Step 1: Create `LICENSE` (MIT)**

```
MIT License

Copyright (c) 2026 Alex Petersen

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Replace `README.md` entirely**

````markdown
# base

<!-- One line: what this project is. -->

Template repository: strict TypeScript, one quality gate, CI that runs it.

## Quickstart

```bash
nvm use
npm install
npm run check
```

## Using this template

1. Rename `name` in `package.json`; update this README's title and description.
2. Update the holder and year in `LICENSE`.
3. Fill in the Project section of `CLAUDE.md`.
4. Delete the template's own design doc from `docs/designs/` and plan from `docs/toDo/`.
5. Delete the placeholder `src/index.ts` and `tests/unit/index.test.ts` once real code exists.
6. Adjust `tsconfig.json` for the project type — see the last section of `CLAUDE.md`.
7. Delete what you do not need: `bin/`, `scripts/`, `tests/e2e/`.

## Scripts

| Command                | Purpose                                        |
| ---------------------- | ---------------------------------------------- |
| `npm run check`        | The gate: typecheck, lint, format check, tests |
| `npm run typecheck`    | `tsc --noEmit`                                 |
| `npm run lint`         | ESLint                                         |
| `npm run lint:fix`     | ESLint with autofix                            |
| `npm run format`       | Prettier, writing changes                      |
| `npm run format:check` | Prettier, check only                           |
| `npm test`             | Vitest, single run                             |
| `npm run test:watch`   | Vitest, watch mode                             |

## Layout

Application code lives in `src/`, split into `lib/` (reusable logic), `types/`
(shared types), and `config/` (configuration and environment). Unit tests live
in `tests/unit/` mirroring `src/` paths; `tests/e2e/` is reserved for Playwright,
which is not installed by default. Shell scripts go in `bin/`, repo-local Node
tooling in `scripts/`, and documentation in `docs/`.

Conventions — including testing and CI rules — are documented in `CLAUDE.md`.

## License

MIT
````

- [ ] **Step 3: Run the full gate**

Run: `npm run format && npm run check`
Expected: exit 0.

- [ ] **Step 4: Verify every planned path is tracked by git**

Run:

```bash
git add -A
for p in .nvmrc package.json package-lock.json tsconfig.json vitest.config.ts \
  eslint.config.js .prettierrc .prettierignore .editorconfig .gitignore \
  .vscode/settings.json .vscode/extensions.json .github/workflows/ci.yml \
  .github/pull_request_template.md src/index.ts tests/unit/index.test.ts \
  CLAUDE.md README.md LICENSE \
  src/lib/.gitkeep src/types/.gitkeep src/config/.gitkeep tests/e2e/.gitkeep \
  bin/.gitkeep scripts/.gitkeep docs/guides/.gitkeep docs/toDo/completed/.gitkeep; do
  git ls-files --error-unmatch "$p" >/dev/null 2>&1 || echo "MISSING: $p"
done
echo "path audit done"
```

Expected: no `MISSING:` lines before `path audit done`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add README and MIT license"
```

This must happen before the clone check below — `git clone` copies committed
history only, so verifying an uncommitted tree would test the wrong thing.

- [ ] **Step 6: Verify a clean clone passes the gate**

Run:

```bash
rm -rf /tmp/base-verify && git clone -q . /tmp/base-verify \
  && (cd /tmp/base-verify && npm ci && npm run check) \
  && rm -rf /tmp/base-verify && echo "CLEAN CLONE OK"
```

Expected: `CLEAN CLONE OK`. This is the spec's headline acceptance criterion — a fresh clone is productive after one install.

- [ ] **Step 7: Move this plan to completed**

```bash
git mv docs/toDo/2026-08-08-universal-template-plan.md docs/toDo/completed/
git commit -m "Move template plan to completed"
```

---

## Post-implementation

Mark the repo as a template on GitHub: **Settings → General → Template repository**. This cannot be done from the CLI without a push and an authenticated `gh` call, so it is left as a manual step.
