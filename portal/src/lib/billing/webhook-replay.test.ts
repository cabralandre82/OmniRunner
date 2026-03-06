import { describe, it, expect } from "vitest";
import {
  buildEventId,
  mapEventToSubscriptionUpdate,
  isSubscriptionLifecycleEvent,
} from "./webhook-logic";

type AsaasPayload = {
  event: string;
  payment?: {
    id?: string;
    customer?: string;
    subscription?: string;
    value?: number;
    netValue?: number;
    billingType?: string;
    status?: string;
    dueDate?: string;
    paymentDate?: string;
    externalReference?: string;
  };
};

function eventIdFromPayload(payload: AsaasPayload): string {
  const payment = payload.payment;
  const paymentId = payment?.id;
  const subId = payment?.subscription;
  const payloadSlice = JSON.stringify(payload);
  return buildEventId(payload.event, paymentId, subId, payloadSlice);
}

describe("Webhook replay with real Asaas payload structures", () => {
  const fullPaymentPayload: AsaasPayload = {
    event: "PAYMENT_CONFIRMED",
    payment: {
      id: "pay_abc123",
      customer: "cus_xyz789",
      subscription: "sub_def456",
      value: 150.0,
      netValue: 146.25,
      billingType: "PIX",
      status: "CONFIRMED",
      dueDate: "2026-04-01",
      paymentDate: "2026-03-28",
      externalReference: "our-subscription-uuid",
    },
  };

  it("1. PAYMENT_CONFIRMED with full payment object → maps to active + last_payment_at + next_due_date", () => {
    const result = mapEventToSubscriptionUpdate(
      fullPaymentPayload.event,
      fullPaymentPayload.payment as Record<string, unknown>
    );
    expect(result).not.toBeNull();
    expect(result!.status).toBe("active");
    expect(result!.extra.last_payment_at).toBeDefined();
    expect(result!.extra.next_due_date).toBe("2026-04-01");
  });

  it("2. PAYMENT_RECEIVED with PIX → maps to active", () => {
    const payload: AsaasPayload = {
      event: "PAYMENT_RECEIVED",
      payment: {
        id: "pay_pix1",
        billingType: "PIX",
        status: "RECEIVED",
      },
    };
    const result = mapEventToSubscriptionUpdate(
      payload.event,
      payload.payment as Record<string, unknown>
    );
    expect(result).not.toBeNull();
    expect(result!.status).toBe("active");
  });

  it("3. PAYMENT_OVERDUE → maps to late", () => {
    const payload: AsaasPayload = {
      event: "PAYMENT_OVERDUE",
      payment: { id: "pay_overdue", status: "OVERDUE" },
    };
    const result = mapEventToSubscriptionUpdate(
      payload.event,
      payload.payment as Record<string, unknown>
    );
    expect(result).not.toBeNull();
    expect(result!.status).toBe("late");
  });

  it("4. PAYMENT_REFUNDED → maps to cancelled + cancelled_at", () => {
    const payload: AsaasPayload = {
      event: "PAYMENT_REFUNDED",
      payment: { id: "pay_refund", status: "REFUNDED" },
    };
    const result = mapEventToSubscriptionUpdate(
      payload.event,
      payload.payment as Record<string, unknown>
    );
    expect(result).not.toBeNull();
    expect(result!.status).toBe("cancelled");
    expect(result!.extra.cancelled_at).toBeDefined();
  });

  it("5. PAYMENT_DELETED → maps to paused", () => {
    const payload: AsaasPayload = {
      event: "PAYMENT_DELETED",
      payment: { id: "pay_del", status: "DELETED" },
    };
    const result = mapEventToSubscriptionUpdate(
      payload.event,
      payload.payment as Record<string, unknown>
    );
    expect(result).not.toBeNull();
    expect(result!.status).toBe("paused");
  });

  it("6. SUBSCRIPTION_INACTIVATED → isSubscriptionLifecycleEvent = true", () => {
    const payload: AsaasPayload = { event: "SUBSCRIPTION_INACTIVATED" };
    expect(isSubscriptionLifecycleEvent(payload.event)).toBe(true);
  });

  it("7. SUBSCRIPTION_DELETED → isSubscriptionLifecycleEvent = true", () => {
    const payload: AsaasPayload = { event: "SUBSCRIPTION_DELETED" };
    expect(isSubscriptionLifecycleEvent(payload.event)).toBe(true);
  });

  it("8. Unknown event PAYMENT_UPDATED → returns null from mapEvent, false from isLifecycle", () => {
    const payload: AsaasPayload = {
      event: "PAYMENT_UPDATED",
      payment: { id: "pay_upd" },
    };
    const mapped = mapEventToSubscriptionUpdate(
      payload.event,
      payload.payment as Record<string, unknown>
    );
    expect(mapped).toBeNull();
    expect(isSubscriptionLifecycleEvent(payload.event)).toBe(false);
  });

  it("9. Event ID determinism: same payment generates same event ID across calls", () => {
    const id1 = eventIdFromPayload(fullPaymentPayload);
    const id2 = eventIdFromPayload(fullPaymentPayload);
    expect(id1).toBe(id2);
    expect(id1).toBe("PAYMENT_CONFIRMED_pay_abc123");
  });

  it("10. Event ID determinism: event without payment ID uses subscription ID", () => {
    const payload: AsaasPayload = {
      event: "SUBSCRIPTION_INACTIVATED",
      payment: { subscription: "sub_xyz", customer: "cus_1" },
    };
    const id = eventIdFromPayload(payload);
    expect(id).toBe("SUBSCRIPTION_INACTIVATED_sub_xyz");
  });

  it("11. Event ID determinism: event without any IDs uses payload slice", () => {
    const payload: AsaasPayload = { event: "PAYMENT_OVERDUE" };
    const id = eventIdFromPayload(payload);
    expect(id).toMatch(/^PAYMENT_OVERDUE_/);
    expect(id).toContain('"event":"PAYMENT_OVERDUE"');
  });

  it("12. Payload with missing payment object → still generates valid event ID", () => {
    const payload: AsaasPayload = { event: "SUBSCRIPTION_DELETED" };
    const id = eventIdFromPayload(payload);
    expect(id).toBeTruthy();
    expect(id).toMatch(/^SUBSCRIPTION_DELETED_/);
  });
});
