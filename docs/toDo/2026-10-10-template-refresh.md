# Template refresh — harvest from dollyVision, outerReach, atlasAdmin, jarvis, fleetDemo

**Goal:** bring the generic lessons the sibling repos learned since the last
port (2026-08-16) back into the template, as four sequential PRs.

**Sources surveyed (2026-10-10):** dollyVision, outerReach, fleetDemo
(`TEMPLATE-FEEDBACK.md`, `DESIGN-GAPS-LOG.md`), atlasAdmin (a post-08-16 fork of
base), jarvis-ur-ops-automation, silentCartographer, sovereignWard,
meridianCore, nothingfortune/workflows.

**Supersedes** the 2026-08-08 plan's "exactly 8 dev dependencies" constraint:
the gates below each justify the dependency they add.

## PR 1 — hardening (no new dependencies)

- [x] `pr-reviews-done.sh` refuses (exit 3) on unaddressed or unknown bot
      threads; today it posts a verdict and exits 0, so
      `pr-reviews-done.sh && gh pr merge` merges over an unread finding
      (dollyVision #85). Failing test first.
- [x] `tests/bin/_harness.sh` unsets git's local env vars: a hook-exported
      `GIT_DIR` overrides `git -C <tmp>`, so bin tests run from a worktree's
      pre-push rewrote the real repo (dollyVision #207). Tripwire test.
- [x] `tests/bin/run.sh`: per-suite timing, heartbeat, `SHELL_TESTS_SKIP`,
      slowest-suites summary (outerReach #403) + `tests/bin/run.test.sh`.
- [x] `tests/bin/script-syntax.test.sh`: `bash -n` over every `bin/**/*.sh`.
- [x] Dependabot: one Monday batch, minor/patch grouped across all deps,
      majors as their own PRs, commit prefixes (dollyVision #132, atlasAdmin,
      outerReach).
- [x] Bump `nothingfortune/workflows` pin `1f28f5a` → `102318a` (current v1:
      setup-node v7).
- [x] `deploy-design-preview.yml`: map the two Cloudflare secrets explicitly;
      `secrets: inherit` is rejected cross-org for a required secret
      (fleetDemo G15).
- [x] `ci.yml`: never cancel a queued main run (concurrency keyed on run id
      off-PR); `timeout-minutes` on base's own jobs.
- [x] `.gitattributes` (`* text=auto eol=lf`); ignore `.claude/worktrees/` in
      `.gitignore`, ESLint, Prettier (atlasAdmin; jarvis phantom failures).

## PR 2 — quality gates

- [ ] `comment-density` (dollyVision's: TS scanner, marker exemptions,
      block-count ratchet against `comment-density-baseline.json`), adapted
      for a root `src/`. In `check`.
- [ ] ESLint test-integrity rules via `@vitest/eslint-plugin`
      (`expect-expect`, `no-conditional-expect`, `no-disabled-tests`, …),
      `--max-warnings 0`, ban `as unknown as` double assertions.
- [ ] Coverage floor (`@vitest/coverage-v8`) + drift ratchet script; `check`
      runs coverage.
- [ ] Docs integrity test: relative links and backticked repo paths in living
      docs must resolve (dollyVision `check-doc-links` + outerReach
      `docs-paths`); also runs in CI's doc-only lane.
- [ ] knip dead-code gate.
- [ ] Tracked-dump guard: `.gitignore` patterns + test failing on tracked
      `*.sql`, `*.dump`, `*.sqlite`, archives (outerReach repo-hygiene gate E).

## PR 3 — bootstraps

- [ ] `bin/setup-github.sh`: idempotent ruleset on the default branch
      requiring `gate` + `e2e / e2e`, auto-merge, delete-branch-on-merge,
      vulnerability alerts + Dependabot security updates, secrets reminder;
      warns when the repo cannot enforce rulesets (private on a free plan).
      Repo settings do not copy from a template — this is how a clone gets
      them.
- [ ] Mutation testing: Stryker + vitest runner, `npm run test:mutation`,
      `mutation.yml` (`workflow_dispatch`, informational, report artifact),
      dependabot ignore for vitest majors (dollyVision #215).
- [ ] `bin/init.sh <name>`: rename package + lockfile, strip the template
      banner, delete the template's own plans/design; `--check` residue audit
      (fleetDemo F1/F2).

## PR 4 — agent and docs surface

- [ ] `AGENTS.md` pointer to `CLAUDE.md` (a pointer cannot drift).
- [ ] `.github/copilot-instructions.md`: review rubric only.
- [ ] `.claude/settings.json`: deny agent edits to its own settings.
- [ ] `CLAUDE.md`: new testing/process rules, one line each; incidents behind
      them in `docs/guides/testing.md`. Comment rules pointer.
- [ ] PR template: Why + test layer.
- [ ] README: checklist uses `bin/init.sh` + `bin/setup-github.sh`.
- [ ] `TEMPLATE-FEEDBACK.md` log so clones report back.

## Backlog (considered, not now)

- Pre-PR fresh-context review skill (atlasAdmin/jarvis): its hook installs to
  `.git/hooks`, which `core.hooksPath` bypasses; and it contradicts
  ci-budget's draft-first model. Needs a decision first.
- Scope-tiered preflight with an e2e tier — once a clone adopts Playwright.
- `merge-when-green.sh` — only for private free-plan clones; documented by
  setup-github's warning instead.
- jscpd clone detection, shell coverage (`coverage-shell.sh`),
  `tsconfig.test.json`, entry-point convention, committed-config parse test.
- `timeout-minutes` inside `nothingfortune/workflows` reusable jobs (other
  repo).
- Decision / design-gaps / lessons-under-test log skeletons — empty logs in a
  template are noise; add per project.

## Rejected

- `.nvmrc` = `engines` guard (jarvis): base keeps `engines` as the breakage
  floor below `.nvmrc` on purpose (2026-08-08 plan).
- outerReach `doctor.sh`, `setup-github.sh`, `version-check.sh`,
  `recon-untested.sh`, `preflight.sh`: WP Engine / WordPress specific.
- outerReach's review-loop scripts and pre-push: base's are equal or ahead.
