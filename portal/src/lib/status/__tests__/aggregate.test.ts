/**
 * L20-06 — Unit tests for the public status-page aggregator.
 */

import { describe, it, expect } from "vitest";

import {
  aggregateStatus,
  collectFromFeeds,
  createCachedAggregator,
  worstLevel,
} from "../aggregate";
import { internalProbeFeed, staticFeed, withTimeout } from "../feeds";
import {
  ComponentStatus,
  STATUS_CACHE_DEFAULT_TTL_MS,
  STATUS_CACHE_MIN_TTL_MS,
  STATUS_COMPONENTS,
  StatusFeed,
  compareStatusLevels,
} from "../types";

const NOW = new Date("2026-04-21T12:00:00.000Z");

describe("status — invariants", () => {
  it("canonical component order has exactly 6 entries and no duplicates", () => {
    expect(STATUS_COMPONENTS).toHaveLength(6);
    expect(new Set(STATUS_COMPONENTS).size).toBe(STATUS_COMPONENTS.length);
  });

  it("status level ranking pins the worst-wins convention", () => {
    expect(compareStatusLevels("operational", "operational")).toBe(0);
    expect(compareStatusLevels("operational", "degraded")).toBeLessThan(0);
    expect(compareStatusLevels("degraded", "partial_outage")).toBeLessThan(0);
    expect(
      compareStatusLevels("partial_outage", "major_outage"),
    ).toBeLessThan(0);
    expect(compareStatusLevels("unknown", "operational")).toBeGreaterThan(0);
    expect(compareStatusLevels("unknown", "degraded")).toBeLessThan(0);
  });

  it("cache TTL floor is 30 s (and default 60 s)", () => {
    expect(STATUS_CACHE_MIN_TTL_MS).toBe(30_000);
    expect(STATUS_CACHE_DEFAULT_TTL_MS).toBe(60_000);
    expect(STATUS_CACHE_DEFAULT_TTL_MS).toBeGreaterThanOrEqual(
      STATUS_CACHE_MIN_TTL_MS,
    );
  });
});

describe("status — worstLevel", () => {
  it("empty → unknown", () => {
    expect(worstLevel([])).toBe("unknown");
  });

  it("all operational → operational", () => {
    expect(worstLevel(["operational", "operational"])).toBe("operational");
  });

  it("one degraded beats operational", () => {
    expect(worstLevel(["operational", "degraded", "operational"])).toBe(
      "degraded",
    );
  });

  it("major_outage beats every other level", () => {
    expect(
      worstLevel([
        "degraded",
        "partial_outage",
        "major_outage",
        "operational",
      ]),
    ).toBe("major_outage");
  });

  it("unknown is worse than operational but better than degraded", () => {
    expect(worstLevel(["operational", "unknown"])).toBe("unknown");
    expect(worstLevel(["unknown", "degraded"])).toBe("degraded");
  });
});

describe("status — aggregateStatus", () => {
  const base: ComponentStatus = {
    component: "web",
    level: "operational",
    observedAt: NOW.toISOString(),
  };

  it("fills missing components with unknown + note", () => {
    const agg = aggregateStatus([base], NOW);
    expect(agg.components).toHaveLength(STATUS_COMPONENTS.length);
    expect(agg.components.map((c) => c.component)).toEqual([
      ...STATUS_COMPONENTS,
    ]);
    const missing = agg.components.find((c) => c.component === "api")!;
    expect(missing.level).toBe("unknown");
    expect(missing.note).toBe("no feed registered");
  });

  it("overall is worst component level", () => {
    const agg = aggregateStatus(
      [
        { ...base, component: "web", level: "operational" },
        { ...base, component: "api", level: "degraded" },
        { ...base, component: "database", level: "operational" },
        { ...base, component: "auth", level: "operational" },
        { ...base, component: "payments", level: "operational" },
        { ...base, component: "strava", level: "operational" },
      ],
      NOW,
    );
    expect(agg.overall).toBe("degraded");
  });

  it("duplicated components: worst wins", () => {
    const agg = aggregateStatus(
      [
        { ...base, component: "api", level: "operational" },
        { ...base, component: "api", level: "major_outage" },
      ],
      NOW,
    );
    const api = agg.components.find((c) => c.component === "api")!;
    expect(api.level).toBe("major_outage");
  });

  it("renders generatedAt as ISO-8601 UTC", () => {
    const agg = aggregateStatus([base], NOW);
    expect(agg.generatedAt).toBe("2026-04-21T12:00:00.000Z");
  });
});

