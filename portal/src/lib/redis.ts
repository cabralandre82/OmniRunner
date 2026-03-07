/**
 * Upstash Redis client — singleton.
 *
 * Reads UPSTASH_REDIS_REST_URL and UPSTASH_REDIS_REST_TOKEN from env.
 * Returns null if not configured, allowing graceful fallback to in-memory.
 *
 * Setup: https://console.upstash.com → Create Database → copy REST URL + Token
 * Then add to .env.local:
 *   UPSTASH_REDIS_REST_URL=https://xxx.upstash.io
 *   UPSTASH_REDIS_REST_TOKEN=AXxx...
 */

import { Redis } from "@upstash/redis";

let _redis: Redis | null = null;
let _checked = false;

export function getRedis(): Redis | null {
  if (_checked) return _redis;
  _checked = true;

  const url = process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.UPSTASH_REDIS_REST_TOKEN;

  if (!url || !token) {
    console.warn("[redis] UPSTASH_REDIS_REST_URL or TOKEN not set — using in-memory fallback");
    return null;
  }

  _redis = new Redis({ url, token });
  return _redis;
}
