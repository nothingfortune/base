# Spending CI minutes and review quota well

GitHub Actions minutes and the Codex/Copilot review quota are finite, and a
fast-moving branch burns both far quicker than it needs to. Nothing here
removes a check — the point is to learn what a check would tell us _before_
paying for it.

(Adapted from the outerReach original; the levers are the same, the numbers
are this stack's.)

## The shape of the spend

|                    | cost                        | who pays it     |
| ------------------ | --------------------------- | --------------- |
| `e2e` (Playwright) | the expensive job, per push | Actions minutes |
| `check` (the gate) | cheap, per push             | Actions minutes |
| Copilot review     | one per PR _review event_   | review quota    |
| Codex review       | one per PR _review event_   | review quota    |

Three pushes in ten minutes on a ready PR is three of everything — three
e2e runs and potentially three re-reviews.

## Three levers, in order of payoff

### 1. The pre-push gate — know before you push

`.githooks/pre-push` runs `npm run check` automatically on `git push`
(wired by `npm install` via the `postinstall` script; the gate covers the
current checkout, and pushes of other refs pass through with a warning
since they can't be validated from here). A push that passes it should not
fail the CI gate for any reason other than infrastructure.

```bash
git push --no-verify   # emergency bypass; you own what happens next
```

### 2. Open the PR as a **draft**

Both review bots trigger when a PR is _opened for review_, _marked ready_,
or explicitly summoned — a draft is not reviewed until you say so. The
`e2e` job also skips on drafts. The cheap gate still runs on every push,
so you keep the signal that costs almost nothing.

**Work in draft, push as often as you like, mark ready once.** One full CI
run and one review per PR, instead of one per push.

```bash
gh pr create --draft ...
gh pr ready <n>          # NOW e2e runs and the bots review
```

`ready_for_review` is in the e2e workflow's `types:` list precisely so
that flip triggers the real run. And because GitHub counts a skipped job
as satisfying a required check, the reviews-done gate must always run as
`DRAFT_SKIPPED_CHECK=e2e bin/pr-reviews-done.sh <PR> …` — it refuses a
merge-ready claim riding a draft-era skip.

### 3. Batch the pushes

`concurrency: cancel-in-progress: true` kills a superseded run when you
push again quickly, so rapid pushes waste less than they might — but a run
that already started the e2e has spent those minutes. Finish a thought,
then push.

## What is deliberately NOT done

- **No check was removed or made non-blocking.** Everything the gate
  asserts, it still asserts.
- **e2e is not dropped from local practice** — its local equivalent is the
  project's `test:e2e` script. (This template ships the CI wiring only;
  per CLAUDE.md, Playwright and the script are added per project.)
  Skipping it on drafts is only safe because you can run it yourself; if
  you bypass the pre-push gate with `--no-verify`, mark the PR ready and
  let CI do the job you skipped.
