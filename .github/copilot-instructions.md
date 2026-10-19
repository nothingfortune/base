# Copilot instructions

**Project facts — layout, commands, conventions — live in
[`CLAUDE.md`](../CLAUDE.md).** Read that first. This file carries only what is
specific to reviewing a pull request here.

## How to review

Order findings by severity: correctness and security first, then tests, then
maintainability. Cite `file:line`. Prefer a concrete fix over general advice.
Skip praise-only comments.

## Tests are required

Treat a missing test as blocking, not a nitpick.

- Every behavior change ships its test in the same PR, never as a follow-up.
  Name the case that should be covered.
- A bug fix includes a test that fails on the old code. Flag a fix without one.
- A new checker, guard, or gate ships a test that plants the defect it hunts
  and shows it firing. A checker that has never been seen to fail is unproven.
- Reject changes that weaken tests to pass: loosened or deleted assertions,
  `.skip`/`.only` left in, arbitrary sleeps instead of awaited events,
  conditionals that let a test pass either way, unexplained snapshot churn.
- Tests go through public interfaces. A test that needs an internal exported
  means the boundary is wrong.
- Mocks only cross the network, filesystem, or clock.

## Code

- TypeScript: no `any`, no non-null `!`, no `as unknown as` double assertions,
  `import type` for types, named exports. Never weaken `tsconfig.json`.
- No unexplained literals in logic: limits, thresholds, and timeouts are named.
- No hardcoded secrets, tokens, hostnames, or account ids.
- Comments state one line of WHY. Flag comments that restate the code and
  multi-line rationale (it belongs in `docs/`). The markers `@public-api`,
  `// strtotime-ok:`, `@covered-by`, and `// env-gate-ok:` are required where
  used and exempt.

## Workflows

- Actions are pinned by commit SHA with a version comment.
- `permissions:` is least-privilege.
- Never interpolate `${{ }}` untrusted input into `run:`; pass it via `env:`.
- A required check is never path-filtered at workflow level (it would never
  report); skip with a job-level `if:` instead.

## PR hygiene

- One concern per PR. The docs a change makes false are updated in the same PR.
- A new dependency is justified in the description.
