/**
 * Pure functions extracted from asaas-webhook Edge Function
 * for unit testing. The Edge Function imports these via copy,
 * but these serve as the canonical test target.
 */

export const STATUS_MAP: Record<string, string> = {
  PAYMENT_CONFIRMED: "active",
  PAYMENT_RECEIVED: "active",
  PAYMENT_OVERDUE: "late",
  PAYMENT_REFUNDED: "cancelled",
  PAYMENT_DELETED: "paused",
};

export function buildEventId(
  event: string,
  asaasPaymentId: string | undefined,
  asaasSubId: string | undefined,
  payloadSlice: string,
): string {
  const key = asaasPaymentId ?? asaasSubId ?? payloadSlice;
  return `${event}_${key}`;
}

export function mapEventToSubscriptionUpdate(
  event: string,
  payment: Record<string, unknown> | undefined,
): { status: string; extra: Record<string, unknown> } | null {
  const newStatus = STATUS_MAP[event];
  if (!newStatus) return null;

  const extra: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
  };

  if (newStatus === "active") {
    extra.last_payment_at = new Date().toISOString();
    if (payment?.dueDate) {
      extra.next_due_date = payment.dueDate;
    }
  }

  if (newStatus === "cancelled") {
    extra.cancelled_at = new Date().toISOString();
  }

  return { status: newStatus, extra };
}

export function isSubscriptionLifecycleEvent(event: string): boolean {
  return event === "SUBSCRIPTION_INACTIVATED" || event === "SUBSCRIPTION_DELETED";
}
