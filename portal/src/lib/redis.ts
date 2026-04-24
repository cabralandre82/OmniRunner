/**
 * Upstash Redis client — request-aware singleton.
 *
 * Reads UPSTASH_REDIS_REST_URL and UPSTASH_REDIS_REST_TOKEN from env.
 * Returns null if not configured, allowing graceful fallback to in-memory.
 *
 * L02-15 — Module-level "_checked" cache used to be set on first call
 * forever. In Vercel Serverless, env vars CAN change between cold starts
 * (e.g. preview branch promoted, secret rotation), so a hot lambda whose
 * first invocation observed "no Redis" would never upgrade to Redis even
 * after the env was fixed. We now re-evaluate the env every
 * `RECHECK_INTERVAL_MS` (60 s) which is short enough that an SRE
 * remediation lands within one cron tick, but long enough to avoid
 * doing a process.env round-trip on every request.
 *
 * Setup: https://console.upstash.com → Create Database → copy REST URL + Token
 * Then add to .env.local:
 *   UPSTASH_REDIS_REST_URL=https://xxx.upstash.io
 *   UPSTASH_REDIS_REST_TOKEN=AXxx...
 */

import { Redis } from "@upstash/redis";

const RECHECK_INTERVAL_MS = 60_000;

let _redis: Redis | null = null;
let _lastCheckedAt = 0;
let _lastWarned = 0;
let _lastConfigKey = "";

export function getRedis(): Redis | null {
  const now = Date.now();
  if (_redis && now - _lastCheckedAt < RECHECK_INTERVAL_MS) {
    return _redis;
  }

  const url = process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.UPSTASH_REDIS_REST_TOKEN;
  const configKey = `${url ?? ""}::${token ? token.length : 0}`;

  if (!url || !token) {
    if (now - _lastWarned > RECHECK_INTERVAL_MS) {
      console.warn(
        "[redis] UPSTASH_REDIS_REST_URL or TOKEN not set — fallback path active",
      );
      _lastWarned = now;
    }
    _redis = null;
    _lastCheckedAt = now;
    _lastConfigKey = configKey;
    return null;
  }

  if (!_redis || configKey !== _lastConfigKey) {
    _redis = new Redis({ url, token });
    _lastConfigKey = configKey;
  }
  _lastCheckedAt = now;
  return _redis;
}

/**
 * Test/audit hook: forces the next getRedis() call to re-read env vars.
 * Production code MUST NOT call this on the hot path.
 */
export function __resetRedisForTests(): void {
  _redis = null;
  _lastCheckedAt = 0;
  _lastConfigKey = "";
  _lastWarned = 0;
}

/**
 * Returns true iff the Upstash Redis client is currently available.
 * Performs the same recheck the rateLimit() entry-point does, so callers
 * that want to fail-closed on financial endpoints (L01-21) can branch on
 * the same signal the limiter uses internally.
 */
export function isRedisAvailable(): boolean {
  return getRedis() !== null;
}
