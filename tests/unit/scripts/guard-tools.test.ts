import { spawnSync } from 'node:child_process';
import { join } from 'node:path';

import { describe, expect, it } from 'vitest';

const HOOK = join(import.meta.dirname, '..', '..', '..', '.claude', 'hooks', 'guard-tools.mjs');

const ALLOWED = { status: 0, said: true };
const ENV_BLOCK = /\.env files are off-limits/;
const CONFIG_BLOCK = /\.claude\/ settings and hooks/;

// Exit status and whether stderr says `expected`, asserted together.
function hook(payload: unknown, expected = /./): { status: number | null; said: boolean } {
  const r = spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify(payload),
    encoding: 'utf8',
  });
  return { status: r.status, said: r.status === 0 || expected.test(r.stderr) };
}

function bash(command: string, expected?: RegExp): { status: number | null; said: boolean } {
  return hook({ tool_name: 'Bash', tool_input: { command } }, expected);
}

describe('shell commands and .env files', () => {
  it.each([
    'cat .env',
    'cat ./.env.local',
    'grep KEY apps/web/.env.staging',
    'source .env',
    '. .env.production',
    'cp .env /tmp/x',
    'echo SECRET=1 >> .env',
    'python -c "print(open(\'.env\').read())"',
    'cat "$HOME/project/.env"',
    'ls -la && cat .envrc',
    'cat .e*',
    'cat .en?',
    'cat .?nv',
    'cat .[e]nv',
    'cat .\\env',
    'cat ".env".local',
  ])('blocks %j', (command) => {
    expect(bash(command, ENV_BLOCK)).toEqual({ status: 2, said: true });
  });

  it.each([
    'cat .env.example',
    'cp .env.example .env.local.example',
    'diff .env.local.example .env.example.local',
    'node -e "console.log(process.env.HOME)"',
    'echo $NODE_ENV',
    'npm install dotenv',
    'git status',
    'ls *.ts',
  ])('allows %j', (command) => {
    expect(bash(command)).toEqual(ALLOWED);
  });

  it('names the file it blocked', () => {
    expect(bash('cat .env.example .env.local', /\.env\.local/)).toEqual({ status: 2, said: true });
  });

  it('checks a PowerShell command the same way', () => {
    expect(
      hook({ tool_name: 'PowerShell', tool_input: { command: 'Get-Content .env' } }, ENV_BLOCK),
    ).toEqual({
      status: 2,
      said: true,
    });
  });
});

describe('shell commands and .claude/ settings and hooks', () => {
  it.each([
    "sed -i '' 's/a/b/' .claude/settings.json",
    'echo {} > .claude/settings.json',
    'echo {} >.claude/settings.json',
    'rm .claude/hooks/guard-tools.mjs',
    'mv .claude/settings.local.json /tmp/',
    'cat .claude/settings.json | tee .claude/settings.json',
    'git checkout -- .claude/settings.json',
    'cd .claude && rm -r hooks',
    "rg --pre 'sh -c x' y .claude/settings.json",
    'less .claude/settings.json',
    'git diff --output=.claude/settings.json',
    'git diff --out=.claude/settings.json',
    'git log --ext-diff -- .claude/hooks',
    'ls -la .claude',
    'echo {} > .claude//settings.json',
    'echo {} > ./.claude/./settings.json',
    "echo {} > '.claude'/settings.json",
    'cp x \\.claude/settings.json',
  ])('blocks %j', (command) => {
    expect(bash(command, CONFIG_BLOCK)).toEqual({ status: 2, said: true });
  });

  it.each([
    'cat .claude/settings.json',
    'git add .claude/settings.json .claude/hooks/guard-tools.mjs',
    'git diff .claude/hooks/guard-tools.mjs',
    'git log -- .claude/settings.json',
    'ls .claude/hooks',
  ])('allows the read-only %j', (command) => {
    expect(bash(command)).toEqual(ALLOWED);
  });
});

describe('file tools and .env files outside the permission rules', () => {
  it.each([
    ['Read', { file_path: '/elsewhere/project/.env' }],
    ['Edit', { file_path: '/elsewhere/.env.local' }],
    ['Write', { file_path: '/elsewhere/apps/.env.staging' }],
    ['NotebookEdit', { notebook_path: '/elsewhere/.env' }],
    ['Grep', { pattern: 'KEY', path: '/elsewhere/.env' }],
    ['Grep', { pattern: 'KEY', path: '/elsewhere', glob: '.env*' }],
    ['Glob', { pattern: '**/.env*', path: '/elsewhere' }],
  ])('blocks %s %j', (tool_name, tool_input) => {
    expect(hook({ tool_name, tool_input }, ENV_BLOCK)).toEqual({ status: 2, said: true });
  });

  it.each([
    ['Read', { file_path: '/elsewhere/.env.example' }],
    ['Edit', { file_path: '/elsewhere/.env.local.example' }],
    ['Read', { file_path: '/elsewhere/src/env.ts' }],
    ['Grep', { pattern: '.env', path: '/elsewhere/src' }],
    ['Glob', { pattern: '**/*.ts' }],
  ])('allows %s %j', (tool_name, tool_input) => {
    expect(hook({ tool_name, tool_input })).toEqual(ALLOWED);
  });
});

