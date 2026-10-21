type TokenType = 'color' | 'dimension' | 'fontFamily' | 'fontWeight' | 'duration' | 'number';

interface Color {
  colorSpace: 'srgb';
  components: [number, number, number];
  alpha?: number;
  hex?: string;
}

interface Measure {
  value: number;
  unit: string;
}

type TokenValue = Color | Measure | string | readonly string[] | number;

export interface Token {
  path: string;
  type: TokenType;
  value: TokenValue | { alias: string };
}

export interface Parsed {
  tokens: Token[];
  errors: string[];
}

type Check = { ok: true; value: TokenValue } | { ok: false; reason: string };

const TYPES: readonly string[] = [
  'color',
  'dimension',
  'fontFamily',
  'fontWeight',
  'duration',
  'number',
];
const META = new Set(['$type', '$value', '$description', '$extensions', '$deprecated']);
const NAME = /^[A-Za-z0-9_-]+$/;
const ALIAS = /^\{([^{}]+)\}$/;
const COLOR_FORM =
  'colors use the object form {"colorSpace": "srgb", "components": [r, g, b], "hex": "#rrggbb"}, each component 0–1';

// DTCG 2025.10 fontWeight keywords: https://www.designtokens.org/tr/2025.10/format/#font-weight
const WEIGHTS: Readonly<Record<string, number>> = {
  thin: 100,
  hairline: 100,
  'extra-light': 200,
  'ultra-light': 200,
  light: 300,
  normal: 400,
  regular: 400,
  book: 400,
  medium: 500,
  'semi-bold': 600,
  'demi-bold': 600,
  bold: 700,
  'extra-bold': 800,
  'ultra-bold': 800,
  black: 900,
  heavy: 900,
  'extra-black': 950,
  'ultra-black': 950,
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isUnit(value: unknown): value is number {
  return typeof value === 'number' && value >= 0 && value <= 1;
}

function isTriple(value: unknown): value is [number, number, number] {
  return Array.isArray(value) && value.length === 3 && value.every(isUnit);
}

function isTokenType(value: string): value is TokenType {
  return TYPES.includes(value);
}

function ok(value: TokenValue): Check {
  return { ok: true, value };
}

function fail(reason: string): Check {
  return { ok: false, reason };
}

function hexOf(components: readonly number[]): string {
  return `#${components
    .map((c) =>
      Math.round(c * 255)
        .toString(16)
        .padStart(2, '0'),
    )
    .join('')}`;
}

function checkColor(raw: unknown): Check {
  if (!isRecord(raw) || raw.colorSpace !== 'srgb') return fail(COLOR_FORM);
  const c = raw.components;
  if (!isTriple(c)) return fail(COLOR_FORM);
  const components: [number, number, number] = [c[0], c[1], c[2]];
  const color: Color = { colorSpace: 'srgb', components };
  if (raw.alpha !== undefined) {
    if (!isUnit(raw.alpha)) return fail('alpha must be a number 0–1');
    color.alpha = raw.alpha;
  }
  if (raw.hex !== undefined) {
    if (typeof raw.hex !== 'string') return fail('hex must be a string');
    const expected = hexOf(components);
    if (raw.hex.toLowerCase() !== expected) {
      return fail(`hex ${raw.hex} does not match components (${expected})`);
    }
    color.hex = raw.hex;
  }
  return ok(color);
}

function checkMeasure(raw: unknown, units: readonly string[]): Check {
  if (!isRecord(raw) || typeof raw.value !== 'number' || !Number.isFinite(raw.value)) {
    return fail(`expected {"value": number, "unit": ${units.join(' | ')}}`);
  }
  if (typeof raw.unit !== 'string' || !units.includes(raw.unit)) {
    return fail(`unit must be one of ${units.join(', ')}`);
  }
  return ok({ value: raw.value, unit: raw.unit });
}

// A raw newline would end the CSS string and let the rest parse as rules.
function hasControl(text: string): boolean {
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code < 32 || code === 127) return true;
  }
  return false;
}

function checkFamily(raw: unknown): Check {
  const names: unknown[] = Array.isArray(raw) ? raw : [raw];
  if (names.length === 0 || !names.every((f) => typeof f === 'string' && f !== '')) {
    return fail('fontFamily must be a non-empty string or list of strings');
  }
  if (names.some((f) => hasControl(String(f)))) {
    return fail('fontFamily must not contain control characters');
  }
  return ok(raw as TokenValue);
}

function checkWeight(raw: unknown): Check {
  if (typeof raw === 'number' && raw >= 1 && raw <= 1000) return ok(raw);
  const weight = typeof raw === 'string' ? WEIGHTS[raw] : undefined;
  return weight === undefined ? fail('fontWeight must be 1–1000 or a DTCG keyword') : ok(weight);
}

function checkValue(type: TokenType, raw: unknown): Check {
  switch (type) {
    case 'color':
      return checkColor(raw);
    case 'dimension':
      return checkMeasure(raw, ['px', 'rem']);
    case 'duration':
      return checkMeasure(raw, ['ms', 's']);
    case 'fontFamily':
      return checkFamily(raw);
    case 'fontWeight':
      return checkWeight(raw);
    case 'number':
      return typeof raw === 'number' && Number.isFinite(raw)
        ? ok(raw)
        : fail('number must be finite');
  }
}

