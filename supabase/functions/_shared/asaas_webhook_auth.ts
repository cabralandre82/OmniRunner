/**
 * Asaas webhook authentication helpers (L01-18).
 *
 * Pure functions extracted from `asaas-webhook/index.ts` to enable
 * deterministic unit tests without DB / network. The webhook handler
 * composes these primitives to:
 *
 *   1. Validate the bearer-style `asaas-access-token` header against the
 *      per-group token stored in supabase_vault (constant-time compare).
 *   2. Optionally validate an HMAC-SHA256 signature provided in the
 *      `asaas-signature` header (forward-compat: Asaas does not currently
 *      sign webhook payloads, but other providers — and Asaas in future
 *      revisions — do, and the same per-group secret is reused).
 *   3. Compute a deterministic, collision-resistant idempotency key from
 *      a webhook payload (replaces the original
 *      `JSON.stringify(payload).slice(0, 64)` which collided trivially
 *      for payloads sharing a common prefix).
 *
 * Threat model:
 *   - Replay of a captured request: defeated by `payment_webhook_events`
 *     UNIQUE on `asaas_event_id` (handled by the caller). These helpers
 *     only protect against forgery.
 *   - Token leak via DB dump: vault encrypts at rest; tokens are read
 *     via `fn_ppc_get_webhook_token` only by service_role.
 *   - Forged payload smuggling token in body: rejected — these helpers
 *     read the token strictly from the request header. The original
 *     code path that accepted `payload.accessToken` was a defense-in-
 *     depth gap (token leaks via JSON dump, not just DB dump).
 *   - Timing oracle on token compare: `safeEq` is constant-time across
 *     equal-length strings and never short-circuits.
 */

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

/** Header name Asaas uses for its bearer-style auth token (lowercased). */
export const ASAAS_TOKEN_HEADER = "asaas-access-token";

/**
 * Header name for HMAC signature. Asaas (as of 2026-04) does not sign
 * webhook payloads, but we accept this header opportunistically: if the
 * request includes it, we MUST validate (fail-closed). If absent, we
 * fall back to token-only auth. This means a future Asaas rollout of
 * HMAC signing is a transparent upgrade — flip a column to require it.
 */
export const ASAAS_SIGNATURE_HEADER = "asaas-signature";

/**
 * Tokens shorter than this are rejected even if they match — guards
 * against catastrophic misconfiguration (e.g. empty string vs empty
 * string false-positive). The vault RPC `fn_ppc_save_webhook_token`
 * also enforces ≥16 chars (P0001 INVALID_TOKEN), but we double-gate
 * here because the secret could have been backfilled via direct SQL.
 */
export const MIN_TOKEN_LENGTH = 16;

// ─────────────────────────────────────────────────────────────────────────────
// Constant-time string equality
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Constant-time equality across the bytes of two strings. Returns false
 * immediately on length mismatch (length is not secret) and otherwise
 * walks every byte regardless of where the first divergence is.
 *
 * Both inputs are encoded as UTF-8; this is safe for our use cases
 * (UUID-like tokens, hex digests, base64 signatures) which are all
 * ASCII-clean, but documenting the choice for posterity.
 */
export function safeEq(a: string, b: string): boolean {
  if (typeof a !== "string" || typeof b !== "string") return false;
  if (a.length !== b.length) return false;
  const enc = new TextEncoder();
  const ab = enc.encode(a);
  const bb = enc.encode(b);
  if (ab.byteLength !== bb.byteLength) return false;
  let diff = 0;
  for (let i = 0; i < ab.byteLength; i++) {
    diff |= ab[i] ^ bb[i];
  }
  return diff === 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// SHA-256 / HMAC helpers
// ─────────────────────────────────────────────────────────────────────────────

function bytesToHex(buf: ArrayBuffer | Uint8Array): string {
  const u8 = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  let out = "";
  for (let i = 0; i < u8.byteLength; i++) {
    out += u8[i].toString(16).padStart(2, "0");
  }
  return out;
}

/**
 * SHA-256 of a UTF-8 string, hex-encoded. Used for the idempotency-key
 * fallback (when the payload has neither paymentId nor subscriptionId).
 *
 * Replaces the original `JSON.stringify(payload).slice(0, 64)` which:
 *   - collided trivially for payloads sharing a 64-char prefix (e.g.
 *     two PAYMENT_RECEIVED events for different small payments often
 *     share the leading metadata block);
 *   - produced false-positives that marked legitimate-second-events as
 *     duplicates, silently dropping them.
 */
export async function sha256Hex(input: string): Promise<string> {
  const buf = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", buf);
  return bytesToHex(digest);
}

/**
 * HMAC-SHA256 of `body` using `secret` as the key, hex-encoded.
 * Used to validate the (future) `asaas-signature` header.
 */
export async function hmacSha256Hex(secret: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(body),
  );
  return bytesToHex(sig);
}

