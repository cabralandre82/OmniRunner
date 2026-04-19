/**
 * Tests for `_shared/wallet_credit.ts` (L18-08).
 *
 * Covers:
 *   • validateEntry: every typed-error branch + happy paths
 *   • validateBatch: empty + first-error semantics
 *   • creditWallets: validation short-circuit (no RPC), RPC happy
 *     path, RPC error path with structured logging
 *   • Logging: structured JSON line per outcome
 *
 * No DB / network dependencies — uses an in-memory `WalletCreditClient`
 * mock and an in-memory logger. Run with `deno test`.
 */

import {
  assert,
  assertEquals,
  assertObjectMatch,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  ALLOWED_REASONS,
  creditWallets,
  isValidUuid,
  validateBatch,
  validateEntry,
  type WalletCreditClient,
  type WalletCreditEntry,
  type WalletCreditLogger,
} from "./wallet_credit.ts";

// ─────────────────────────────────────────────────────────────────────────────
// Test fixtures
// ─────────────────────────────────────────────────────────────────────────────

const VALID_UUID = "11111111-1111-4111-8111-111111111111";
const ANOTHER_UUID = "22222222-2222-4222-8222-222222222222";
const ISSUER_UUID = "33333333-3333-4333-8333-333333333333";
const REQUEST_ID = "req-abc-123";
const FN_NAME = "settle-challenge-test";

function makeEntry(
  overrides: Partial<WalletCreditEntry> = {},
): WalletCreditEntry {
  return {
    user_id: VALID_UUID,
    delta: 100,
    reason: "challenge_one_vs_one_won",
    ref_id: "challenge:abc",
    ...overrides,
  };
}

function captureLogger(): {
  logger: WalletCreditLogger;
  info: string[];
  error: string[];
} {
  const info: string[] = [];
  const error: string[] = [];
  return {
    info,
    error,
    logger: {
      info: (line) => info.push(line),
      error: (line) => error.push(line),
    },
  };
}

