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
