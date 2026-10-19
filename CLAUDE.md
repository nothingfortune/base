# CLAUDE.md

This is a template base repo, this file needs to be updated to match specific project needs.

## Project

<!-- One line: what this project is. Fill in when you start from this template. -->

## Commands

`npm run check` is the gate. It must pass before you claim work is done.

| Command                                   | Purpose                                                                                                   |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `npm run check`                           | typecheck + lint + comment density + integrity + format check + coverage + drift + bin tests + docs check |
| `npm run typecheck`                       | `tsc --noEmit`                                                                                            |
| `npm run lint` / `npm run lint:fix`       | ESLint, `--max-warnings 0`                                                                                |
| `npm run comment-density`                 | Multi-line comment blocks must equal `comment-density-baseline.json`                                      |
| `npm run integrity`                       | Integrity engine: broken references, dead code, import cycles (`build/integrity/report.json`)             |
| `npm run format` / `npm run format:check` | Prettier                                                                                                  |
| `npm test` / `npm run test:watch`         | Vitest (the fast loop; no coverage)                                                                       |
| `npm run test:coverage`                   | Vitest with v8 coverage against the floors in `vitest.config.ts`                                          |
| `npm run coverage:drift`                  | Fails when a floor sits more than 2 points under measured coverage                                        |
| `npm run test:bin`                        | Bash tests for `bin/` scripts and repo guards                                                             |
| `npm run docs:check`                      | Relative links and living-doc repo paths resolve                                                          |
| `npm run test:mutation`                   | Stryker mutation run; informational, never part of `check`                                                |
| `bin/setup-github.sh [--dry-run]`         | Apply the default-branch ruleset and repo settings; safe to re-run                                        |

What each gate enforces, and how to move its ratchet, is in
`docs/guides/quality-gates.md`.

## Layout

| Path             | Contents                                                                      |
| ---------------- | ----------------------------------------------------------------------------- |
| `src/`           | Application code. Entry point is `src/index.ts`.                              |
| `src/lib/`       | Reusable logic with no framework or IO coupling.                              |
| `src/types/`     | Types shared across modules. Types used in one module stay in that module.    |
| `src/config/`    | Configuration loading and environment parsing.                                |
| `tests/unit/`    | Vitest specs, mirroring `src/` paths; tooling specs in `tests/unit/scripts/`. |
| `tests/e2e/`     | Playwright specs. Not installed by default.                                   |
| `tests/support/` | Shared test helpers (`thrown()` / `thrownAsync()`).                           |
| `bin/`           | Shell scripts (build helpers, AI PR-review loop).                             |
| `tests/bin/`     | Bash tests for `bin/` scripts, run by `tests/bin/run.sh`.                     |
| `scripts/`       | Repo-local Node/TS tooling.                                                   |
| `docs/designs/`  | Design docs, named `YYYY-MM-DD-topic-design.md`.                              |
| `docs/guides/`   | How-to documentation.                                                         |
| `docs/toDo/`     | Active plans. Move to `docs/toDo/completed/` when finished.                   |

## TypeScript

- Strict mode with `noUncheckedIndexedAccess` and `exactOptionalPropertyTypes`.
  Do not weaken `tsconfig.json` to make code compile.
- No `any`. Use `unknown` and narrow.
- No non-null assertions (`!`). Handle the null case.
- Named exports, not default exports.
- Use `import type` for type-only imports — `verbatimModuleSyntax` requires it.

## Testing

- Every behavior change ships with a test in the same commit.
- Unit tests live in `tests/unit/` and mirror `src/` paths: `src/lib/<name>.ts`
  becomes `tests/unit/lib/<name>.test.ts`.
- End-to-end tests live in `tests/e2e/` and are Playwright. Vitest does not run
  them. Add Playwright per project; the template does not install it.
- Test observable behavior through public interfaces. If a test needs access to
  something private, the boundary is wrong — fix the boundary, do not export the
  internal.
- Every bug fix starts with a failing test that reproduces the bug. Watch it
  fail for the right reason, then fix it: a test green before the fix is not
  testing the bug.