function metaError(node: Record<string, unknown>): string | undefined {
  if (node.$description !== undefined && typeof node.$description !== 'string') {
    return '$description must be a string';
  }
  const deprecated = node.$deprecated;
  if (
    deprecated !== undefined &&
    typeof deprecated !== 'boolean' &&
    typeof deprecated !== 'string'
  ) {
    return '$deprecated must be a boolean or a string';
  }
  if (node.$extensions !== undefined && !isRecord(node.$extensions)) {
    return '$extensions must be an object';
  }
  return undefined;
}

interface Walk {
  tokens: Token[];
  errors: string[];
  typeOf: ((path: string) => string | undefined) | undefined;
}

function parseToken(
  node: Record<string, unknown>,
  path: string,
  type: string | undefined,
  w: Walk,
): void {
  if (Object.keys(node).some((k) => !k.startsWith('$'))) {
    w.errors.push(`${path}: a token cannot have child tokens`);
    return;
  }
  const unknown = Object.keys(node).find((k) => !META.has(k));
  if (unknown !== undefined) {
    w.errors.push(`${path}: unknown key "${unknown}"`);
    return;
  }
  const meta = metaError(node);
  if (meta !== undefined) {
    w.errors.push(`${path}: ${meta}`);
    return;
  }
  const resolved = type ?? w.typeOf?.(path);
  if (resolved === undefined || !isTokenType(resolved)) {
    w.errors.push(
      w.typeOf === undefined
        ? `${path}: no $type on the token or any group above it`
        : `${path}: no such token in tokens.json`,
    );
    return;
  }
  const raw = node.$value;
  const alias = typeof raw === 'string' ? ALIAS.exec(raw) : null;
  if (alias?.[1] !== undefined) {
    w.tokens.push({ path, type: resolved, value: { alias: alias[1] } });
    return;
  }
  const checked = checkValue(resolved, raw);
  if (checked.ok) w.tokens.push({ path, type: resolved, value: checked.value });
  else w.errors.push(`${path}: ${checked.reason}`);
}

function walk(
  node: Record<string, unknown>,
  path: string[],
  type: string | undefined,
  w: Walk,
): void {
  const here = path.length > 0 ? path.join('.') : 'tokens';
  for (const [key, child] of Object.entries(node)) {
    if (key.startsWith('$')) {
      if (!META.has(key)) w.errors.push(`${here}: unknown key "${key}"`);
      continue;
    }
    const childPath = [...path, key];
    const at = childPath.join('.');
    if (!NAME.test(key)) {
      w.errors.push(`${at}: name "${key}" may only use letters, digits, _ and -`);
      continue;
    }
    if (!isRecord(child)) {
      w.errors.push(`${at}: expected a group or a token`);
      continue;
    }
    const own = child.$type;
    if (own !== undefined && (typeof own !== 'string' || !isTokenType(own))) {
      w.errors.push(`${at}: unsupported $type ${JSON.stringify(own)}`);
      continue;
    }
    if ('$value' in child) {
      parseToken(child, at, own ?? type, w);
      continue;
    }
    const meta = metaError(child);
    if (meta !== undefined) w.errors.push(`${at}: ${meta}`);
    walk(child, childPath, own ?? type, w);
  }
}

/** Parse a DTCG token document; `typeOf` types an override file's paths from the base tokens. */
export function parseTokens(doc: unknown, typeOf?: (path: string) => string | undefined): Parsed {
  if (!isRecord(doc)) return { tokens: [], errors: ['tokens: document must be an object'] };
  const root = doc.$type;
  if (root !== undefined && (typeof root !== 'string' || !isTokenType(root))) {
    return { tokens: [], errors: [`tokens: unsupported $type ${JSON.stringify(root)}`] };
  }
  const meta = metaError(doc);
  if (meta !== undefined) return { tokens: [], errors: [`tokens: ${meta}`] };
  const w: Walk = { tokens: [], errors: [], typeOf };
  walk(doc, [], root, w);
  return { tokens: w.tokens, errors: w.errors };
}

function isAlias(value: Token['value']): value is { alias: string } {
  return typeof value === 'object' && 'alias' in value;
}

function resolveError(token: Token, byPath: ReadonlyMap<string, Token>): string | undefined {
  if (!isAlias(token.value)) return undefined;
  const first = token.value.alias;
  const seen = [token.path];
  let current: Token = token;
  while (isAlias(current.value)) {
    const target = byPath.get(current.value.alias);
    if (target === undefined) return `${token.path}: alias {${current.value.alias}} has no target`;
    if (seen.includes(target.path)) {
      return `${token.path}: alias cycle: ${[...seen, target.path].join(' → ')}`;
    }
    seen.push(target.path);
    current = target;
  }
  return current.type === token.type
    ? undefined
    : `${token.path}: alias {${first}} is ${current.type}, expected ${token.type}`;
}

/** Validate aliases and dark overrides; an empty list means valid. */
export function validateTokens(base: readonly Token[], dark: readonly Token[]): string[] {
  const light = new Map(base.map((t) => [t.path, t]));
  const errors: string[] = [];
  const failed = new Set<string>();
  for (const token of base) {
    const error = resolveError(token, light);
    if (error !== undefined) {
      errors.push(error);
      failed.add(token.path);
    }
  }
  const merged = new Map(light);
  for (const token of dark) {
    const original = light.get(token.path);
    if (original === undefined) errors.push(`dark: ${token.path}: no such token in tokens.json`);
    else if (original.type !== token.type) {
      errors.push(`dark: ${token.path}: is ${token.type}, but tokens.json has ${original.type}`);
    } else merged.set(token.path, token);
  }
  for (const token of merged.values()) {
    if (failed.has(token.path)) continue;
    const error = resolveError(token, merged);
    if (error !== undefined) errors.push(`dark: ${error}`);
  }
  return errors;
}
