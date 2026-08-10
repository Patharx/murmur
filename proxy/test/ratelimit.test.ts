import { describe, expect, it } from 'vitest';
import { checkAndIncrement, rateLimitKey } from '../src/ratelimit';

function fakeKv() {
  const store = new Map<string, string>();
  const kv = {
    async get(key: string) {
      return store.get(key) ?? null;
    },
    async put(key: string, value: string) {
      store.set(key, value);
    },
  };
  return { kv: kv as unknown as KVNamespace, store };
}

const SUB = '110000000000000000001';

describe('rateLimitKey', () => {
  it('is scoped to one user and one UTC day, and holds nothing else', () => {
    expect(rateLimitKey(SUB, new Date('2026-08-09T23:59:00Z'))).toBe(`rl:${SUB}:2026-08-09`);
    expect(rateLimitKey(SUB, new Date('2026-08-10T00:01:00Z'))).toBe(`rl:${SUB}:2026-08-10`);
  });
});

describe('checkAndIncrement', () => {
  it('counts up from nothing', async () => {
    const { kv } = fakeKv();
    expect(await checkAndIncrement(kv, SUB, 3)).toEqual({ allowed: true, used: 1, remaining: 2 });
    expect(await checkAndIncrement(kv, SUB, 3)).toEqual({ allowed: true, used: 2, remaining: 1 });
    expect(await checkAndIncrement(kv, SUB, 3)).toEqual({ allowed: true, used: 3, remaining: 0 });
  });

  it('refuses once the day’s allowance is spent', async () => {
    const { kv } = fakeKv();
    for (let i = 0; i < 3; i++) await checkAndIncrement(kv, SUB, 3);
    expect(await checkAndIncrement(kv, SUB, 3)).toEqual({ allowed: false, used: 3, remaining: 0 });
  });

  it('does not spend a request when it refuses one', async () => {
    const { kv, store } = fakeKv();
    for (let i = 0; i < 3; i++) await checkAndIncrement(kv, SUB, 3);
    await checkAndIncrement(kv, SUB, 3);
    await checkAndIncrement(kv, SUB, 3);
    expect(store.get(rateLimitKey(SUB))).toBe('3');
  });

  it('starts over on the next day', async () => {
    const { kv } = fakeKv();
    const monday = new Date('2026-08-09T12:00:00Z');
    const tuesday = new Date('2026-08-10T12:00:00Z');
    for (let i = 0; i < 3; i++) await checkAndIncrement(kv, SUB, 3, monday);
    expect((await checkAndIncrement(kv, SUB, 3, monday)).allowed).toBe(false);
    expect((await checkAndIncrement(kv, SUB, 3, tuesday)).allowed).toBe(true);
  });

  it('keeps users apart', async () => {
    const { kv } = fakeKv();
    for (let i = 0; i < 3; i++) await checkAndIncrement(kv, SUB, 3);
    expect((await checkAndIncrement(kv, 'a-different-account', 3)).allowed).toBe(true);
  });

  it('treats a corrupt counter as zero rather than locking the user out', async () => {
    const { kv, store } = fakeKv();
    store.set(rateLimitKey(SUB), 'not a number');
    expect((await checkAndIncrement(kv, SUB, 3)).allowed).toBe(true);
  });

  it('stores only a count — no note content, no identity beyond the key', async () => {
    const { kv, store } = fakeKv();
    await checkAndIncrement(kv, SUB, 200);
    expect([...store.values()]).toEqual(['1']);
  });
});
