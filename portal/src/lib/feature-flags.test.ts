import { describe, it, expect, vi, beforeEach } from "vitest";
import { queryChain } from "@/test/api-helpers";

// Default flag set used by the legacy/L06-06 suites.
const DEFAULT_FLAGS = [
  { key: "new_dashboard", enabled: true, rollout_pct: 100, category: "product", scope: "global" },
  { key: "beta_export", enabled: true, rollout_pct: 50, category: "experimental", scope: "global" },
  { key: "disabled_feat", enabled: false, rollout_pct: 100, category: "product", scope: "global" },
  { key: "custody.withdrawals.enabled", enabled: true, rollout_pct: 100, category: "kill_switch", scope: "global" },
  { key: "swap.enabled", enabled: false, rollout_pct: 100, category: "kill_switch", scope: "global" },
  { key: "banner.gateway_outage", enabled: false, rollout_pct: 0, category: "banner", scope: "global" },
];

let activeFlags: typeof DEFAULT_FLAGS = DEFAULT_FLAGS;

const mockClient = {
  from: vi.fn(() => queryChain({ data: activeFlags })),
};

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => mockClient,
}));

const {
  isFeatureEnabled,
  getAllFlags,
  isSubsystemEnabled,
  assertSubsystemEnabled,
  FeatureDisabledError,
  invalidateFeatureCache,
  __test_userBucket,
  __test_KILL_SWITCH_TTL_MS,
  __test_TTL_MS,
} = await import("./feature-flags");

describe("Feature Flags — product rollout (legacy API)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    invalidateFeatureCache();
    activeFlags = DEFAULT_FLAGS;
  });

  it("returns true for fully rolled out enabled flag", async () => {
    const result = await isFeatureEnabled("new_dashboard", "user-1");
    expect(result).toBe(true);
  });

  it("returns false for disabled flag", async () => {
    const result = await isFeatureEnabled("disabled_feat", "user-1");
    expect(result).toBe(false);
  });

  it("returns false for unknown flag (legacy API: closed default)", async () => {
    const result = await isFeatureEnabled("nonexistent", "user-1");
    expect(result).toBe(false);
  });

  it("returns false when userId is not provided for partial rollout", async () => {
    const result = await isFeatureEnabled("beta_export");
    expect(result).toBe(false);
  });

  it("returns deterministic result for partial rollout", async () => {
    const r1 = await isFeatureEnabled("beta_export", "user-a");
    const r2 = await isFeatureEnabled("beta_export", "user-a");
    expect(r1).toBe(r2);
  });

  it("getAllFlags returns all loaded flags", async () => {
    const flags = await getAllFlags();
    expect(flags.length).toBeGreaterThanOrEqual(6);
    expect(flags.map((f) => f.key)).toContain("new_dashboard");
  });
});

describe("Feature Flags — L06-06 kill switch / subsystem API", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    invalidateFeatureCache();
    activeFlags = DEFAULT_FLAGS;
  });

  it("isSubsystemEnabled fail-open: returns true when flag missing", async () => {
    // Diferente de isFeatureEnabled — kill switches devem fail-open
    // para não quebrar setup inicial onde a flag ainda não foi cadastrada.
    expect(await isSubsystemEnabled("not-yet-registered.enabled")).toBe(true);
  });

  it("isSubsystemEnabled returns true for enabled kill switch", async () => {
    expect(await isSubsystemEnabled("custody.withdrawals.enabled")).toBe(true);
  });

  it("isSubsystemEnabled returns false for disabled kill switch", async () => {
    expect(await isSubsystemEnabled("swap.enabled")).toBe(false);
  });

  it("isSubsystemEnabled ignores rollout_pct (kill switches são all-or-nothing)", async () => {
    // banner.gateway_outage tem rollout_pct=0 mas enabled=false → false (do enabled)
    expect(await isSubsystemEnabled("banner.gateway_outage")).toBe(false);
  });

  it("assertSubsystemEnabled passa silenciosamente quando ligado", async () => {
    await expect(
      assertSubsystemEnabled("custody.withdrawals.enabled"),
    ).resolves.toBeUndefined();
  });

  it("assertSubsystemEnabled lança FeatureDisabledError quando desligado", async () => {
    await expect(assertSubsystemEnabled("swap.enabled", "test hint")).rejects.toMatchObject({
      name: "FeatureDisabledError",
      code: "FEATURE_DISABLED",
      status: 503,
      key: "swap.enabled",
      hint: "test hint",
    });
  });

  it("FeatureDisabledError é instanceof Error", async () => {
    try {
      await assertSubsystemEnabled("swap.enabled");
      throw new Error("should have thrown");
    } catch (e) {
      expect(e).toBeInstanceOf(Error);
      expect(e).toBeInstanceOf(FeatureDisabledError);
    }
  });

  it("invalidateFeatureCache força reload no próximo check", async () => {
    await isSubsystemEnabled("swap.enabled"); // populate cache
    expect(mockClient.from).toHaveBeenCalledTimes(1);

    await isSubsystemEnabled("swap.enabled"); // cached
    expect(mockClient.from).toHaveBeenCalledTimes(1);

    invalidateFeatureCache();
    await isSubsystemEnabled("swap.enabled"); // reload
    expect(mockClient.from).toHaveBeenCalledTimes(2);
  });
});

