import { describe, it, expect, vi, beforeEach } from "vitest";
import { queryChain } from "@/test/api-helpers";

const mockClient = {
  from: vi.fn(() =>
    queryChain({
      data: [
        { key: "new_dashboard", enabled: true, rollout_pct: 100 },
        { key: "beta_export", enabled: true, rollout_pct: 50 },
        { key: "disabled_feat", enabled: false, rollout_pct: 100 },
      ],
    }),
  ),
};

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => mockClient,
}));

const { isFeatureEnabled, getAllFlags } = await import("./feature-flags");

describe("Feature Flags", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns true for fully rolled out enabled flag", async () => {
    const result = await isFeatureEnabled("new_dashboard", "user-1");
    expect(result).toBe(true);
  });

  it("returns false for disabled flag", async () => {
    const result = await isFeatureEnabled("disabled_feat", "user-1");
    expect(result).toBe(false);
  });

  it("returns false for unknown flag", async () => {
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
    expect(flags).toHaveLength(3);
    expect(flags.map((f) => f.key)).toContain("new_dashboard");
  });
});
