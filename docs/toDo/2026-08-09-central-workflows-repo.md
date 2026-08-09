# Central workflows repo — plan + reuse catalog

**Goal:** one `nothingfortune/workflows` repo that every project sources its
CI/automation from via reusable workflows (`workflow_call`), so fixes land
once and propagate — instead of re-porting per repo. Callers pin `@v1`;
rollout = moving the tag (deliberate, blast-radius controlled; dependabot
bumps callers on new majors).

**Division of labor:** workflows centralize in the workflows repo; things
that must live on disk in each clone (bin scripts, git hooks, guides) stay
template-vendored in `base` (phase 2 option: npm-package the review tools so
dependabot updates them everywhere).

## Phase 1 — core (the three we run everywhere)

- [ ] Create `nothingfortune/workflows`; decide plain name vs `.github`
      (the `.github` repo also centralizes default community-health files —
      PR template for free — at the cost of a muddier repo purpose).
- [ ] Convert to `workflow_call`:
  - [ ] `ci.yml` — no inputs; concurrency + least-privilege as shipped.
  - [ ] `e2e.yml` — keep the playwright-probe dormancy + draft-skip;
        document `DRAFT_SKIPPED_CHECK=e2e` in the workflow header.
  - [ ] `deploy-design-preview.yml` — inputs: `project_name`
        (default computed `<repo>-design`), `path`
        (default `docs/designs/handoff`); `secrets: inherit` for the two
        Cloudflare secrets. Kills the RENAME-ME placeholder.
- [ ] Tag `v1`. Verify a private→private call works (source repo
      Actions access setting) or keep repos public.
- [ ] Swap `base` to thin callers; verify dormancy still no-ops.
- [ ] Swap `dollyVision` to thin callers (incl. its `engine-image.yml`
      once the docker workflow below exists); verify all three gates stay
      green on a test PR.

## Phase 2 — discovered candidates (from dollyVision + outerReach)

- [ ] **`dependabot-auto-merge.yml`** (outerReach, near-verbatim reusable):
      auto-merge patch/minor everywhere + dev-only majors; prod majors get
      labeled for a human. NOTE: only meaningful with branch protection —
      auto-merge waits on _required_ checks.
- [ ] **Branch protection bootstrap**: `gh api` script (or repo ruleset)
      requiring `check` (+ `e2e` where adopted) on main, applied per repo —
      prerequisite for auto-merge, and it upgrades `DRAFT_SKIPPED_CHECK`
      from advisory to enforced.
- [ ] **Reusable docker-image workflow** (generalize dollyVision's
      `engine-image.yml`): inputs `dockerfile`, `image_name`,
      `smoke_command`; build + artifact smoke on PRs, GHCR push (latest +
      sha) on main via `GITHUB_TOKEN`.
- [ ] **Pre-push preflight** (outerReach pattern, slimmed for base):
      `.githooks/pre-push` running `npm run check` (tiered: e2e only when
      the diff touches covered code; `--no-verify` bypass), wired via
      `git config core.hooksPath .githooks` — saves the CI round-trip on
      doomed pushes. Template-vendored in `base`, not a workflow.
- [ ] **`docs/guides/ci-budget.md`** (outerReach): port the
      draft-PRs-skip-expensive-jobs / one-review-per-PR philosophy doc into
      `base` — it's the WHY behind the e2e + review-loop mechanics.

## Backlog (worth a look, not yet)

- [ ] `check-security-headers.sh` + lib (outerReach): live-URL header
      assertion with the CF-403 browser-UA lesson baked in — generic with a
      headers-list input; pairs with any deploy workflow.
- [ ] Weekly informational quality job pattern (outerReach `mutation.yml`):
      the shape (scheduled, honest-labeling, never merge-blocking) ported to
      JS via Stryker if/when a repo wants it.
- [ ] `doctor.sh` pattern: read-only env/wiring diagnostic skeleton.
- [ ] `setup-github.sh` (outerReach): inspect for a generic repo-bootstrap
      (secrets, protection, labels) worth templating.
- [ ] npm-package the PR-review tools (`bin/` loop) so they update via
      dependabot instead of template drift.

## Explicitly not centralizing

WP Engine deploys, DDEV tooling, GTM/content scripts (stack-specific);
`design-sync` state (per-repo by nature); the `bin/` review loop stays
on-disk (template) until the npm-package item above.
