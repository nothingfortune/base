# Quality gates

Every gate below runs inside `npm run check`, so the pre-push hook and CI
enforce it the same way. Each section says what the gate enforces, why it
exists, how to move it when it is right to, and the incident behind it.

Source comments for these gates stay at one line; the longer rationale lives
here.

## Comment density

**Enforces:** the number of multi-line comment blocks in each workspace's
`src/` equals the count in `comment-density-baseline.json`. A block is a
`/* */` comment spanning more than one line, or two or more consecutive `//`
lines. Blocks containing `@public-api`, `strtotime-ok:`, `@covered-by` or
`env-gate-ok:` are exempt.

**How:** `bin/comment-density.sh` (logic in `scripts/comment-density.mjs`).
Workspaces are a root `src/` (reported as `.`) plus any `packages/*/src` and
`apps/*/src`. Comment ranges come from the TypeScript scanner, so a `/*`
inside a string or template literal is never counted. The table also prints
comment-line density per workspace for information; only the block count
gates.

**Why:** the house comment rule is one WHY line per comment, with extended
rationale in docs. Code review alone does not hold that line: multi-line
blocks creep back one PR at a time.

**Ratchet:** the count must equal the baseline in both directions.

- Rose: a new multi-line block. Collapse it to one line and move the
  rationale into a guide, spec or plan.
- Fell: you removed blocks. Lower the workspace's number in
  `comment-density-baseline.json` to the reported count in the same commit.
- Missing workspace: a new `packages/*` or `apps/*` package. Run
  `bash bin/comment-density.sh --update-baseline` and commit the new entry.

Never raise a number to make the gate pass. An unreadable baseline fails
closed: every workspace reports as missing.

**Incident:** dollyVision's 2026-09-26 holistic code review (findings 5 and
29, plan item A2) found that the global comment rules named
`bin/comment-density.sh` as the CI backstop while no such script existed in
any repo. dollyVision built it; its PR #174 then fixed the scanner to walk
`getChildren` so comments before a closing `}` and at end of file are
counted. This port keeps all of its test cases and adds root-`src/`
discovery for single-package repos.
