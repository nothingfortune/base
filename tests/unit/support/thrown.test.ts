import { describe, expect, it } from 'vitest';

import { thrown, thrownAsync } from '../../support/thrown';

class CodedError extends Error {
  constructor(readonly code: string) {
    super(code);
  }
}

describe('thrown', () => {
  it('returns the error so the caller can assert on its shape', () => {
    const err = thrown<CodedError>(() => {
      throw new CodedError('locked');
    });
    expect(err.code).toBe('locked');
  });

  it('fails when the call returns normally', () => {
    expect(() => thrown(() => 'no error here')).toThrow(/expected the call to throw/);
  });

  it('counts a falsy non-Error throw as thrown', () => {
    expect(
      thrown(() => {
        // eslint-disable-next-line @typescript-eslint/only-throw-error -- the falsy throw is the case under test
        throw undefined;
      }),
    ).toBeUndefined();
  });
});

describe('thrownAsync', () => {
  it('returns the rejection reason', async () => {
    const err = await thrownAsync<CodedError>(() => Promise.reject(new CodedError('corrupt')));
    expect(err.code).toBe('corrupt');
  });

  it('fails when the promise resolves', async () => {
    await expect(thrownAsync(() => Promise.resolve('fine'))).rejects.toThrow(
      /expected the call to reject/,
    );
  });
});
