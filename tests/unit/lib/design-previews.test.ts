import { describe, expect, it } from 'vitest';

import { CARD_FILES, emitPreviews, missingDsCard } from '../../../src/lib/design-previews';
import type { Token } from '../../../src/lib/design-tokens';

const name = (path: string): string => `--${path.split('.').join('-')}`;
const rgb = (r: number) => ({
  colorSpace: 'srgb' as const,
  components: [r, 0, 0] as [number, number, number],
});

const RED: Token = { path: 'color.a', type: 'color', value: rgb(1) };

const TOKENS: Token[] = [
  RED,
  { path: 'color.b', type: 'color', value: rgb(0) },
  { path: 'color.c', type: 'color', value: { alias: 'color.a' } },
  { path: 'font.family.sans', type: 'fontFamily', value: ['A<b"c', 'system-ui'] },
  { path: 'font.size.md', type: 'dimension', value: { value: 1, unit: 'rem' } },
  { path: 'font.weight.bold', type: 'fontWeight', value: 700 },
  { path: 'font.leading', type: 'number', value: 1.5 },
  { path: 'space.1', type: 'dimension', value: { value: 4, unit: 'px' } },
  { path: 'radius.sm', type: 'dimension', value: { value: 2, unit: 'px' } },
];

const cards = emitPreviews(TOKENS, name);

function card(file: string): string {
  return cards.get(file) ?? '';
}

describe('emitPreviews', () => {
  it('emits one card per file name, in CARD_FILES order', () => {
    expect([...cards.keys()]).toEqual(['colors.html', 'type.html', 'spacing.html', 'radius.html']);
  });

  it('lists exactly the generated card names', () => {
    expect(CARD_FILES).toEqual(['colors.html', 'type.html', 'spacing.html', 'radius.html']);
  });

  it.each([
    ['colors.html', 'Colors'],
    ['type.html', 'Type'],
    ['spacing.html', 'Spacing'],
    ['radius.html', 'Radius'],
  ])('%s starts with its @dsCard line', (file, group) => {
    expect(card(file).startsWith(`<!-- @dsCard group="${group}" -->\n<!doctype html>`)).toBe(true);
  });

  it.each([...CARD_FILES])('%s links ../tokens.css', (file) => {
    expect(card(file)).toContain('<link rel="stylesheet" href="../tokens.css">');
  });

  it.each([...CARD_FILES])('%s has no script and no external URL', (file) => {
    expect(/<script|https?:/i.test(card(file))).toBe(false);
  });

  it('shows one swatch per color token, painted from its custom property', () => {
    expect(
      card('colors.html').match(
        /data-token="color\.[a-c]" style="background: var\(--color-[a-c]\)"/g,
      ),
    ).toHaveLength(3);
  });

  it('applies each type token through the matching property', () => {
    const type = card('type.html');
    expect([
      type.includes('style="font-family: var(--font-family-sans)"'),
      type.includes('style="font-size: var(--font-size-md)"'),
      type.includes('style="font-weight: var(--font-weight-bold)"'),
      type.includes('data-token="font.leading"'),
    ]).toEqual([true, true, true, true]);
  });

  it('shows a single-string family as written', () => {
    const solo: Token = { path: 'font.family.serif', type: 'fontFamily', value: 'Georgia' };
    expect(emitPreviews([solo], name).get('type.html')).toContain('<small>Georgia</small>');
  });

  it('escapes token values in HTML', () => {
    expect(card('type.html')).toContain('A&lt;b&quot;c, system-ui');
  });

  it('sizes spacing bars and radius boxes from their tokens', () => {
    expect([
      card('spacing.html').includes('style="width: var(--space-1)"'),
      card('radius.html').includes('style="border-radius: var(--radius-sm)"'),
    ]).toEqual([true, true]);
  });

  it('omits a card whose group has no tokens', () => {
    expect([...emitPreviews([RED], name).keys()]).toEqual(['colors.html']);
  });

  it('ignores tokens outside the four groups', () => {
    expect([
      ...emitPreviews([{ path: 'motion.fast', type: 'number', value: 1 }], name).keys(),
    ]).toEqual([]);
  });
});

describe('missingDsCard', () => {
  const good = '<!-- @dsCard group="Colors" -->\n<!doctype html>';

  it('accepts a file whose first line is the marker', () => {
    expect(missingDsCard([{ path: 'ok.html', content: good }])).toEqual([]);
  });

  it('flags a blank first line, a marker on line 2, and a marker without a group', () => {
    expect(
      missingDsCard([
        { path: 'blank.html', content: `\n${good}` },
        { path: 'second.html', content: `<!doctype html>\n${good}` },
        { path: 'nogroup.html', content: '<!-- @dsCard -->\n<!doctype html>' },
      ]),
    ).toEqual(['blank.html', 'second.html', 'nogroup.html']);
  });
});

describe('missingDsCard group line', () => {
  it('flags a group that spills past the first line', () => {
    const content = '<!-- @dsCard group="Colors\nstill-group" -->\n<!doctype html>';
    expect(missingDsCard([{ path: 'spill.html', content }])).toEqual(['spill.html']);
  });
});
