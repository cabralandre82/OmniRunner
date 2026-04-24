/**
 * Pluggable sliding-window rate limiter for API routes.
 *
 * Auto-detects Upstash Redis. When available, uses distributed store
 * that works correctly across multiple serverless instances.
 * Falls back to in-memory store (single-instance only) when Redis is not configured.
 *
 * L01-21 — In Vercel Serverless, each invocation can be a fresh lambda,
 * so the in-memory Map is effectively rate-limit OFF. For sensitive
 * surfaces (login/financial mutations) we expose `rateLimitFailClosed`
 * which returns "denied" when Redis is unavailable, and a generic
 * `rateLimit` whose default mode is `degrade` (current legacy behaviour).
 *
 * L02-15 — `getRedis()` is now request-scoped (re-evaluates env every
 * 60 s in `redis.ts`), so we no longer cache `_hasRedis` at module
 * init. The recheck cost is one process.env read per minute.
 */

import { getRedis, isRedisAvailable } from "./redis";

export interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  resetAt: number;
  /** Indicates whether Redis or memory backed this decision. */
  store?: "redis" | "memory" | "fail_closed";
}

export interface RateLimitStore {
  get(key: string): Promise<{ count: number; resetAt: number } | null>;
  set(key: string, entry: { count: number; resetAt: number }): Promise<void>;
  delete(key: string): Promise<void>;
}

interface RateLimitOptions {
  maxRequests?: number;
  windowMs?: number;
  /**
   * `degrade` (default): when Redis is missing fall back to in-memory.
   *   Acceptable for low-risk surfaces.
   * `fail_closed`: when Redis is missing return `allowed: false`.
   *   MANDATORY for login/financial mutations (L01-21).
   */
  onMissingRedis?: "degrade" | "fail_closed";
}

interface Entry {
  count: number;
  resetAt: number;
}

const memoryStore = new Map<string, Entry>();
const CLEANUP_INTERVAL = 60_000;
let lastCleanup = Date.now();

let _fallbackHits = 0;
let _failClosedHits = 0;

function cleanup() {
  const now = Date.now();
  if (now - lastCleanup < CLEANUP_INTERVAL) return;
  lastCleanup = now;
  memoryStore.forEach((entry, key) => {
    if (entry.resetAt <= now) memoryStore.delete(key);
  });
}

function rateLimitInMemory(
  key: string,
  { maxRequests = 10, windowMs = 60_000 }: RateLimitOptions = {},
): RateLimitResult {
  cleanup();
  const now = Date.now();
  const entry = memoryStore.get(key);

  if (!entry || entry.resetAt <= now) {
    memoryStore.set(key, { count: 1, resetAt: now + windowMs });
    return {
      allowed: true,
      remaining: maxRequests - 1,
      resetAt: now + windowMs,
      store: "memory",
    };
  }

  entry.count++;
  if (entry.count > maxRequests) {
    return { allowed: false, remaining: 0, resetAt: entry.resetAt, store: "memory" };
  }

  return {
    allowed: true,
    remaining: maxRequests - entry.count,
    resetAt: entry.resetAt,
    store: "memory",
  };
}

async function rateLimitRedis(
  key: string,
  { maxRequests = 10, windowMs = 60_000 }: RateLimitOptions = {},
): Promise<RateLimitResult> {
  const redis = getRedis()!;
  const now = Date.now();
  const redisKey = `rl:${key}`;
  const ttlSec = Math.ceil(windowMs / 1000);

  try {
    const raw = await redis.get<{ count: number; resetAt: number }>(redisKey);

    if (!raw || raw.resetAt <= now) {
      const entry = { count: 1, resetAt: now + windowMs };
      await redis.set(redisKey, entry, { ex: ttlSec });
      return {
        allowed: true,
        remaining: maxRequests - 1,
        resetAt: entry.resetAt,
        store: "redis",
      };
    }

    raw.count++;
    await redis.set(redisKey, raw, { ex: ttlSec });

    if (raw.count > maxRequests) {
      return { allowed: false, remaining: 0, resetAt: raw.resetAt, store: "redis" };
    }

    return {
      allowed: true,
      remaining: maxRequests - raw.count,
      resetAt: raw.resetAt,
      store: "redis",
    };
  } catch (err) {
    console.error("[rate-limit] Redis error, falling back to in-memory:", err);
    _fallbackHits++;
    return rateLimitInMemory(key, { maxRequests, windowMs });
  }
}

export async function rateLimit(
  key: string,
  options: RateLimitOptions = {},
): Promise<RateLimitResult> {
  const onMissingRedis = options.onMissingRedis ?? "degrade";
  if (isRedisAvailable()) {
    return rateLimitRedis(key, options);
  }
  if (onMissingRedis === "fail_closed") {
    _failClosedHits++;
    const windowMs = options.windowMs ?? 60_000;
    return {
      allowed: false,
      remaining: 0,
      resetAt: Date.now() + windowMs,
      store: "fail_closed",
    };
  }
  _fallbackHits++;
  return rateLimitInMemory(key, options);
}

/**
 * L01-21 — strict variant. Use on login, custody mutations, swap
 * accept/cancel, distribute-coins, withdraw, and platform-admin
 * approval endpoints. If Redis is unreachable we return `allowed:
 * false` instead of silently degrading to a per-instance Map that
 * grants every cold-start lambda its own quota.
 */
export async function rateLimitFailClosed(
  key: string,
  options: Omit<RateLimitOptions, "onMissingRedis"> = {},
): Promise<RateLimitResult> {
  return rateLimit(key, { ...options, onMissingRedis: "fail_closed" });
}

/**
 * Telemetry counters used by the /api/_internal/rate-limit-stats
 * scrape endpoint and unit tests.
 */
export function rateLimitTelemetrySnapshot(): {
  fallbackHits: number;
  failClosedHits: number;
} {
  return { fallbackHits: _fallbackHits, failClosedHits: _failClosedHits };
}

export function __resetRateLimitTelemetryForTests(): void {
  _fallbackHits = 0;
  _failClosedHits = 0;
  memoryStore.clear();
}

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

    return {
      allowed: true,
      remaining: maxRequests - entry.count,
      resetAt: entry.resetAt,
    };
  };
}
