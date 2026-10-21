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

// Letter ranges like {d..f} spelled out, so the brace check sees every letter they produce.
function expandRanges(n) {
  return n.replace(/\{(.)\.\.(.)\}/g, (_, lo, hi) => {
    let out = '';
    for (let c = lo.charCodeAt(0); c <= hi.charCodeAt(0); c++) out += String.fromCharCode(c);
    return out;
  });
}

// A dotfile name, or a glob or brace expansion that could become one, other than a plain *.example name.
function envLike(name) {
  const n = name.toLowerCase();
  if (!/[{}*?[\]]/.test(n) && n.includes('.example')) return false;
  if (/\{[^}]*(?:,|\.\.)[^}]*\}/.test(n)) {
    const spelled = expandRanges(n);
    return spelled.replace(/\.\./g, '').includes('.') && spelled.includes('e');
  }
  if (!n.startsWith('.')) return false;
  return n.startsWith('.env') || (/[*?[]/.test(n) && globCouldStartWithE(n));
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

function checkFiles(input) {
  const paths = [input.file_path, input.notebook_path, input.path];
  const globs = [input.glob, input.tool === 'Glob' ? input.pattern : undefined];
  const names = [
    ...paths.map((p) => (typeof p === 'string' ? path.basename(p) : '')),
    ...globs.map((g) => (typeof g === 'string' ? g.slice(g.lastIndexOf('/') + 1) : '')),
  ];
  const env = names.filter(envLike);
  if (env.length > 0) blockEnv(env);
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
