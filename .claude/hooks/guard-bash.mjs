#!/usr/bin/env node
// PreToolUse hook for Bash: blocks commands that name .env files (except *.example) or change .claude/ settings and hooks.
// It matches command text, so it stops accidents, not a determined bypass: https://code.claude.com/docs/en/permissions
import { readFileSync } from 'node:fs';

const ENV_FILE = /(?:^|[^\w.$-])(\.env[\w.-]*)/g;
const AGENT_CONFIG = /(?:^|[\s"'=/])\.claude(?:\/(?:settings|hooks)|\/?(?=[\s"';&|)]|$))/;
const CHAINED = /[;&|<>`]|\$\(/;
const READ_ONLY = /^\s*(?:cat|head|tail|less|ls|wc|grep|rg|diff|stat|file|jq)\s/;
const GIT_READ = /^\s*git\s+(?:add|diff|status|log|show|ls-files|blame|commit)\b/;

function block(reason) {
  console.error(reason);
  process.exit(2);
}

let command;
try {
  const input = JSON.parse(readFileSync(0, 'utf8'));
  if (input.tool_name !== 'Bash') process.exit(0);
  command = String(input.tool_input?.command ?? '');
} catch {
  block('guard-bash: could not read the hook input; blocking to be safe.');
}

const envFiles = [...command.matchAll(ENV_FILE)]
  .map((m) => m[1])
  .filter((name) => !name.includes('.example'));
if (envFiles.length > 0) {
  block(
    `Blocked: .env files are off-limits to agents (only *.example files are allowed): ${envFiles.join(', ')}`,
  );
}

const readOnly = !CHAINED.test(command) && (READ_ONLY.test(command) || GIT_READ.test(command));
if (AGENT_CONFIG.test(command) && !readOnly) {
  block(
    'Blocked: .claude/ settings and hooks are read-only for agents. Only a single read-only command (cat, ls, git add/diff/log, …) may name them; ask the user to make the change.',
  );
}
process.exit(0);
