# Universal Template Repo — Design

**Date:** 2026-08-08
**Status:** Approved, pending implementation
**Repo:** `base` (to be marked a GitHub template repository)

## Purpose

One template repo that every new project starts from, carrying the standards that
are true regardless of what the project turns into: folder conventions, git
hygiene, editor config, a single quality gate, CI, and agent instructions.

Because most projects here are strict TypeScript, a working strict TS toolchain
ships in the template. Non-TS projects delete about six files on day one.

### Goals

- A new repo is productive within one `npm install`.
- Exactly one command (`npm run check`) defines "is this good".
- CI enforces that command and nothing else, so CI never surprises you locally.
- An agent picking up any derived repo learns the conventions from `CLAUDE.md`
  without being told.

### Non-goals

- Framework scaffolding (Next, Vite, WordPress). Those are added per project.
- Release automation, containerization, or commit-message enforcement.
- Being genuinely language-agnostic. TypeScript is the default; other languages
  keep the process layer and drop the toolchain.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Template scope | Process layer + strict TS baseline + standard folders | Matches the common case; the minority case is a small delete |
| Folder layout | Structured `src/` + separate `tests/` | Chosen for up-front guidance over minimal surface |
| Lint + format | ESLint (flat config) + Prettier | Plugin ecosystem matters for React/Next/WP-flavored projects |
| Tests | Vitest for unit; Playwright slot reserved, not installed | Playwright is a heavy install most projects skip |
| Package manager | npm, committed `package-lock.json` | Default, no extra install step for collaborators |
| Module system | ESM (`"type": "module"`) | Current default for new work |
| License | MIT, placeholder holder/year | Permissive default; swap per project |

## File tree

```
.
├── .github/
│   ├── workflows/ci.yml
│   └── pull_request_template.md
├── .vscode/
│   ├── settings.json
│   └── extensions.json
├── bin/                        # .gitkeep — shell scripts (deploy, build helpers)
├── docs/
│   ├── designs/                # design docs, this file
│   ├── guides/                 # .gitkeep — how-to docs
│   └── toDo/
│       └── completed/          # .gitkeep
├── scripts/                    # .gitkeep — repo-local Node/TS tooling
├── src/
│   ├── index.ts
│   ├── config/                 # .gitkeep
│   ├── lib/                    # .gitkeep
│   └── types/                  # .gitkeep
├── tests/
│   ├── unit/                   # Vitest; mirrors src/ paths
│   │   └── index.test.ts
│   └── e2e/                    # .gitkeep — Playwright, added per project
├── .editorconfig
├── .gitignore
├── .nvmrc
├── .prettierignore
├── .prettierrc
├── CLAUDE.md
├── LICENSE
├── README.md
├── eslint.config.js
├── package.json
├── package-lock.json
├── tsconfig.json
└── vitest.config.ts
```

Empty directories carry `.gitkeep` so git preserves them. Their purpose is
documented once in `CLAUDE.md`, not repeated in per-folder READMEs.

## Toolchain

### `package.json`

```json
{
  "name": "base",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "engines": { "node": ">=22" },
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

Dev dependencies (8): `typescript`, `eslint`, `@eslint/js`, `typescript-eslint`,
`eslint-config-prettier`, `prettier`, `vitest`, `@types/node`.

`check` is the gate. CI runs it verbatim.

`engines.node` and `.nvmrc` serve different jobs and are intentionally not equal:
`engines` is the permissive floor below which the project is known to break
(`>=22`), while `.nvmrc` pins the exact version developers and CI run (`24`).

### `tsconfig.json`

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

Two deliberate choices:

- **`noUnusedLocals` / `noUnusedParameters` are omitted here on purpose.** They
  live in ESLint instead. In `tsc` they hard-fail a typecheck the moment you
  comment out three lines mid-refactor; as lint rules they surface in the editor
  and fail in CI, which is where the pressure belongs.
- **`module: "preserve"` + `noEmit: true` is a bundler-friendly default.** This
  is the one setting that cannot be correct for every project type. Swaps are
  documented in `CLAUDE.md`: `nodenext` for pure Node ESM, `noEmit: false` plus
  an `outDir` for packages that ship JS, `"lib": ["ES2023", "DOM"]` for browser
  code.

### `eslint.config.js`

```js
import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import prettier from 'eslint-config-prettier';

