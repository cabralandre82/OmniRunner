import { describe, it, expect } from "vitest";
import {
  STATUS_MAP,
  buildEventId,
  mapEventToSubscriptionUpdate,
  isSubscriptionLifecycleEvent,
} from "./webhook-logic";

describe("STATUS_MAP", () => {
  it("maps PAYMENT_CONFIRMED to active", () => {
    expect(STATUS_MAP.PAYMENT_CONFIRMED).toBe("active");
  });

  it("maps PAYMENT_RECEIVED to active", () => {
    expect(STATUS_MAP.PAYMENT_RECEIVED).toBe("active");
  });

  it("maps PAYMENT_OVERDUE to late", () => {
    expect(STATUS_MAP.PAYMENT_OVERDUE).toBe("late");
  });

  it("maps PAYMENT_REFUNDED to cancelled", () => {
    expect(STATUS_MAP.PAYMENT_REFUNDED).toBe("cancelled");
  });

  it("maps PAYMENT_DELETED to paused", () => {
    expect(STATUS_MAP.PAYMENT_DELETED).toBe("paused");
  });

  it("does not map unknown events", () => {
    expect(STATUS_MAP.SOME_RANDOM_EVENT).toBeUndefined();
  });
});

describe("buildEventId", () => {
  it("uses asaasPaymentId when available", () => {
    const id = buildEventId("PAYMENT_CONFIRMED", "pay_123", "sub_456", "fallback");
    expect(id).toBe("PAYMENT_CONFIRMED_pay_123");
  });

  it("falls back to asaasSubId when no paymentId", () => {
    const id = buildEventId("SUBSCRIPTION_INACTIVATED", undefined, "sub_456", "fallback");
    expect(id).toBe("SUBSCRIPTION_INACTIVATED_sub_456");
  });

  it("falls back to payload slice when no IDs", () => {
    const id = buildEventId("PAYMENT_OVERDUE", undefined, undefined, "payload_hash");
    expect(id).toBe("PAYMENT_OVERDUE_payload_hash");
  });

  it("is deterministic — same inputs produce same output", () => {
    const a = buildEventId("PAYMENT_CONFIRMED", "pay_1", undefined, "");
    const b = buildEventId("PAYMENT_CONFIRMED", "pay_1", undefined, "");
    expect(a).toBe(b);
  });

  it("different events with same payment produce different IDs", () => {
    const a = buildEventId("PAYMENT_CONFIRMED", "pay_1", undefined, "");
    const b = buildEventId("PAYMENT_OVERDUE", "pay_1", undefined, "");
    expect(a).not.toBe(b);
  });
});

describe("mapEventToSubscriptionUpdate", () => {
  it("returns null for unknown events", () => {
    expect(mapEventToSubscriptionUpdate("UNKNOWN", undefined)).toBeNull();
  });

  it("sets status to active and last_payment_at for PAYMENT_CONFIRMED", () => {
    const result = mapEventToSubscriptionUpdate("PAYMENT_CONFIRMED", { dueDate: "2026-04-01" });
    expect(result).not.toBeNull();
    expect(result!.status).toBe("active");
    expect(result!.extra.last_payment_at).toBeDefined();
    expect(result!.extra.next_due_date).toBe("2026-04-01");
  });

  it("sets status to active without next_due_date when not in payment", () => {
    const result = mapEventToSubscriptionUpdate("PAYMENT_RECEIVED", {});
    expect(result!.status).toBe("active");
    expect(result!.extra.next_due_date).toBeUndefined();
  });

  it("sets cancelled_at for PAYMENT_REFUNDED", () => {
    const result = mapEventToSubscriptionUpdate("PAYMENT_REFUNDED", undefined);
    expect(result!.status).toBe("cancelled");
    expect(result!.extra.cancelled_at).toBeDefined();
  });

  it("sets status to late for PAYMENT_OVERDUE", () => {
    const result = mapEventToSubscriptionUpdate("PAYMENT_OVERDUE", undefined);
    expect(result!.status).toBe("late");
    expect(result!.extra.cancelled_at).toBeUndefined();
    expect(result!.extra.last_payment_at).toBeUndefined();
  });

  it("sets status to paused for PAYMENT_DELETED", () => {
    const result = mapEventToSubscriptionUpdate("PAYMENT_DELETED", undefined);
    expect(result!.status).toBe("paused");
  });

  it("always includes updated_at", () => {
    const result = mapEventToSubscriptionUpdate("PAYMENT_OVERDUE", undefined);
    expect(result!.extra.updated_at).toBeDefined();
  });
});

describe("isSubscriptionLifecycleEvent", () => {
  it("returns true for SUBSCRIPTION_INACTIVATED", () => {
    expect(isSubscriptionLifecycleEvent("SUBSCRIPTION_INACTIVATED")).toBe(true);
  });

  it("returns true for SUBSCRIPTION_DELETED", () => {
    expect(isSubscriptionLifecycleEvent("SUBSCRIPTION_DELETED")).toBe(true);
  });

  it("returns false for payment events", () => {
    expect(isSubscriptionLifecycleEvent("PAYMENT_CONFIRMED")).toBe(false);
    expect(isSubscriptionLifecycleEvent("PAYMENT_OVERDUE")).toBe(false);
  });

  it("returns false for unknown events", () => {
    expect(isSubscriptionLifecycleEvent("RANDOM")).toBe(false);
  });
});
