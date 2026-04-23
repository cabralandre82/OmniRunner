import {
  AggregateStatus,
  ComponentStatus,
  StatusComponent,
  StatusFeed,
  StatusLevel,
  STATUS_CACHE_DEFAULT_TTL_MS,
  STATUS_CACHE_MIN_TTL_MS,
  STATUS_COMPONENTS,
  compareStatusLevels,
} from "./types";

/**
 * Pick the worst status level in the list. Empty list → `unknown`
 * (we can't say anything useful).
 */
export function worstLevel(levels: readonly StatusLevel[]): StatusLevel {
  if (levels.length === 0) return "unknown";
  let worst: StatusLevel = "operational";
  for (const l of levels) {
    if (compareStatusLevels(l, worst) > 0) worst = l;
  }
  return worst;
}

/**
 * Aggregate component statuses into the {@link AggregateStatus}
 * payload.
 *
 * Contract:
 *  - Result always contains exactly one entry per
 *    {@link StatusComponent}, in the canonical order.
 *  - Missing components are filled with
 *    `{ level: 'unknown', note: 'no feed registered' }`.
 *  - Duplicated components: the **worst** level wins (defensive —
 *    an aggregator that accidentally polls two feeds for the same
 *    component shouldn't degrade the signal by showing the nicer
 *    one).
 *  - `overall` is the worst level across the final component list.
 */
export function aggregateStatus(
  statuses: readonly ComponentStatus[],
  now: Date,
): AggregateStatus {
  const byComponent = new Map<StatusComponent, ComponentStatus>();

  for (const s of statuses) {
    const existing = byComponent.get(s.component);
    if (!existing || compareStatusLevels(s.level, existing.level) > 0) {
      byComponent.set(s.component, s);
    }
  }

  const components: ComponentStatus[] = STATUS_COMPONENTS.map((c) => {
    const hit = byComponent.get(c);
    if (hit) return hit;
    return {
      component: c,
      level: "unknown",
      observedAt: now.toISOString(),
      note: "no feed registered",
    };
  });

  return {
    overall: worstLevel(components.map((c) => c.level)),
    components,
    generatedAt: now.toISOString(),
  };
}

/**
 * Gather component statuses from a list of feeds. Any feed that
 * rejects or throws is coerced to `unknown` with a short note —
 * the whole point is that a single vendor outage must never knock
 * the status endpoint offline.
 *
 * Feeds are invoked in parallel. Callers that need strict ordering
 * should sort the result themselves (the aggregator does this
 * already).
 */
export async function collectFromFeeds(
  feeds: readonly StatusFeed[],
  now: Date,
): Promise<ComponentStatus[]> {
  const tasks = feeds.map(async (feed) => {
    try {
      const res = await feed.fetch(now);
      if (res.component !== feed.component) {
        return {
          component: feed.component,
          level: "unknown" as StatusLevel,
          observedAt: now.toISOString(),
          note: "feed returned wrong component",
        } satisfies ComponentStatus;
      }
      return res;
    } catch {
      return {
        component: feed.component,
        level: "unknown" as StatusLevel,
        observedAt: now.toISOString(),
        note: "feed fetch failed",
      } satisfies ComponentStatus;
    }
  });
  return Promise.all(tasks);
}

export interface CachedAggregatorOptions {
  feeds: readonly StatusFeed[];
  ttlMs?: number;
  now?: () => Date;
}

/**
 * TTL-cached aggregator. Subsequent calls within `ttlMs` return the
 * cached payload without invoking feeds. Designed for stateless
 * serverless contexts where the module-level cache survives for the
 * duration of a warm container.
 *
 * Enforces {@link STATUS_CACHE_MIN_TTL_MS} as the floor — dropping
 * below 30s risks vendor rate limits and makes the status endpoint
 * a DoS amplifier against third-party status APIs.
 */
export function createCachedAggregator(opts: CachedAggregatorOptions) {
  const ttlMs = Math.max(
    opts.ttlMs ?? STATUS_CACHE_DEFAULT_TTL_MS,
    STATUS_CACHE_MIN_TTL_MS,
  );
  const clock = opts.now ?? (() => new Date());
  const { feeds } = opts;

  let cached: { at: number; value: AggregateStatus } | null = null;

  async function get(): Promise<AggregateStatus> {
    const now = clock();
    const nowMs = now.getTime();
    if (cached && nowMs - cached.at < ttlMs) return cached.value;

    const statuses = await collectFromFeeds(feeds, now);
    const value = aggregateStatus(statuses, now);
    cached = { at: nowMs, value };
    return value;
  }

  function invalidate() {
    cached = null;
  }

  return { get, invalidate, ttlMs };
}