export default tseslint.config(
  { ignores: ['dist/**', 'build/**', 'coverage/**', 'node_modules/**'] },
  js.configs.recommended,
  ...tseslint.configs.strictTypeChecked,
  ...tseslint.configs.stylisticTypeChecked,
  {
    languageOptions: {
      parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname },
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

Type-aware linting (`strictTypeChecked`) is slower than syntactic linting but
catches floating promises and unsafe `any` propagation — the failures strict
`tsc` alone misses. `eslint-config-prettier` is last so formatting rules never
conflict.

### `vitest.config.ts`

```ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['tests/unit/**/*.test.ts'],
    environment: 'node',
  },
});
```

Scoping to `tests/unit/**` keeps `tests/e2e/` free for Playwright without Vitest
trying to run it.

### `.prettierrc`

```json
{
  "semi": true,
  "singleQuote": true,
  "trailingComma": "all",
  "printWidth": 100,
  "tabWidth": 2
}
```

### `.prettierignore`

```
dist/
build/
coverage/
node_modules/
package-lock.json
.gitkeep
```

### `.editorconfig`

`root = true`; UTF-8, LF, 2-space indent, final newline, trim trailing whitespace.
Markdown exempted from whitespace trimming (trailing spaces are line breaks).

### `.vscode/`

`settings.json`: format-on-save via Prettier, `source.fixAll.eslint` on save,
workspace TypeScript SDK. `extensions.json`: recommends ESLint, Prettier, and
EditorConfig.

## CI

`.github/workflows/ci.yml`:

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

`npm ci` requires a committed `package-lock.json` — the template must ship one,
generated by running `npm install` once during implementation.

`.github/pull_request_template.md` covers: summary, what changed, how it was
tested, and a short checklist (`npm run check` passes, docs updated if needed).

## `CLAUDE.md`

The agent-facing conventions file. Sections:

1. **Project** — one-line placeholder to fill per project.
2. **Commands** — `npm run check` is the gate; the sub-scripts.
3. **Folder conventions** — what belongs in `src/lib`, `src/types`, `src/config`,
   `bin/`, `scripts/`, `docs/designs`, `docs/guides`, `docs/toDo`.
4. **TypeScript rules** — no `any` (use `unknown` and narrow); no non-null `!`
   assertions; named exports over default; types in `src/types` only when shared
   across modules, otherwise beside their use.
5. **Testing approach** — see below.
6. **CI structure** — see below.
7. **Project-type adjustments** — the `tsconfig` swaps listed above.

### Testing approach (verbatim rules)

- Every behavior change ships with a test in the same commit.
- Unit tests live in `tests/unit/` and mirror `src/` paths: `src/lib/parse.ts` →
  `tests/unit/lib/parse.test.ts`.
- End-to-end tests live in `tests/e2e/` and are Playwright. Vitest does not run
  them. Playwright is added per project, not by the template.
- Test observable behavior through public interfaces. If a test needs access to
  something private, the boundary is wrong — fix the boundary, don't export the
  internal.
- Every bug fix starts with a failing test that reproduces the bug. Watch it
  fail, then fix it.
- Never make a suite green by deleting a test, adding `.skip`, or loosening an
  assertion. If a test is genuinely wrong, say so and explain why before
  changing it.
- Mock only what crosses the network, filesystem, or clock. Prefer real objects.
- A test asserts one expected result. No conditionals or `try`/`catch` that let
  it pass on either outcome.

### CI structure (verbatim rules)

- CI runs exactly `npm run check`. Anything CI enforces must be reproducible
  locally with that same command — to add a check, add it to the `check` script,
  not as a bare workflow step.
- One workflow file (`ci.yml`) until there is a concrete reason for a second.
- `.nvmrc` is the single source of truth for the Node version, read via
  `node-version-file`. Never hardcode a version in the workflow.
- Install with `npm ci`, never `npm install`, in CI. `package-lock.json` is
  committed.
- Secrets come from GitHub repository secrets. Never commit `.env*` files.
- Do not claim work passes because it looks correct. Run `npm run check` and
  read the output first.

## Cleanups to existing files

The repo currently carries leftovers from a prior project (`dollyVision`).

1. **`.gitignore` ignores `.vscode/` wholesale**, which would silently discard
   the shared editor settings this design adds. Replace with:
   ```
   .vscode/*
   !.vscode/settings.json
   !.vscode/extensions.json
   ```
2. **The OS block (`.DS_Store`, `Thumbs.db`) appears twice.** Dedupe.
3. **Drop the `bin/build-wpe.sh` WP Engine comment**, keeping `build/` generic.
4. **`README.md` currently reads `# dollyVision`.** Replace with the template
   README.
5. **Delete the on-disk `.DS_Store` files** at the repo root and in `docs/`.
   They are untracked and already ignored, so this is local housekeeping only —
   no git history to clean.
6. **`.env.local` is empty and gitignored** — leave it, it is harmless and
   signals where local config goes.

## README

Title, one-line description placeholder, then a **Using this template**
checklist:

1. Rename `name` in `package.json`; update the README title and description.
2. Update `LICENSE` holder and year.
3. Fill in the Project section of `CLAUDE.md`.
4. Delete this template's own design doc from `docs/designs/`.
5. Adjust `tsconfig.json` for the project type (see `CLAUDE.md`).
6. `nvm use && npm install`, then commit the lockfile.
7. Delete what you don't need — `bin/`, `scripts/`, `tests/e2e/`.

Plus a scripts table and a one-paragraph layout overview.

## Deliberately excluded

| Excluded | Why |
|---|---|
| Husky / lint-staged | Adds an install-time hook to every clone to enforce what CI already blocks. Easiest to add back if pre-commit friction is wanted. |
| commitlint / conventional commits | Ceremony without payoff absent release automation. |
| Changesets / semantic-release | Most of these projects are apps, not published packages. |
| Dockerfile | Deployment targets vary too much for a useful default. |
| Playwright dependency | Heavy install; the `tests/e2e/` slot is reserved instead. |

## Verification

Implementation is done when, from a clean clone:

1. `npm ci && npm run check` exits 0.
2. `npm run check` fails when a deliberate type error is introduced in
   `src/index.ts`, and fails separately on a lint violation and on unformatted
   code — confirming each leg of the gate is wired, not just present.
3. `git status` is clean after `npm run format` (formatter agrees with committed
   state).
4. Every directory in the tree above exists in `git ls-files`.
5. CI passes on a pull request against `main`.

## Decided defaults worth a second look

Both are settled above so implementation is unblocked; both are one-line changes
if the call is wrong.

- **`.nvmrc` = `24`** (Active LTS). Note the local machine runs Node 25.6.0, so
  `nvm use` will prompt to install 24. Pinning `25` instead means tracking a
  non-LTS line that goes end-of-life sooner.
- **Prettier style** — single quotes, 100 columns, trailing commas, semicolons.
  A guess at preference rather than a derived requirement.
