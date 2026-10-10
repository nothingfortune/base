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

1. Rename `name` in `package.json`; update this README's title and description.
2. Update the holder and year in `LICENSE`.
3. Fill in the Project section of `CLAUDE.md`.
4. Delete the template's own design doc from `docs/designs/` and plan from
   `docs/toDo/completed/`.
5. Delete the placeholder `src/index.ts` and `tests/unit/index.test.ts` once real
   code exists. In that same first commit with real code, set the coverage
   `thresholds` in `vitest.config.ts` to about 1 point under what
   `npm run test:coverage` measures. This one-time calibration is the only time
   a floor goes down; afterwards floors only rise (see
   [quality gates](docs/guides/quality-gates.md#coverage-floor-and-drift-ratchet)).
6. Adjust `tsconfig.json` for the project type — see the last section of
   `CLAUDE.md`.
7. Delete what you do not need: `tests/e2e/`, and the PR-review scripts in
   `bin/` if you skip the AI review loop. Keep `scripts/` and
   `bin/comment-density.sh`: `npm run check` runs them.

## Scripts

| Command                   | Purpose                                                        |
| ------------------------- | -------------------------------------------------------------- |
| `npm run check`           | The gate: every check below; coverage stands in for `npm test` |
| `npm run typecheck`       | `tsc --noEmit`                                                 |
| `npm run lint`            | ESLint, zero warnings allowed                                  |
| `npm run lint:fix`        | ESLint with autofix                                            |
| `npm run comment-density` | Multi-line comment block ratchet                               |
| `npm run knip`            | Dead code and unused dependencies                              |
| `npm run format`          | Prettier, writing changes                                      |
| `npm run format:check`    | Prettier, check only                                           |
| `npm test`                | Vitest, single run                                             |
| `npm run test:watch`      | Vitest, watch mode                                             |
| `npm run test:coverage`   | Vitest with coverage floors                                    |
| `npm run coverage:drift`  | Coverage floors must track measured coverage                   |
| `npm run test:bin`        | Bash tests for `bin/` scripts and repo guards                  |
| `npm run docs:check`      | Markdown links and living-doc paths resolve                    |

The gates are explained in [quality gates](docs/guides/quality-gates.md).

## Layout

Application code lives in `src/`, split into `lib/` (reusable logic), `types/`
(shared types), and `config/` (configuration and environment). Unit tests live
in `tests/unit/` mirroring `src/` paths; `tests/e2e/` is reserved for Playwright,
which is not installed by default. Shell scripts go in `bin/`, repo-local Node
tooling in `scripts/`, and documentation in `docs/`.

Conventions — including testing and CI rules — are documented in `CLAUDE.md`.

## License

MIT
