import { describe, it, expect, vi, beforeEach } from "vitest";
import crypto from "node:crypto";

const STRIPE_SECRET = "whsec_test_stripe_custody_secret";
const MP_SECRET = "mp_test_custody_secret";

process.env.STRIPE_CUSTODY_WEBHOOK_SECRET = STRIPE_SECRET;
process.env.MP_CUSTODY_WEBHOOK_SECRET = MP_SECRET;

const confirmDepositByReferenceMock = vi.hoisted(() =>
  vi.fn(async () => ({ depositId: "dep-1", alreadyConfirmed: false })),
);
// L03-20 — mock fn_handle_custody_dispute_atomic wrapper. Default
// behaviour: a successful auto-reversal (outcome=reversed).
const handleCustodyDisputeMock = vi.hoisted(() =>
  vi.fn(async () => ({
    outcome: "reversed" as const,
    caseId: "case-1",
    caseState: "RESOLVED_REVERSED",
    depositId: "dep-1",
    groupId: "group-1",
    amountUsd: 100,
    reversalId: "rev-1",
    refundedUsd: 100,
    wasIdempotent: false,
  })),
);
const auditLogMock = vi.hoisted(() => vi.fn(async () => undefined));
const metricsIncrementMock = vi.hoisted(() => vi.fn());
const loggerMocks = vi.hoisted(() => ({
  info: vi.fn(),
  warn: vi.fn(),
  error: vi.fn(),
}));

const rpcMock = vi.hoisted(() => vi.fn());
const serviceClient = vi.hoisted(() => ({ rpc: vi.fn() }));

vi.mock("@/lib/custody", () => ({
  confirmDepositByReference: confirmDepositByReferenceMock,
  handleCustodyDispute: handleCustodyDisputeMock,
}));
vi.mock("@/lib/audit", () => ({ auditLog: auditLogMock }));
vi.mock("@/lib/metrics", () => ({
  metrics: { increment: metricsIncrementMock },
}));
vi.mock("@/lib/logger", () => ({ logger: loggerMocks }));
vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => serviceClient,
}));

const { POST } = await import("./route");

// ────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────

function stripeSignature(payload: string, secret: string, ts?: number): string {
  const t = ts ?? Math.floor(Date.now() / 1000);
  const sig = crypto.createHmac("sha256", secret).update(`${t}.${payload}`).digest("hex");
  return `t=${t},v1=${sig}`;
}

function mpV2Signature(args: {
  payload: string;
  dataId: string;
  xRequestId: string;
  secret: string;
  ts?: number;
}): { signature: string; ts: number } {
  const ts = args.ts ?? Math.floor(Date.now() / 1000);
  const manifest = `id:${args.dataId};request-id:${args.xRequestId};ts:${ts};`;
  const sig = crypto.createHmac("sha256", args.secret).update(manifest).digest("hex");
  return { signature: `ts=${ts},v1=${sig}`, ts };
}

function makeReq(args: {
  body: unknown;
  headers?: Record<string, string>;
}) {
  const rawBody = typeof args.body === "string" ? args.body : JSON.stringify(args.body);
  return new Request("http://localhost/api/custody/webhook", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...(args.headers ?? {}) },
    body: rawBody,
  }) as unknown as import("next/server").NextRequest;
}

const STRIPE_EVENT = {
  id: "evt_test_1",
  type: "payment_intent.succeeded",
  data: { object: { id: "pi_charge_ref_123" } },
};

const MP_EVENT = {
  action: "payment.updated",
  type: "payment",
  data: { id: "1234567890" },
};

// ────────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────────