describe("status — collectFromFeeds", () => {
  it("collects all feeds in parallel", async () => {
    const feeds: StatusFeed[] = [
      staticFeed("web", "operational"),
      staticFeed("api", "degraded", "p95 >1s"),
    ];
    const out = await collectFromFeeds(feeds, NOW);
    expect(out).toHaveLength(2);
    expect(out[0].component).toBe("web");
    expect(out[1].component).toBe("api");
    expect(out[1].note).toBe("p95 >1s");
  });

  it("coerces throwing feeds to unknown", async () => {
    const broken: StatusFeed = {
      component: "payments",
      async fetch() {
        throw new Error("vendor timeout");
      },
    };
    const out = await collectFromFeeds([broken], NOW);
    expect(out[0].level).toBe("unknown");
    expect(out[0].note).toBe("feed fetch failed");
  });

  it("detects feed that returns the wrong component", async () => {
    const lying: StatusFeed = {
      component: "payments",
      async fetch() {
        return {
          component: "strava",
          level: "operational",
          observedAt: NOW.toISOString(),
        };
      },
    };
    const out = await collectFromFeeds([lying], NOW);
    expect(out[0].component).toBe("payments");
    expect(out[0].level).toBe("unknown");
    expect(out[0].note).toBe("feed returned wrong component");
  });
});

describe("status — internalProbeFeed", () => {
  it("maps ok → operational", async () => {
    const res = await internalProbeFeed("api", async () => "ok").fetch(NOW);
    expect(res.level).toBe("operational");
  });

  it("maps degraded → degraded", async () => {
    const res = await internalProbeFeed("api", async () => "degraded").fetch(
      NOW,
    );
    expect(res.level).toBe("degraded");
  });

  it("maps down → major_outage", async () => {
    const res = await internalProbeFeed("api", async () => "down").fetch(NOW);
    expect(res.level).toBe("major_outage");
  });

  it("probe rejection bubbles up (aggregator handles the coerce)", async () => {
    const feed = internalProbeFeed("api", async () => {
      throw new Error("db down");
    });
    await expect(feed.fetch(NOW)).rejects.toThrow("db down");
  });
});

describe("status — withTimeout", () => {
  it("lets fast feeds through", async () => {
    const fast = staticFeed("web", "operational");
    const res = await withTimeout(fast, 1_000).fetch(NOW);
    expect(res.level).toBe("operational");
  });

  it("rejects slow feeds after timeout", async () => {
    const slow: StatusFeed = {
      component: "api",
      async fetch() {
        return new Promise((resolve) => {
          setTimeout(
            () =>
              resolve({
                component: "api",
                level: "operational",
                observedAt: NOW.toISOString(),
              }),
            5_000,
          );
        });
      },
    };
    await expect(withTimeout(slow, 10).fetch(NOW)).rejects.toThrow(
      "status feed timeout",
    );
  });

  it("rejects non-positive timeouts at wrap-time", () => {
    expect(() => withTimeout(staticFeed("web", "operational"), 0)).toThrow();
    expect(() =>
      withTimeout(staticFeed("web", "operational"), -1),
    ).toThrow();
  });
});

describe("status — createCachedAggregator", () => {
  it("invokes feeds once within TTL window", async () => {
    let calls = 0;
    const feed: StatusFeed = {
      component: "api",
      async fetch() {
        calls += 1;
        return {
          component: "api",
          level: "operational",
          observedAt: NOW.toISOString(),
        };
      },
    };
    let t = NOW.getTime();
    const agg = createCachedAggregator({
      feeds: [feed],
      ttlMs: 60_000,
      now: () => new Date(t),
    });
    await agg.get();
    await agg.get();
    t += 10_000;
    await agg.get();
    expect(calls).toBe(1);
  });

  it("re-invokes feeds after TTL elapses", async () => {
    let calls = 0;
    const feed: StatusFeed = {
      component: "api",
      async fetch() {
        calls += 1;
        return {
          component: "api",
          level: "operational",
          observedAt: NOW.toISOString(),
        };
      },
    };
    let t = NOW.getTime();
    const agg = createCachedAggregator({
      feeds: [feed],
      ttlMs: 60_000,
      now: () => new Date(t),
    });
    await agg.get();
    t += 61_000;
    await agg.get();
    expect(calls).toBe(2);
  });

  it("floors TTL at STATUS_CACHE_MIN_TTL_MS", () => {
    const agg = createCachedAggregator({ feeds: [], ttlMs: 5_000 });
    expect(agg.ttlMs).toBe(STATUS_CACHE_MIN_TTL_MS);
  });

  it("invalidate() forces a re-fetch on next get()", async () => {
    let calls = 0;
    const feed: StatusFeed = {
      component: "api",
      async fetch() {
        calls += 1;
        return {
          component: "api",
          level: "operational",
          observedAt: NOW.toISOString(),
        };
      },
    };
    const agg = createCachedAggregator({ feeds: [feed], ttlMs: 60_000 });
    await agg.get();
    agg.invalidate();
    await agg.get();
    expect(calls).toBe(2);
  });

  it("never throws when a feed throws — aggregator coerces to unknown", async () => {
    const broken: StatusFeed = {
      component: "database",
      async fetch() {
        throw new Error("nope");
      },
    };
    const agg = createCachedAggregator({ feeds: [broken], ttlMs: 30_000 });
    const payload = await agg.get();
    const db = payload.components.find((c) => c.component === "database")!;
    expect(db.level).toBe("unknown");
    expect(payload.overall).toBe("unknown");
  });
});
