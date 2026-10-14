import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

const SCRIPT = join(import.meta.dirname, '..', '..', '..', 'scripts', 'check-coverage-drift.mjs');

type Metrics = Record<'statements' | 'branches' | 'functions' | 'lines', number>;

let root: string;
beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), 'coverage-drift-'));
});
afterEach(() => {
  rmSync(root, { recursive: true, force: true });
});

function writeConfig(floors: Partial<Metrics>): void {
  const lines = Object.entries(floors).map(([k, v]) => `        ${k}: ${String(v)},`);
  writeFileSync(
    join(root, 'vitest.config.ts'),
    `export default {\n  test: {\n    coverage: {\n      thresholds: {\n${lines.join('\n')}\n      },\n    },\n  },\n};\n`,
  );
}

function writeSummary(measured: Metrics): void {
  mkdirSync(join(root, 'coverage'));
  const total = Object.fromEntries(Object.entries(measured).map(([k, pct]) => [k, { pct }]));
  writeFileSync(join(root, 'coverage', 'coverage-summary.json'), JSON.stringify({ total }));
}

// The exit status and whether the output says `expected`, asserted together.
function run(expected: RegExp): { status: number | null; said: boolean } {
  const r = spawnSync(process.execPath, [SCRIPT, '--root', root], { encoding: 'utf8' });
  return { status: r.status, said: expected.test(r.stdout + r.stderr) };
}

const FLOORS: Metrics = { statements: 90, branches: 85, functions: 90, lines: 90 };

describe('check-coverage-drift', () => {
  it('passes when every metric is within 2 points of its floor', () => {
    writeConfig(FLOORS);
    writeSummary({ statements: 92, branches: 86.5, functions: 90, lines: 91 });
    expect(run(/coverage-drift OK/)).toEqual({ status: 0, said: true });
  });

  it('fails when a metric climbs more than 2 points above its floor', () => {
    writeConfig(FLOORS);
    writeSummary({ statements: 91, branches: 87.01, functions: 90, lines: 90 });
    expect(run(/branches .*raise this/)).toEqual({ status: 1, said: true });
  });

  it('fails closed when the coverage summary is missing', () => {
    writeConfig(FLOORS);
    expect(run(/cannot read/)).toEqual({ status: 1, said: true });
  });

  it('fails when a metric has no floor in vitest.config.ts', () => {
    writeConfig({ statements: 90, functions: 90, lines: 90 });
    writeSummary({ statements: 90, branches: 85, functions: 90, lines: 90 });
    expect(run(/no floor for branches/)).toEqual({ status: 1, said: true });
  });
});
