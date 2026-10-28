#!/usr/bin/env node
// Tests must never write to the repo they run in (L-0103): run every suite with git aimed at a sentinel and diff it.
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import os from 'node:os';
import { clearTimeout, setTimeout } from 'node:timers';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SELF_TEST = 'git-isolation-check.test.sh';
const HARNESS = /^\s*(?:source|\.)\s+.*_harness\.sh/m;
const SUITE_TIMEOUT_MS = 300_000;
const GIT_VARS = [
  'GIT_DIR',
  'GIT_WORK_TREE',
  'GIT_INDEX_FILE',
  'GIT_OBJECT_DIRECTORY',
  'GIT_COMMON_DIR',
];

function cleanEnv() {
  return Object.fromEntries(Object.entries(process.env).filter(([k]) => !GIT_VARS.includes(k)));
}

function git(repo, args) {
  const r = spawnSync('git', ['-C', repo, ...args], { env: cleanEnv(), encoding: 'utf8' });
  return `${r.stdout ?? ''}${r.status === 0 ? '' : `[exit ${r.status}] ${r.stderr ?? ''}`}`;
}

function sentinel() {
  const dir = mkdtempSync(path.join(os.tmpdir(), 'sentinel.'));
  spawnSync('git', ['init', '-q', '-b', 'main', dir], { env: cleanEnv() });
  spawnSync(
    'git',
    [
      '-C',
      dir,
      '-c',
      'user.email=s@s',
      '-c',
      'user.name=s',
      'commit',
      '-q',
      '--allow-empty',
      '-m',
      'sentinel',
    ],
    { env: cleanEnv() },
  );
  return dir;
}

/** Everything a stray git command could change: bare flag, HEAD, refs, local config and the index. */
function snapshot(repo) {
  return [
    git(repo, ['rev-parse', '--is-bare-repository', 'HEAD']),
    git(repo, ['for-each-ref', '--format=%(refname) %(objectname)']),
    git(repo, ['config', '--local', '--list']).split('\n').sort().join('\n'),
    git(repo, ['ls-files', '--stage']),
  ].join('\n--\n');
}

function runSuite(root, suite, repo) {
  const env = {
    ...cleanEnv(),
    GIT_DIR: path.join(repo, '.git'),
    GIT_WORK_TREE: repo,
    GIT_INDEX_FILE: path.join(repo, '.git', 'index'),
  };
  return new Promise((resolve) => {
    const child = spawn('bash', [suite], { cwd: root, env, stdio: ['ignore', 'pipe', 'pipe'] });
    let out = '';
    child.stdout.on('data', (b) => {
      out += b;
    });
    child.stderr.on('data', (b) => {
      out += b;
    });
    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      resolve({ code: 'timeout', out });
    }, SUITE_TIMEOUT_MS);
    child.on('close', (code) => {
      clearTimeout(timer);
      resolve({ code, out });
    });
  });
}

async function check(root, suitesDir, file) {
  const suite = path.join(suitesDir, file);
  const problems = [];
  if (!HARNESS.test(readFileSync(suite, 'utf8')))
    problems.push('does not source _harness.sh, which clears inherited GIT_* variables');
  const repo = sentinel();
  try {
    const before = snapshot(repo);
    const r = await runSuite(root, suite, repo);
    const after = snapshot(repo);
    if (after !== before)
      problems.push(
        'changed the repository named by the exported GIT_DIR (bare flag, refs, config or index)',
      );
    if (r.code !== 0)
      problems.push(
        `fails when GIT_DIR is exported (${r.code === 'timeout' ? 'timed out' : `exit ${r.code}`})`,
      );
  } finally {
    rmSync(repo, { recursive: true, force: true });
  }
  return { file, problems };
}

async function main(argv) {
  const flag = (name, fallback) => {
    const i = argv.indexOf(name);
    return i >= 0 ? (argv[i + 1] ?? fallback) : fallback;
  };
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  const suitesDir = path.resolve(flag('--suites', path.join(root, 'tests/bin')));
  const jobs = Number(flag('--jobs', String(Math.max(1, os.availableParallelism() - 1))));
  const files = readdirSync(suitesDir)
    .filter((f) => f.endsWith('.test.sh') && f !== SELF_TEST)
    .sort();
  const results = [];
  let next = 0;
  await Promise.all(
    Array.from({ length: Math.min(jobs, files.length) }, async () => {
      while (next < files.length) {
        const f = files[next];
        next += 1;
        results.push(await check(root, suitesDir, f));
      }
    }),
  );
  const bad = results
    .filter((r) => r.problems.length > 0)
    .sort((a, b) => a.file.localeCompare(b.file));
  for (const r of bad) for (const p of r.problems) console.log(`${r.file}: ${p}`);
  if (bad.length > 0) {
    console.log(
      `\ngit-isolation-check: ${bad.length} suite(s) leak into the repo they run in (L-0103). A pre-push hook in a linked worktree exports an absolute GIT_DIR; source _harness.sh first.`,
    );
    return 1;
  }
  console.log(
    `git-isolation-check OK: ${files.length} suite(s) pass with GIT_DIR exported and leave the sentinel repo untouched.`,
  );
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  process.exit(await main(process.argv.slice(2)));
