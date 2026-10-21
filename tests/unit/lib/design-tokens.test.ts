import { describe, expect, it } from 'vitest';

import { parseTokens } from '../../../src/lib/design-tokens';

const BLUE = { colorSpace: 'srgb', components: [0, 0.4, 1], hex: '#0066ff' };

function errorsOf(doc: unknown): string[] {
  return parseTokens(doc).errors;
}

function valueOf(type: string, value: unknown): unknown {
  return parseTokens({ t: { $type: type, x: { $value: value } } }).tokens[0]?.value;
}

describe('parseTokens', () => {
  it('parses a color token with group-inherited $type', () => {
    expect(parseTokens({ color: { $type: 'color', accent: { $value: BLUE } } })).toEqual({
      tokens: [{ path: 'color.accent', type: 'color', value: BLUE }],
      errors: [],
    });
  });

  it('rejects a bare hex color and shows the object form', () => {
    expect(errorsOf({ color: { $type: 'color', accent: { $value: '#0066ff' } } })).toEqual([
      expect.stringMatching(/^color\.accent: .*colorSpace/),
    ]);
  });

  it('rejects a hex that disagrees with components', () => {
    const stale = { ...BLUE, hex: '#0066fe' };
    expect(errorsOf({ c: { $type: 'color', a: { $value: stale } } })).toEqual([
      expect.stringMatching(/^c\.a: hex #0066fe does not match components \(#0066ff\)/),
    ]);
  });

  it.each([
    ['a component above 1', { colorSpace: 'srgb', components: [0, 0, 1.5] }],
    ['two components', { colorSpace: 'srgb', components: [0, 0] }],
    ['a non-number component', { colorSpace: 'srgb', components: [0, '0', 1] }],
    ['another color space', { colorSpace: 'display-p3', components: [0, 0, 1] }],
    ['a non-string hex', { colorSpace: 'srgb', components: [0, 0, 0], hex: 0 }],
  ])('rejects a color with %s', (_label, value) => {
    expect(errorsOf({ c: { $type: 'color', a: { $value: value } } })).toEqual([
      expect.stringMatching(/^c\.a: /),
    ]);
  });

  it('keeps a valid alpha', () => {
    const value = { colorSpace: 'srgb', components: [0, 0, 0], alpha: 0.5 };
    expect(valueOf('color', value)).toEqual(value);
  });

  it('rejects alpha outside 0–1', () => {
    const value = { colorSpace: 'srgb', components: [0, 0, 0], alpha: 2 };
    expect(errorsOf({ c: { $type: 'color', a: { $value: value } } })).toEqual([
      expect.stringMatching(/^c\.a: alpha/),
    ]);
  });

  it('rejects an unsupported $type naming the token', () => {
    expect(errorsOf({ fx: { drop: { $type: 'shadow', $value: {} } } })).toEqual([
      expect.stringMatching(/^fx\.drop: unsupported \$type "shadow"/),
    ]);
  });

  it('rejects a bad $type on a group', () => {
    expect(errorsOf({ fx: { $type: 'gradient', a: { $value: 1 } } })).toEqual([
      expect.stringMatching(/^fx: unsupported \$type "gradient"/),
    ]);
  });

  it('rejects a token with no $type anywhere', () => {
    expect(errorsOf({ space: { sm: { $value: { value: 8, unit: 'px' } } } })).toEqual([
      expect.stringMatching(/^space\.sm: no \$type/),
    ]);
  });

  it('takes the type from typeOf when the doc has none', () => {
    const parsed = parseTokens({ n: { a: { $value: 2 } } }, (path) =>
      path === 'n.a' ? 'number' : undefined,
    );
    expect(parsed).toEqual({ tokens: [{ path: 'n.a', type: 'number', value: 2 }], errors: [] });
  });

  it.each(['bad name', 'a{b', 'a.b'])(
    'rejects the name %j, which a CSS ident cannot hold',
    (key) => {
      expect(errorsOf({ n: { $type: 'number', [key]: { $value: 1 } } })).toEqual([
        expect.stringContaining(key),
      ]);
    },
  );

  it.each(['$root', '$x'])('rejects the $ key %s outside the allowlist', (key) => {
    expect(errorsOf({ n: { $type: 'number', [key]: { $value: 1 } } })).toEqual([
      expect.stringContaining(key),
    ]);
  });

  it('rejects an unknown $ key on a token', () => {
    expect(errorsOf({ n: { $type: 'number', a: { $value: 1, $foo: 2 } } })).toEqual([
      'n.a: unknown key "$foo"',
    ]);
  });

  it('allows $description, $extensions and $deprecated', () => {
    const token = { $value: 1, $description: 'd', $extensions: {}, $deprecated: true };
    expect(errorsOf({ n: { $type: 'number', $description: 'g', a: token } })).toEqual([]);
  });

  it('rejects a token that also has children', () => {
    const doc = { color: { $type: 'color', accent: { $value: BLUE, fg: { $value: BLUE } } } };
    expect(errorsOf(doc)).toEqual([
      expect.stringMatching(/^color\.accent: a token cannot have child tokens/),
    ]);
  });

  it('rejects a non-object group node', () => {
    expect(errorsOf({ n: { $type: 'number', a: 3 } })).toEqual([
      expect.stringMatching(/^n\.a: expected a group or a token/),
    ]);
  });

  it('rejects a non-object document', () => {
    expect(parseTokens(42).errors).toEqual(['tokens: document must be an object']);
  });

  it('turns "{color.accent}" into an alias', () => {
    expect(valueOf('color', '{color.accent}')).toEqual({ alias: 'color.accent' });
  });

  it.each([
    ['dimension', { value: 8, unit: 'px' }],
    ['dimension', { value: 1.5, unit: 'rem' }],
    ['duration', { value: 200, unit: 'ms' }],
    ['duration', { value: 1, unit: 's' }],
    ['fontFamily', 'Inter'],
    ['fontFamily', ['Segoe UI', 'system-ui']],
    ['fontWeight', 700],
    ['number', 1.5],
  ])('accepts a %s of %j', (type, value) => {
    expect(valueOf(type, value)).toEqual(value);
  });

  it.each([
    ['bold', 700],
    ['book', 400],
    ['extra-black', 950],
  ])('normalizes the fontWeight keyword %s to %d', (keyword, weight) => {
    expect(valueOf('fontWeight', keyword)).toBe(weight);
  });

  it.each([
    ['dimension', { value: 1, unit: 'em' }],
    ['dimension', { value: '8', unit: 'px' }],
    ['duration', { value: 1, unit: 'min' }],
    ['fontFamily', ['Inter', 3]],
    ['fontFamily', []],
    ['fontWeight', 'heavyish'],
    ['fontWeight', 1001],
    ['fontWeight', 0],
    ['number', '3'],
    ['number', Number.POSITIVE_INFINITY],
  ])('rejects a %s of %j', (type, value) => {
    expect(errorsOf({ t: { $type: type, x: { $value: value } } })).toEqual([
      expect.stringMatching(/^t\.x: /),
    ]);
  });
});
