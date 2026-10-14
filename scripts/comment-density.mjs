#!/usr/bin/env node
// Ratchets multi-line comment blocks per workspace; ranges come from the TS scanner, never a regex.
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import ts from 'typescript';

const GROUPS = ['packages', 'apps'];
const SKIP_DIRS = new Set(['node_modules', 'dist', 'build', '.tsbuild']);
// The greppable markers CLAUDE.md exempts from the one-WHY-line rule.
const MARKERS = ['@public-api', 'strtotime-ok:', '@covered-by', 'env-gate-ok:'];

function findWorkspaces(root) {
  const found = existsSync(join(root, 'src')) ? ['.'] : [];
  for (const group of GROUPS) {
    const groupDir = join(root, group);
    let entries;
    try {
      entries = readdirSync(groupDir, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      if (entry.isDirectory() && existsSync(join(groupDir, entry.name, 'src'))) {
        found.push(`${group}/${entry.name}`);
      }
    }
  }
  return found.sort();
}

function collectFiles(dir) {
  const out = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      if (!SKIP_DIRS.has(entry.name)) out.push(...collectFiles(join(dir, entry.name)));
      continue;
    }
    if (!/\.tsx?$/.test(entry.name)) continue;
    if (entry.name.endsWith('.stories.tsx') || entry.name.endsWith('.d.ts')) continue;
    out.push(join(dir, entry.name));
  }
  return out;
}

function isExempt(texts) {
  const joined = texts.join('\n');
  return MARKERS.some((marker) => joined.includes(marker));
}

/** Every comment range in a file, deduped: one node's leading trivia is another's trailing trivia. */
function collectComments(sourceFile, text) {
  const seen = new Set();
  const comments = [];
  const collect = (pos, getRanges) => {
    for (const range of getRanges(text, pos) ?? []) {
      const key = `${range.pos}:${range.end}`;
      if (seen.has(key)) continue;
      seen.add(key);
      comments.push(range);
    }
  };
  // getChildren, not forEachChild: only it yields the `}` and EOF tokens whose trivia holds trailing comments.
  const visit = (node) => {
    collect(node.getFullStart(), ts.getLeadingCommentRanges);
    for (const child of node.getChildren(sourceFile)) visit(child);
    collect(node.getEnd(), ts.getTrailingCommentRanges);
  };
  visit(sourceFile);
  comments.sort((a, b) => a.pos - b.pos);
  return comments;
}

function analyzeFile(filePath) {
  const text = readFileSync(filePath, 'utf8');
  const scriptKind = filePath.endsWith('.tsx') ? ts.ScriptKind.TSX : ts.ScriptKind.TS;
  const sourceFile = ts.createSourceFile(filePath, text, ts.ScriptTarget.Latest, true, scriptKind);
  const comments = collectComments(sourceFile, text);
  const lineOf = (pos) => sourceFile.getLineAndCharacterOfPosition(pos).line;

  const commentLines = new Set();
  for (const c of comments) {
    for (let l = lineOf(c.pos); l <= lineOf(Math.max(c.pos, c.end - 1)); l++) commentLines.add(l);
  }

  let blocks = 0;
  let i = 0;
  while (i < comments.length) {
    const c = comments[i];
    if (c.kind === ts.SyntaxKind.MultiLineCommentTrivia) {
      const spansLines = lineOf(c.end - 1) > lineOf(c.pos);
      if (spansLines && !isExempt([text.slice(c.pos, c.end)])) blocks++;
      i++;
      continue;
    }
    // A run of `//` lines separated only by whitespace is one block, not N single lines.
    let j = i;
    const run = [c];
    while (
      j + 1 < comments.length &&
      comments[j + 1].kind === ts.SyntaxKind.SingleLineCommentTrivia &&
      /^\s*$/.test(text.slice(run[run.length - 1].end, comments[j + 1].pos))
    ) {
      run.push(comments[j + 1]);
      j++;
    }
    if (run.length >= 2 && !isExempt(run.map((r) => text.slice(r.pos, r.end)))) blocks++;
    i = j + 1;
  }

  return {
    sourceLines: sourceFile.getLineStarts().length,
    commentLines: commentLines.size,
    blocks,
  };
}

