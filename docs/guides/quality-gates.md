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

## Monolith limits (ESLint)

**Enforces:** `npm run lint` errors on a file in `src/` or `scripts/` over 400
lines and on a function there over 150 lines. Test files (`tests/**` and every
`*.test.*`) get a 600-line file limit and no function limit. Blank lines and
comments do not count.

**Why:** a function that encodes several invariants can only be tested as a
whole, and every change to it carries the risk of all of them. Files grow the
same way one feature at a time, and no reviewer sees the size of a file in a
diff. The limits catch the growth on the PR that causes it, while the split is
still cheap. Tests have no function limit because every `describe` and `it`
callback is a function, and a real suite outgrows 150 lines on its first day.

**Updating:** split a file along its existing export or `describe` boundaries;
split a function where its invariants separate, so each gets its own test. A
genuine exception (a generated table, a parser state machine) takes a
file-level `/* eslint-disable max-lines -- <why> */` whose reason names what
makes splitting it wrong. Change a limit for the whole repo only in its own PR.

**Proof:** `tests/unit/eslint-config.test.ts` lints sized fixtures through
ESLint's Node API. The `src/` limits pass at their size and fire one line
over, blank lines and comments do not count, `scripts/` and test files are
covered, and a 200-line test callback stays clean.

**Origin:** dollyVision's 2026-09-26 holistic code review found
`matchVersions` (365 lines), `assertIdentityAgainstVersion` (395) and
`runScanInner` (560), and recommended `max-lines` ~400 and
`max-lines-per-function` ~150 to stop them regrowing after the split.
jarvis-ur-ops-automation's 2026-09-23 code review (row 4.8) flagged test
suites of 900 to 1,135 lines.

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
not paths. Generated paths (`node_modules`, `dist`, `build`, `coverage`) are
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

## Code integrity

**Enforces:** `npm run integrity` runs the `@nothingfortune/workflows`
integrity engine and fails on any finding. Rules: REF-001, REF-002 and REF-003
(broken references, including `package.json` scripts that point at a missing
file), DEAD-001 to DEAD-004 (unused files, unused exports, unused dependencies,
and modules reachable only from tests), and CYC-001 (import cycles). The
engine runs knip three times: default, `--production` and a cycles-only
production pass. `knip.json` declares the entries: `src/index.ts` and every
`scripts/*.mjs` (the `bin/*.sh` wrappers call them, which knip cannot follow);
knip's own plugins pick up the vitest, ESLint and TypeScript configs and the
test files.

**Why:** dead code, stale dependencies and dangling references cost review
time, install time and attack surface, and nothing else in `check` notices
them. A template is where this starts cheapest: every clone inherits a clean
graph.

**Updating:** when a new kind of entry point appears (a CLI, a worker, a
second `scripts/` file type), add it to `entry`. Fix the import graph rather
than ignoring a finding; an `ignore*` entry in `knip.json` needs a reason in
the PR that adds it. There is no per-finding suppression yet: until phase I2,
observe mode via `integrity.json` is the only outlet. Engine releases arrive as
one Dependabot PR (the `nothingfortune-workflows` npm group).

**Production pass:** the second run, `knip --production`, reads only the
entries and files marked with `!` in `knip.json` (`src/`), so tests drop out of
the graph. A module imported only by its own test passes the first run and
fails the second (DEAD-004). Write a module test-first if you like, but wire it
into `src/` before the PR that adds it merges.

**Output:** exit 0 is a pass, exit 1 means findings, and exit 2 means the
analysis itself failed (a knip crash, bad config); exit 2 is never a pass. The
engine writes `build/integrity/report.json` (git-ignored). In GitHub Actions it
also writes a step summary table and emits an inline annotation per finding.

**Proof:** a manual run planting four defects one at a time, each giving
exactly one finding of the named rule and exit 1: a second, unused export in a
new `src/lib/` module (DEAD-002), an orphan `src/` file (DEAD-001), a `src/`
module imported only by a test (DEAD-004), and a `package.json` script
`node scripts/gone.mjs` (REF-003). Reverted afterwards; `npm run check` then
passed on the clean tree.

**Origin:** jarvis-ur-ops-automation runs knip in its `validate` gate
(`check:dead`); its 2026-09-23 code review (item 3.6) recorded the test-entry
blind spot that the production pass now closes.

## Tracked dumps and archives

