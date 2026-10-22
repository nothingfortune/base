#!/usr/bin/env node
// PreToolUse hook: keeps agents out of .env files (except *.example) and stops shell changes to .claude/ settings and hooks.
// Shell checks read command text, so they stop accidents, not a determined bypass: https://code.claude.com/docs/en/permissions
import { readFileSync } from 'node:fs';
import path from 'node:path';

const SHELLS = new Set(['Bash', 'PowerShell']);
const ENV_NAME = /(?<![\w$-])\.env[\w.-]*/g;
const WORD_BREAK = /[\s;&|()<>=]+/;
const AGENT_CONFIG = /(?<![\w.-])\.claude(?![\w-])/;
// Newlines separate commands; PowerShell runs (…), {…} and @(…) as subexpressions.
const CHAINED = /[;&|<>`\n\r(){}@]|\$\(/;
const READ_ONLY = new Set(['cat', 'head', 'tail', 'ls', 'wc', 'stat', 'file', 'diff', 'grep']);
const GIT_READ_ONLY = new Set(['add', 'diff', 'log', 'show', 'status', 'ls-files', 'blame']);

function block(reason) {
  console.error(reason);
  process.exit(2);
}

function blockEnv(names) {
  block(
    `Blocked: .env files are off-limits to agents (only *.example files are allowed): ${names.join(', ')}`,
  );
}

// Whether the glob after a leading dot could match an e; only digit classes such as jq's .[0:7] are exempt.
function globCouldStartWithE(n) {
  const c = n[1];
  if (c === 'e' || c === '*' || c === '?') return true;
  if (c !== '[') return false;
  // A ] right after [ is a class member, so .[]e]nv is a class; a lone .[] is literal.
  if (n[2] === ']') return n.indexOf(']', 3) !== -1;
  const close = n.indexOf(']', 2);
  return close !== -1 && !/^[0-9:-]*$/.test(n.slice(2, close));
}

const NUMBER_RANGE = /^-?\d+\.\.-?\d+(?:\.\.-?\d+)?$/;
const LETTER_RANGE = /^(.)\.\.(.)(?:\.\.-?\d+)?$/;

// The alternatives one brace group yields; a step is ignored, so a range yields a superset.
function alternatives(inner) {
  if (NUMBER_RANGE.test(inner)) return ['0'];
  const range = LETTER_RANGE.exec(inner);
  if (range) {
    const [lo, hi] = [range[1], range[2]].map((c) => c.charCodeAt(0)).sort((a, b) => a - b);
    return Array.from({ length: hi - lo + 1 }, (_, i) => String.fromCharCode(lo + i));
  }
  if (inner.includes('..')) return null;
  return inner.includes(',') ? inner.split(',') : undefined;
}

// Every word bash brace expansion makes of `word`, or null when it cannot be worked out safely.
function expandBraces(word) {
  const words = [];
  const queue = [word];
  while (queue.length > 0) {
    const w = queue.pop();
    const groups = [...w.matchAll(/\{([^{}]*)\}/g)].map((m) => ({ m, alts: alternatives(m[1]) }));
    const group = groups.find((g) => g.alts !== undefined);
    // A literal inner group like {x} is masked so the group around it can still expand.
    if (group === undefined && groups.length > 0) {
      queue.push(w.replace(/\{([^{}]*)\}/g, '\u0001$1\u0002'));
    } else if (group === undefined)
      words.push(w.replaceAll('\u0001', '{').replaceAll('\u0002', '}'));
    else if (group.alts === null) return null;
    else {
      const { index } = group.m;
      const rest = w.slice(index + group.m[0].length);
      queue.push(...group.alts.map((a) => w.slice(0, index) + a + rest));
    }
    if (words.length + queue.length > 1024) return null;
  }
  return words;
}

// A dotfile name or a glob that could match one, other than a plain *.example name.
function dotEnvLike(n) {
  if (!/[*?[\]]/.test(n) && n.includes('.example')) return false;
  if (!n.startsWith('.')) return false;
  return n.startsWith('.env') || (/[*?[]/.test(n) && globCouldStartWithE(n));
}

// Whether `name`, or any word its braces expand to, is .env-like.
function envLike(name) {
  const words = expandBraces(name.toLowerCase());
  return words === null || words.some((w) => dotEnvLike(w.slice(w.lastIndexOf('/') + 1)));
}

// Options are refused outright: allowlisting flags loses to abbreviations like --out for --output.
function readOnly(command) {
  if (CHAINED.test(command)) return false;
  const [first, second, ...rest] = command.trim().split(/\s+/);
  let args = null;
  if (first === 'git' && GIT_READ_ONLY.has(second)) args = rest;
  else if (READ_ONLY.has(first)) args = second === undefined ? [] : [second, ...rest];
  return args !== null && args.every((a) => a === '--' || !a.startsWith('-'));
}

// Quotes and redundant path segments go, so '.claude'/x and .claude//x read plainly; lowercased because macOS paths ignore case.
function normalize(raw, backslash) {
  return raw
    .toLowerCase()
    .replace(/["']/g, '')
    .replace(/\\/g, backslash)
    .replace(/\/(?:\.\/)+/g, '/')
    .replace(/\/{2,}/g, '/');
}

// A backslash is a shell escape (.\env) or a Windows separator (C:\x\.env), so both readings are checked.
function checkShell(raw) {
  checkCommand(normalize(raw, ''));
  checkCommand(normalize(raw, '/'));
}

function checkCommand(command) {
  const named = [...command.matchAll(ENV_NAME)].map((m) => m[0]);
  const globbed = command.split(WORD_BREAK).map((w) => w.slice(w.lastIndexOf('/') + 1));
  const env = [...named, ...globbed].filter(envLike);
  if (env.length > 0) blockEnv([...new Set(env)]);
  if (AGENT_CONFIG.test(command) && !readOnly(command)) {
    block(
      'Blocked: .claude/ settings and hooks are read-only for agents. Only a single read-only command with no options (cat, ls, git add/diff/log, …) may name them; ask the user to make the change.',
    );
  }
}

// The cwd-relative deny rules miss settings and hooks in other folders, so mutating tools are checked here.
const CONFIG_FILE = /(?:^|\/)\.claude\/(?:settings(?:\.local)?\.json$|hooks(?:\/|$))/;
const MUTATING = new Set(['Edit', 'Write', 'NotebookEdit']);

function checkFiles(input) {
  // Normalizing can break a brace group apart ({a/../,}.env), so raw and normalized forms are both checked.
  const forms = (v) => {
    if (typeof v !== 'string') return [];
    const raw = v.toLowerCase().replace(/\\/g, '/');
    return [raw, path.posix.normalize(raw)];
  };
  const paths = [input.file_path, input.notebook_path, input.path].flatMap(forms);
  const globs = [input.glob, input.tool === 'Glob' ? input.pattern : undefined].flatMap(forms);
  const env = [...new Set([...paths, ...globs])].filter((p) => p !== '' && envLike(p));
  if (env.length > 0) blockEnv(env);
  if (MUTATING.has(input.tool) && paths.some((p) => CONFIG_FILE.test(p))) {
    block(
      'Blocked: .claude/ settings and hooks are read-only for agents, in any folder; ask the user to make the change.',
    );
  }
}

let input;
try {
  input = JSON.parse(readFileSync(0, 'utf8'));
} catch {
  block('guard-tools: could not read the hook input; blocking to be safe.');
}
const toolInput = input.tool_input ?? {};
if (SHELLS.has(input.tool_name)) checkShell(String(toolInput.command ?? ''));
else checkFiles({ ...toolInput, tool: input.tool_name });
process.exit(0);
