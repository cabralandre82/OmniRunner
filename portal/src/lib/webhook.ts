/**
 * Webhook signature verification utilities.
 *
 * Supports:
 *   • Stripe (HMAC-SHA256 with `t=…,v1=…` scheme + tolerance window)
 *   • MercadoPago (HMAC-SHA256 v2 with `ts=…,v1=…` scheme + manifest +
 *     tolerance window) — see L01-01.
 *   • Generic HMAC-SHA256 (legacy / arbitrary callers — kept for
 *     back-compat but no longer used by the custody webhook).
 *
 * All comparisons are constant-time to prevent timing oracles.
 */

import crypto from "crypto";

export class WebhookError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "WebhookError";
  }
}

interface VerifyOptions {
  payload: string | Buffer;
  signature: string;
  secret: string;
  tolerance?: number;
}

/**
 * Verifies a Stripe webhook signature (v1 scheme).
 * @throws {WebhookError} if the signature is invalid or the timestamp is stale.
 */
export function verifyStripeSignature({
  payload,
  signature,
  secret,
  tolerance = 300,
}: VerifyOptions): { timestamp: number } {
  const elements = signature.split(",");
  const tPart = elements.find((e) => e.startsWith("t="));
  const v1Part = elements.find((e) => e.startsWith("v1="));

  if (!tPart || !v1Part) {
    throw new WebhookError("Invalid signature format: missing t= or v1=");
  }

  const timestamp = parseInt(tPart.slice(2), 10);
  const expectedSig = v1Part.slice(3);

  if (isNaN(timestamp)) {
    throw new WebhookError("Invalid signature format: non-numeric timestamp");
  }

  const now = Math.floor(Date.now() / 1000);
  if (Math.abs(now - timestamp) > tolerance) {
    throw new WebhookError(
      `Webhook timestamp too old: ${now - timestamp}s (tolerance=${tolerance}s)`,
    );
  }

  const signedPayload = `${timestamp}.${typeof payload === "string" ? payload : payload.toString("utf8")}`;
  const computed = crypto
    .createHmac("sha256", secret)
    .update(signedPayload)
    .digest("hex");

  if (!timingSafeEqual(computed, expectedSig)) {
    throw new WebhookError("Signature mismatch");
  }

  return { timestamp };
}

// ────────────────────────────────────────────────────────────────────────
// MercadoPago (L01-01)
// ────────────────────────────────────────────────────────────────────────
//
// MercadoPago v2 webhook signature is sent in the `x-signature` header in
// the form:
//
//     x-signature: ts=1700000000,v1=<hex hmac>
//
// The signed manifest is `id:<resource id>;request-id:<x-request-id>;ts:<ts>;`
// where:
//
//   • <resource id>   is `body.data.id` (string), the payment id MP is
//                     notifying about. Numeric in production, but always
//                     compared as a string.
//   • <x-request-id>  is the value of the `x-request-id` header MP sends
//                     alongside `x-signature`. Required for v2.
//   • <ts>            is the value parsed from `ts=…` in `x-signature`.
//
// Reference: https://www.mercadopago.com.br/developers/en/docs/your-integrations/notifications/webhooks#configuration
//
// Why a dedicated verifier (vs reusing `verifyStripeSignature`):
//   - The signed string format differs (manifest with extra ids vs.
//     `ts.payload`). Sharing a function would force every caller to
//     specify which scheme — a footgun ripe for "MP request validated
//     against Stripe scheme" silent acceptance.
//   - Dedicated TS types let the route handler pass `xRequestId` /
//     `dataId` explicitly so the contract is checked at compile-time.

interface VerifyMercadoPagoOptions {
  /** Raw request body — used as a fallback signed payload when the v2
   *  manifest cannot be assembled (e.g. test events without `data.id`). */
  payload: string | Buffer;
  /** Value of the `x-signature` header. */
  signature: string;
  /** Value of the `x-request-id` header. Required for the v2 manifest. */
  xRequestId: string | null | undefined;
  /** `body.data.id` — the resource the webhook is notifying about. */
  dataId: string | null | undefined;
  /** Vault secret. */
  secret: string;
  /** Replay window in seconds. Default: 300 (matches Stripe). */
  tolerance?: number;
}

