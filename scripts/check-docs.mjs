#!/usr/bin/env node
// Every relative link in tracked markdown, and every backticked repo path in living docs, must resolve.
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const LINK = /!?\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g;
const EXTERNAL = /^(?:[a-z][a-z0-9+.-]*:|\/\/|#)/i;
const CODE_SPAN = /`([^`\s]+)`/g;
const REPO_ROOTS = /^(?:src|tests|bin|scripts|docs|\.github|\.githooks|\.vscode)\//;
const PATH_SHAPE = /^[\w./@-]+\/?$/;
const PLACEHOLDER = /[<>{}*…$%]|\.\.\./;
// Generated or gitignored paths a fresh checkout lacks.
const ABSENT_BY_DESIGN = /^(?:node_modules|dist|build|coverage)(?:\/|$)/;
// Dated plans and designs are records of their time; their prose paths may age.
const LIVING = /^(?:README\.md|CLAUDE\.md|AGENTS\.md|docs\/guides\/.+\.md)$/;

/** Non-fenced lines with 1-based numbers: code blocks are examples, not references. */
function proseLines(markdown) {
  const out = [];
  let fenced = false;
  markdown.split('\n').forEach((text, index) => {
    if (/^\s*(?:```|~~~)/.test(text)) {
      fenced = !fenced;
      return;
    }
    if (!fenced) out.push({ text, line: index + 1 });
  });
  return out;
}

function resolve(doc, href, exists) {
  let decoded;
  try {
    decoded = decodeURI(href);
  } catch {
    return false;
  }
  const target = decoded.startsWith('/')
    ? path.posix.normalize(decoded.slice(1))
    : path.posix.normalize(path.posix.join(path.posix.dirname(doc), decoded));
  // Escaping the repo is broken by definition; never probe the host filesystem.
  if (target.startsWith('..')) return false;
  return ABSENT_BY_DESIGN.test(target) || exists(target);
}

function checkFile(doc, markdown, exists) {
  const failures = [];
  for (const { text, line } of proseLines(markdown)) {
    for (const match of text.replace(/`[^`]*`/g, '').matchAll(LINK)) {
      const raw = match[1] ?? '';
      if (EXTERNAL.test(raw)) continue;
      const href = raw.split('#')[0]?.split('?')[0] ?? '';
      if (href !== '' && !resolve(doc, href, exists))
        failures.push(`${doc}:${line} broken link → ${href}`);
    }
    if (!LIVING.test(doc)) continue;
    for (const match of text.matchAll(CODE_SPAN)) {
      const span = (match[1] ?? '').replace(/[.,;:]+$/, '').split('#')[0] ?? '';
      if (!REPO_ROOTS.test(span) || !PATH_SHAPE.test(span) || PLACEHOLDER.test(span)) continue;
      if (!ABSENT_BY_DESIGN.test(span) && !exists(span))
        failures.push(`${doc}:${line} missing path → ${span}`);
    }
  }
  return failures;
}

function main() {
  const rootFlag = process.argv.indexOf('--root');
  const root =
    rootFlag === -1
      ? path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
      : path.resolve(process.argv[rootFlag + 1] ?? '.');
  const exists = (target) => existsSync(path.join(root, target));
  // ls-files still lists a tracked doc deleted from disk until the deletion is staged.
  const tracked = execFileSync('git', ['ls-files', '-z', '--', '*.md'], {
    cwd: root,
    encoding: 'utf8',
  })
    .split('\0')
    .filter((file) => file !== '' && exists(file));
  const failures = tracked.flatMap((doc) =>
    checkFile(doc, readFileSync(path.join(root, doc), 'utf8'), exists),
  );
  if (failures.length > 0) {
    for (const failure of failures) console.error(failure);
    console.error(
      '\nFix the doc or the path; dated plans under docs/toDo and docs/designs only need working links.',
    );
    process.exit(1);
  }
  console.log(`docs:check OK — ${tracked.length} markdown files checked`);
}

main();
