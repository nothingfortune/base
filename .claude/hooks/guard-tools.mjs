#!/usr/bin/env node
// PreToolUse hook: keeps agents out of .env files (except *.example) and stops shell changes to .claude/ settings and hooks.
// Shell checks read command text, so they stop accidents, not a determined bypass: https://code.claude.com/docs/en/permissions
import { readFileSync } from 'node:fs';
import path from 'node:path';

const SHELLS = new Set(['Bash', 'PowerShell']);
const ENV_NAME = /(?<![\w$-])\.env[\w.-]*/g;
const WORD_BREAK = /[\s;&|()<>=]+/;
const AGENT_CONFIG = /(?<![\w.-])\.claude(?![\w-])/;
const CHAINED = /[;&|<>`]|\$\(/;
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

// A dotfile name, or a glob that could expand to one, other than an *.example file.
function envLike(name) {
  if (!name.startsWith('.') || name.includes('.example')) return false;
  return name.startsWith('.env') || /[*?[]/.test(name);
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

function checkShell(raw) {
  // Quotes, backslashes and redundant path segments go, so '.claude'/x, .\env and .claude//x read plainly.
  const command = raw
    .replace(/["'\\]/g, '')
    .replace(/\/(?:\.\/)+/g, '/')
    .replace(/\/{2,}/g, '/');
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
