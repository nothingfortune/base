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
   code exists.
6. Adjust `tsconfig.json` for the project type — see the last section of
   `CLAUDE.md`.
7. Delete what you do not need: `bin/`, `scripts/`, `tests/e2e/`.

## Scripts

| Command                | Purpose                                        |
| ---------------------- | ---------------------------------------------- |
| `npm run check`        | The gate: typecheck, lint, format check, tests |
| `npm run typecheck`    | `tsc --noEmit`                                 |
| `npm run lint`         | ESLint                                         |
| `npm run lint:fix`     | ESLint with autofix                            |
| `npm run format`       | Prettier, writing changes                      |
| `npm run format:check` | Prettier, check only                           |
| `npm test`             | Vitest, single run                             |
| `npm run test:watch`   | Vitest, watch mode                             |

## Layout

Application code lives in `src/`, split into `lib/` (reusable logic), `types/`
(shared types), and `config/` (configuration and environment). Unit tests live
in `tests/unit/` mirroring `src/` paths; `tests/e2e/` is reserved for Playwright,
which is not installed by default. Shell scripts go in `bin/`, repo-local Node
tooling in `scripts/`, and documentation in `docs/`.

Conventions — including testing and CI rules — are documented in `CLAUDE.md`.

## License

MIT
