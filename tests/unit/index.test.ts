import { describe, expect, it } from 'vitest';

import { greet } from '../../src/index';

describe('greet', () => {
  it('addresses the given name', () => {
    expect(greet('world')).toBe('Hello, world!');
  });
});
