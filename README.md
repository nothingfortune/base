# base

<!-- One line: what this project is. -->

Template repository: strict TypeScript, one quality gate, CI that runs it.

## Quickstart

```bash
nvm use
npm install
npm run check
```

## Using this template

1. Create a repo from this template, clone it, and run `npm install`.
2. Run `bin/init.sh <package-name> [--title "Title"] [--github]`. It renames the
   package, removes the template's own docs (this section included), and with
   `--github` applies the ruleset and repo settings via `bin/setup-github.sh`
   (repo settings do not copy from a template). Then it deletes itself and
   prints the remaining steps:
3. Fill in the Project section of `CLAUDE.md`, this README's description, and
   the holder and year in `LICENSE`.
4. Adjust `tsconfig.json` for the project type — see the last section of
   `CLAUDE.md`.
5. Delete the placeholder `src/index.ts` and `tests/unit/index.test.ts` once real
   code exists. In that same first commit with real code, set the coverage
   `thresholds` in `vitest.config.ts` to about 1 point under what
   `npm run test:coverage` measures. This one-time calibration is the only time
   a floor goes down; afterwards floors only rise (see
   [quality gates](docs/guides/quality-gates.md#coverage-floor-and-drift-ratchet)).
6. Delete what you do not need: `tests/e2e/`, and the PR-review scripts in
   `bin/` if you skip the AI review loop. Keep `scripts/` and
   `bin/comment-density.sh`: `npm run check` runs them. Keep `e2e.yml` even
   while dormant: `bin/setup-github.sh` requires its `e2e / e2e` check. If you
   delete it, run setup with `SETUP_REQUIRED_CHECKS=gate`. No UI? Remove the
   design tokens with the list in
   [design tokens](docs/guides/design-tokens.md#opting-out).

`bin/setup-github.sh` stays and is safe to re-run whenever settings drift.

## Scripts

| Command                   | Purpose                                                        |
| ------------------------- | -------------------------------------------------------------- |
| `npm run check`           | The gate: every check below; coverage stands in for `npm test` |
| `npm run typecheck`       | `tsc --noEmit`                                                 |
| `npm run lint`            | ESLint, zero warnings allowed                                  |
| `npm run lint:fix`        | ESLint with autofix                                            |
| `npm run comment-density` | Multi-line comment block ratchet                               |
| `npm run integrity`       | Reference, dead-code and cycle checks (integrity engine)       |
| `npm run format`          | Prettier, writing changes                                      |
| `npm run format:check`    | Prettier, check only                                           |
| `npm test`                | Vitest, single run                                             |
| `npm run test:watch`      | Vitest, watch mode                                             |
| `npm run test:coverage`   | Vitest with coverage floors                                    |
| `npm run coverage:drift`  | Coverage floors must track measured coverage                   |
| `npm run test:bin`        | Bash tests for `bin/` scripts and repo guards                  |
| `npm run test:mutation`   | Stryker mutation testing (informational)                       |
| `npm run docs:check`      | Markdown links and living-doc paths resolve                    |
| `npm run tokens`          | Regenerate design-token CSS and preview cards                  |
| `npm run design:check`    | Design tokens valid and generated files current                |

The gates are explained in [quality gates](docs/guides/quality-gates.md).

## Layout

Application code lives in `src/`, split into `lib/` (reusable logic), `types/`
(shared types), and `config/` (configuration and environment). Unit tests live
in `tests/unit/` mirroring `src/` paths; `tests/e2e/` is reserved for Playwright,
which is not installed by default. Shell scripts go in `bin/`, repo-local Node
tooling in `scripts/`, design tokens and their preview cards in `design/`, and
documentation in `docs/`.

Conventions — including testing and CI rules — are documented in `CLAUDE.md`.

## License

MIT
