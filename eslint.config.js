import js from '@eslint/js';
import vitest from '@vitest/eslint-plugin';
import prettier from 'eslint-config-prettier';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  { ignores: ['dist/**', 'build/**', 'coverage/**', 'node_modules/**', '.claude/worktrees/**'] },
  js.configs.recommended,
  ...tseslint.configs.strictTypeChecked,
  ...tseslint.configs.stylisticTypeChecked,
  {
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],
      'no-console': ['warn', { allow: ['warn', 'error'] }],
      'no-restricted-syntax': [
        'error',
        {
          selector: 'TSAsExpression > TSAsExpression.expression',
          message: 'No double assertion (`as unknown as T`): narrow the value or fix the type.',
        },
      ],
    },
  },
  // Monolith limits: a file or function past these sizes hides invariants no test can isolate.
  {
    files: ['src/**/*.{ts,tsx}', 'scripts/**/*.{ts,js,mjs}'],
    rules: {
      'max-lines': ['error', { max: 400, skipBlankLines: true, skipComments: true }],
      'max-lines-per-function': ['error', { max: 150, skipBlankLines: true, skipComments: true }],
    },
  },
  // Every describe/it callback is a function, so suites get a file limit only.
  {
    files: ['tests/**/*.{ts,tsx}', '**/*.test.{ts,tsx}'],
    rules: { 'max-lines': ['error', { max: 600, skipBlankLines: true, skipComments: true }] },
  },
  // Each rule bans a shape of test that stays green while checking nothing.
  {
    files: ['tests/**/*.{ts,tsx}', '**/*.test.{ts,tsx}'],
    plugins: { vitest },
    rules: {
      'vitest/expect-expect': 'error',
      'vitest/require-to-throw-message': 'error',
      'vitest/no-conditional-expect': 'error',
      // maxArgs 2: vitest takes a failure message as expect's second argument.
      'vitest/valid-expect': ['error', { maxArgs: 2 }],
      'vitest/no-identical-title': 'error',
      'vitest/no-focused-tests': 'error',
      'vitest/no-disabled-tests': 'error',
    },
  },
  { files: ['**/*.js', '**/*.mjs'], ...tseslint.configs.disableTypeChecked },
  {
    files: ['**/*.mjs'],
    languageOptions: { globals: { console: 'readonly', process: 'readonly' } },
  },
  // Repo tooling reports on stdout; that output is its interface.
  { files: ['scripts/**'], rules: { 'no-console': 'off' } },
  prettier,
);
