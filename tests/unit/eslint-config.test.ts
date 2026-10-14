import { join } from 'node:path';

import { ESLint } from 'eslint';
import { describe, expect, it } from 'vitest';

const ROOT = join(import.meta.dirname, '..', '..');
// lintText needs a path the project service already knows; the snippet replaces its contents.
const TEST_FILE = join(ROOT, 'tests', 'unit', 'index.test.ts');
const SRC_FILE = join(ROOT, 'src', 'index.ts');

const eslint = new ESLint({ cwd: ROOT });

async function ruleIds(code: string, filePath: string): Promise<(string | null)[]> {
  const [result] = await eslint.lintText(code, { filePath });
  return (result?.messages ?? []).map((m) => m.ruleId);
}

const HEADER = "import { describe, expect, it } from 'vitest';\n";

const PLANTED: [rule: string, snippet: string][] = [
  ['vitest/expect-expect', "it('asserts nothing', () => { void 1; });"],
  [
    'vitest/require-to-throw-message',
    "it('throws', () => { expect(() => { throw new Error('x'); }).toThrow(); });",
  ],
  [
    'vitest/no-conditional-expect',
    "it('catches', () => { try { JSON.parse('{'); } catch (e) { expect(e).toBeInstanceOf(SyntaxError); } });",
  ],
  ['vitest/valid-expect', "it('three args', () => { expect(1, 'a', 'b').toBe(1); });"],
  [
    'vitest/no-identical-title',
    "describe('d', () => { it('same', () => { expect(1).toBe(1); }); it('same', () => { expect(2).toBe(2); }); });",
  ],
  ['vitest/no-focused-tests', "it.only('focused', () => { expect(1).toBe(1); });"],
  ['vitest/no-disabled-tests', "it.skip('skipped', () => { expect(1).toBe(1); });"],
  [
    'no-restricted-syntax',
    "it('double', () => { const n = 'x' as unknown as number; expect(n).toBe(1); });",
  ],
];

// Type-aware linting builds a TS program on first use, which can outlast the 5s default.
describe('eslint test-integrity rules', { timeout: 30_000 }, () => {
  it.each(PLANTED)('%s fires on a planted defect', async (rule, snippet) => {
    expect(await ruleIds(HEADER + snippet + '\n', TEST_FILE)).toContain(rule);
  });

  it('passes a clean test that names its assertion', async () => {
    const clean =
      HEADER +
      "describe('d', () => {\n  it('adds', () => {\n    expect(1 + 1, 'sum').toBe(2);\n  });\n});\n";
    expect(await ruleIds(clean, TEST_FILE)).toEqual([]);
  });

  it('allows a single assertion', async () => {
    const code = "export const n = JSON.parse('1') as number;\n";
    expect(await ruleIds(code, SRC_FILE)).toEqual([]);
  });

  it('bans a double assertion in src too', async () => {
    const code = "export const n = 'x' as unknown as number;\n";
    expect(await ruleIds(code, SRC_FILE)).toContain('no-restricted-syntax');
  });
});

const lines = (n: number, line: (i: number) => string): string =>
  Array.from({ length: n }, (_, i) => line(i)).join('\n') + '\n';
const constants = (n: number): string =>
  lines(n, (i) => `export const v${String(i)} = ${String(i)};`);
// A function whose body has `n` statements: signature and closing brace add 2 lines.
const fn = (n: number): string =>
  `export function f(): number {\n  let n = 0;\n${lines(n - 4, () => '  n += 1;')}  return n;\n}\n`;

describe('eslint monolith limits', { timeout: 30_000 }, () => {
  it('src: 400 code lines pass, blank lines and comments not counted', async () => {
    const code = constants(400) + lines(50, () => '') + lines(50, () => '// note');
    expect(await ruleIds(code, SRC_FILE)).toEqual([]);
  });

  it('src: a 401st code line fails max-lines', async () => {
    expect(await ruleIds(constants(401), SRC_FILE)).toContain('max-lines');
  });

  it('src: a 150-line function passes', async () => {
    expect(await ruleIds(fn(150), SRC_FILE)).toEqual([]);
  });

  it('src: a 151-line function fails max-lines-per-function', async () => {
    expect(await ruleIds(fn(151), SRC_FILE)).toContain('max-lines-per-function');
  });

  it('scripts: the same limits apply to repo tooling', async () => {
    const script = join(ROOT, 'scripts', 'check-docs.mjs');
    expect(await ruleIds(constants(401), script)).toContain('max-lines');
  });

  it('tests: a 200-line describe callback is allowed', async () => {
    const code =
      HEADER +
      `describe('d', () => {\n  it('sums', () => {\n    let n = 0;\n${lines(195, () => '    n += 1;')}    expect(n).toBe(195);\n  });\n});\n`;
    expect(await ruleIds(code, TEST_FILE)).toEqual([]);
  });

  it('tests: a file over 600 code lines fails max-lines', async () => {
    const code =
      HEADER +
      lines(600, (i) => `it('t${String(i)}', () => { expect(${String(i)}).toBe(${String(i)}); });`);
    expect(await ruleIds(code, TEST_FILE)).toContain('max-lines');
  });
});
