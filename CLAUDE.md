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

- Strict mode with `noUncheckedIndexedAccess` and `exactOptionalPropertyTypes`.
  Do not weaken `tsconfig.json` to make code compile.
- No `any`. Use `unknown` and narrow.
- No non-null assertions (`!`). Handle the null case.
- Named exports, not default exports.
- Use `import type` for type-only imports — `verbatimModuleSyntax` requires it.

## Testing

- Every behavior change ships with a test in the same commit.
- Unit tests live in `tests/unit/` and mirror `src/` paths: `src/lib/parse.ts`
  becomes `tests/unit/lib/parse.test.ts`.
- End-to-end tests live in `tests/e2e/` and are Playwright. Vitest does not run
  them. Add Playwright per project; the template does not install it.
- Test observable behavior through public interfaces. If a test needs access to
  something private, the boundary is wrong — fix the boundary, do not export the
  internal.
- Every bug fix starts with a failing test that reproduces the bug. Watch it
  fail, then fix it.
- Never make a suite green by deleting a test, adding `.skip`, or loosening an
  assertion. If a test is genuinely wrong, say so and explain why before
  changing it.
- Mock only what crosses the network, filesystem, or clock. Prefer real objects.
- A test asserts one expected result. No conditionals or `try`/`catch` that let
  it pass either way.

## CI

- CI runs exactly `npm run check`. Anything CI enforces must be reproducible
  locally with that command — to add a check, add it to the `check` script, not
  as a bare workflow step.
- One workflow file (`.github/workflows/ci.yml`) until there is a concrete
  reason for a second.
- `.nvmrc` is the single source of truth for the Node version, read via
  `node-version-file`. Never hardcode a version in the workflow.
- Install with `npm ci`, never `npm install`, in CI. `package-lock.json` is
  committed.
- Secrets come from GitHub repository secrets. Never commit `.env*` files.
- Do not claim work passes because it looks correct. Run `npm run check` and
  read the output.

## Adjusting for project type

`tsconfig.json` ships bundler-friendly (`module: "preserve"`, `noEmit: true`).
Other project shapes need one change:

- **Pure Node ESM (CLI, server):** set `"module": "nodenext"` and
  `"moduleResolution": "nodenext"`. Relative imports then require `.js`
  extensions.
- **Package that ships JS:** set `"noEmit": false`, add `"outDir": "dist"`, and
  add a `"build": "tsc"` script.
- **Browser / DOM code:** set `"lib": ["ES2023", "DOM", "DOM.Iterable"]`.
