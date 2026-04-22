import { NextRequest, NextResponse } from "next/server";

import {
  verifyStripeSignature,
  verifyMercadoPagoSignature,
  WebhookError,
} from "@/lib/webhook";
import {
  confirmDepositByReference,
  handleCustodyDispute,
  type CustodyDisputeOutcome,
} from "@/lib/custody";
import { auditLog } from "@/lib/audit";
import { logger } from "@/lib/logger";
import { metrics } from "@/lib/metrics";
import { createServiceClient } from "@/lib/supabase/service";
import { apiError, resolveRequestId } from "@/lib/api/errors";
import { withErrorHandler } from "@/lib/api-handler";

const STRIPE_WEBHOOK_SECRET = process.env.STRIPE_CUSTODY_WEBHOOK_SECRET ?? "";
const MP_WEBHOOK_SECRET = process.env.MP_CUSTODY_WEBHOOK_SECRET ?? "";

/**
 * Maximum body size accepted by the receiver. Stripe and MercadoPago
 * webhooks for custody events are well under 4 KiB in practice; 64 KiB
 * leaves a 16x headroom while still capping resource exhaustion attacks
 * (e.g. an attacker probing the endpoint with a 50 MB JSON blob to fill
 * the audit log / log pipeline).
 */
const MAX_WEBHOOK_BODY_BYTES = 64 * 1024;

type Gateway = "stripe" | "mercadopago";

/**
 * POST /api/custody/webhook (L01-01 hardened)
 *
 * Receives payment-gateway notifications to confirm custody deposits.
 *
 * Defence-in-depth layered on the original receiver:
 *
 *   1. **Authoritative gateway detection** — the gateway used to pick the
 *      verification secret is derived ONLY from which signature header is
 *      present (`stripe-signature` vs `x-signature`). The legacy
 *      `x-gateway` request header used to influence this decision; any
 *      attacker who could inject custom headers via a misconfigured proxy
 *      could force the receiver onto the weaker MP path. We now ignore
 *      `x-gateway` entirely and reject ambiguous requests (both / neither
 *      header present) with 400 BAD_REQUEST before any HMAC work.
 *
 *   2. **Body size cap** — `text()` is bounded at 64 KiB
 *      (`MAX_WEBHOOK_BODY_BYTES`). The framework itself imposes no cap on
 *      `request.text()`; without this guard a single 100 MB POST burns
 *      both memory and the audit-log JSON column.
 *
 *   3. **MercadoPago timestamp window** — `verifyMercadoPagoSignature`
 *      enforces a 300 s tolerance window plus the v2 manifest-bound HMAC.
 *      Pre-fix this path was a flat HMAC with no replay protection — an
 *      intercepted webhook could be replayed indefinitely.
 *
 *   4. **Receiver-side dedup** — every accepted event is written to
 *      `custody_webhook_events (gateway, event_id) PRIMARY KEY` via
 *      `fn_record_custody_webhook_event`. A second arrival of the same
 *      pair short-circuits BEFORE invoking `confirmDepositByReference`
 *      (so we don't even touch the deposit row, the audit log, or the
 *      metrics counter for replays — only `custody.webhook.replayed`
 *      ticks). This complements the existing UNIQUE on
 *      `custody_deposits.payment_reference`: the dedup table catches
 *      replays in the race window before the deposit reference is even
 *      known.
 *
 *   5. **Canonical error envelope** — all responses (success and error)
 *      use the `apiError` / NextResponse pattern with `request_id`
 *      propagation (L13-06 / L14-05).
 */
// L17-01 — outermost safety-net. O receiver já tem try/catch granulares
// para signature/dedup/confirm; o wrapper só protege contra throws
// inesperados (e.g. JSON.parse com input malformado depois da extração
// inicial, falhas de DB no audit) — devolvem 500 canônico em vez de
// stack trace.
export const POST = withErrorHandler(_post, "api.custody.webhook.post");

