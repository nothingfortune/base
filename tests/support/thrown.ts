import { expect } from 'vitest';

/** Run `fn`, require it to throw, and return the error: no assertion lives in a catch. */
// E appears only in the return type on purpose: the call site states the expected error once.
// eslint-disable-next-line @typescript-eslint/no-unnecessary-type-parameters
export function thrown<E = unknown>(fn: () => unknown): E {
  try {
    fn();
  } catch (err) {
    return err as E;
  }
  return expect.unreachable('expected the call to throw, and it returned normally');
}

/** The awaited form: require `fn`'s promise to reject and return the reason. */
export async function thrownAsync<E = unknown>(fn: () => Promise<unknown>): Promise<E> {
  try {
    await fn();
  } catch (err) {
    return err as E;
  }
  return expect.unreachable('expected the call to reject, and it resolved');
}
