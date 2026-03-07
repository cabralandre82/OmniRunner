/**
 * Pluggable sliding-window rate limiter for API routes.
 *
 * Auto-detects Upstash Redis. When available, uses distributed store
 * that works correctly across multiple serverless instances.
 * Falls back to in-memory store (single-instance only) when Redis is not configured.
 */

import { getRedis } from "./redis";

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

// --- In-memory store (fallback) ---

interface Entry {
  count: number;
  resetAt: number;
}

const memoryStore = new Map<string, Entry>();
const CLEANUP_INTERVAL = 60_000;
let lastCleanup = Date.now();

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
    return { allowed: true, remaining: maxRequests - 1, resetAt: now + windowMs };
  }

  entry.count++;
  if (entry.count > maxRequests) {
    return { allowed: false, remaining: 0, resetAt: entry.resetAt };
  }

  return { allowed: true, remaining: maxRequests - entry.count, resetAt: entry.resetAt };
}

// --- Redis store (Upstash) ---

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
      return { allowed: true, remaining: maxRequests - 1, resetAt: entry.resetAt };
    }

    raw.count++;
    await redis.set(redisKey, raw, { ex: ttlSec });

    if (raw.count > maxRequests) {
      return { allowed: false, remaining: 0, resetAt: raw.resetAt };
    }

    return { allowed: true, remaining: maxRequests - raw.count, resetAt: raw.resetAt };
  } catch (err) {
    console.error("[rate-limit] Redis error, falling back to in-memory:", err);
    return rateLimitInMemory(key, { maxRequests, windowMs });
  }
}

// --- Unified entry point (always async for consistent API) ---

const _hasRedis = !!getRedis();

export async function rateLimit(
  key: string,
  options: RateLimitOptions = {},
): Promise<RateLimitResult> {
  if (_hasRedis) {
    return rateLimitRedis(key, options);
  }
  return rateLimitInMemory(key, options);
}

// --- Async factory for custom stores (backward compat) ---

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