function analyzeWorkspace(root, workspace) {
  const totals = { sourceLines: 0, commentLines: 0, blocks: 0 };
  for (const file of collectFiles(join(root, workspace, 'src'))) {
    const r = analyzeFile(file);
    totals.sourceLines += r.sourceLines;
    totals.commentLines += r.commentLines;
    totals.blocks += r.blocks;
  }
  return { workspace, ...totals };
}

function printTable(results) {
  const width = Math.max(...results.map((r) => r.workspace.length), 'workspace'.length);
  console.log(
    'comment-density (src/, packages/*/src, apps/*/src; .ts/.tsx, excluding stories/.d.ts)\n',
  );
  console.log(`  ${'workspace'.padEnd(width)}  source  comment  density   blocks`);
  for (const r of results) {
    const density =
      r.sourceLines > 0 ? ((r.commentLines / r.sourceLines) * 100).toFixed(2) : '0.00';
    console.log(
      `  ${r.workspace.padEnd(width)}  ${String(r.sourceLines).padStart(6)}  ${String(r.commentLines).padStart(7)}  ${density.padStart(6)}%  ${String(r.blocks).padStart(6)}`,
    );
  }
  console.log('');
}

function readBaseline(path) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'));
  } catch {
    // Fail closed: an unreadable baseline reports every workspace missing.
    return {};
  }
}

function writeBaseline(path, results) {
  const data = {};
  for (const r of [...results].sort((a, b) => a.workspace.localeCompare(b.workspace))) {
    data[r.workspace] = r.blocks;
  }
  writeFileSync(path, `${JSON.stringify(data, null, 2)}\n`);
}

function parseArgs(argv) {
  const flag = (name) => {
    const idx = argv.indexOf(name);
    return idx === -1 ? undefined : argv[idx + 1];
  };
  return {
    updateBaseline: argv.includes('--update-baseline'),
    root: flag('--root'),
    baseline: flag('--baseline'),
  };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const root = args.root ?? join(dirname(fileURLToPath(import.meta.url)), '..');
  const baselinePath = args.baseline ?? join(root, 'comment-density-baseline.json');

  const workspaces = findWorkspaces(root);
  if (workspaces.length === 0) {
    console.error(`comment-density: no workspaces with a src/ dir found under ${root}`);
    process.exit(1);
  }
  const results = workspaces.map((ws) => analyzeWorkspace(root, ws));
  printTable(results);

  if (args.updateBaseline) {
    writeBaseline(baselinePath, results);
    console.log(`comment-density: baseline updated at ${baselinePath}`);
    return;
  }

  const baseline = readBaseline(baselinePath);
  let failed = false;
  for (const r of results) {
    const base = baseline[r.workspace];
    if (base === undefined) {
      console.error(
        `comment-density: ${r.workspace} is missing from comment-density-baseline.json.`,
      );
      console.error('Run --update-baseline to add it.');
      failed = true;
    } else if (r.blocks > base) {
      console.error(
        `comment-density: ${r.workspace} rose to ${r.blocks} multi-line block(s) (baseline ${base}).`,
      );
      console.error(
        'new multi-line comments: keep a comment to one WHY line; rationale goes in docs.',
      );
      failed = true;
    } else if (r.blocks < base) {
      console.error(
        `comment-density: ${r.workspace} fell to ${r.blocks} multi-line block(s) (baseline ${base}).`,
      );
      console.error(`lower comment-density-baseline.json ${r.workspace} to ${r.blocks}.`);
      failed = true;
    }
  }

  if (failed) process.exit(1);
  console.log('comment-density OK — multi-line comment block counts match the baseline');
}

main();