describe('evasions from the third security review', () => {
  it.each([
    'cat .claude/settings.json\nrm .claude/settings.json',
    'cat .claude/settings.json\r\nrm .claude/settings.json',
    'ls (Remove-Item .claude/settings.json)',
    'ls @(Remove-Item .claude/hooks)',
    'cat {.claude/hooks}',
    'echo {} > .Claude/Settings.json',
  ])('blocks %j', (command) => {
    expect(bash(command, CONFIG_BLOCK)).toEqual({ status: 2, said: true });
  });

  it.each(['cat .ENV', 'cat .Env.Local', 'cat .{e,x}nv', 'cat {.,x}env', 'cat .e{n,x}v'])(
    'blocks the .env evasion %j',
    (command) => {
      expect(bash(command, ENV_BLOCK)).toEqual({ status: 2, said: true });
    },
  );

  it('blocks a file path whose name differs only in case', () => {
    expect(
      hook({ tool_name: 'Read', tool_input: { file_path: '/elsewhere/.ENV' } }, ENV_BLOCK),
    ).toEqual({
      status: 2,
      said: true,
    });
  });

  it('blocks a bracket range that covers e', () => {
    expect(bash('cat .[a-z]nv', ENV_BLOCK)).toEqual({ status: 2, said: true });
  });

  it.each([
    "gh api x --jq '.[] | .commit_id[0:7]'",
    "jq '.[].number' f.json",
    "jq '{state: .state, sha: .head.sha}' f.json",
    "sed -n 's/^v = .[0-9]*$/x/p' f",
  ])('allows the jq or regex filter %j', (command) => {
    expect(bash(command)).toEqual(ALLOWED);
  });

  it('still allows an .EXAMPLE file in any case', () => {
    expect(bash('cat .ENV.EXAMPLE')).toEqual(ALLOWED);
  });
});

describe('evasions from the commit security review', () => {
  it.each([
    'cat .[[:alpha:]]nv',
    'cat .[]e]nv',
    'cat .{d..f}nv',
    'cat .{env,x.example}',
    'cat {.env,a.example}',
    'cat .{d..f..1}nv',
    'cat .{a..z..4}nv',
    'cat .{d..f..1..}nv',
  ])('blocks %j', (command) => {
    expect(bash(command, ENV_BLOCK)).toEqual({ status: 2, said: true });
  });

  it.each([
    'for i in {1..5}; do echo $i; done',
    'for i in {1..10..2}; do echo $i; done',
    "jq '.[0-9]' f.json",
  ])('allows %j', (command) => {
    expect(bash(command)).toEqual(ALLOWED);
  });
});

describe('file tools and .claude/ settings and hooks outside the session folder', () => {
  it.each([
    ['Edit', { file_path: '/elsewhere/.claude/hooks/guard-tools.mjs' }],
    ['Write', { file_path: '/elsewhere/.claude/settings.local.json' }],
    ['Edit', { file_path: '/elsewhere/.claude/settings.json' }],
    ['Write', { file_path: 'C:\\elsewhere\\.claude\\settings.json' }],
  ])('blocks %s %j', (tool_name, tool_input) => {
    expect(hook({ tool_name, tool_input }, CONFIG_BLOCK)).toEqual({ status: 2, said: true });
  });

  it.each([
    ['Read', { file_path: '/elsewhere/.claude/settings.json' }],
    ['Edit', { file_path: '/elsewhere/.claude/skills/notes.md' }],
  ])('allows %s %j', (tool_name, tool_input) => {
    expect(hook({ tool_name, tool_input })).toEqual(ALLOWED);
  });
});

describe('brace expansion is checked by expanding it', () => {
  it.each([
    "gh api repos/o/r/pulls/1 --jq '{state:.state,sha:.head.sha}'",
    "jq '{a:.e,b:.c}' f.json",
  ])('allows the compact jq object %j', (command) => {
    expect(bash(command)).toEqual(ALLOWED);
  });
});

describe('Windows paths in PowerShell commands', () => {
  function ps(command: string, expected?: RegExp): { status: number | null; said: boolean } {
    return hook({ tool_name: 'PowerShell', tool_input: { command } }, expected);
  }

  it.each(['Get-Content C:\\project\\.env', 'Get-Content ..\\.env.local'])(
    'blocks the .env path %j',
    (command) => {
      expect(ps(command, ENV_BLOCK)).toEqual({ status: 2, said: true });
    },
  );

  it.each([
    'Set-Content C:\\project\\.claude\\settings.json "{}"',
    'Remove-Item .claude\\hooks\\guard-tools.mjs',
  ])('blocks the .claude path %j', (command) => {
    expect(ps(command, CONFIG_BLOCK)).toEqual({ status: 2, said: true });
  });

  it('blocks a file tool given a Windows .env path', () => {
    expect(
      hook({ tool_name: 'Read', tool_input: { file_path: 'C:\\elsewhere\\.env' } }, ENV_BLOCK),
    ).toEqual({ status: 2, said: true });
  });

  it('allows a Windows path to an .example file', () => {
    expect(ps('Get-Content C:\\project\\.env.example')).toEqual(ALLOWED);
  });
});

describe('input handling', () => {
  it('allows a tool it does not guard', () => {
    expect(
      hook({ tool_name: 'WebFetch', tool_input: { url: 'https://example.com/.env' } }),
    ).toEqual(ALLOWED);
  });

  it('fails closed on unreadable input', () => {
    const r = spawnSync(process.execPath, [HOOK], { input: 'not json', encoding: 'utf8' });
    expect(r.status).toBe(2);
  });
});
