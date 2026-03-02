/**
 * Webhook signature verification utilities.
 *
 * Supports Stripe (HMAC-SHA256) and generic HMAC-based webhooks.
 * Uses constant-time comparison to prevent timing attacks.
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

/**
 * Verifies a generic HMAC-SHA256 webhook signature.
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
