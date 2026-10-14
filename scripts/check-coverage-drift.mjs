#!/usr/bin/env node
// Fails when measured coverage climbs more than MAX_GAP above its floor: a floor left behind catches nothing.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// Never widen this to pass: raise the floor instead.
const MAX_GAP = 2;
const METRICS = ['statements', 'branches', 'functions', 'lines'];

const rootFlag = process.argv.indexOf('--root');
const root =
  rootFlag === -1
    ? join(dirname(fileURLToPath(import.meta.url)), '..')
    : (process.argv[rootFlag + 1] ?? '');
const summaryPath = join(root, 'coverage', 'coverage-summary.json');
const configPath = join(root, 'vitest.config.ts');

let summary;
try {
  summary = JSON.parse(readFileSync(summaryPath, 'utf8'));
} catch {
  // Fail closed: this runs after test:coverage, so a missing summary is a misconfigured reporter.
  console.error(`coverage-drift: cannot read ${summaryPath}`);
  console.error('Run `npm run test:coverage` first; the json-summary reporter writes it.');
  process.exit(1);
}

const config = readFileSync(configPath, 'utf8');
const thresholds = config.slice(config.indexOf('thresholds: {'));

const rows = [];
let worst = 0;
for (const metric of METRICS) {
  const measured = summary.total?.[metric]?.pct;
  if (typeof measured !== 'number') {
    console.error(`coverage-drift: no measured total for ${metric}`);
    process.exit(1);
  }
  const found = new RegExp(`${metric}:\\s*([0-9.]+)`).exec(thresholds);
  if (found === null) {
    console.error(`coverage-drift: no floor for ${metric} in vitest.config.ts`);
    process.exit(1);
  }
  const floor = Number(found[1]);
  const gap = Number((measured - floor).toFixed(2));
  worst = Math.max(worst, gap);
  rows.push({ metric, measured, floor, gap });
}

const width = Math.max(...METRICS.map((m) => m.length));
for (const { metric, measured, floor, gap } of rows) {
  const flag = gap > MAX_GAP ? '  <-- raise this' : '';
  console.log(
    `  ${metric.padEnd(width)}  measured ${String(measured).padStart(6)}  floor ${String(floor).padStart(5)}  gap ${gap.toFixed(2).padStart(5)}${flag}`,
  );
}

if (worst > MAX_GAP) {
  console.error(
    `\ncoverage-drift: the floor is ${worst.toFixed(2)} points below measured (max ${MAX_GAP}).`,
  );
  console.error('Coverage rose and the floor did not follow, so it no longer catches a slide.');
  console.error('Raise the `thresholds` in vitest.config.ts to ~1 point under the measured');
  console.error('totals above. Do NOT widen MAX_GAP: that is the check, not the obstacle.');
  process.exit(1);
}

console.log(`coverage-drift OK — floor is within ${MAX_GAP} points of measured`);