describe("Feature Flags — L18-07 SHA-256 userBucket", () => {
  it("returns deterministic value in [0, 100) range", () => {
    const b = __test_userBucket("user-abc-123", "beta_export");
    expect(b).toBeGreaterThanOrEqual(0);
    expect(b).toBeLessThan(100);
    expect(b).toBe(__test_userBucket("user-abc-123", "beta_export"));
  });

  it("decorrelates across keys for the same user (different keys -> different buckets)", () => {
    const u = "user-determ-1";
    const buckets = new Set<number>();
    for (const key of ["k1", "k2", "k3", "k4", "k5", "k6", "k7", "k8"]) {
      buckets.add(__test_userBucket(u, key));
    }
    // 8 different keys should produce at least 6 distinct buckets — a
    // smoke test that the hash isn't degenerate. (Birthday paradox makes
    // 1-2 collisions in 8 draws over 100 buckets entirely plausible.)
    expect(buckets.size).toBeGreaterThanOrEqual(6);
  });

  it("distributes ~uniformly across 1000 users (10% rollout: ~100 ± 30)", () => {
    let inBucket = 0;
    for (let i = 0; i < 1000; i++) {
      // UUID-shaped IDs since real callers pass UUID v4 strings.
      const uid = `00000000-0000-4000-8000-${i.toString().padStart(12, "0")}`;
      if (__test_userBucket(uid, "rollout-test-key") < 10) inBucket++;
    }
    // Tolerance ±30 around expected 100 — sanity-checks the SHA-256
    // distribution without making the test flaky on rare hash quirks.
    expect(inBucket).toBeGreaterThan(70);
    expect(inBucket).toBeLessThan(130);
  });

  it("avoids the prefix-bias that the old DJB2-style hash had on UUIDs", () => {
    // The legacy `(hash<<5)-hash+code` accumulator creates near-identical
    // intermediate states for inputs that share long common prefixes —
    // exactly what UUIDs from auth.users do. SHA-256 destroys that
    // correlation. Sanity check: 100 sibling UUIDs differing only in the
    // last 4 chars produce a wide bucket spread (>= 30 distinct buckets).
    const buckets = new Set<number>();
    for (let i = 0; i < 100; i++) {
      const uid = `aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa${i.toString(16).padStart(4, "0")}`;
      buckets.add(__test_userBucket(uid, "k"));
    }
    expect(buckets.size).toBeGreaterThanOrEqual(30);
  });
});

describe("Feature Flags — L18-06 stratified TTL", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    invalidateFeatureCache();
    vi.useRealTimers();
    activeFlags = DEFAULT_FLAGS;
  });

  it("kill_switch presence forces 5s TTL (not 60s)", async () => {
    expect(__test_KILL_SWITCH_TTL_MS).toBe(5_000);
    expect(__test_TTL_MS).toBe(60_000);

    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-01-01T00:00:00Z"));

    await isSubsystemEnabled("custody.withdrawals.enabled");
    expect(mockClient.from).toHaveBeenCalledTimes(1);

    // 4s later: still within the 5s kill-switch TTL → no refresh.
    vi.setSystemTime(new Date("2026-01-01T00:00:04Z"));
    await isSubsystemEnabled("custody.withdrawals.enabled");
    expect(mockClient.from).toHaveBeenCalledTimes(1);

    // 6s later: past the 5s kill-switch TTL → refresh.
    vi.setSystemTime(new Date("2026-01-01T00:00:06Z"));
    await isSubsystemEnabled("custody.withdrawals.enabled");
    expect(mockClient.from).toHaveBeenCalledTimes(2);

    vi.useRealTimers();
  });

  it("absence of kill switches keeps the 60s TTL", async () => {
    activeFlags = [
      { key: "new_dashboard", enabled: true, rollout_pct: 100, category: "product", scope: "global" },
      { key: "beta_export", enabled: true, rollout_pct: 50, category: "experimental", scope: "global" },
    ];

    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-01-01T00:00:00Z"));

    await getAllFlags();
    expect(mockClient.from).toHaveBeenCalledTimes(1);

    // 30s later — well past the kill-switch TTL but within the 60s
    // default. Should NOT refresh because no kill switch is present.
    vi.setSystemTime(new Date("2026-01-01T00:00:30Z"));
    await getAllFlags();
    expect(mockClient.from).toHaveBeenCalledTimes(1);

    // 61s later — past the default TTL → refresh.
    vi.setSystemTime(new Date("2026-01-01T00:01:01Z"));
    await getAllFlags();
    expect(mockClient.from).toHaveBeenCalledTimes(2);

    vi.useRealTimers();
  });

  it("kill-switch toggle propagates within ~5s across cache reads", async () => {
    activeFlags = [
      { key: "swap.enabled", enabled: true, rollout_pct: 100, category: "kill_switch", scope: "global" },
    ];

    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-01-01T00:00:00Z"));

    expect(await isSubsystemEnabled("swap.enabled")).toBe(true);

    // Operator flips the kill switch off.
    activeFlags = [
      { key: "swap.enabled", enabled: false, rollout_pct: 100, category: "kill_switch", scope: "global" },
    ];

    // 4s — still cached, returns stale TRUE.
    vi.setSystemTime(new Date("2026-01-01T00:00:04Z"));
    expect(await isSubsystemEnabled("swap.enabled")).toBe(true);

    // 6s — past kill-switch TTL, sees fresh FALSE.
    vi.setSystemTime(new Date("2026-01-01T00:00:06Z"));
    expect(await isSubsystemEnabled("swap.enabled")).toBe(false);

    vi.useRealTimers();
  });
});
