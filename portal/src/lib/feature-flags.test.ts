import { describe, it, expect, vi, beforeEach } from "vitest";
import { queryChain } from "@/test/api-helpers";

const mockClient = {
  from: vi.fn(() =>
    queryChain({
      data: [
        { key: "new_dashboard", enabled: true, rollout_pct: 100, category: "product", scope: "global" },
        { key: "beta_export", enabled: true, rollout_pct: 50, category: "experimental", scope: "global" },
        { key: "disabled_feat", enabled: false, rollout_pct: 100, category: "product", scope: "global" },
        { key: "custody.withdrawals.enabled", enabled: true, rollout_pct: 100, category: "kill_switch", scope: "global" },
        { key: "swap.enabled", enabled: false, rollout_pct: 100, category: "kill_switch", scope: "global" },
        { key: "banner.gateway_outage", enabled: false, rollout_pct: 0, category: "banner", scope: "global" },
      ],
    }),
  ),
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
} = await import("./feature-flags");

describe("Feature Flags — product rollout (legacy API)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    invalidateFeatureCache();
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
