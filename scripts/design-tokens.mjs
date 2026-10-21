#!/usr/bin/env node
// Generate design/tokens.css and design/previews/*.html from design/tokens*.json; --check diffs instead.
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { cssCollisions, cssName, emitCss } from '../src/lib/design-css.ts';
import { CARD_FILES, emitPreviews, missingDsCard } from '../src/lib/design-previews.ts';
import { parseTokens, validateTokens } from '../src/lib/design-tokens.ts';

const args = process.argv.slice(2);
const check = args.includes('--check');
const rootFlag = args.indexOf('--root');
const root =
  rootFlag === -1
    ? path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
    : path.resolve(args[rootFlag + 1] ?? '.');
const design = path.join(root, 'design');
const rel = (file) => path.relative(root, file).split(path.sep).join('/');

function fail(errors) {
  for (const e of errors) console.error(e);
  process.exit(1);
}

function readJson(file, required) {
  if (!existsSync(file)) return required ? fail([`${rel(file)}: missing`]) : undefined;
  try {
    return JSON.parse(readFileSync(file, 'utf8'));
  } catch (err) {
    return fail([`${rel(file)}: invalid JSON: ${err.message}`]);
  }
}

function htmlFiles(dir) {
  if (!existsSync(dir)) return [];
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) return htmlFiles(full);
    return entry.name.endsWith('.html') ? [full] : [];
  });
}

if (!existsSync(design)) {
  console.log('design: no design/ directory, skipped');
  process.exit(0);
}

const baseFile = path.join(design, 'tokens.json');
const darkFile = path.join(design, 'tokens.dark.json');
const base = parseTokens(readJson(baseFile, true));
const types = new Map(base.tokens.map((t) => [t.path, t.type]));
const darkDoc = readJson(darkFile, false);
const dark =
  darkDoc === undefined ? { tokens: [], errors: [] } : parseTokens(darkDoc, (p) => types.get(p));
const errors = [
  ...base.errors.map((e) => `${rel(baseFile)}: ${e}`),
  ...dark.errors.map((e) => `${rel(darkFile)}: ${e}`),
  ...validateTokens(base.tokens, dark.tokens),
  ...cssCollisions(base.tokens),
];
if (errors.length > 0) fail(errors);

const previewsDir = path.join(design, 'previews');
const expected = new Map([[path.join(design, 'tokens.css'), emitCss(base.tokens, dark.tokens)]]);
for (const [file, html] of emitPreviews(base.tokens, cssName)) {
  expected.set(path.join(previewsDir, file), html);
}
const stale = CARD_FILES.map((f) => path.join(previewsDir, f)).filter(
  (f) => !expected.has(f) && existsSync(f),
);

if (!check) {
  mkdirSync(previewsDir, { recursive: true });
  for (const [file, content] of expected) writeFileSync(file, content);
  for (const file of stale) rmSync(file);
  console.log(
    `design: wrote ${String(expected.size)} files, removed ${String(stale.length)} stale`,
  );
  process.exit(0);
}

const problems = [];
for (const [file, content] of expected) {
  if (!existsSync(file)) problems.push(`${rel(file)}: missing — run npm run tokens`);
  else if (readFileSync(file, 'utf8') !== content) {
    problems.push(`${rel(file)}: out of date — run npm run tokens`);
  }
}
for (const file of stale) {
  problems.push(`${rel(file)}: stale, its group has no tokens — run npm run tokens`);
}
const pages = htmlFiles(design).map((f) => ({ path: rel(f), content: readFileSync(f, 'utf8') }));
for (const p of missingDsCard(pages)) {
  problems.push(`${p}: first line must be <!-- @dsCard group="…" -->`);
}
if (problems.length > 0) fail(problems);
console.log(`design:check OK — ${String(expected.size)} generated files current`);