// ─────────────────────────────────────────────────────────────────────────────
// Auth verification
// ─────────────────────────────────────────────────────────────────────────────

export type AuthFailureReason =
  | "missing_token"
  | "missing_stored_token"
  | "weak_stored_token"
  | "token_mismatch"
  | "signature_invalid";

export interface AuthVerificationResult {
  ok: boolean;
  reason?: AuthFailureReason;
  /** True iff a signature header was present AND verified. */
  signatureVerified: boolean;
}

export interface AuthVerificationInputs {
  /** Value of `asaas-access-token` request header (or null/undefined if absent). */
  incomingToken: string | null | undefined;
  /** Value of `asaas-signature` request header (or null/undefined if absent). */
  incomingSignature: string | null | undefined;
  /** Per-group token loaded from vault via fn_ppc_get_webhook_token. */
  storedToken: string | null | undefined;
  /** Raw request body as a string; required for HMAC verification. */
  rawBody: string;
}

/**
 * Verify webhook authentication. Two-tier policy:
 *
 *   1. The `asaas-access-token` header MUST be present and match the
 *      stored vault token (constant-time). The legacy code path that
 *      also accepted `payload.accessToken` is INTENTIONALLY removed —
 *      a token leaked via a JSON dump (logs, DLQ, replication) is a
 *      separate exposure surface from a DB column leak.
 *
 *   2. If the request includes `asaas-signature`, the HMAC-SHA256 of
 *      the raw body using the stored token as the HMAC key MUST match.
 *      Fail-closed: a present-but-invalid signature is rejected even
 *      if the bearer token matched.
 */
export async function verifyAsaasWebhookAuth(
  inputs: AuthVerificationInputs,
): Promise<AuthVerificationResult> {
  const { incomingToken, incomingSignature, storedToken, rawBody } = inputs;

  if (!incomingToken || incomingToken.length === 0) {
    return { ok: false, reason: "missing_token", signatureVerified: false };
  }
  if (!storedToken || storedToken.length === 0) {
    return { ok: false, reason: "missing_stored_token", signatureVerified: false };
  }
  if (storedToken.length < MIN_TOKEN_LENGTH) {
    return { ok: false, reason: "weak_stored_token", signatureVerified: false };
  }

  if (!safeEq(incomingToken, storedToken)) {
    return { ok: false, reason: "token_mismatch", signatureVerified: false };
  }

  if (incomingSignature && incomingSignature.length > 0) {
    const expected = await hmacSha256Hex(storedToken, rawBody);
    if (!safeEq(incomingSignature.toLowerCase(), expected.toLowerCase())) {
      return { ok: false, reason: "signature_invalid", signatureVerified: false };
    }
    return { ok: true, signatureVerified: true };
  }

  return { ok: true, signatureVerified: false };
}

// ─────────────────────────────────────────────────────────────────────────────
// Idempotency key
// ─────────────────────────────────────────────────────────────────────────────

export interface IdempotencyKeyInputs {
  /** Asaas event name, e.g. "PAYMENT_RECEIVED". MUST be present. */
  event: string;
  /** Asaas payment id (preferred — globally unique). */
  paymentId?: string | null;
  /** Asaas subscription id (fallback for SUBSCRIPTION_* events). */
  subscriptionId?: string | null;
  /** Raw request body (used as last-resort hash input). */
  rawBody: string;
}

/**
 * Compute the canonical idempotency key for a webhook event.
 *
 * Preference order (most specific first):
 *   1. `<event>_<paymentId>` — the original Asaas payment object always
 *      carries `payment.id`, which is globally unique. This handles
 *      every PAYMENT_* event and is the common case (~99.5%).
 *   2. `<event>_<subscriptionId>` — used by SUBSCRIPTION_INACTIVATED /
 *      SUBSCRIPTION_DELETED which lack `payment.id`.
 *   3. `<event>_<sha256(rawBody)>` — pathological fallback. Returns a
 *      deterministic 64-hex-char digest of the entire raw body, which
 *      cannot collide on a hash function bit-flip basis (Asaas would
 *      have to break SHA-256 for this to false-positive). Original
 *      code used `slice(0, 64)` of `JSON.stringify(payload)` which
 *      collided whenever two payloads shared a 64-char prefix.
 */
export async function computeAsaasIdempotencyKey(
  inputs: IdempotencyKeyInputs,
): Promise<string> {
  const { event, paymentId, subscriptionId, rawBody } = inputs;
  if (!event || event.length === 0) {
    throw new Error("event_required");
  }
  if (paymentId && paymentId.length > 0) {
    return `${event}_${paymentId}`;
  }
  if (subscriptionId && subscriptionId.length > 0) {
    return `${event}_${subscriptionId}`;
  }
  const digest = await sha256Hex(rawBody);
  return `${event}_${digest}`;
}
