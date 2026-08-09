# CLAUDE.md

This is a template base repo, this file needs to be updated to match specific project needs.

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
| `npm run test:bin`                        | Bash tests for `bin/` scripts           |

## Layout

| Path            | Contents                                                                   |
| --------------- | -------------------------------------------------------------------------- |
| `src/`          | Application code. Entry point is `src/index.ts`.                           |
| `src/lib/`      | Reusable logic with no framework or IO coupling.                           |
| `src/types/`    | Types shared across modules. Types used in one module stay in that module. |
| `src/config/`   | Configuration loading and environment parsing.                             |
| `tests/unit/`   | Vitest specs, mirroring `src/` paths.                                      |
| `tests/e2e/`    | Playwright specs. Not installed by default.                                |
| `bin/`          | Shell scripts (build helpers, AI PR-review loop).                          |
| `tests/bin/`    | Bash tests for `bin/` scripts, run by `tests/bin/run.sh`.                  |
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

- CI runs exactly `npm run check` — with ONE sanctioned exception: Playwright
  e2e is the deliberately expensive layer, run by `e2e.yml` on
  ready-for-review PRs and main pushes (skipped on drafts; dormant until the
  project adopts a `playwright.config.*`). Its local equivalent is
  `npm run test:e2e`. Everything else CI enforces must be reproducible via
  `check` — to add a check, add it to the `check` script, not as a bare
  workflow step.
- Gates run against the BUILT artifact, never dev-server or stale local
  state: if the project gains a build, `check` runs it before typecheck and
  tests, and gate fixes are verified from a wiped-clean state (delete
  dist/build dirs, run `check`) before claiming they work.
- Every workflow carries a stated reason:
  - `ci.yml` — the gate: `npm ci` + `npm run check`, every PR + main push.
  - `e2e.yml` — the expensive layer (above), draft-skipped, self-activating.
  - `deploy-design-preview.yml` — publishes `docs/designs/handoff/` to
    Cloudflare Pages (main → production, branches → previews). Dormant until
    that path exists; per-project setup is documented in the file (rename
    the Pages project, add `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID`).
- Dependabot (npm + actions, weekly): minors/patches ride CI; a major that
  fails the gate gets CLOSED with a comment and taken deliberately in a
  dedicated branch — never merged red, never left rotting open.
- `.nvmrc` is the single source of truth for the Node version, read via
  `node-version-file`. Never hardcode a version in the workflow.
- Install with `npm ci`, never `npm install`, in CI. `package-lock.json` is
  committed.
- Secrets come from GitHub repository secrets. Never commit `.env*` files.
- Do not claim work passes because it looks correct. Run `npm run check` and
  read the output.
- The pre-push hook (`.githooks/pre-push`, wired by `npm install`) runs the
  gate before every push — see `docs/guides/ci-budget.md` for the full
  spend model (work in drafts, mark ready once). Bypass only with
  `--no-verify`, and then let CI do the job you skipped.

## PR review loop

AI reviewers (Codex + GitHub Copilot) review PRs. The loop, in order:

1. `bin/await-codex-review.sh [PR]` and `bin/await-copilot-review.sh [PR]` —
   request (Copilot only; Codex cannot be requested) and poll for reviews.
   Both print inline findings **and** findings hidden in collapsed
   "Suppressed comments" blocks, which never appear in the comments API.
2. Address every finding; reply in each thread
   (`gh api repos/<repo>/pulls/<pr>/comments/<id>/replies -f body=...`).
3. `bin/pr-unaddressed.sh [PR]` — exits non-zero while any bot thread lacks
   our reply. Usable as a gate.
4. `DRAFT_SKIPPED_CHECK=e2e bin/pr-reviews-done.sh [PR] --lessons "..."` —
   posts the summary comment. It refuses (exit 3) if threads lack replies,
   suppressed findings are unacknowledged (`--ack-suppressed` after actually
   reading them), a takeaway is missing when findings existed, or the
   named draft-skipped check rode a draft-era skip onto a ready PR.
   `--lessons` names the testing-strategy change that keeps the bug class
   from recurring; `"none new: <why>"` is valid but must be explicit.

All four fail closed: a failed API fetch is never reported as "nothing to
address".

## Adjusting for project type

`tsconfig.json` ships bundler-friendly (`module: "preserve"`, `noEmit: true`).
Other project shapes need one change:

- **Pure Node ESM (CLI, server):** set `"module": "nodenext"` and
  `"moduleResolution": "nodenext"`. Relative imports then require `.js`
  extensions.
- **Package that ships JS:** set `"noEmit": false`, add `"outDir": "dist"`, and
  add a `"build": "tsc"` script.
- **Browser / DOM code:** set `"lib": ["ES2023", "DOM", "DOM.Iterable"]`.
