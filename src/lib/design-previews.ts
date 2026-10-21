import type { Token } from './design-tokens';

type Name = (path: string) => string;

interface Card {
  file: string;
  group: string;
  segment: string;
  item: (token: Token, name: Name) => string;
}

const MARKER = /^<!-- @dsCard group="[^"]+" -->(?:\r?\n|$)/;
const SAMPLE = 'The quick brown fox jumps over the lazy dog';

function escapeHtml(text: string): string {
  return text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function label(token: Token): string {
  return `<code>${escapeHtml(token.path)}</code>`;
}

function typeItem(token: Token, name: Name): string {
  const v = token.value;
  const shown = Array.isArray(v) ? v.join(', ') : typeof v === 'string' ? v : '';
  const property: Partial<Record<Token['type'], string>> = {
    fontFamily: 'font-family',
    dimension: 'font-size',
    fontWeight: 'font-weight',
  };
  const css = property[token.type];
  const style = css === undefined ? '' : ` style="${css}: var(${name(token.path)})"`;
  const note = shown === '' ? '' : ` <small>${escapeHtml(shown)}</small>`;
  return `<p data-token="${token.path}"${style}>${SAMPLE}</p>${label(token)}${note}`;
}

const CARDS: readonly Card[] = [
  {
    file: 'colors.html',
    group: 'Colors',
    segment: 'color',
    item: (t, n) =>
      `<div class="swatch" data-token="${t.path}" style="background: var(${n(t.path)})"></div>${label(t)}`,
  },
  { file: 'type.html', group: 'Type', segment: 'font', item: typeItem },
  {
    file: 'spacing.html',
    group: 'Spacing',
    segment: 'space',
    item: (t, n) =>
      `<div class="bar" data-token="${t.path}" style="width: var(${n(t.path)})"></div>${label(t)}`,
  },
  {
    file: 'radius.html',
    group: 'Radius',
    segment: 'radius',
    item: (t, n) =>
      `<div class="box" data-token="${t.path}" style="border-radius: var(${n(t.path)})"></div>${label(t)}`,
  },
];

export const CARD_FILES: readonly string[] = CARDS.map((c) => c.file);

const STYLE = [
  ':root { color-scheme: light dark; }',
  'body { margin: 0; padding: 16px; font: 14px/1.4 system-ui, sans-serif; background: Canvas; color: CanvasText; }',
  'li { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 4px 12px; align-items: center; padding: 6px 0; }',
  'li > :first-child { grid-column: 1 / -1; }',
  '.swatch { height: 40px; border-radius: 6px; border: 1px solid GrayText; }',
  '.bar { height: 12px; background: CanvasText; }',
  '.box { width: 64px; height: 64px; border: 2px solid CanvasText; }',
  'ul { list-style: none; margin: 0; padding: 0; }',
  'p { margin: 0; }',
].join('\n');

function page(card: Card, tokens: readonly Token[], name: Name): string {
  const items = tokens.map((t) => `    <li>${card.item(t, name)}</li>`).join('\n');
  return [
    `<!-- @dsCard group="${card.group}" -->`,
    '<!doctype html>',
    '<html lang="en">',
    '<head>',
    '  <meta charset="utf-8">',
    '  <meta name="viewport" content="width=device-width, initial-scale=1">',
    `  <title>${card.group}</title>`,
    '  <link rel="stylesheet" href="../tokens.css">',
    `  <style>\n${STYLE}\n  </style>`,
    '</head>',
    '<body>',
    `  <h1>${card.group}</h1>`,
    '  <ul>',
    items,
    '  </ul>',
    '</body>',
    '</html>',
    '',
  ].join('\n');
}

/** One preview card per token group that has tokens, keyed by file name. */
export function emitPreviews(tokens: readonly Token[], name: Name): Map<string, string> {
  const out = new Map<string, string>();
  for (const card of CARDS) {
    const mine = tokens.filter((t) => t.path.split('.')[0] === card.segment);
    if (mine.length > 0) out.set(card.file, page(card, mine, name));
  }
  return out;
}

/** Paths whose first line is not a `@dsCard` marker with a group. */
export function missingDsCard(files: readonly { path: string; content: string }[]): string[] {
  return files.filter((f) => !MARKER.test(f.content)).map((f) => f.path);
}