**Enforces:** `tests/bin/tracked-dumps.test.sh` (part of `npm run test:bin`)
fails when `git ls-files` lists a file ending in `.sql`, `.sql.gz`, `.dump`,
`.sqlite`, `.sqlite3`, `.db`, `.tar`, `.tar.gz`, `.tgz` or `.zip`
(case-insensitive), and when `.gitignore` stops ignoring any of those
extensions.

**Why:** a database dump carries real user data (password hashes, emails),
and an archive hides whatever it contains from review. Once committed it
lives in every clone and fork, and removing it means rewriting history. The
`.gitignore` patterns stop the accidental `git add .`; the test catches a
force-add or a pattern someone deletes.

**Updating:** an intentional fixture goes in the `ALLOWED` array at the top
of the test as a repo-relative path, added with `git add -f`. Keep the
extension list in the test and the `.gitignore` block in sync; the test
checks the second against the first.

**Proof:** the test force-adds `dump.sql`, `data/app.sqlite3`,
`backup.tar.gz`, `EXPORT.ZIP` and an allowlisted `fixtures/seed.sql` to a
throwaway repo and requires exactly the first four back; a control repo of
lookalike names (`database.ts`, `dump.sql.md`) must report nothing.
Force-adding `probe.sql` to this repo made the suite fail naming it.

