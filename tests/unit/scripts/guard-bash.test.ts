import { spawnSync } from 'node:child_process';
import { join } from 'node:path';

import { describe, expect, it } from 'vitest';

const HOOK = join(import.meta.dirname, '..', '..', '..', '.claude', 'hooks', 'guard-bash.mjs');

// Exit status and whether stderr says `expected`, asserted together.
function guard(command: string, expected = /./): { status: number | null; said: boolean } {
  const input = JSON.stringify({ tool_name: 'Bash', tool_input: { command } });
  const r = spawnSync(process.execPath, [HOOK], { input, encoding: 'utf8' });
  return { status: r.status, said: r.status === 0 || expected.test(r.stderr) };
}

const ALLOWED = { status: 0, said: true };

describe('guard-bash: .env files', () => {
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
  ])('blocks %j', (command) => {
    expect(guard(command, /\.env files are off-limits/)).toEqual({ status: 2, said: true });
  });

  it.each([
    'cat .env.example',
    'cp .env.example .env.local.example',
    'diff .env.local.example .env.example.local',
    'node -e "console.log(process.env.HOME)"',
    'echo $NODE_ENV',
    'npm install dotenv',
    'git status',
  ])('allows %j', (command) => {
    expect(guard(command)).toEqual(ALLOWED);
  });

  it('names the file it blocked', () => {
    expect(guard('cat .env.example .env.local', /\.env\.local/)).toEqual({ status: 2, said: true });
  });
});

describe('guard-bash: agent settings and hooks', () => {
  it.each([
    "sed -i '' 's/a/b/' .claude/settings.json",
    'echo {} > .claude/settings.json',
    'rm .claude/hooks/guard-bash.mjs',
    'mv .claude/settings.local.json /tmp/',
    'cat .claude/settings.json | tee .claude/settings.json',
    'git checkout -- .claude/settings.json',
    'cd .claude && rm -r hooks',
  ])('blocks %j', (command) => {
    expect(guard(command, /\.claude\/ settings and hooks/)).toEqual({ status: 2, said: true });
  });

  it.each([
    'cat .claude/settings.json',
    'git add .claude/settings.json',
    'git diff .claude/hooks/guard-bash.mjs',
    'git log -- .claude/settings.json',
    'ls .claude/hooks',
  ])('allows the read-only %j', (command) => {
    expect(guard(command)).toEqual(ALLOWED);
  });
});

describe('guard-bash: input handling', () => {
  it('allows a non-Bash payload', () => {
    const r = spawnSync(process.execPath, [HOOK], {
      input: JSON.stringify({ tool_name: 'Read', tool_input: { file_path: '/x' } }),
      encoding: 'utf8',
    });
    expect(r.status).toBe(0);
  });

  it('fails closed on unreadable input', () => {
    const r = spawnSync(process.execPath, [HOOK], { input: 'not json', encoding: 'utf8' });
    expect(r.status).toBe(2);
  });
});