// deno-lint-ignore no-explicit-any
function makeClient(impl: (params: Record<string, unknown>) => { data: any; error: any }): WalletCreditClient {
  return {
    rpc(fn, params) {
      assertEquals(fn, "fn_increment_wallets_batch", "RPC name canonical");
      return Promise.resolve(impl(params));
    },
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// isValidUuid
// ─────────────────────────────────────────────────────────────────────────────

Deno.test("isValidUuid: accepts canonical v4 UUIDs", () => {
  assert(isValidUuid(VALID_UUID));
  assert(isValidUuid("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"));
});

Deno.test("isValidUuid: rejects non-string + malformed", () => {
  assert(!isValidUuid(null));
  assert(!isValidUuid(undefined));
  assert(!isValidUuid(""));
  assert(!isValidUuid("not-a-uuid"));
  assert(!isValidUuid("11111111111111114111811111111111")); // missing dashes
  assert(!isValidUuid(123));
  assert(!isValidUuid({}));
});

// ─────────────────────────────────────────────────────────────────────────────
// validateEntry
// ─────────────────────────────────────────────────────────────────────────────

Deno.test("validateEntry: happy path returns null", () => {
  assertEquals(validateEntry(makeEntry(), 0), null);
});

Deno.test("validateEntry: rejects non-object", () => {
  const err = validateEntry("nope", 0);
  assert(err);
  assertEquals(err.code, "INVALID_ENTRY");
});

Deno.test("validateEntry: rejects null", () => {
  const err = validateEntry(null, 0);
  assert(err);
  assertEquals(err.code, "INVALID_ENTRY");
});

Deno.test("validateEntry: rejects bad user_id", () => {
  const err = validateEntry(makeEntry({ user_id: "garbage" }), 0);
  assert(err);
  assertEquals(err.code, "INVALID_USER_ID");
});

Deno.test("validateEntry: rejects zero delta", () => {
  const err = validateEntry(makeEntry({ delta: 0 }), 0);
  assert(err);
  assertEquals(err.code, "INVALID_DELTA");
});

Deno.test("validateEntry: rejects non-integer delta", () => {
  const err = validateEntry(makeEntry({ delta: 1.5 }), 0);
  assert(err);
  assertEquals(err.code, "INVALID_DELTA");
});

Deno.test("validateEntry: accepts negative delta (debits allowed)", () => {
  assertEquals(
    validateEntry(makeEntry({ delta: -50, reason: "challenge_entry_fee" }), 0),
    null,
  );
});

Deno.test("validateEntry: rejects empty reason", () => {
  const err = validateEntry(makeEntry({ reason: "" }), 0);
  assert(err);
  assertEquals(err.code, "INVALID_REASON");
});

Deno.test("validateEntry: rejects reason not in allowlist", () => {
  const err = validateEntry(
    makeEntry({ reason: "magic_money_printer" }),
    0,
  );
  assert(err);
  assertEquals(err.code, "INVALID_REASON");
});

Deno.test("validateEntry: ref_id null/undefined are accepted (optional)", () => {
  assertEquals(validateEntry(makeEntry({ ref_id: null }), 0), null);
  assertEquals(validateEntry(makeEntry({ ref_id: undefined }), 0), null);
});

Deno.test("validateEntry: ref_id empty string is REJECTED", () => {
  const err = validateEntry(makeEntry({ ref_id: "" }), 0);
  assert(err);
  assertEquals(err.code, "INVALID_REF_ID");
});

Deno.test("validateEntry: ref_id over 200 chars is REJECTED", () => {
  const err = validateEntry(makeEntry({ ref_id: "x".repeat(201) }), 0);
  assert(err);
  assertEquals(err.code, "INVALID_REF_ID");
});

Deno.test("validateEntry: ref_id non-UUID strings ARE accepted (composite keys)", () => {
  // Key insight: ref_id is TEXT in coin_ledger; non-UUID composite keys
  // like 'idem:user:nonce' are valid by design (covered by L18-02).
  assertEquals(
    validateEntry(makeEntry({ ref_id: "idem:abc:42" }), 0),
    null,
  );
});

Deno.test("validateEntry: issuer_group_id rejected when malformed", () => {
  const err = validateEntry(makeEntry({ issuer_group_id: "not-uuid" }), 0);
  assert(err);
  assertEquals(err.code, "INVALID_ISSUER_GROUP");
});

Deno.test("validateEntry: issuer_group_id valid UUID accepted", () => {
  assertEquals(
    validateEntry(makeEntry({ issuer_group_id: ISSUER_UUID }), 0),
    null,
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// validateBatch
// ─────────────────────────────────────────────────────────────────────────────

Deno.test("validateBatch: empty array rejected with EMPTY_BATCH", () => {
  const err = validateBatch([]);
  assert(err);
  assertEquals(err.code, "EMPTY_BATCH");
});

Deno.test("validateBatch: non-array rejected with EMPTY_BATCH", () => {
  const err = validateBatch("not-an-array" as unknown as unknown[]);
  assert(err);
  assertEquals(err.code, "EMPTY_BATCH");
});

Deno.test("validateBatch: returns FIRST error with index in details", () => {
  const err = validateBatch([
    makeEntry(),
    makeEntry({ delta: 0 }),
    makeEntry({ user_id: "bad" }),
  ]);
  assert(err);
  assertEquals(err.code, "INVALID_DELTA");
  assertEquals(err.details, { index: 1 });
});

Deno.test("validateBatch: happy path returns null for all-valid batch", () => {
  assertEquals(
    validateBatch([
      makeEntry({ user_id: VALID_UUID, delta: 50 }),
      makeEntry({ user_id: ANOTHER_UUID, delta: -25, reason: "challenge_entry_fee" }),
    ]),
    null,
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// creditWallets — validation short-circuit
// ─────────────────────────────────────────────────────────────────────────────

Deno.test("creditWallets: validation failure does NOT call RPC", async () => {
  let rpcCalled = false;
  const client: WalletCreditClient = {
    rpc() {
      rpcCalled = true;
      return Promise.resolve({ data: null, error: null });
    },
  };
  const { logger, error } = captureLogger();

  const result = await creditWallets(
    client,
    [makeEntry({ delta: 0 })],
    { request_id: REQUEST_ID, fn: FN_NAME },
    logger,
  );

  assert(!rpcCalled, "validation failure must short-circuit RPC");
  assert(!result.ok);
  if (!result.ok) {
    assertEquals(result.code, "INVALID_DELTA");
  }
  assertEquals(error.length, 1, "exactly one error log line");
  const parsed = JSON.parse(error[0]);
  assertObjectMatch(parsed, {
    request_id: REQUEST_ID,
    fn: FN_NAME,
    event: "wallet_credit.validation_failed",
    code: "INVALID_DELTA",
  });
});

Deno.test("creditWallets: empty batch rejected with EMPTY_BATCH", async () => {
  const client = makeClient(() => ({ data: null, error: null }));
  const { logger } = captureLogger();
  const result = await creditWallets(client, [], { request_id: REQUEST_ID, fn: FN_NAME }, logger);
  assert(!result.ok);
  if (!result.ok) assertEquals(result.code, "EMPTY_BATCH");
});

// ─────────────────────────────────────────────────────────────────────────────
// creditWallets — happy path
// ─────────────────────────────────────────────────────────────────────────────

Deno.test("creditWallets: happy path forwards canonical RPC payload", async () => {
  let captured: Record<string, unknown> | null = null;
  const client = makeClient((params) => {
    captured = params as Record<string, unknown>;
    return { data: 2, error: null };
  });
  const { logger, info } = captureLogger();

  const entries: WalletCreditEntry[] = [
    {
      user_id: VALID_UUID,
      delta: 100,
      reason: "challenge_one_vs_one_won",
      ref_id: "challenge:abc",
    },
    {
      user_id: ANOTHER_UUID,
      delta: -25,
      reason: "challenge_entry_fee",
      ref_id: "challenge:xyz",
      issuer_group_id: ISSUER_UUID,
    },
  ];

  const result = await creditWallets(
    client,
    entries,
    { request_id: REQUEST_ID, fn: FN_NAME, meta: { challenge_id: "ch-1" } },
    logger,
  );

  assert(result.ok);
  if (result.ok) assertEquals(result.processed, 2);

  // RPC payload shape
  assert(captured);
  const cap = captured as Record<string, unknown>;
  const sent = cap.p_entries as Array<Record<string, unknown>>;
  assertEquals(sent.length, 2);
  assertEquals(sent[0].user_id, VALID_UUID);
  assertEquals(sent[0].delta, 100);
  assertEquals(sent[0].reason, "challenge_one_vs_one_won");
  assertEquals(sent[0].ref_id, "challenge:abc");
  assertEquals(sent[0].issuer_group_id, null, "missing issuer becomes null");
  assertEquals(sent[1].issuer_group_id, ISSUER_UUID);

  // Structured log line
  assertEquals(info.length, 1);
  const line = JSON.parse(info[0]);
  assertObjectMatch(line, {
    request_id: REQUEST_ID,
    fn: FN_NAME,
    event: "wallet_credit.ok",
    entry_count: 2,
    processed: 2,
    total_delta: 75,
    challenge_id: "ch-1",
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// creditWallets — RPC error path
// ─────────────────────────────────────────────────────────────────────────────

Deno.test("creditWallets: RPC error returns RPC_ERROR with pg_code", async () => {
  const client = makeClient(() => ({
    data: null,
    error: {
      code: "55P03",
      message: "lock_not_available: row blocked",
    },
  }));
  const { logger, error } = captureLogger();

  const result = await creditWallets(
    client,
    [makeEntry()],
    { request_id: REQUEST_ID, fn: FN_NAME },
    logger,
  );

  assert(!result.ok);
  if (!result.ok) {
    assertEquals(result.code, "RPC_ERROR");
    assert(result.message.includes("lock_not_available"));
    assertEquals((result.details as { pg_code: string }).pg_code, "55P03");
    assertEquals((result.details as { entry_count: number }).entry_count, 1);
  }

  assertEquals(error.length, 1);
  const parsed = JSON.parse(error[0]);
  assertObjectMatch(parsed, {
    request_id: REQUEST_ID,
    fn: FN_NAME,
    event: "wallet_credit.rpc_failed",
    pg_code: "55P03",
  });
});

Deno.test("creditWallets: RPC error WITHOUT code still surfaces gracefully", async () => {
  const client = makeClient(() => ({
    data: null,
    error: { message: "network blip" },
  }));
  const { logger } = captureLogger();
  const result = await creditWallets(
    client,
    [makeEntry()],
    { request_id: REQUEST_ID, fn: FN_NAME },
    logger,
  );
  assert(!result.ok);
  if (!result.ok) {
    assertEquals(result.code, "RPC_ERROR");
    assertEquals((result.details as { pg_code: string | null }).pg_code, null);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// creditWallets — defensive contract checks
// ─────────────────────────────────────────────────────────────────────────────

Deno.test("creditWallets: RPC returning non-number data still yields processed", async () => {
  // Defensive — supabase-js typing returns `data` as the function's
  // declared return; we coerce to number with fallback to entry_count.
  const client = makeClient(() => ({ data: null, error: null }));
  const { logger } = captureLogger();
  const result = await creditWallets(
    client,
    [makeEntry(), makeEntry({ user_id: ANOTHER_UUID })],
    { request_id: REQUEST_ID, fn: FN_NAME },
    logger,
  );
  assert(result.ok);
  if (result.ok) assertEquals(result.processed, 2);
});

// ─────────────────────────────────────────────────────────────────────────────
// ALLOWED_REASONS exposed
// ─────────────────────────────────────────────────────────────────────────────

Deno.test("ALLOWED_REASONS: includes the three settle-challenge reasons", () => {
  assert(ALLOWED_REASONS.has("challenge_one_vs_one_won"));
  assert(ALLOWED_REASONS.has("challenge_team_won"));
  assert(ALLOWED_REASONS.has("challenge_group_completed"));
});

Deno.test("ALLOWED_REASONS: includes refund reasons used by withdrawal/settle", () => {
  assert(ALLOWED_REASONS.has("challenge_entry_refund"));
  assert(ALLOWED_REASONS.has("challenge_withdrawal_refund"));
});
