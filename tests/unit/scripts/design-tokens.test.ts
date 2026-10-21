import { spawnSync } from 'node:child_process';
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

const SCRIPT = join(import.meta.dirname, '..', '..', '..', 'scripts', 'design-tokens.mjs');

const TOKENS = {
  color: {
    $type: 'color',
    ink: { $value: { colorSpace: 'srgb', components: [0, 0, 0], hex: '#000000' } },
    fg: { $value: '{color.ink}' },
  },
  space: { $type: 'dimension', 1: { $value: { value: 4, unit: 'px' } } },
};
const DARK = {
  color: { fg: { $value: { colorSpace: 'srgb', components: [1, 1, 1], hex: '#ffffff' } } },
};

let root: string;
beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), 'design-tokens-'));
});
afterEach(() => {
  rmSync(root, { recursive: true, force: true });
});

function at(...parts: string[]): string {
  return join(root, 'design', ...parts);
}

function seed(tokens: unknown = TOKENS, dark: unknown = DARK): void {
  mkdirSync(at(), { recursive: true });
  writeFileSync(at('tokens.json'), JSON.stringify(tokens));
  if (dark !== undefined) writeFileSync(at('tokens.dark.json'), JSON.stringify(dark));
}

// Exit status and whether stdout+stderr says `expected`, asserted together.
function run(expected: RegExp, ...args: string[]): { status: number | null; said: boolean } {
  const r = spawnSync(process.execPath, [SCRIPT, '--root', root, ...args], { encoding: 'utf8' });
  return { status: r.status, said: expected.test(r.stdout + r.stderr) };
}

function write(): void {
  expect(run(/wrote/)).toEqual({ status: 0, said: true });
}

describe('design-tokens CLI', () => {
  it('writes tokens.css and the previews', () => {
    seed();
    write();
    expect([
      readFileSync(at('tokens.css'), 'utf8').includes('--color-fg: var(--color-ink);'),
      existsSync(at('previews', 'colors.html')),
      existsSync(at('previews', 'spacing.html')),
    ]).toEqual([true, true, true]);
  });

  it('--check passes right after a write', () => {
    seed();
    write();
    expect(run(/design:check OK/, '--check')).toEqual({ status: 0, said: true });
  });

  it('--check fails naming tokens.css when it was hand-edited', () => {
    seed();
    write();
    writeFileSync(at('tokens.css'), ':root {}\n');
    expect(run(/design\/tokens\.css: out of date/, '--check')).toEqual({ status: 1, said: true });
  });

  it('--check fails naming colors.html when it was hand-edited', () => {
    seed();
    write();
    writeFileSync(at('previews', 'colors.html'), '<!-- @dsCard group="Colors" -->\n');
    expect(run(/design\/previews\/colors\.html: out of date/, '--check')).toEqual({
      status: 1,
      said: true,
    });
  });

  it('--check fails naming a deleted generated card', () => {
    seed();
    write();
    unlinkSync(at('previews', 'spacing.html'));
    expect(run(/design\/previews\/spacing\.html: missing/, '--check')).toEqual({
      status: 1,
      said: true,
    });
  });

  it('--check fails naming a generated card whose group is now empty', () => {
    seed();
    write();
    seed({ color: TOKENS.color });
    expect(run(/design\/previews\/spacing\.html: stale/, '--check')).toEqual({
      status: 1,
      said: true,
    });
  });

  it('a write deletes a stale generated card', () => {
    seed();
    write();
    seed({ color: TOKENS.color });
    write();
    expect(existsSync(at('previews', 'spacing.html'))).toBe(false);
  });

  it('--check fails naming a nested hand-added card without a marker', () => {
    seed();
    write();
    mkdirSync(at('previews', 'extra'));
    writeFileSync(at('previews', 'extra', 'x.html'), '<!doctype html>\n');
    expect(run(/design\/previews\/extra\/x\.html: first line must be/, '--check')).toEqual({
      status: 1,
      said: true,
    });
  });

  it('--check fails on a validation error, printing it', () => {
    seed({ color: { $type: 'color', a: { $value: '#000' } } });
    expect(run(/design\/tokens\.json: color\.a: colors use the object form/, '--check')).toEqual({
      status: 1,
      said: true,
    });
  });

  it('reports an error in the dark file against that file', () => {
    seed(TOKENS, { color: { gone: { $value: 1 } } });
    expect(run(/design\/tokens\.dark\.json: color\.gone: no \$type/, '--check')).toEqual({
      status: 1,
      said: true,
    });
  });

  it('reports invalid JSON naming the file', () => {
    mkdirSync(at());
    writeFileSync(at('tokens.json'), '{');
    expect(run(/design\/tokens\.json: invalid JSON/, '--check')).toEqual({ status: 1, said: true });
  });

  it('reports two paths that collide on one CSS name', () => {
    seed({ n: { $type: 'number', 'a-b': { $value: 1 }, a: { b: { $value: 2 } } } });
    expect(run(/--n-a-b: n\.a-b and n\.a\.b/, '--check')).toEqual({ status: 1, said: true });
  });

  it('--check with no design/ skips', () => {
    expect(run(/no design\/ directory, skipped/, '--check')).toEqual({ status: 0, said: true });
  });

  it('--check fails when previews exist but tokens.json is missing', () => {
    mkdirSync(at('previews'), { recursive: true });
    writeFileSync(at('previews', 'colors.html'), '<!-- @dsCard group="Colors" -->\n');
    expect(run(/design\/tokens\.json: missing/, '--check')).toEqual({ status: 1, said: true });
  });

  it('tokens.dark.json is optional', () => {
    seed(TOKENS, undefined);
    write();
    expect(run(/design:check OK/, '--check')).toEqual({ status: 0, said: true });
  });
});
