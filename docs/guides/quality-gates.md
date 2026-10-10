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
