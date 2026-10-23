#!/usr/bin/env node
// A failed read must never pass as an empty one (L-0029): a network read with a silent fallback needs a marker.
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const READ = /\b(?:gh api|gh pr checks|curl|wget)\b/;
const FALLBACK = /\|\|\s*(?:echo\b|true\b|printf\b|:(?=\s|\)|;|$))/;
const MARKER = /fail-open-ok:\s*\S/;

/** Shell text → findings; backslash-continued lines are one logical line reported at its first line. */
export function lintText(text) {
  const physical = text.split('\n');
  const findings = [];
  for (let i = 0; i < physical.length; i += 1) {
    const start = i;
    let logical = physical[i] ?? '';
    while (/\\\s*$/.test(physical[i] ?? '') && i + 1 < physical.length) {
      i += 1;
      logical += `\n${physical[i] ?? ''}`;
    }
    if (/^\s*#/.test(logical)) continue;
    if (!READ.test(logical) || !FALLBACK.test(logical)) continue;
    const previous = physical[start - 1] ?? '';
    if (MARKER.test(logical) || (/^\s*#/.test(previous) && MARKER.test(previous))) continue;
    findings.push({ line: start + 1, text: (physical[start] ?? '').trim() });
  }
  return findings;
}

function shellFiles(root) {
  const out = [];
  for (const dir of ['bin', 'bin/lib']) {
    const abs = path.join(root, dir);
    if (!existsSync(abs)) continue;
    for (const name of readdirSync(abs).sort())
      if (name.endsWith('.sh')) out.push(path.join(dir, name));
  }
  return out;
}

function main(argv) {
  const rootFlag = argv.indexOf('--root');
  const root =
    rootFlag >= 0
      ? path.resolve(argv[rootFlag + 1] ?? '.')
      : path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  const files = argv.filter((a, i) => !a.startsWith('--') && argv[i - 1] !== '--root');
  const targets = files.length > 0 ? files : shellFiles(root);
  let count = 0;
  for (const rel of targets) {
    for (const f of lintText(readFileSync(path.join(root, rel), 'utf8'))) {
      count += 1;
      console.log(`${rel}:${f.line}: ${f.text}`);
    }
  }
  if (count > 0) {
    console.log(
      `\nfail-open-lint: ${count} network read(s) fall back silently, so a failed read would look empty (L-0029).`,
    );
    console.log(
      'Handle the failure (exit non-zero or report UNKNOWN), or mark the line "# fail-open-ok: <why>" when an unknown result is genuinely safe.',
    );
    return 1;
  }
  console.log(
    `fail-open-lint OK: ${targets.length} shell file(s), every network-read fallback is handled or marked.`,
  );
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  process.exit(main(process.argv.slice(2)));