describe("POST /api/custody/webhook (L01-01 hardened)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    confirmDepositByReferenceMock.mockResolvedValue({
      depositId: "dep-1",
      alreadyConfirmed: false,
    });
    rpcMock.mockResolvedValue({ data: [{ was_replay: false }], error: null });
    serviceClient.rpc.mockImplementation((fn: string, ...args: unknown[]) =>
      rpcMock(fn, ...args),
    );
  });

  // ── Gateway detection ────────────────────────────────────────────────

  it("rejects requests with no recognised signature header", async () => {
    const res = await POST(makeReq({ body: STRIPE_EVENT }));
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error.code).toBe("BAD_REQUEST");
    expect(body.error.message).toMatch(/no recognised gateway/i);
    expect(metricsIncrementMock).toHaveBeenCalledWith(
      "custody.webhook.rejected",
      { reason: "ambiguous_gateway" },
    );
  });

  it("rejects requests with BOTH signature headers (anti header-smuggling)", async () => {
    const res = await POST(
      makeReq({
        body: STRIPE_EVENT,
        headers: {
          "stripe-signature": "t=1,v1=abc",
          "x-signature": "ts=1,v1=def",
        },
      }),
    );
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error.message).toMatch(/both stripe-signature and x-signature/i);
    expect(metricsIncrementMock).toHaveBeenCalledWith(
      "custody.webhook.rejected",
      { reason: "ambiguous_gateway" },
    );
  });

  it("ignores x-gateway header (cannot influence verification path)", async () => {
    // Send a Stripe-signed payload but lie that gateway is mercadopago.
    // The route MUST detect Stripe from the header and validate as Stripe.
    const payload = JSON.stringify(STRIPE_EVENT);
    const res = await POST(
      makeReq({
        body: payload,
        headers: {
          "stripe-signature": stripeSignature(payload, STRIPE_SECRET),
          "x-gateway": "mercadopago",
        },
      }),
    );
    expect(res.status).toBe(200);
    expect(rpcMock).toHaveBeenCalledWith(
      "fn_record_custody_webhook_event",
      expect.objectContaining({ p_gateway: "stripe" }),
    );
  });

  // ── Stripe signature path ────────────────────────────────────────────

  it("accepts a valid Stripe webhook end-to-end", async () => {
    const payload = JSON.stringify(STRIPE_EVENT);
    const res = await POST(
      makeReq({
        body: payload,
        headers: { "stripe-signature": stripeSignature(payload, STRIPE_SECRET) },
      }),
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.deposit_id).toBe("dep-1");
    expect(body.event_id).toBe("evt_test_1");
    expect(confirmDepositByReferenceMock).toHaveBeenCalledWith("pi_charge_ref_123");
    expect(metricsIncrementMock).toHaveBeenCalledWith(
      "custody.webhook.confirmed",
      { gateway: "stripe" },
    );
    expect(auditLogMock).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "custody.deposit.webhook_confirmed",
        targetId: "dep-1",
        metadata: expect.objectContaining({
          gateway: "stripe",
          event_id: "evt_test_1",
        }),
      }),
    );
  });

  it("rejects a Stripe webhook with bad signature → 401", async () => {
    const payload = JSON.stringify(STRIPE_EVENT);
    const res = await POST(
      makeReq({
        body: payload,
        headers: {
          "stripe-signature": "t=1700000000,v1=" + "0".repeat(64),
        },
      }),
    );
    expect(res.status).toBe(401);
    expect(metricsIncrementMock).toHaveBeenCalledWith(
      "custody.webhook.rejected",
      { reason: "signature" },
    );
    expect(confirmDepositByReferenceMock).not.toHaveBeenCalled();
  });

  it("rejects a Stripe webhook with stale timestamp → 401", async () => {
    const payload = JSON.stringify(STRIPE_EVENT);
    const staleSig = stripeSignature(
      payload,
      STRIPE_SECRET,
      Math.floor(Date.now() / 1000) - 600,
    );
    const res = await POST(
      makeReq({ body: payload, headers: { "stripe-signature": staleSig } }),
    );
    expect(res.status).toBe(401);
    const body = await res.json();
    expect(body.error.message).toMatch(/too old/i);
  });

  // ── MercadoPago signature path ───────────────────────────────────────

  it("accepts a valid MercadoPago v2 webhook end-to-end", async () => {
    const payload = JSON.stringify(MP_EVENT);
    const { signature } = mpV2Signature({
      payload,
      dataId: MP_EVENT.data.id,
      xRequestId: "mp-req-id-1",
      secret: MP_SECRET,
    });
    const res = await POST(
      makeReq({
        body: payload,
        headers: { "x-signature": signature, "x-request-id": "mp-req-id-1" },
      }),
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.deposit_id).toBe("dep-1");
    expect(body.event_id).toBe("1234567890");
    expect(rpcMock).toHaveBeenCalledWith(
      "fn_record_custody_webhook_event",
      expect.objectContaining({ p_gateway: "mercadopago", p_event_id: "1234567890" }),
    );
  });

  it("rejects a MercadoPago webhook replayed >300s in the past → 401", async () => {
    const payload = JSON.stringify(MP_EVENT);
    const staleTs = Math.floor(Date.now() / 1000) - 600;
    const { signature } = mpV2Signature({
      payload,
      dataId: MP_EVENT.data.id,
      xRequestId: "mp-req-id-1",
      secret: MP_SECRET,
      ts: staleTs,
    });
    const res = await POST(
      makeReq({
        body: payload,
        headers: { "x-signature": signature, "x-request-id": "mp-req-id-1" },
      }),
    );
    expect(res.status).toBe(401);
    expect(confirmDepositByReferenceMock).not.toHaveBeenCalled();
  });

  it("rejects a MercadoPago webhook with bad signature → 401", async () => {
    const payload = JSON.stringify(MP_EVENT);
    const ts = Math.floor(Date.now() / 1000);
    const res = await POST(
      makeReq({
        body: payload,
        headers: {
          "x-signature": `ts=${ts},v1=${"0".repeat(64)}`,
          "x-request-id": "mp-req-id-1",
        },
      }),
    );
    expect(res.status).toBe(401);
  });

  // ── Receiver-side dedup ──────────────────────────────────────────────

  it("returns 200 + replayed=true and skips deposit confirm on duplicate event_id", async () => {
    rpcMock.mockResolvedValueOnce({ data: [{ was_replay: true }], error: null });
    const payload = JSON.stringify(STRIPE_EVENT);
    const res = await POST(
      makeReq({
        body: payload,
        headers: { "stripe-signature": stripeSignature(payload, STRIPE_SECRET) },
      }),
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.replayed).toBe(true);
    expect(body.event_id).toBe("evt_test_1");
    expect(confirmDepositByReferenceMock).not.toHaveBeenCalled();
    expect(metricsIncrementMock).toHaveBeenCalledWith(
      "custody.webhook.replayed",
      { gateway: "stripe" },
    );
    expect(metricsIncrementMock).not.toHaveBeenCalledWith(
      "custody.webhook.confirmed",
      expect.anything(),
    );
  });

  it("returns 500 when dedup RPC errors with non-missing-relation error", async () => {
    rpcMock.mockResolvedValueOnce({
      data: null,
      error: { message: "lock_timeout exceeded", code: "55P03" },
    });
    const payload = JSON.stringify(STRIPE_EVENT);
    const res = await POST(
      makeReq({
        body: payload,
        headers: { "stripe-signature": stripeSignature(payload, STRIPE_SECRET) },
      }),
    );
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.error.code).toBe("INTERNAL_ERROR");
    expect(metricsIncrementMock).toHaveBeenCalledWith(
      "custody.webhook.error",
      { gateway: "stripe", reason: "dedup" },
    );
  });

  it("falls through gracefully when dedup table is missing (legacy install)", async () => {
    rpcMock
      // first call: dedup, table missing
      .mockResolvedValueOnce({
        data: null,
        error: { message: "function does not exist", code: "42883" },
      })
      // second call: mark processed, also table missing — must be tolerated
      .mockResolvedValueOnce({
        data: null,
        error: { message: "function does not exist", code: "42883" },
      });
    const payload = JSON.stringify(STRIPE_EVENT);
    const res = await POST(
      makeReq({
        body: payload,
        headers: { "stripe-signature": stripeSignature(payload, STRIPE_SECRET) },
      }),
    );
    expect(res.status).toBe(200);
    expect(confirmDepositByReferenceMock).toHaveBeenCalled();
  });

  // ── Body cap ─────────────────────────────────────────────────────────

  it("rejects content-length > 64 KiB with 413", async () => {
    const payload = JSON.stringify(STRIPE_EVENT);
    const req = new Request("http://localhost/api/custody/webhook", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "stripe-signature": stripeSignature(payload, STRIPE_SECRET),
        "content-length": String(70 * 1024),
      },
      body: payload,
    }) as unknown as import("next/server").NextRequest;
    const res = await POST(req);
    expect(res.status).toBe(413);
    const body = await res.json();
    expect(body.error.code).toBe("PAYLOAD_TOO_LARGE");
    expect(metricsIncrementMock).toHaveBeenCalledWith(
      "custody.webhook.rejected",
      { reason: "body_too_large" },
    );
  });

  it("rejects oversized body even when content-length is missing/lying", async () => {
    const huge = "x".repeat(70 * 1024);
    const payload = JSON.stringify({ ...STRIPE_EVENT, padding: huge });
    const res = await POST(
      makeReq({
        body: payload,
        headers: { "stripe-signature": stripeSignature(payload, STRIPE_SECRET) },
      }),
    );
    expect(res.status).toBe(413);
  });

  // ── Misc ─────────────────────────────────────────────────────────────

  it("rejects payload with no event id → 400 VALIDATION_FAILED", async () => {
    const eventNoId = { type: "payment_intent.succeeded", data: { object: { id: "ref" } } };
    const payload = JSON.stringify(eventNoId);
    const res = await POST(
      makeReq({
        body: payload,
        headers: { "stripe-signature": stripeSignature(payload, STRIPE_SECRET) },
      }),
    );
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error.code).toBe("VALIDATION_FAILED");
    expect(body.error.message).toMatch(/event id/i);
  });

  it("returns 400 VALIDATION_FAILED for invalid JSON body", async () => {
    const payload = "{not-json";
    const res = await POST(
      makeReq({
        body: payload,
        headers: { "stripe-signature": stripeSignature(payload, STRIPE_SECRET) },
      }),
    );
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error.code).toBe("VALIDATION_FAILED");
    expect(body.error.message).toMatch(/json/i);
  });

  it("does NOT inflate audit log on already-confirmed deposit", async () => {
    confirmDepositByReferenceMock.mockResolvedValueOnce({
      depositId: "dep-1",
      alreadyConfirmed: true,
    });
    const payload = JSON.stringify(STRIPE_EVENT);
    const res = await POST(
      makeReq({
        body: payload,
        headers: { "stripe-signature": stripeSignature(payload, STRIPE_SECRET) },
      }),
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.already_confirmed).toBe(true);
    expect(auditLogMock).not.toHaveBeenCalled();
  });

  // ── L03-20 — dispute / refund / chargeback routing ───────────────────

  const DISPUTE_EVENT = {
    id: "evt_dispute_1",
    type: "charge.dispute.created",
    data: {
      object: {
        id: "du_test_1",
        payment_intent: "pi_charge_ref_123",
        reason: "fraudulent",
      },
    },
  };

  const REFUND_EVENT = {
    id: "evt_refund_1",
    type: "charge.refunded",
    data: {
      object: {
        id: "ch_test_1",
        payment_intent: "pi_charge_ref_123",
        reason: "requested_by_customer",
      },
    },
  };

  const DISPUTE_CLOSED_LOST_EVENT = {
    id: "evt_dispute_closed_1",
    type: "charge.dispute.closed",
    data: {
      object: {
        id: "du_test_2",
        payment_intent: "pi_charge_ref_999",
        reason: "product_not_received",
        status: "lost",
      },
    },
  };

  const DISPUTE_CLOSED_WON_EVENT = {
    id: "evt_dispute_closed_won",
    type: "charge.dispute.closed",
    data: {
      object: {
        id: "du_won",
        payment_intent: "pi_charge_ref_won",
        reason: "fraudulent",
        status: "won",
      },
    },
  };

  const MP_REFUND_EVENT = {
    action: "payment.refunded",
    type: "payment",
    data: { id: "9876543210" },
  };

  it("Stripe dispute — auto-reverses happy path (RESOLVED_REVERSED)", async () => {
    const payload = JSON.stringify(DISPUTE_EVENT);
    const res = await POST(
      makeReq({
        body: payload,
        headers: { "stripe-signature": stripeSignature(payload, STRIPE_SECRET) },
      }),
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.kind).toBe("chargeback");
    expect(body.outcome).toBe("reversed");
    expect(body.case_state).toBe("RESOLVED_REVERSED");
    expect(body.reversal_id).toBe("rev-1");

    expect(handleCustodyDisputeMock).toHaveBeenCalledWith(
      expect.objectContaining({
        gateway: "stripe",
        gatewayEventId: "evt_dispute_1",
        gatewayDisputeRef: "du_test_1",
        paymentReference: "pi_charge_ref_123",
        kind: "chargeback",
        reasonCode: "fraudulent",
      }),
    );
    expect(confirmDepositByReferenceMock).not.toHaveBeenCalled();
    expect(metricsIncrementMock).toHaveBeenCalledWith(
      "custody.webhook.dispute",
      { gateway: "stripe", kind: "chargeback", outcome: "reversed" },
    );
    expect(auditLogMock).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "custody.dispute.auto_reversed",
        targetId: "case-1",
      }),
    );
  });

  it("Stripe refund — routed through dispute handler (not legacy confirm)", async () => {
    handleCustodyDisputeMock.mockResolvedValueOnce({
      outcome: "reversed" as const,
      caseId: "case-refund",
      caseState: "RESOLVED_REVERSED",
      depositId: "dep-2",
      groupId: "group-2",
      amountUsd: 50,
      reversalId: "rev-2",
      refundedUsd: 50,
      wasIdempotent: false,
    });
    const payload = JSON.stringify(REFUND_EVENT);
    const res = await POST(
      makeReq({
        body: payload,
        headers: { "stripe-signature": stripeSignature(payload, STRIPE_SECRET) },
      }),
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.kind).toBe("refund");
    expect(handleCustodyDisputeMock).toHaveBeenCalledWith(
      expect.objectContaining({
        kind: "refund",
        paymentReference: "pi_charge_ref_123",
        gatewayDisputeRef: "ch_test_1",
      }),
    );
    expect(confirmDepositByReferenceMock).not.toHaveBeenCalled();
  });

  it("Stripe dispute — escalates to CFO when coins already spent (INVARIANT_VIOLATION)", async () => {
    // Simulate the RPC returning 'escalated' because
    // reverse_custody_deposit_atomic raised P0008.
    handleCustodyDisputeMock.mockResolvedValueOnce({
      outcome: "escalated" as const,
      caseId: "case-esc",
      caseState: "ESCALATED_CFO",
      depositId: "dep-3",
      groupId: "group-3",
      amountUsd: 200,
      reversalId: null,
      refundedUsd: null,
      wasIdempotent: false,
    });
    const payload = JSON.stringify(DISPUTE_EVENT);
    const res = await POST(
      makeReq({
        body: payload,
        headers: { "stripe-signature": stripeSignature(payload, STRIPE_SECRET) },
      }),
    );
    expect(res.status).toBe(200); // 200 so Stripe doesn't retry
    const body = await res.json();
    expect(body.outcome).toBe("escalated");
    expect(body.case_state).toBe("ESCALATED_CFO");
    expect(body.reversal_id).toBe(null);
    expect(auditLogMock).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "custody.dispute.escalated_cfo",
        targetId: "case-esc",
      }),
    );
  });

  it("Stripe dispute — idempotent replay does NOT re-audit", async () => {
    handleCustodyDisputeMock.mockResolvedValueOnce({
      outcome: "idempotent_replay" as const,
      caseId: "case-1",
      caseState: "RESOLVED_REVERSED",
      depositId: "dep-1",
      groupId: "group-1",
      amountUsd: 100,
      reversalId: "rev-1",
      refundedUsd: null,
      wasIdempotent: true,
    });
    const payload = JSON.stringify(DISPUTE_EVENT);
    const res = await POST(
      makeReq({
        body: payload,
        headers: { "stripe-signature": stripeSignature(payload, STRIPE_SECRET) },
      }),
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.was_idempotent).toBe(true);
    expect(body.outcome).toBe("idempotent_replay");
    // Audit is NOT re-written on replay — the original call already did.
    expect(auditLogMock).not.toHaveBeenCalled();
  });

  it("Stripe dispute — returns deposit_not_found when no matching deposit", async () => {
    handleCustodyDisputeMock.mockResolvedValueOnce({
      outcome: "deposit_not_found" as const,
      caseId: "case-dnf",
      caseState: "DEPOSIT_NOT_FOUND",
      depositId: null,
      groupId: null,
      amountUsd: null,
      reversalId: null,
      refundedUsd: null,
      wasIdempotent: false,
    });
    const payload = JSON.stringify(DISPUTE_EVENT);
    const res = await POST(
      makeReq({
        body: payload,
        headers: { "stripe-signature": stripeSignature(payload, STRIPE_SECRET) },
      }),
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.outcome).toBe("deposit_not_found");
    expect(body.case_state).toBe("DEPOSIT_NOT_FOUND");
    expect(body.deposit_id).toBe(null);
  });

  it("Stripe charge.dispute.closed status=lost → chargeback path (triggers reversal)", async () => {
    const payload = JSON.stringify(DISPUTE_CLOSED_LOST_EVENT);
    const res = await POST(
      makeReq({
        body: payload,
        headers: { "stripe-signature": stripeSignature(payload, STRIPE_SECRET) },
      }),
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.kind).toBe("chargeback");
    expect(handleCustodyDisputeMock).toHaveBeenCalled();
  });

  it("Stripe charge.dispute.closed status=won → unsupported path (no reversal)", async () => {
    const payload = JSON.stringify(DISPUTE_CLOSED_WON_EVENT);
    const res = await POST(
      makeReq({
        body: payload,
        headers: { "stripe-signature": stripeSignature(payload, STRIPE_SECRET) },
      }),
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.skipped).toBe(true);
    expect(body.reason).toBe("unsupported_event_type");
    expect(handleCustodyDisputeMock).not.toHaveBeenCalled();
    expect(confirmDepositByReferenceMock).not.toHaveBeenCalled();
  });

  it("MercadoPago refund (action=payment.refunded) → dispute handler with kind=refund", async () => {
    const payload = JSON.stringify(MP_REFUND_EVENT);
    const { signature } = mpV2Signature({
      payload,
      dataId: MP_REFUND_EVENT.data.id,
      xRequestId: "mp-req-refund-1",
      secret: MP_SECRET,
    });
    const res = await POST(
      makeReq({
        body: payload,
        headers: { "x-signature": signature, "x-request-id": "mp-req-refund-1" },
      }),
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.kind).toBe("refund");
    expect(handleCustodyDisputeMock).toHaveBeenCalledWith(
      expect.objectContaining({
        gateway: "mercadopago",
        kind: "refund",
        paymentReference: "9876543210",
        reasonCode: "mp_refunded",
      }),
    );
  });

  it("dispute RPC unavailable (legacy install) → 503 SERVICE_UNAVAILABLE", async () => {
    handleCustodyDisputeMock.mockResolvedValueOnce(null);
    const payload = JSON.stringify(DISPUTE_EVENT);
    const res = await POST(
      makeReq({
        body: payload,
        headers: { "stripe-signature": stripeSignature(payload, STRIPE_SECRET) },
      }),
    );
    expect(res.status).toBe(503);
    const body = await res.json();
    expect(body.error.code).toBe("SERVICE_UNAVAILABLE");
  });

  it("dispute RPC throws → 500 INTERNAL_ERROR (allows gateway retry)", async () => {
    handleCustodyDisputeMock.mockRejectedValueOnce(new Error("db down"));
    const payload = JSON.stringify(DISPUTE_EVENT);
    const res = await POST(
      makeReq({
        body: payload,
        headers: { "stripe-signature": stripeSignature(payload, STRIPE_SECRET) },
      }),
    );
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.error.code).toBe("INTERNAL_ERROR");
    expect(metricsIncrementMock).toHaveBeenCalledWith(
      "custody.webhook.error",
      { gateway: "stripe", reason: "dispute" },
    );
  });

  it("unsupported Stripe event type → 200 OK with skipped=true (no retries)", async () => {
    const UNKNOWN = {
      id: "evt_unknown_1",
      type: "customer.created",
      data: { object: { id: "cus_123" } },
    };
    const payload = JSON.stringify(UNKNOWN);
    const res = await POST(
      makeReq({
        body: payload,
        headers: { "stripe-signature": stripeSignature(payload, STRIPE_SECRET) },
      }),
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.skipped).toBe(true);
    expect(body.event_type).toBe("customer.created");
    expect(confirmDepositByReferenceMock).not.toHaveBeenCalled();
    expect(handleCustodyDisputeMock).not.toHaveBeenCalled();
  });

  it("returns 503 when STRIPE secret is not configured", async () => {
    const previous = process.env.STRIPE_CUSTODY_WEBHOOK_SECRET;
    process.env.STRIPE_CUSTODY_WEBHOOK_SECRET = "";
    vi.resetModules();
    try {
      const { POST: POST2 } = await import("./route");
      const payload = JSON.stringify(STRIPE_EVENT);
      const res = await POST2(
        makeReq({
          body: payload,
          headers: { "stripe-signature": stripeSignature(payload, STRIPE_SECRET) },
        }),
      );
      expect(res.status).toBe(503);
      const body = await res.json();
      expect(body.error.code).toBe("SERVICE_UNAVAILABLE");
    } finally {
      process.env.STRIPE_CUSTODY_WEBHOOK_SECRET = previous;
      vi.resetModules();
    }
  });
});
