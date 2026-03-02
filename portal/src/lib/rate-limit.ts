/**
 * Pluggable sliding-window rate limiter for API routes.
 *
 * Default export is a synchronous in-memory limiter (zero-config).
 * For production at scale, use createAsyncRateLimiter() with a
 * Redis/Upstash store that implements RateLimitStore.
 */

export interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  resetAt: number;
}

export interface RateLimitStore {
  get(key: string): Promise<{ count: number; resetAt: number } | null>;
  set(key: string, entry: { count: number; resetAt: number }): Promise<void>;
  delete(key: string): Promise<void>;
}

interface RateLimitOptions {
  maxRequests?: number;
  windowMs?: number;
}

// --- In-memory store (default, sync) ---

interface Entry {
  count: number;
  resetAt: number;
}

const store = new Map<string, Entry>();
const CLEANUP_INTERVAL = 60_000;
let lastCleanup = Date.now();

function cleanup() {
  const now = Date.now();
  if (now - lastCleanup < CLEANUP_INTERVAL) return;
  lastCleanup = now;
  store.forEach((entry, key) => {
    if (entry.resetAt <= now) store.delete(key);
  });
}

export function rateLimit(
  key: string,
  { maxRequests = 10, windowMs = 60_000 }: RateLimitOptions = {},
): RateLimitResult {
  cleanup();
  const now = Date.now();
  const entry = store.get(key);

  if (!entry || entry.resetAt <= now) {
    store.set(key, { count: 1, resetAt: now + windowMs });
    return { allowed: true, remaining: maxRequests - 1, resetAt: now + windowMs };
  }

  entry.count++;
  if (entry.count > maxRequests) {
    return { allowed: false, remaining: 0, resetAt: entry.resetAt };
  }

  return { allowed: true, remaining: maxRequests - entry.count, resetAt: entry.resetAt };
}

// --- Async factory for distributed stores (Redis, Upstash, etc.) ---

export function createAsyncRateLimiter(externalStore: RateLimitStore) {
  return async function rateLimitAsync(
    key: string,
    { maxRequests = 10, windowMs = 60_000 }: RateLimitOptions = {},
  ): Promise<RateLimitResult> {
    const now = Date.now();
    const entry = await externalStore.get(key);

    if (!entry || entry.resetAt <= now) {
      await externalStore.set(key, { count: 1, resetAt: now + windowMs });
      return { allowed: true, remaining: maxRequests - 1, resetAt: now + windowMs };
    }

    entry.count++;
    await externalStore.set(key, entry);

    if (entry.count > maxRequests) {
      return { allowed: false, remaining: 0, resetAt: entry.resetAt };
    }

    return { allowed: true, remaining: maxRequests - entry.count, resetAt: entry.resetAt };
  };
}