/**
 * Verifies a MercadoPago v2 webhook signature.
 *
 * Behaviour matrix:
 *
 *   | x-request-id | data.id | manifest used                 |
 *   |--------------|---------|-------------------------------|
 *   | present      | present | `id:<id>;request-id:<rid>;ts:<ts>;` (v2) |
 *   | missing      | any     | `<ts>.<payload>` (legacy / test fallback) |
 *   | present      | missing | `<ts>.<payload>` (legacy / test fallback) |
 *
 * The fallback exists because:
 *   1. MP test panel sometimes sends events without `data.id` (e.g.
 *      `topic=payment` with body `{ "type": "test" }`).
 *   2. Some legacy MP apps still ship without `x-request-id`.
 * Both cases still get **timestamp-bound replay protection**, which is
 * the core L01-01 fix — the manifest format is a defence-in-depth bonus.
 *
 * @throws {WebhookError} if the format is malformed, the timestamp is
 *   outside `tolerance`, or the HMAC mismatches.
 */
export function verifyMercadoPagoSignature({
  payload,
  signature,
  xRequestId,
  dataId,
  secret,
  tolerance = 300,
}: VerifyMercadoPagoOptions): { timestamp: number; manifestUsed: "v2" | "fallback" } {
  // Parse `ts=…,v1=…`. MP allows arbitrary ordering and whitespace; we
  // tolerate both.
  const parts = signature.split(",").map((p) => p.trim());
  const tsPart = parts.find((p) => p.startsWith("ts="));
  const v1Part = parts.find((p) => p.startsWith("v1="));

  if (!tsPart || !v1Part) {
    throw new WebhookError("Invalid signature format: missing ts= or v1=");
  }

  // MP timestamps are reported in seconds (their own docs are inconsistent
  // — historic samples show milliseconds, current docs show seconds). We
  // accept both: any value >= 1e12 is treated as ms.
  const rawTs = tsPart.slice(3);
  let timestamp = parseInt(rawTs, 10);
  if (isNaN(timestamp)) {
    throw new WebhookError("Invalid signature format: non-numeric timestamp");
  }
  if (timestamp >= 1e12) {
    timestamp = Math.floor(timestamp / 1000);
  }

  const expectedSig = v1Part.slice(3);
  if (!expectedSig) {
    throw new WebhookError("Invalid signature format: empty v1=");
  }

  const now = Math.floor(Date.now() / 1000);
  if (Math.abs(now - timestamp) > tolerance) {
    throw new WebhookError(
      `Webhook timestamp too old: ${now - timestamp}s (tolerance=${tolerance}s)`,
    );
  }

  // Build the signed manifest. v2 path requires BOTH x-request-id AND
  // data.id. Anything else falls back to `ts.payload` (still timestamp
  // bound — replay window honored).
  const hasV2Inputs =
    typeof xRequestId === "string" && xRequestId.length > 0 &&
    typeof dataId === "string" && dataId.length > 0;

  const manifestUsed: "v2" | "fallback" = hasV2Inputs ? "v2" : "fallback";
  const signedString = hasV2Inputs
    ? `id:${dataId};request-id:${xRequestId};ts:${timestamp};`
    : `${timestamp}.${typeof payload === "string" ? payload : payload.toString("utf8")}`;

  const computed = crypto
    .createHmac("sha256", secret)
    .update(signedString)
    .digest("hex");

  if (!timingSafeEqual(computed, expectedSig)) {
    throw new WebhookError("Signature mismatch");
  }

  return { timestamp, manifestUsed };
}

/**
 * Verifies a generic HMAC-SHA256 webhook signature.
 *
 * **Deprecated for new gateways.** Provides no replay protection (no
 * timestamp). Kept only for legacy callers. Custody webhook now uses
 * `verifyMercadoPagoSignature` for MP and `verifyStripeSignature` for
 * Stripe — both timestamp-bounded.
 *
 * @throws {WebhookError} if the signature is invalid.
 */
export function verifyHmacSignature({
  payload,
  signature,
  secret,
}: Omit<VerifyOptions, "tolerance">): void {
  const computed = crypto
    .createHmac("sha256", secret)
    .update(payload)
    .digest("hex");

  if (!timingSafeEqual(computed, signature)) {
    throw new WebhookError("Signature mismatch");
  }
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  const bufA = Buffer.from(a, "utf8");
  const bufB = Buffer.from(b, "utf8");
  return crypto.timingSafeEqual(bufA, bufB);
}
