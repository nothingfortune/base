#!/usr/bin/env node
// Every guard must be proven to fire (L-0040): plant each defect in a throwaway copy and require a suite to fail.
import { spawn } from 'node:child_process';
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import { clearTimeout, setTimeout } from 'node:timers';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const EXIT = /\bexit [1-9][0-9]*\b/;
const SUITE_TIMEOUT_MS = 120_000;
// A hook-exported GIT_DIR would point every suite at the real repo (L-0103), so the copies never inherit it.
const GIT_VARS = [
  'GIT_DIR',
  'GIT_WORK_TREE',
  'GIT_INDEX_FILE',
  'GIT_OBJECT_DIRECTORY',
  'GIT_COMMON_DIR',
];

/** Manifest → defects: an `exit N` refusal neutralised on each listed line, plus the hand-written semantic defects. */
export function plan(root, manifest) {
  const defects = [];
  for (const file of manifest.auto?.files ?? []) {
    const lines = readFileSync(path.join(root, file), 'utf8').split('\n');
    lines.forEach((text, index) => {
      if (/^\s*#/.test(text) || !EXIT.test(text)) return;
      const skip = (manifest.auto?.skip ?? []).find(
        (s) => s.file === file && text.includes(s.contains),
      );
      if (skip) return;
      defects.push({
        file,
        line: index + 1,
        name: `${file}:${index + 1} refusal removed`,
        apply: (src) => {
          const all = src.split('\n');
          all[index] = (all[index] ?? '').replace(EXIT, ':');
          return all.join('\n');
        },
      });
    });
  }
  for (const d of manifest.defects ?? []) {
    defects.push({
      file: d.file,
      name: d.why,
      apply: (src) => {
        const hits = src.split(d.find).length - 1;
        if (hits !== 1)
          throw new Error(
            `stale manifest: "${d.why}" expects its find text exactly once in ${d.file}, found ${hits}`,
          );
        return src.replace(d.find, d.replace);
      },
    });
  }
  return defects;
}

function cleanEnv() {
  return Object.fromEntries(Object.entries(process.env).filter(([k]) => !GIT_VARS.includes(k)));
}

function runSuite(dir, suite) {
  return new Promise((resolve) => {
    const child = spawn('bash', [suite], {
      cwd: dir,
      env: cleanEnv(),
      stdio: ['ignore', 'pipe', 'pipe'],
    });
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

function copyTree(root, dirs) {
  const tmp = mkdtempSync(path.join(os.tmpdir(), 'defect.'));
  for (const d of dirs) cpSync(path.join(root, d), path.join(tmp, d), { recursive: true });
  return tmp;
}

async function attempt(root, manifest, defect) {
  const suites = manifest.suites?.[defect.file];
  if (!suites?.length)
    return { ...defect, status: 'error', detail: `no suites mapped for ${defect.file}` };
  const tmp = copyTree(root, manifest.copy);
  try {
    const target = path.join(tmp, defect.file);
    writeFileSync(target, defect.apply(readFileSync(target, 'utf8')));
    for (const s of suites) {
      const r = await runSuite(tmp, s);
      if (r.code !== 0)
        return { ...defect, status: 'caught', detail: r.code === 'timeout' ? `${s} timed out` : s };
    }
    return { ...defect, status: 'survived', detail: suites.join(', ') };
  } catch (e) {
    return { ...defect, status: 'error', detail: e instanceof Error ? e.message : String(e) };
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

async function pool(items, size, fn) {
  const results = new Array(items.length);
  let next = 0;
  await Promise.all(
    Array.from({ length: Math.min(size, items.length) }, async () => {
      while (next < items.length) {
        const i = next;
        next += 1;
        results[i] = await fn(items[i]);
      }
    }),
  );
  return results;
}

async function main(argv) {
  const flag = (name, fallback) => {
    const i = argv.indexOf(name);
    return i >= 0 ? (argv[i + 1] ?? fallback) : fallback;
  };
  const root = path.resolve(
    flag('--root', path.join(path.dirname(fileURLToPath(import.meta.url)), '..')),
  );
  const manifest = JSON.parse(
    readFileSync(path.resolve(root, flag('--manifest', 'tests/bin/planted-defects.json')), 'utf8'),
  );
  const jobs = Number(flag('--jobs', String(Math.max(1, os.availableParallelism() - 1))));

  // Known state first: if the suites already fail, every defect would look "caught".
  const allSuites = [...new Set(Object.values(manifest.suites ?? {}).flat())];
  const base = copyTree(root, manifest.copy);
  try {
    for (const s of allSuites) {
      const r = await runSuite(base, s);
      if (r.code !== 0) {
        console.log(
          `planted-defects: ${s} fails before any defect is planted; fix it first.\n${r.out}`,
        );
        return 1;
      }
    }
  } finally {
    rmSync(base, { recursive: true, force: true });
  }

  const results = await pool(plan(root, manifest), jobs, (d) => attempt(root, manifest, d));
  const bad = results.filter((r) => r.status !== 'caught');
  for (const r of results)
    console.log(
      `${r.status === 'caught' ? 'caught  ' : r.status.toUpperCase().padEnd(8)} ${r.name}${r.status === 'caught' ? '' : `  (${r.detail})`}`,
    );
  if (bad.length > 0) {
    console.log(
      `\nplanted-defects: ${bad.length} of ${results.length} defect(s) did not fail a test (L-0040). Add a test that fails on each, or, for a refusal no test can reach, an auto.skip entry with its reason.`,
    );
    return 1;
  }
  console.log(`\nplanted-defects OK: all ${results.length} planted defects fail a test.`);
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  process.exit(await main(process.argv.slice(2)));
