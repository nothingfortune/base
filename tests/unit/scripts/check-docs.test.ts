import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

const SCRIPT = join(import.meta.dirname, '..', '..', '..', 'scripts', 'check-docs.mjs');

// A hook-exported GIT_DIR would point fixture git commands at the real repo.
const ENV = Object.fromEntries(
  Object.entries(process.env).filter(([key]) => !key.startsWith('GIT_')),
);

function git(cwd: string, ...args: string[]): void {
  const r = spawnSync('git', args, { cwd, env: ENV, encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')} failed: ${r.stderr}`);
}

function fixture(files: Record<string, string>, untracked: Record<string, string> = {}): string {
  const root = mkdtempSync(join(tmpdir(), 'check-docs-'));
  git(root, 'init', '-q');
  for (const [path, contents] of Object.entries({ ...files, ...untracked })) {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), contents);
  }
  git(root, 'add', '--', ...Object.keys(files));
  return root;
}

function check(root: string): { status: number | null; output: string } {
  const r = spawnSync(process.execPath, [SCRIPT, '--root', root], { env: ENV, encoding: 'utf8' });
  return { status: r.status, output: r.stdout + r.stderr };
}

const FENCE = '```';

const PLANTED = {
  'bin/real.sh': '',
  'docs/guides/real.md': '# Real\n',
  'README.md': [
    '# Fixture',
    '[ok](docs/guides/real.md) and [dir](bin/) and [web](https://example.com) and [anchor](#top)',
    '[broken](docs/missing.md)',
    'Run `bin/real.sh`, not `bin/missing.sh`.',
    'Placeholders like `src/lib/<name>.ts` and generated `coverage/index.html` are exempt.',
    FENCE,
    '[fenced](fenced-missing.md) `bin/fenced-missing.sh`',
    FENCE,
    'Inline code is not a link: `[x](inline-missing.md)`.',
    '[escape](../outside.md)',
    '[fragment](docs/guides/real.md#section) [frag-broken](docs/nope.md#section)',
  ].join('\n'),
  'docs/guides/living.md': 'See `docs/guides/gone.md` and [up](../../README.md).\n',
  'docs/toDo/plan.md':
    'A record mentions `bin/retired.sh`; its [link](gone.md) still must resolve.\n',
};
const UNTRACKED = { 'notes.md': '[untracked](nowhere.md)\n' };

describe('check-docs on planted defects', () => {
  let root: string;
  let result: { status: number | null; output: string };
  beforeAll(() => {
    root = fixture(PLANTED, UNTRACKED);
    result = check(root);
  });
  afterAll(() => {
    rmSync(root, { recursive: true, force: true });
  });

  it('exits non-zero', () => {
    expect(result.status).toBe(1);
  });

  it.each([
    ['a broken relative link', 'README.md:3 broken link → docs/missing.md'],
    ['a missing backticked path in a living doc', 'README.md:4 missing path → bin/missing.sh'],
    ['a link escaping the repo', 'README.md:10 broken link → ../outside.md'],
    ['a broken link with a fragment', 'README.md:11 broken link → docs/nope.md'],
    ['a missing path in docs/guides', 'docs/guides/living.md:1 missing path → docs/guides/gone.md'],
    ['a broken link in a dated record', 'docs/toDo/plan.md:1 broken link → gone.md'],
  ])('reports %s', (_name, line) => {
    expect(result.output).toContain(line);
  });

  it('reports nothing else: controls, code, records and untracked files stay quiet', () => {
    const reported = result.output.split('\n').filter((l) => l.includes(' → '));
    expect(reported).toHaveLength(6);
  });
});

describe('check-docs on clean docs', () => {
  it('passes and says how many files it checked', () => {
    const root = fixture({
      'README.md': '[guide](docs/guides/a.md) `docs/guides/a.md`\n',
      'docs/guides/a.md': '[back](../../README.md)\n',
    });
    const result = check(root);
    rmSync(root, { recursive: true, force: true });
    expect(result).toEqual({ status: 0, output: 'docs:check OK — 2 markdown files checked\n' });
  });
});
