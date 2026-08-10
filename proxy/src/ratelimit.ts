// Per-user daily request limit, held in Workers KV.
//
// The key is `rl:<google sub>:<UTC date>` and nothing else — no note content,
// no email address, no request log. Entries expire on their own after 25 hours,
// so the store empties itself and holds at most one integer per active user per
// day.
//
// KV read-modify-write is not atomic, so a user firing several requests in the
// same instant can slip a few over the limit. That is fine: the limit is a
// runaway-bug backstop, not an access control. docs/ARCHITECTURE.md §7 is
// explicit that exceeding it should be read as a bug report rather than an
// attack.

const TTL_SECONDS = 90_000; // 25 hours — comfortably past any day boundary

export type RateLimitResult = { allowed: boolean; used: number; remaining: number };

export function rateLimitKey(sub: string, now: Date = new Date()): string {
  return `rl:${sub}:${now.toISOString().slice(0, 10)}`;
}

export async function checkAndIncrement(
  kv: KVNamespace,
  sub: string,
  limit: number,
  now: Date = new Date(),
): Promise<RateLimitResult> {
  const key = rateLimitKey(sub, now);
  const raw = await kv.get(key);
  const used = Number.parseInt(raw ?? '0', 10) || 0;

  if (used >= limit) {
    return { allowed: false, used, remaining: 0 };
  }

  const next = used + 1;
  await kv.put(key, String(next), { expirationTtl: TTL_SECONDS });
  return { allowed: true, used: next, remaining: Math.max(0, limit - next) };
}