- Never make a suite green by deleting a test, adding `.skip`, or loosening an
  assertion. If a test is genuinely wrong, say so and explain why before
  changing it.
- Mock only what crosses the network, filesystem, or clock. Prefer real objects.
- A test asserts one expected result. No conditionals or `try`/`catch` that let
  it pass either way.
- Assert what separates the branches, not what they share. If deleting the
  branch you just wrote leaves the suite green, the test is decorative.
- Drive the precondition; do not assume it. Assert the state a step depends on
  exists before asserting what the step does with it.
- A test may not depend on another defect. When a fix breaks an unrelated test,
  give that test a real trigger; never restore the old behavior.
- A green exit code is not evidence. Read the diff after any scripted edit, and
  plant the defect a new checker hunts to watch it fire.
- A suppression marker is a claim. Its reason must be specific enough to be
  falsifiable.
- A spec sentence that states a behavior gets its test in the same change.
  Ordering claims are tested with out-of-order input.
- A failure reported as a return value, not an exception, gets a test that
  makes it fail.
- A displayed count is tested by counting the records behind it, never against
  another number the same code produced.
- Assert absence against the data source, never against the first render.
- Run the whole suite before claiming done, not just the file you touched.

Why each rule exists: `docs/guides/testing.md`.

## Comments

The nine rules ([Spertus](https://stackoverflow.blog/2021/12/23/best-practices-for-writing-code-comments/)):
comments do not duplicate the code; do not excuse unclear code; if a clear one
cannot be written, fix the code; dispel confusion; explain unidiomatic code;
link the source of copied code; link external references where they help;
accompany bug fixes; mark incomplete implementations.

- A justified comment is ONE line stating WHY. Extended rationale goes in
  `docs/`, never source.
- The markers `@public-api`, `// strtotime-ok:`, `@covered-by`, and
  `// env-gate-ok:` are required where they apply and exempt from the above.
- `npm run comment-density` holds the count of multi-line comment blocks in
  `src/` to its baseline; a new block fails `check`.

## Working rules

- A plan prescribes intent, evidence, and acceptance criteria — not code it has
  not executed.
- A commit message is a claim. If it says "verified by X", X was run.
- Before trusting a probe you wrote, run it where you already know the answer,
  in both directions.
- When a review flags one instance, sweep its whole class in the same round.
  Prefer making the class inexpressible over catching it.
- Two review rounds on one line means the operation is wrong, not the value.
- Docs name the command, not the count it prints; counts go stale.

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
  - `mutation.yml` — manual Stryker run (`npm run test:mutation`).
    Informational: never on PRs, never required; fails only when Stryker
    kills nothing, which means the runner broke.
- Dependabot (npm + actions, one Monday batch): minors/patches arrive grouped
  and ride CI; each major arrives alone. A major that fails the gate gets
  CLOSED with a comment and taken deliberately in a dedicated branch — never
  merged red, never left rotting open. Vitest and coverage-v8 majors are
  ignored until Stryker supports them (`docs/guides/quality-gates.md`).
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

Pull requests:

- One concern per PR. A behavior change, its test, and the docs it makes false
  ship together; nothing else rides along. A change that will not converge in
  review is too big: split it.
- Stage files by path, never `git add -A` or `git add .`.
- Answer every finding on the PR: fixed (with the commit), tracked (where), or
  won't fix (why). Push a round's fixes as one commit from a clean tree.
- Codex reads `AGENTS.md`, which points here and at the review rubric;
  Copilot reads `.github/copilot-instructions.md` (the rubric). Rules every
  reviewer must enforce go in this file or the rubric.

## Adjusting for project type

`tsconfig.json` ships bundler-friendly (`module: "preserve"`, `noEmit: true`).
Other project shapes need one change:

- **Pure Node ESM (CLI, server):** set `"module": "nodenext"` and
  `"moduleResolution": "nodenext"`. Relative imports then require `.js`
  extensions.
- **Package that ships JS:** set `"noEmit": false`, add `"outDir": "dist"`, and
  add a `"build": "tsc"` script.
- **Browser / DOM code:** set `"lib": ["ES2023", "DOM", "DOM.Iterable"]`.
