/**
 * Strategic caching layer — Redis (Upstash) with in-memory fallback.
 *
 * Usage:
 *   const data = await cached("dashboard:kpis:group123", 60, () => fetchKPIs(groupId));
 *
 * TTL presets by data type:
 *   - KPIs/dashboards: 60s (refreshes every minute)
 *   - Rankings/leaderboards: 120s
 *   - Badge counts: 300s (5 min)
 *   - Static config: 600s (10 min)
 */

import { getRedis } from "./redis";

const memCache = new Map<string, { data: unknown; expiresAt: number }>();

export async function cached<T>(
  key: string,
  ttlSeconds: number,
  fetcher: () => Promise<T>,
): Promise<T> {
  const redis = getRedis();

  if (redis) {
    try {
      const hit = await redis.get<T>(key);
      if (hit !== null && hit !== undefined) return hit;

      const fresh = await fetcher();
      await redis.set(key, fresh, { ex: ttlSeconds });
      return fresh;
    } catch {
      return fetcher();
    }
  }

  const now = Date.now();
  const hit = memCache.get(key);
  if (hit && hit.expiresAt > now) return hit.data as T;

  const fresh = await fetcher();
  memCache.set(key, { data: fresh, expiresAt: now + ttlSeconds * 1000 });
  return fresh;
}

export async function invalidate(key: string): Promise<void> {
  const redis = getRedis();
  if (redis) {
    try { await redis.del(key); } catch { /* best effort */ }
  }
  memCache.delete(key);
}

export async function invalidatePattern(pattern: string): Promise<void> {
  const redis = getRedis();
  if (redis) {
    try {
      let cursor = 0;
      do {
        const [next, keys] = await redis.scan(cursor, { match: pattern, count: 100 });
        cursor = next;
        if (keys.length > 0) await redis.del(...keys);
      } while (cursor !== 0);
    } catch { /* best effort */ }
  }

  for (const k of memCache.keys()) {
    if (matchGlob(pattern, k)) memCache.delete(k);
  }
}

function matchGlob(pattern: string, str: string): boolean {
  const re = new RegExp("^" + pattern.replace(/\*/g, ".*") + "$");
  return re.test(str);
}

export const CacheTTL = {
  DASHBOARD_KPI: 60,
  RANKINGS: 120,
  BADGES: 300,
  CONFIG: 600,
  LEADERBOARD: 120,
  ATHLETE_COUNT: 60,
} as const;
