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

## Test integrity (ESLint)

**Enforces:** in `tests/**` and every `*.test.*` file, `@vitest/eslint-plugin`
errors on `expect-expect`, `require-to-throw-message`,
`no-conditional-expect`, `valid-expect` (`maxArgs: 2`), `no-identical-title`,
`no-focused-tests` and `no-disabled-tests`. Everywhere, `no-restricted-syntax`
bans a double assertion (`x as unknown as T`). `npm run lint` runs with
`--max-warnings 0`, so a warning fails the gate too.

**Why:** each rule bans a shape of test that is green while checking nothing:
a test with no assertion, a `toThrow()` that accepts any error (including one
from the test's own setup), an assertion inside a `catch` that never runs when
nothing throws, an un-awaited async matcher, a focused or skipped test that
silently stops covering. `maxArgs: 2` because vitest, unlike jest, takes a
failure message as `expect`'s second argument. A double assertion tells the
compiler to stop checking; narrow the value instead.

**Helpers:** `tests/support/thrown.ts` exports `thrown()` and `thrownAsync()`.
They run a call, require it to throw (or reject), and return the error for
assertions on its shape. There is no path out of them without a throw, so no
assertion sits in a `catch` and none can be forgotten. Prefer
`expect(...).toThrow(<matcher>)` when the message alone is the assertion.

**Proof:** `tests/unit/eslint-config.test.ts` lints a planted defect for every
rule through ESLint's Node API and requires the rule to fire, plus clean
controls that must produce no messages.

**Updating:** keep every rule at `error`. A `warn` only bites while
`--max-warnings 0` stays on the lint script; drop the flag and it enforces
nothing. A genuine exception takes an inline
`eslint-disable-next-line <rule> -- <why>`.

**Incident:** dollyVision #77 (Codex review): `no-disabled-tests` at `warn`
let a committed `.skip` reach main because `eslint .` exits 0 on warnings.
dollyVision #79 replaced try/catch assertion blocks, safe only while each one
remembered an `expect.unreachable` guard, with `thrown()`/`thrownAsync()`, which
let `no-conditional-expect` become an error.

## Coverage floor and drift ratchet

**Enforces:** `npm run test:coverage` (vitest with `@vitest/coverage-v8`)
fails when statements, branches, functions or lines across `src/**/*.ts` fall
below the `thresholds` in `vitest.config.ts`. `npm run coverage:drift`
(`scripts/check-coverage-drift.mjs`) then fails when any measured metric sits
more than 2 points (`MAX_GAP`) above its floor. It fails closed when
`coverage/coverage-summary.json` is missing or a metric has no floor.

**Why:** a floor only catches a regression while it sits just under the
measured totals. Left behind as coverage rises, it becomes decoration, and
the slack is code that can go untested with a green gate. The drift check
makes a stale floor as loud as one set too high. `check` runs coverage in
place of the plain test run; `npm test` stays the fast loop.

**Ratchet:**

- Coverage rose and drift fails: raise the floors to about 1 point under the
  measured totals it prints, in the same PR.
- Coverage fell below a floor: add the missing tests. Never lower a floor to
  pass, and never widen `MAX_GAP`.
- The one exception is a clone's initial calibration. The template's
  placeholder measures 100%, so its floors are 99. In the first commit with
  real code, set each floor to about 1 point under what that code measures.
  After that commit the rules above apply.

`coverage-drift` reads the floors with a regex over `thresholds: {` in
`vitest.config.ts`, so keep them as plain numeric literals in that block.

**Upgrades:** `vitest` and `@vitest/coverage-v8` must stay on the same
version; coverage-v8 pins vitest as an exact peer. Dependabot's minor/patch
group moves them together. A vitest major arrives as its own PR: take it with
the matching coverage-v8 major in the same branch.

**Proof:** `tests/unit/scripts/check-coverage-drift.test.ts` runs the script
against fixture configs and summaries: a 2.01-point gap fails and flags the
metric, an in-gap summary passes, a missing summary and a missing floor both
fail.

**Incident:** dollyVision #83: its floor was raised on 2026-08-13 and was over
3 points adrift by 2026-08-17, about 60 statements and 50 branches that could
go untested with a green gate. It had happened twice, so the fix was a
mechanism rather than a reminder.

## Docs integrity

**Enforces:** `npm run docs:check` (`scripts/check-docs.mjs`) fails when:

- a relative markdown link in any tracked `*.md` does not resolve to a file
  or directory. URI schemes, scheme-relative URLs and pure anchors are
  skipped; a `#fragment` is stripped before resolving; a link that escapes
  the repo with `..` is broken by definition.
- a backticked repo path (a span starting `src/`, `tests/`, `bin/`,
  `scripts/`, `docs/`, `.github/`, `.githooks/` or `.vscode/`) in a living
  doc does not exist. Living docs are `README.md`, `CLAUDE.md`, `AGENTS.md`
  and `docs/guides/**`.

Fenced code blocks are skipped for both checks, and inline code is not
scanned for links. Spans with placeholders (`<name>`, `*`, `{}`, `...`) are
not paths. Generated paths (`node_modules`, `dist`, `build`, `coverage`) and
`docs/designs/handoff/`, which `deploy-design-preview.yml` waits for, are
absent by design and always pass.

**Why:** a renamed or moved file leaves dangling references, and nothing else
in `check` reads prose. Dated plans and designs under `docs/toDo/` and
`docs/designs/` are records of their time, so the paths they mention may age;
only their links must keep working. The check runs in `check` and in CI's
doc-only lane, because a doc-only PR is exactly where links break and
`check` is skipped there.

**Updating:** fix the doc or the path. To exempt a path that is absent by
design, extend `ABSENT_BY_DESIGN` in the script; to make a new folder of
living docs checked, extend `LIVING`.

**Proof:** `tests/unit/scripts/check-docs.test.ts` builds a throwaway git
repo with a broken link, a missing backticked path, a repo-escaping link and
a broken record link, and requires each to be reported, with controls
(external links, anchors, fenced and inline code, placeholders, a record's
aged path, an untracked file) that must stay quiet.

**Origin:** a merge of `dollyVision/scripts/check-doc-links.mjs` (the
relative-link half, its `docs:links` gate) and
`outerReach/scripts/docs-paths.test.mts` (the backticked-path half, policing
only the living tier). Neither source names a single motivating PR; both
guard the drift class where a rename leaves references dangling. Its first
run here caught `CLAUDE.md` naming an illustrative `parse.ts` under `src/lib/`
that does not exist, and while this guide was written it caught the guide citing
sibling-repo paths as if they were this repo's. The CLAUDE.md example now
uses a `<name>` placeholder.