**Origin:** `outerReach/bin/repo-hygiene.sh` gate E (#387/#389), which bans
tracked dumps because a WordPress dump carries `wp_users`.

## Lesson enforcement

These three gates enforce the engineering-lessons that kept recurring across
the fleet's review sweeps: L-0029, L-0040 and L-0103. Each had at least three
recorded origins when it was promoted from a written lesson to a check.

### Fail-open reads (L-0029)

**Enforces:** `npm run lint:fail-open` (`bin/fail-open-lint.sh`, logic in
`scripts/fail-open-lint.mjs`). In `bin/*.sh` and `bin/lib/*.sh`, a network
read (`gh api`, `gh pr checks`, `curl`, `wget`) whose logical line ends in a
silent fallback (`|| echo`, `|| true`, `|| printf`, `|| :`) fails the gate.
Backslash-continued lines count as one line.

**Why:** a fallback turns a failed read into an empty one. An empty list then
reads as "no findings", "no review" or "no checks", and the gate built on it
passes having checked nothing.

**Updating:** handle the failure. Exit non-zero, report UNKNOWN, or branch with
`if ! x="$(...)"; then` and say what the default means. When an unknown result
is safe, such as polling (unknown means "not yet") or a degrade-to-request
policy, mark the line, or the comment line above it, with
`# fail-open-ok: <why>`. A marker with no reason does not count.

**Proof:** `tests/bin/fail-open-lint.test.sh`. The lint found six sites in this
repo. Two were bugs, both fixed with tests: an unreadable CI rollup posted "No
CI checks reported yet", and an unreadable reviews list at the Copilot
deadline printed "No Copilot review". The other four are polling or
degrade-to-request paths and carry markers.

### Planted defects (L-0040)

**Enforces:** `npm run test:defects` (`bin/planted-defects.sh`, logic in
`scripts/planted-defects.mjs`, manifest `tests/bin/planted-defects.json`).
Every refusal (`exit N`, N > 0) in the review-loop scripts, and every
hand-written semantic defect in the manifest, is planted one at a time in a
throwaway copy of `bin/` and `tests/`. At least one mapped suite must then
fail. The suites must pass unmodified first, or nothing is counted.

**Why:** a guard nobody has seen fire is a claim, not a check. On base #38,
four review rounds each found one more guard whose removal left every test
green. Some tests asserted only "exit 3, nothing posted", so a later refusal
masked the missing one. Refusal tests now also assert that exactly one gate
refused.

**Updating:** a new refusal in a listed script is covered automatically, so it
needs a test. A new filter or parse step needs a `defects` entry: `find` (text
that appears exactly once), `replace` and `why`. A `find` that no longer
matches fails the gate as a stale manifest. A refusal no test can reach gets an
`auto.skip` entry with its reason. To cover a new script, add it to
`auto.files` and map it in `suites`.

**Proof:** `tests/bin/planted-defects.test.sh` covers five cases against a
fixture gate:

- an untested refusal fails the gate, and the tested one is reported caught;
- a skip with a reason passes;
- a semantic defect the tests catch passes;
- a stale `find` fails the gate;
- a suite that already fails stops the run.

On this repo, 42 defects are planted and all are caught.

### Git isolation in tests (L-0103)

**Enforces:** `npm run test:git-isolation` (`bin/git-isolation-check.sh`,
logic in `scripts/git-isolation-check.mjs`). Every `tests/bin/*.test.sh`
suite must source `_harness.sh`, which clears inherited `GIT_*` variables.
Each suite is also run with `GIT_DIR`, `GIT_WORK_TREE` and `GIT_INDEX_FILE`
exported to a sentinel repository. The gate fails if the suite then fails, or
if the sentinel's bare flag, refs, local config or index change. This replaces
the old single-suite tripwire `git-env-isolation.test.sh`.

**Why:** a pre-push hook run from a linked worktree exports an absolute
`GIT_DIR`, and that overrides `cd` and `git -C`. In two clones of this
template, test fixtures that ran `git init`, `git config user.*` and
`git add -A` in temp dirs wrote to the real repository instead. The result
was `core.bare = true` and a fixture identity in both main checkouts.

**Proof:** `tests/bin/git-isolation-check.test.sh` runs three fixture suites:

- a clean suite passes;
- a suite with exactly that leak fails, and the check names both the leak and
  the missing harness;
- a suite that is harmless but skips the harness fails the static rule.

## Design tokens

**Enforces:** `npm run design:check` (`scripts/design-tokens.mjs --check`),
the last step of `check`, fails when:

- `design/tokens.json` or `design/tokens.dark.json` is not valid DTCG for
  the supported types, an alias has no target, forms a cycle or changes
  type, a dark override names a token `tokens.json` lacks, or two paths map
  to one CSS property name.
- `design/tokens.css` or a generated card in `design/previews/` is missing,
  out of date, or stale (its group has no tokens left).
- any `design/**/*.html` does not start with `<!-- @dsCard group="…" -->`.

A repo without `design/` skips the check; a `design/` without
`tokens.json` fails it.

**Why:** generated files that nobody regenerates drift from their source,
and a card without its marker silently drops out of the claude.ai/design
Design System pane.

**Updating:** edit the JSON and run `npm run tokens`; never hand-edit the
generated files. The format, the CSS shape and the opt-out list are in
[design tokens](design-tokens.md).

**Proof:** `tests/unit/lib/design-tokens.test.ts`, `design-css.test.ts` and
`design-previews.test.ts` pin the parser, the stylesheet and the cards;
`tests/unit/scripts/design-tokens.test.ts` runs the CLI against throwaway
trees for each failure above, plus the opt-out skip.

## Mutation testing (informational)

**What:** `npm run test:mutation` runs Stryker over `src/**/*.ts`: it mutates
the code and re-runs Vitest per mutant. A surviving mutant is a change the
suite cannot detect. Reports land in `reports/mutation/` (gitignored), with
incremental state so re-runs test only changed mutants. `mutation.yml` runs
it on manual dispatch, optionally scoped by a `mutate` glob.

**Why:** line coverage counts a line run by any test; mutation testing asks
whether any test would fail if that line were wrong.

**Not a gate:** `thresholds.break` is `null` and the workflow never runs on
PRs, so a low score never blocks. If it does not block, it must not look like
it blocks. The workflow fails only when Stryker kills zero mutants, which
means the runner is broken, not the tests.

**Updating:** accept a mutant only with a single-line
`// Stryker disable next-line <Mutator>: <reason>`; never by weakening an
assertion or narrowing `mutate`. Vitest and coverage-v8 majors are ignored by
Dependabot because Vitest 5 made Stryker run zero tests per mutant
([stryker-js#6210](https://github.com/stryker-mutator/stryker-js/issues/6210));
take one deliberately and confirm `npm run test:mutation` still reports kills.

**Override:** `package.json` `overrides` lifts `qs` under `typed-rest-client`
to `^6.16.0`. Stryker 10 depends on `typed-rest-client` 2.x, which pins a `qs`
with open advisories; delete the override once Stryker moves to
`typed-rest-client` 3, which needs no override.

**Origin:** dollyVision (`stryker.config.mjs`, `mutation.yml`; #173 dropped the weekly schedule for a dispatched glob because the full scope does not fit a job; #215 pinned Vitest after a major broke the runner) and
jarvis-ur-ops-automation (manual, advisory workflow).
