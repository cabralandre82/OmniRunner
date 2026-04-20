import { describe, it, expect, vi, beforeEach } from "vitest";
import {
  PRODUCT_EVENT_MAX_STRING_LEN,
  PRODUCT_EVENT_NAMES,
  PRODUCT_EVENT_PROPERTY_KEYS,
  trackBillingEvent,
  validateProductEvent,
} from "./analytics";

const mockInsert = vi.fn().mockResolvedValue({ error: null });
const mockGetUser = vi.fn();

vi.mock("@/lib/supabase/server", () => ({
  createClient: () => ({
    auth: { getUser: mockGetUser },
    from: () => ({ insert: mockInsert }),
  }),
}));

const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});

describe("trackBillingEvent (L08-01 + L08-02)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    warnSpy.mockClear();
  });

  it("inserts a whitelisted event with valid properties", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });

    await trackBillingEvent("billing_credits_viewed", {
      group_id: "g-123",
      balance: 50,
      products_count: 4,
    });

    expect(mockInsert).toHaveBeenCalledWith({
      user_id: "u1",
      event_name: "billing_credits_viewed",
      properties: {
        group_id: "g-123",
        balance: 50,
        products_count: 4,
      },
    });
    expect(warnSpy).not.toHaveBeenCalled();
  });

  it("skips insert when no user", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });

    await trackBillingEvent("billing_settings_viewed", { group_id: "g1" });

    expect(mockInsert).not.toHaveBeenCalled();
  });

  it("never throws even on transport error", async () => {
    mockGetUser.mockRejectedValue(new Error("network fail"));

    await expect(
      trackBillingEvent("billing_settings_viewed", { group_id: "g1" }),
    ).resolves.toBeUndefined();
  });

  it("passes empty properties by default", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u2" } } });

    await trackBillingEvent("billing_checkout_returned");

    expect(mockInsert).toHaveBeenCalledWith(
      expect.objectContaining({ properties: {} }),
    );
  });

  // ── L08-02 — schema validation rejects bad payloads BEFORE insert ──

  it("drops event with unknown event_name (PE001 mirror) without inserting", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });

    await trackBillingEvent("plan.upgrade" as unknown as string, {});

    expect(mockInsert).not.toHaveBeenCalled();
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining('unknown event_name "plan.upgrade"'),
    );
  });

  it("drops event with unknown property key (PE002 mirror) without inserting", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });

    await trackBillingEvent("billing_settings_viewed", {
      email: "leak@example.com",
    });

    expect(mockInsert).not.toHaveBeenCalled();
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining('unknown property key "email"'),
    );
  });

  it("drops event with nested-object value (PE003 mirror) without inserting", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });

    await trackBillingEvent("billing_settings_viewed", {
      group_id: { nested: "oops" },
    });

    expect(mockInsert).not.toHaveBeenCalled();
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining('property "group_id" has unsupported value type'),
    );
  });

  it("drops event with array value (PE003 mirror) without inserting", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });

    await trackBillingEvent("billing_settings_viewed", {
      group_id: [1, 2, 3],
    });

    expect(mockInsert).not.toHaveBeenCalled();
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining('property "group_id"'),
    );
  });

  it("drops event with oversize string value (PE004 mirror) without inserting", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });

    await trackBillingEvent("billing_settings_viewed", {
      method: "x".repeat(PRODUCT_EVENT_MAX_STRING_LEN + 1),
    });

    expect(mockInsert).not.toHaveBeenCalled();
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining(
        `string value exceeds ${PRODUCT_EVENT_MAX_STRING_LEN}`,
      ),
    );
  });

  it("accepts string at exactly the max length (boundary)", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });

    await trackBillingEvent("billing_settings_viewed", {
      method: "x".repeat(PRODUCT_EVENT_MAX_STRING_LEN),
    });

    expect(mockInsert).toHaveBeenCalledTimes(1);
    expect(warnSpy).not.toHaveBeenCalled();
  });
});

describe("validateProductEvent — schema mirror of fn_validate_product_event", () => {
  it("accepts every (event_name, key) pair currently emitted by the portal", () => {
    const realCallSites: Array<[string, Record<string, unknown>]> = [
      ["billing_settings_viewed", { group_id: "g" }],
      ["billing_credits_viewed", { group_id: "g", balance: 1, products_count: 0 }],
      ["billing_purchases_viewed", { group_id: "g", total_count: 0 }],
      ["billing_checkout_returned", { outcome: "success" }],
      ["billing_checkout_returned", { outcome: "cancelled" }],
    ];
    for (const [name, props] of realCallSites) {
      expect(validateProductEvent(name, props)).toBeNull();
    }
  });

  it("accepts the mobile-side events (cross-platform whitelist)", () => {
    const mobileSites: Array<[string, Record<string, unknown>]> = [
      ["onboarding_completed", { role: "ATLETA", method: "accept_invite" }],
      ["onboarding_completed", { role: "ASSESSORIA_STAFF", method: "skip" }],
      ["first_challenge_created", { type: "DISTANCE", goal: "5K" }],
      ["first_championship_launched", { metric: "distance", template_id: "t1" }],
      ["flow_abandoned", { flow: "onboarding", step: "join", reason: "skipped" }],
    ];
    for (const [name, props] of mobileSites) {
      expect(validateProductEvent(name, props)).toBeNull();
    }
  });

  it("treats null and undefined values as primitive (allowed)", () => {
    expect(
      validateProductEvent("billing_settings_viewed", {
        group_id: null,
      }),
    ).toBeNull();
    expect(
      validateProductEvent("billing_settings_viewed", {
        group_id: undefined,
      }),
    ).toBeNull();
  });

  it("exposes a stable, alphabetised whitelist", () => {
    expect([...PRODUCT_EVENT_NAMES]).toEqual(
      [...PRODUCT_EVENT_NAMES].slice().sort(),
    );
    expect([...PRODUCT_EVENT_PROPERTY_KEYS]).toEqual(
      [...PRODUCT_EVENT_PROPERTY_KEYS].slice().sort(),
    );
  });
});
