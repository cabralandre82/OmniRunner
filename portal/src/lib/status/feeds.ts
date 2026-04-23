import {
  ComponentStatus,
  StatusComponent,
  StatusFeed,
  StatusLevel,
} from "./types";

/**
 * Trivial feed that returns a fixed status. Useful for tests and
 * for the first iteration of `/api/public/status` while we wire up
 * real vendor feeds.
 */
export function staticFeed(
  component: StatusComponent,
  level: StatusLevel,
  note?: string,
): StatusFeed {
  return {
    component,
    async fetch(now) {
      return {
        component,
        level,
        observedAt: now.toISOString(),
        note,
      } satisfies ComponentStatus;
    },
  };
}

/**
 * Feed that delegates to an internal health probe. The probe is
 * passed in rather than hard-coded so the feed stays pure and
 * server-runtime agnostic — route handlers wire the probe to
 * `createServiceClient()` at the edge.
 *
 * Probe contract:
 *  - Resolve `'ok' | 'degraded' | 'down'`;
 *  - Reject to signal total failure (rare, typically an uncaught
 *    throw).
 *
 * Map:
 *  - `'ok'`        → `operational`
 *  - `'degraded'`  → `degraded`
 *  - `'down'`      → `major_outage`
 *  - reject/throw  → `unknown` (handled by the aggregator)
 */
export function internalProbeFeed(
  component: StatusComponent,
  probe: () => Promise<"ok" | "degraded" | "down">,
): StatusFeed {
  return {
    component,
    async fetch(now) {
      const result = await probe();
      const level: StatusLevel =
        result === "ok"
          ? "operational"
          : result === "degraded"
            ? "degraded"
            : "major_outage";
      return {
        component,
        level,
        observedAt: now.toISOString(),
      } satisfies ComponentStatus;
    },
  };
}

/**
 * Wrap a feed in a timeout so a slow vendor cannot stall the whole
 * aggregator. On timeout the wrapped feed rejects (the aggregator
 * then coerces this to `unknown`).
 */
export function withTimeout(
  inner: StatusFeed,
  timeoutMs: number,
): StatusFeed {
  if (timeoutMs <= 0) {
    throw new Error("withTimeout: timeoutMs must be > 0");
  }
  return {
    component: inner.component,
    async fetch(now) {
      const timer = new Promise<never>((_, reject) => {
        setTimeout(() => reject(new Error("status feed timeout")), timeoutMs);
      });
      return Promise.race([inner.fetch(now), timer]);
    },
  };
}
