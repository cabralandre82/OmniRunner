/**
 * Unit tests for asaas_webhook_auth.ts (L01-18).
 *
 * Run with:
 *   deno test --allow-none supabase/functions/_shared/asaas_webhook_auth.test.ts
 *
 * Or via CI step (see .github/workflows/supabase.yml — `deno test`).
 *
 * No DB / network access — pure helpers.
 */

import {
  assertEquals,
  assertNotEquals,
  assertRejects,
  assertStrictEquals,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

import {
  ASAAS_SIGNATURE_HEADER,
  ASAAS_TOKEN_HEADER,
  computeAsaasIdempotencyKey,
  hmacSha256Hex,
  MIN_TOKEN_LENGTH,
  safeEq,
  sha256Hex,
  verifyAsaasWebhookAuth,
} from "./asaas_webhook_auth.ts";

// Realistic-shaped inputs reused across tests
const VALID_TOKEN = "vault_token_3f8c2e9b1d4a7f60_xyz"; // 35 chars
const RAW_BODY = JSON.stringify({
  event: "PAYMENT_RECEIVED",
  payment: { id: "pay_abc123", value: 49.9 },
});

// ─────────────────────────────────────────────────────────────────────────────
// Constants exposed
// ─────────────────────────────────────────────────────────────────────────────

Deno.test("constants — header names are lowercase", () => {
  assertEquals(ASAAS_TOKEN_HEADER, "asaas-access-token");
  assertEquals(ASAAS_SIGNATURE_HEADER, "asaas-signature");
});

Deno.test("constants — MIN_TOKEN_LENGTH gates against weak vault entries", () => {
  assertEquals(MIN_TOKEN_LENGTH, 16);
});

// ─────────────────────────────────────────────────────────────────────────────
// safeEq
// ─────────────────────────────────────────────────────────────────────────────

Deno.test("safeEq — equal strings → true", () => {
  assertEquals(safeEq("abcdef", "abcdef"), true);
});

Deno.test("safeEq — different lengths → false", () => {
  assertEquals(safeEq("abc", "abcd"), false);
});

Deno.test("safeEq — same length, last byte differs → false", () => {
  assertEquals(safeEq("abcdef", "abcdez"), false);
});

Deno.test("safeEq — same length, first byte differs → false", () => {
  assertEquals(safeEq("abcdef", "zbcdef"), false);
});

Deno.test("safeEq — empty strings → true (defensive: caller MUST guard)", () => {
  // verifyAsaasWebhookAuth never reaches safeEq with empty inputs because
  // we check missing_token first; documenting behavior either way.
  assertEquals(safeEq("", ""), true);
});

Deno.test("safeEq — non-string input → false", () => {
  assertEquals(safeEq(null as unknown as string, "abc"), false);
  assertEquals(safeEq("abc", undefined as unknown as string), false);
});

Deno.test("safeEq — UTF-8 multi-byte equality", () => {
  assertEquals(safeEq("café", "café"), true);
  assertEquals(safeEq("café", "cafe"), false); // different lengths in bytes
});

// ─────────────────────────────────────────────────────────────────────────────
// sha256Hex
// ─────────────────────────────────────────────────────────────────────────────

Deno.test("sha256Hex — known vector for empty string", async () => {
  // Standard SHA-256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
  const got = await sha256Hex("");
  assertEquals(
    got,
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  );
});

Deno.test("sha256Hex — known vector for 'abc'", async () => {
  // Standard SHA-256("abc") = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
  const got = await sha256Hex("abc");
  assertEquals(
    got,
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  );
});

Deno.test("sha256Hex — output is 64-char lowercase hex", async () => {
  const got = await sha256Hex("anything");
  assertEquals(got.length, 64);
  assertEquals(got, got.toLowerCase());
  assertEquals(/^[0-9a-f]{64}$/.test(got), true);
});

Deno.test("sha256Hex — different prefixes do NOT collide (anti-slice)", async () => {
  // The original code used JSON.stringify(payload).slice(0,64). Two payloads
  // sharing a 64-char prefix collided. With sha256Hex they MUST differ.
  const a = '{"event":"PAYMENT_RECEIVED","payment":{"id":"pay_a","value":1}}';
  const b = '{"event":"PAYMENT_RECEIVED","payment":{"id":"pay_b","value":1}}';
  const ha = await sha256Hex(a);
  const hb = await sha256Hex(b);
  assertNotEquals(ha, hb);
});

// ─────────────────────────────────────────────────────────────────────────────
// hmacSha256Hex
// ─────────────────────────────────────────────────────────────────────────────

Deno.test("hmacSha256Hex — RFC 4231 test case 1", async () => {
  // key=0x0b * 20, body="Hi There" → expected 4-tuple from RFC 4231 section 4.2
  const key = "\x0b".repeat(20);
  const got = await hmacSha256Hex(key, "Hi There");
  assertEquals(
    got,
    "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
  );
});

Deno.test("hmacSha256Hex — different key → different signature", async () => {
  const a = await hmacSha256Hex("secret-a", "payload");
  const b = await hmacSha256Hex("secret-b", "payload");
  assertNotEquals(a, b);
});

Deno.test("hmacSha256Hex — different body → different signature", async () => {
  const a = await hmacSha256Hex("secret", "payload-a");
  const b = await hmacSha256Hex("secret", "payload-b");
  assertNotEquals(a, b);
});

// ─────────────────────────────────────────────────────────────────────────────
// verifyAsaasWebhookAuth — token-only path (legacy / current Asaas behavior)
// ─────────────────────────────────────────────────────────────────────────────

Deno.test("verifyAsaasWebhookAuth — happy path: token matches, no signature", async () => {
  const r = await verifyAsaasWebhookAuth({
    incomingToken: VALID_TOKEN,
    incomingSignature: null,
    storedToken: VALID_TOKEN,
    rawBody: RAW_BODY,
  });
  assertEquals(r.ok, true);
  assertEquals(r.signatureVerified, false);
  assertStrictEquals(r.reason, undefined);
});

Deno.test("verifyAsaasWebhookAuth — missing incoming token rejected", async () => {
  const r = await verifyAsaasWebhookAuth({
    incomingToken: null,
    incomingSignature: null,
    storedToken: VALID_TOKEN,
    rawBody: RAW_BODY,
  });
  assertEquals(r.ok, false);
  assertEquals(r.reason, "missing_token");
});

Deno.test("verifyAsaasWebhookAuth — empty incoming token rejected", async () => {
  const r = await verifyAsaasWebhookAuth({
    incomingToken: "",
    incomingSignature: null,
    storedToken: VALID_TOKEN,
    rawBody: RAW_BODY,
  });
  assertEquals(r.ok, false);
  assertEquals(r.reason, "missing_token");
});

Deno.test("verifyAsaasWebhookAuth — missing stored token rejected (no group config)", async () => {
  const r = await verifyAsaasWebhookAuth({
    incomingToken: VALID_TOKEN,
    incomingSignature: null,
    storedToken: null,
    rawBody: RAW_BODY,
  });
  assertEquals(r.ok, false);
  assertEquals(r.reason, "missing_stored_token");
});

Deno.test("verifyAsaasWebhookAuth — weak stored token rejected (≥ 16 chars)", async () => {
  const weak = "short_token_123"; // 15 chars
  const r = await verifyAsaasWebhookAuth({
    incomingToken: weak,
    incomingSignature: null,
    storedToken: weak,
    rawBody: RAW_BODY,
  });
  assertEquals(r.ok, false);
  assertEquals(r.reason, "weak_stored_token");
});

Deno.test("verifyAsaasWebhookAuth — token mismatch rejected", async () => {
  const r = await verifyAsaasWebhookAuth({
    incomingToken: "x".repeat(VALID_TOKEN.length),
    incomingSignature: null,
    storedToken: VALID_TOKEN,
    rawBody: RAW_BODY,
  });
  assertEquals(r.ok, false);
  assertEquals(r.reason, "token_mismatch");
});

Deno.test("verifyAsaasWebhookAuth — token mismatch on length difference rejected", async () => {
  const r = await verifyAsaasWebhookAuth({
    incomingToken: VALID_TOKEN + "_extra",
    incomingSignature: null,
    storedToken: VALID_TOKEN,
    rawBody: RAW_BODY,
  });
  assertEquals(r.ok, false);
  assertEquals(r.reason, "token_mismatch");
});

// ─────────────────────────────────────────────────────────────────────────────
// verifyAsaasWebhookAuth — HMAC signature path (forward-compat)
// ─────────────────────────────────────────────────────────────────────────────

Deno.test("verifyAsaasWebhookAuth — token + valid signature → ok + signatureVerified=true", async () => {
  const sig = await hmacSha256Hex(VALID_TOKEN, RAW_BODY);
  const r = await verifyAsaasWebhookAuth({
    incomingToken: VALID_TOKEN,
    incomingSignature: sig,
    storedToken: VALID_TOKEN,
    rawBody: RAW_BODY,
  });
  assertEquals(r.ok, true);
  assertEquals(r.signatureVerified, true);
});

Deno.test("verifyAsaasWebhookAuth — uppercase signature accepted (case-insensitive)", async () => {
  const sig = (await hmacSha256Hex(VALID_TOKEN, RAW_BODY)).toUpperCase();
  const r = await verifyAsaasWebhookAuth({
    incomingToken: VALID_TOKEN,
    incomingSignature: sig,
    storedToken: VALID_TOKEN,
    rawBody: RAW_BODY,
  });
  assertEquals(r.ok, true);
  assertEquals(r.signatureVerified, true);
});

Deno.test("verifyAsaasWebhookAuth — token ok but signature INVALID → fail-closed", async () => {
  const r = await verifyAsaasWebhookAuth({
    incomingToken: VALID_TOKEN,
    incomingSignature: "deadbeef".repeat(8),
    storedToken: VALID_TOKEN,
    rawBody: RAW_BODY,
  });
  assertEquals(r.ok, false);
  assertEquals(r.reason, "signature_invalid");
});

Deno.test("verifyAsaasWebhookAuth — body tampered after signing → invalid", async () => {
  const sig = await hmacSha256Hex(VALID_TOKEN, RAW_BODY);
  const tamperedBody = RAW_BODY.replace("49.9", "49999");
  const r = await verifyAsaasWebhookAuth({
    incomingToken: VALID_TOKEN,
    incomingSignature: sig,
    storedToken: VALID_TOKEN,
    rawBody: tamperedBody,
  });
  assertEquals(r.ok, false);
  assertEquals(r.reason, "signature_invalid");
});

// ─────────────────────────────────────────────────────────────────────────────
// computeAsaasIdempotencyKey
// ─────────────────────────────────────────────────────────────────────────────

Deno.test("computeAsaasIdempotencyKey — paymentId preferred over subscriptionId", async () => {
  const got = await computeAsaasIdempotencyKey({
    event: "PAYMENT_RECEIVED",
    paymentId: "pay_abc",
    subscriptionId: "sub_xyz",
    rawBody: RAW_BODY,
  });
  assertEquals(got, "PAYMENT_RECEIVED_pay_abc");
});

Deno.test("computeAsaasIdempotencyKey — subscriptionId fallback when no paymentId", async () => {
  const got = await computeAsaasIdempotencyKey({
    event: "SUBSCRIPTION_INACTIVATED",
    paymentId: null,
    subscriptionId: "sub_xyz",
    rawBody: RAW_BODY,
  });
  assertEquals(got, "SUBSCRIPTION_INACTIVATED_sub_xyz");
});

Deno.test("computeAsaasIdempotencyKey — sha256 fallback when neither id present", async () => {
  const got = await computeAsaasIdempotencyKey({
    event: "PAYMENT_RECEIVED",
    paymentId: null,
    subscriptionId: null,
    rawBody: RAW_BODY,
  });
  // event_<64 hex chars>
  const re = /^PAYMENT_RECEIVED_[0-9a-f]{64}$/;
  assertEquals(re.test(got), true, `got=${got}`);
});

Deno.test("computeAsaasIdempotencyKey — sha256 fallback differs for distinct payloads", async () => {
  const a = await computeAsaasIdempotencyKey({
    event: "PAYMENT_RECEIVED",
    paymentId: null,
    subscriptionId: null,
    rawBody: '{"event":"PAYMENT_RECEIVED","payment":{"id":"pay_a","value":1}}',
  });
  const b = await computeAsaasIdempotencyKey({
    event: "PAYMENT_RECEIVED",
    paymentId: null,
    subscriptionId: null,
    rawBody: '{"event":"PAYMENT_RECEIVED","payment":{"id":"pay_b","value":1}}',
  });
  assertNotEquals(a, b);
});

Deno.test("computeAsaasIdempotencyKey — empty event throws", async () => {
  await assertRejects(
    () =>
      computeAsaasIdempotencyKey({
        event: "",
        paymentId: "pay_abc",
        subscriptionId: null,
        rawBody: RAW_BODY,
      }),
    Error,
    "event_required",
  );
});

Deno.test("computeAsaasIdempotencyKey — empty paymentId treated as missing (sha fallback)", async () => {
  const got = await computeAsaasIdempotencyKey({
    event: "PAYMENT_RECEIVED",
    paymentId: "",
    subscriptionId: "sub_xyz",
    rawBody: RAW_BODY,
  });
  assertEquals(got, "PAYMENT_RECEIVED_sub_xyz");
});
