# Why the testing rules exist

`CLAUDE.md` states each rule in one line. This guide gives the failure mode
behind each, in the same order, and where the rule came from, so a rule can be
judged against what it was for. Sources are sibling projects built from this
template; where a specific incident is on record it is cited.

## Watch it fail for the right reason

A test seen only green may pass on the old code too; the red run is the
evidence it tests the bug. Source: dollyVision `CLAUDE.md`.

## Assert what separates the branches

An assertion on output both branches produce stays green when the new branch
is deleted. Source: dollyVision `CLAUDE.md`.

## Drive the precondition

A test that assumes the state a step depends on can pass without the step ever
running. Source: dollyVision `CLAUDE.md`.

## A test may not depend on another defect

When a fix breaks an unrelated test, that test was passing because of the bug;
restoring the bug is the wrong repair. Source: dollyVision `CLAUDE.md`.

## A green exit code is not evidence

A scripted edit can exit 0 having matched nothing, and a new scanner can pass
by scanning an empty set. Source: outerReach `CLAUDE.md` testing rules.

## A suppression marker is a claim

A marker with a vague reason reads as reviewed while excusing nothing
checkable. Source: outerReach `CLAUDE.md` testing rules.

## A spec sentence gets its test in the same change

Untested spec sentences drift from the code; ordering claims pass with
in-order input. Source: outerReach `CLAUDE.md` testing rules.

## A failure reported as a return value gets a test that makes it fail

Nothing forces a caller to look at a return value, so the failure path goes
unexercised unless a test drives it. Source: outerReach `CLAUDE.md`.

## Count the records behind a displayed count

Two numbers from the same code agree with each other while both are wrong.
Source: outerReach `CLAUDE.md`.

## Assert absence against the data source

An absence check against the first render can pass before the data has
loaded. Source: dollyVision #224.

## Run the whole suite

fleetDemo logged defects "found by running things that had never been run"
(`DESIGN-GAPS-LOG.md` G58).

## Review-loop gates refuse, they do not report

`bin/pr-reviews-done.sh` named unanswered review threads in its summary and
posted anyway with exit 0, so `pr-reviews-done.sh && gh pr merge` merged over
an unread finding. Gates exit non-zero; a verdict that names a problem is not a
gate. Source: dollyVision #85.

## Repo-building tests clear git's environment

A hook or `git rebase --exec` exports `GIT_DIR`, absolute in a linked worktree,
which overrides `git -C`. dollyVision's bin tests, run from a worktree's
pre-push, rewrote the real repository. `tests/bin/_harness.sh` unsets git's
local variables. Source: dollyVision #207.