async function _post(req: NextRequest) {
  const requestId = resolveRequestId(req);

  // ── 1. Body — bounded read ──────────────────────────────────────────
  const contentLengthHeader = req.headers.get("content-length");
  if (contentLengthHeader) {
    const declared = Number.parseInt(contentLengthHeader, 10);
    if (Number.isFinite(declared) && declared > MAX_WEBHOOK_BODY_BYTES) {
      logger.warn("custody.webhook.body_too_large", {
        request_id: requestId,
        declared,
        cap: MAX_WEBHOOK_BODY_BYTES,
      });
      metrics.increment("custody.webhook.rejected", { reason: "body_too_large" });
      return apiError(
        req,
        "PAYLOAD_TOO_LARGE",
        `Webhook body exceeds ${MAX_WEBHOOK_BODY_BYTES} bytes`,
        413,
      );
    }
  }

  const rawBody = await req.text();
  if (Buffer.byteLength(rawBody, "utf8") > MAX_WEBHOOK_BODY_BYTES) {
    metrics.increment("custody.webhook.rejected", { reason: "body_too_large" });
    return apiError(
      req,
      "PAYLOAD_TOO_LARGE",
      `Webhook body exceeds ${MAX_WEBHOOK_BODY_BYTES} bytes`,
      413,
    );
  }

  // ── 2. Authoritative gateway detection ──────────────────────────────
  const stripeSig = req.headers.get("stripe-signature");
  const mpSig = req.headers.get("x-signature");
  const gateway = detectGateway(stripeSig, mpSig);

  if (!gateway) {
    metrics.increment("custody.webhook.rejected", { reason: "ambiguous_gateway" });
    return apiError(
      req,
      "BAD_REQUEST",
      stripeSig && mpSig
        ? "Both stripe-signature and x-signature headers present"
        : "No recognised gateway signature header present",
      400,
    );
  }

  // ── 3. Signature verification ───────────────────────────────────────
  try {
    if (gateway === "stripe") {
      if (!STRIPE_WEBHOOK_SECRET) {
        logger.error("custody.webhook.config_missing", undefined, { gateway });
        metrics.increment("custody.webhook.error", { gateway });
        return apiError(req, "SERVICE_UNAVAILABLE", "Webhook secret not configured", 503);
      }
      verifyStripeSignature({
        payload: rawBody,
        signature: stripeSig as string,
        secret: STRIPE_WEBHOOK_SECRET,
      });
    } else {
      if (!MP_WEBHOOK_SECRET) {
        logger.error("custody.webhook.config_missing", undefined, { gateway });
        metrics.increment("custody.webhook.error", { gateway });
        return apiError(req, "SERVICE_UNAVAILABLE", "Webhook secret not configured", 503);
      }
      verifyMercadoPagoSignature({
        payload: rawBody,
        signature: mpSig as string,
        xRequestId: req.headers.get("x-request-id"),
        dataId: extractMpDataId(rawBody),
        secret: MP_WEBHOOK_SECRET,
      });
    }
  } catch (err) {
    if (err instanceof WebhookError) {
      logger.warn("custody.webhook.signature_invalid", {
        request_id: requestId,
        gateway,
        error: err.message,
      });
      metrics.increment("custody.webhook.rejected", { reason: "signature" });
      return apiError(req, "UNAUTHORIZED", err.message, 401);
    }
    throw err;
  }

  // ── 4. Parse payload (after signature is verified) ──────────────────
  let event: Record<string, unknown>;
  try {
    event = JSON.parse(rawBody) as Record<string, unknown>;
  } catch {
    metrics.increment("custody.webhook.rejected", { reason: "invalid_json" });
    return apiError(req, "VALIDATION_FAILED", "Webhook body is not valid JSON", 400);
  }

  const eventId = extractEventId(event, gateway);
  const paymentReference = extractPaymentReference(event, gateway);

  if (!eventId) {
    metrics.increment("custody.webhook.rejected", { reason: "no_event_id" });
    return apiError(req, "VALIDATION_FAILED", "No event id in payload", 400);
  }

  // ── 5. Receiver-side dedup ──────────────────────────────────────────
  let dedup: { wasReplay: boolean } | null;
  try {
    dedup = await recordWebhookEvent({
      gateway,
      eventId,
      paymentReference,
      payload: event,
    });
  } catch (err) {
    logger.error("custody.webhook.dedup_failed", err, {
      request_id: requestId,
      gateway,
      event_id: eventId,
    });
    metrics.increment("custody.webhook.error", { gateway, reason: "dedup" });
    return apiError(req, "INTERNAL_ERROR", "Webhook dedup unavailable", 500);
  }

  if (dedup?.wasReplay) {
    metrics.increment("custody.webhook.replayed", { gateway });
    logger.info("custody.webhook.replayed", {
      request_id: requestId,
      gateway,
      event_id: eventId,
    });
    return NextResponse.json({ ok: true, replayed: true, event_id: eventId });
  }

  // ── 6. Classify event and route ─────────────────────────────────────
  //
  // Pre-L03-20 this branch ALWAYS called `confirmDepositByReference` —
  // a dispute/refund webhook would silently increment
  // `custody.webhook.confirmed` for a deposit that was being REVERSED
  // by the gateway. We now classify the event type first and route
  // dispute / refund / chargeback payloads to
  // `fn_handle_custody_dispute_atomic`.
  const classification = classifyEvent(event, gateway);

  if (classification.kind === "unsupported") {
    // Accept + ack (200 OK) — unknown/untracked event types must not
    // trigger gateway retries. Dedup row already recorded. Metrics +
    // log so ops can spot unexpected topic growth.
    metrics.increment("custody.webhook.unsupported", { gateway });
    logger.info("custody.webhook.unsupported_event", {
      request_id: requestId,
      gateway,
      event_id: eventId,
      event_type: classification.eventType,
    });
    await markWebhookEventProcessed({ gateway, eventId });
    return NextResponse.json({
      ok: true,
      skipped: true,
      reason: "unsupported_event_type",
      event_id: eventId,
      event_type: classification.eventType,
    });
  }

  if (classification.kind === "dispute" || classification.kind === "refund" || classification.kind === "chargeback") {
    return handleDispute({
      req,
      requestId,
      gateway,
      eventId,
      paymentReference: classification.paymentReference,
      gatewayDisputeRef: classification.gatewayDisputeRef,
      kind: classification.kind,
      reasonCode: classification.reasonCode,
      event,
    });
  }

  // classification.kind === 'success' — legacy deposit-confirmation path.
  if (!paymentReference) {
    metrics.increment("custody.webhook.rejected", { reason: "no_payment_reference" });
    return apiError(req, "VALIDATION_FAILED", "No payment reference found", 400);
  }

  try {
    const result = await confirmDepositByReference(paymentReference);
    if (!result) {
      return apiError(req, "SERVICE_UNAVAILABLE", "Custody feature not available", 503);
    }
    metrics.increment("custody.webhook.confirmed", { gateway });

    if (!result.alreadyConfirmed) {
      await auditLog({
        actorId: "system",
        action: "custody.deposit.webhook_confirmed",
        targetId: result.depositId,
        metadata: { gateway, payment_reference: paymentReference, event_id: eventId },
      });
    }

    await markWebhookEventProcessed({ gateway, eventId });

    return NextResponse.json({
      ok: true,
      deposit_id: result.depositId,
      already_confirmed: result.alreadyConfirmed,
      event_id: eventId,
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Confirmation failed";
    logger.error("custody.webhook.confirm_failed", err, {
      request_id: requestId,
      gateway,
      event_id: eventId,
      payment_reference: paymentReference,
    });
    metrics.increment("custody.webhook.error", { gateway });
    return apiError(req, "INTERNAL_ERROR", msg, 422);
  }
}

// ────────────────────────────────────────────────────────────────────────
// L03-20 — dispute / refund / chargeback handler
// ────────────────────────────────────────────────────────────────────────

interface HandleDisputeArgs {
  req: NextRequest;
  requestId: string | null;
  gateway: Gateway;
  eventId: string;
  paymentReference: string | null;
  gatewayDisputeRef: string | null;
  kind: "dispute" | "refund" | "chargeback";
  reasonCode: string;
  event: Record<string, unknown>;
}

async function handleDispute(args: HandleDisputeArgs): Promise<NextResponse> {
  const { req, requestId, gateway, eventId, paymentReference, gatewayDisputeRef, kind, reasonCode, event } = args;

  try {
    const result = await handleCustodyDispute({
      gateway,
      gatewayEventId: eventId,
      gatewayDisputeRef,
      paymentReference,
      kind,
      reasonCode,
      rawEvent: event,
    });

    if (!result) {
      // Tables/RPC missing — degrade gracefully (legacy DB). Log loud
      // because in prod this should never happen.
      logger.error("custody.webhook.dispute_feature_unavailable", undefined, {
        request_id: requestId,
        gateway,
        event_id: eventId,
      });
      metrics.increment("custody.webhook.error", { gateway, reason: "dispute_rpc_missing" });
      return apiError(req, "SERVICE_UNAVAILABLE", "Dispute handling not available", 503);
    }

    metrics.increment("custody.webhook.dispute", {
      gateway,
      kind,
      outcome: result.outcome,
    });

    logger.info("custody.webhook.dispute_handled", {
      request_id: requestId,
      gateway,
      event_id: eventId,
      kind,
      reason_code: reasonCode,
      outcome: result.outcome,
      case_id: result.caseId,
      case_state: result.caseState,
      deposit_id: result.depositId,
      reversal_id: result.reversalId,
    });

    // Audit for every NON-idempotent resolution — idempotent replays
    // already audited on first call.
    if (!result.wasIdempotent) {
      await auditLog({
        actorId: "system",
        action: auditActionFor(result.outcome),
        targetId: result.caseId,
        metadata: {
          gateway,
          event_id: eventId,
          kind,
          reason_code: reasonCode,
          outcome: result.outcome,
          case_state: result.caseState,
          deposit_id: result.depositId,
          reversal_id: result.reversalId,
          refunded_usd: result.refundedUsd,
          payment_reference: paymentReference,
        },
      });
    }

    await markWebhookEventProcessed({ gateway, eventId });

    return NextResponse.json({
      ok: true,
      event_id: eventId,
      kind,
      outcome: result.outcome,
      case_id: result.caseId,
      case_state: result.caseState,
      deposit_id: result.depositId,
      reversal_id: result.reversalId,
      refunded_usd: result.refundedUsd,
      was_idempotent: result.wasIdempotent,
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Dispute handling failed";
    logger.error("custody.webhook.dispute_failed", err, {
      request_id: requestId,
      gateway,
      event_id: eventId,
      kind,
      payment_reference: paymentReference,
    });
    metrics.increment("custody.webhook.error", { gateway, reason: "dispute" });
    // 500 (not 4xx) so the gateway retries — our idempotency key is
    // (gateway, event_id), so retrying is safe and preferred over
    // dropping a legitimate dispute.
    return apiError(req, "INTERNAL_ERROR", msg, 500);
  }
}

function auditActionFor(outcome: CustodyDisputeOutcome): string {
  switch (outcome) {
    case "reversed":          return "custody.dispute.auto_reversed";
    case "escalated":         return "custody.dispute.escalated_cfo";
    case "deposit_not_found": return "custody.dispute.deposit_not_found";
    case "dismissed":         return "custody.dispute.dismissed";
    case "idempotent_replay": return "custody.dispute.replay";
  }
}

// ────────────────────────────────────────────────────────────────────────
// Helpers — event classification (L03-20)
// ────────────────────────────────────────────────────────────────────────

type EventKind = "success" | "dispute" | "refund" | "chargeback" | "unsupported";

interface EventClassification {
  kind: EventKind;
  /** Human-readable event type echoed in logs/response for observability. */
  eventType: string;
  /** `pi_…` / MP payment id — the key used to locate the custody_deposit. */
  paymentReference: string | null;
  /** `du_…` / `re_…` / MP refund id — stored on custody_dispute_cases. */
  gatewayDisputeRef: string | null;
  /** Gateway-reported reason (or synthesized constant when none exists). */
  reasonCode: string;
}

/**
 * Classify a verified webhook payload into one of the L03-20 buckets.
 *
 * The classifier is strictly driven by the payload `type` (Stripe) or
 * derived status (MercadoPago). Unknown types map to `unsupported` —
 * the receiver ACKs 200 and persists the dedup row, so the gateway
 * stops retrying, but no business logic runs.
 *
 * For Stripe dispute payloads the `paymentReference` is pulled from
 * `data.object.payment_intent` (the dispute resource itself has id
 * `du_…` which is NOT what `custody_deposits.payment_reference`
 * stores).
 */
function classifyEvent(
  event: Record<string, unknown>,
  gateway: Gateway,
): EventClassification {
  if (gateway === "stripe") return classifyStripe(event);
  return classifyMercadoPago(event);
}

function classifyStripe(event: Record<string, unknown>): EventClassification {
  const type = typeof event.type === "string" ? event.type : "";
  const dataObj =
    (event as { data?: { object?: Record<string, unknown> } }).data?.object ?? {};

  // Pull these with the tolerant shape helpers — Stripe payloads can be
  // sparse (esp. in test mode) and we don't want to crash on a missing
  // nested field.
  const objectId = typeof dataObj.id === "string" ? dataObj.id : null;
  const paymentIntent =
    typeof dataObj.payment_intent === "string" ? dataObj.payment_intent : null;
  const reason = typeof dataObj.reason === "string" ? dataObj.reason : null;
  const status = typeof dataObj.status === "string" ? dataObj.status : null;

  switch (type) {
    case "payment_intent.succeeded":
    case "checkout.session.completed":
      return {
        kind: "success",
        eventType: type,
        paymentReference: objectId,
        gatewayDisputeRef: null,
        reasonCode: "payment_succeeded",
      };

    case "charge.dispute.created":
    case "charge.dispute.funds_withdrawn":
      return {
        kind: "chargeback",
        eventType: type,
        paymentReference: paymentIntent,
        gatewayDisputeRef: objectId,
        reasonCode: reason ?? "dispute_opened",
      };

    case "charge.dispute.closed":
      // Only `lost` requires reversal — `won` means we keep the funds
      // (no-op). `warning_*` states are informational: we classify
      // them as unsupported so they ACK without side effects.
      if (status === "lost") {
        return {
          kind: "chargeback",
          eventType: type,
          paymentReference: paymentIntent,
          gatewayDisputeRef: objectId,
          reasonCode: reason ?? "dispute_lost",
        };
      }
      return {
        kind: "unsupported",
        eventType: `${type}:${status ?? "no_status"}`,
        paymentReference: paymentIntent,
        gatewayDisputeRef: objectId,
        reasonCode: reason ?? "dispute_closed_non_lost",
      };

    case "charge.refunded":
    case "refund.created":
    case "charge.refund.updated": {
      // `charge.refund.updated` with status=succeeded is the canonical
      // "funds moved back to customer" signal on Stripe. For legacy
      // `charge.refunded` events `dataObj.refunded=true` is what
      // matters; we treat both as refunds.
      return {
        kind: "refund",
        eventType: type,
        paymentReference: paymentIntent,
        gatewayDisputeRef: objectId,
        reasonCode: reason ?? "refund_issued",
      };
    }

    default:
      return {
        kind: "unsupported",
        eventType: type || "unknown",
        paymentReference: objectId,
        gatewayDisputeRef: null,
        reasonCode: "stripe_unsupported",
      };
  }
}

function classifyMercadoPago(event: Record<string, unknown>): EventClassification {
  // MP's webhook shape is `{type: 'payment', action: 'payment.updated',
  // data: {id}}` — the DETAILED status (approved/refunded/charged_back)
  // is NOT in the webhook body. Gateways that only carry the id force
  // us to fetch the payment from the API to know the status, but for
  // the `action` field (when present) we can shortcut.
  //
  // We honour two signals in order of trust:
  //   1. `action` field (`payment.refunded`, `payment.charged_back`,
  //      `payment.created`/`payment.updated` default to success).
  //   2. `data.status` (if the integrator attaches it — our own internal
  //      retry harness does, Stripe-style).
  const action =
    typeof (event as { action?: unknown }).action === "string"
      ? ((event as { action: string }).action)
      : null;
  const type =
    typeof (event as { type?: unknown }).type === "string"
      ? ((event as { type: string }).type)
      : null;
  const data = (event as { data?: { id?: unknown; status?: unknown } }).data ?? {};
  const dataId =
    data.id !== undefined && data.id !== null && String(data.id).length > 0
      ? String(data.id)
      : null;
  const status =
    typeof data.status === "string" ? data.status : null;

  const eventType = action ?? type ?? "unknown";

  // Refund / chargeback signals.
  if (
    action === "payment.refunded" ||
    action === "refund.created" ||
    status === "refunded"
  ) {
    return {
      kind: "refund",
      eventType,
      paymentReference: dataId,
      gatewayDisputeRef: null,
      reasonCode: "mp_refunded",
    };
  }
  if (
    action === "payment.charged_back" ||
    status === "charged_back"
  ) {
    return {
      kind: "chargeback",
      eventType,
      paymentReference: dataId,
      gatewayDisputeRef: null,
      reasonCode: "mp_charged_back",
    };
  }

  // Default MP `payment.updated` / `payment.created` — treat as
  // confirmation. The existing receiver fetched the detailed status
  // from the MP API here; we preserve that behaviour downstream via
  // `confirmDepositByReference` which is idempotent.
  if (
    action === null ||
    action === "payment.created" ||
    action === "payment.updated" ||
    type === "payment"
  ) {
    return {
      kind: "success",
      eventType,
      paymentReference: dataId,
      gatewayDisputeRef: null,
      reasonCode: "mp_payment_updated",
    };
  }

  return {
    kind: "unsupported",
    eventType,
    paymentReference: dataId,
    gatewayDisputeRef: null,
    reasonCode: "mp_unsupported",
  };
}

// ────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────

/**
 * Decide which gateway the request belongs to from header presence ALONE.
 *
 * Returns null when the request is ambiguous (both signature headers
 * present — possible header smuggling) or when neither is present (no
 * gateway can be inferred).
 *
 * Deliberately ignores the `x-gateway` request header — see route JSDoc.
 */
function detectGateway(
  stripeSig: string | null,
  mpSig: string | null,
): Gateway | null {
  if (stripeSig && mpSig) return null;
  if (stripeSig) return "stripe";
  if (mpSig) return "mercadopago";
  return null;
}

function extractEventId(event: Record<string, unknown>, gateway: Gateway): string | null {
  if (gateway === "stripe") {
    const id = (event as { id?: unknown }).id;
    return typeof id === "string" && id.length > 0 ? id : null;
  }
  // MercadoPago shapes vary by topic; the most stable identifier across
  // topics is `data.id` (resource id) — falls back to top-level `id`.
  const data = (event as { data?: { id?: unknown } }).data;
  if (data && typeof data.id !== "undefined" && data.id !== null) {
    const v = String(data.id);
    if (v.length > 0) return v;
  }
  const topId = (event as { id?: unknown }).id;
  if (topId !== undefined && topId !== null) {
    const v = String(topId);
    if (v.length > 0) return v;
  }
  return null;
}

function extractPaymentReference(
  event: Record<string, unknown>,
  gateway: Gateway,
): string | null {
  if (gateway === "stripe") {
    const obj = (event as { data?: { object?: { id?: string } } }).data?.object;
    return typeof obj?.id === "string" ? obj.id : null;
  }
  if (gateway === "mercadopago") {
    const data = (event as { data?: { id?: unknown } }).data;
    if (data?.id !== undefined && data.id !== null) {
      const v = String(data.id);
      return v.length > 0 ? v : null;
    }
    return null;
  }
  return null;
}

/**
 * Pull `data.id` out of a raw MP body for the v2 manifest. Returns
 * `null` when the JSON is malformed or the field is absent — the
 * verifier will then fall back to the legacy `ts.payload` manifest.
 */
function extractMpDataId(rawBody: string): string | null {
  try {
    const parsed = JSON.parse(rawBody) as { data?: { id?: unknown } };
    const id = parsed?.data?.id;
    if (id === undefined || id === null) return null;
    const s = String(id);
    return s.length > 0 ? s : null;
  } catch {
    return null;
  }
}

interface RecordWebhookEventInput {
  gateway: Gateway;
  eventId: string;
  paymentReference: string | null;
  payload: Record<string, unknown>;
}

/**
 * Insert the receiver-side dedup row. Returns `wasReplay=true` when the
 * (gateway, event_id) pair already exists.
 *
 * Returns `null` (not throw) when the underlying table is missing — that
 * happens in the legacy migration path before this commit ships and we
 * prefer to keep accepting webhooks (with a warn log) rather than refuse
 * paying customers' deposits because of an out-of-order migration.
 */
async function recordWebhookEvent(
  input: RecordWebhookEventInput,
): Promise<{ wasReplay: boolean } | null> {
  const db = createServiceClient();
  const { data, error } = await db.rpc("fn_record_custody_webhook_event", {
    p_gateway: input.gateway,
    p_event_id: input.eventId,
    p_payment_reference: input.paymentReference,
    p_payload: input.payload,
  });

  if (error) {
    if (isMissingRelation(error)) {
      logger.warn("custody.webhook.dedup_table_missing", {
        gateway: input.gateway,
      });
      return null;
    }
    throw new Error(error.message ?? "fn_record_custody_webhook_event failed");
  }

  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    return { wasReplay: false };
  }
  const wasReplay = Boolean((row as { was_replay?: unknown }).was_replay);
  return { wasReplay };
}

async function markWebhookEventProcessed(args: {
  gateway: Gateway;
  eventId: string;
}): Promise<void> {
  const db = createServiceClient();
  const { error } = await db.rpc("fn_mark_custody_webhook_event_processed", {
    p_gateway: args.gateway,
    p_event_id: args.eventId,
  });
  if (error && !isMissingRelation(error)) {
    logger.warn("custody.webhook.mark_processed_failed", {
      gateway: args.gateway,
      event_id: args.eventId,
      error: error.message,
    });
  }
}

function isMissingRelation(err: { message?: string; code?: string }): boolean {
  if (err.code === "42P01" || err.code === "PGRST202") return true;
  const msg = err.message ?? "";
  return /does not exist|fn_record_custody_webhook_event|fn_mark_custody_webhook_event_processed/.test(msg);
}
