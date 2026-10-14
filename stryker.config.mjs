// Mutation testing: informational, never a gate (`break: null`). Rationale: docs/guides/quality-gates.md.
export default {
  testRunner: 'vitest',
  mutate: ['src/**/*.ts'],
  ignorePatterns: ['coverage', 'reports', 'docs', '.claude'],
  reporters: ['clear-text', 'progress', 'html', 'json'],
  htmlReporter: { fileName: 'reports/mutation/mutation.html' },
  jsonReporter: { fileName: 'reports/mutation/mutation.json' },
  // Re-runs test only changed mutants; delete the file to force a full pass.
  incremental: true,
  incrementalFile: 'reports/mutation/incremental.json',
  thresholds: { high: 90, low: 75, break: null },
};
