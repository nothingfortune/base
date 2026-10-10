import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['tests/unit/**/*.test.ts'],
    environment: 'node',
    coverage: {
      provider: 'v8',
      // `include` reports untested src files at 0% instead of leaving them out.
      include: ['src/**/*.ts'],
      // json-summary feeds scripts/check-coverage-drift.mjs.
      reporter: ['text', 'html', 'json-summary'],
      // Floors sit ~1 point under measured; raise them as coverage rises (docs/guides/quality-gates.md).
      thresholds: {
        statements: 99,
        branches: 99,
        functions: 99,
        lines: 99,
      },
    },
  },
});
