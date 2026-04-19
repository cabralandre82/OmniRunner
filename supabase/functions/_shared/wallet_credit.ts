/**
 * Canonical wallet-credit helper for Supabase Edge Functions (L18-08).
 *
 * Why this exists
 * ───────────────
 *   Both Route Handlers (portal/.../route.ts) and Edge Functions
 *   (supabase/functions/.../index.ts) mutate user wallets, but until
 *   L18-08 the Edge Function path was a copy-pasted bag of ad-hoc
 *   `.rpc("fn_increment_wallets_batch", { p_entries: ... })` calls
 *   with no shared validation or error mapping. The result was three
 *   classes of subtle bug:
 *
 *     1. **Schema mismatch** — `fn_increment_wallets_batch` was last
 *        touched by the L18-01 wallet-mutation-guard migration, which
 *        ALSO retained the legacy `created_at` (timestamptz) column in
 *        its INSERT. After L19-01 partitioned `coin_ledger`,
 *        `created_at_ms` (bigint) became NOT NULL with no default; the
 *        next caller in a fresh schema would have failed with
 *        `null value in column "created_at_ms"`. Fixed in
 *        20260419140000_l18_canonical_wallet_credit.sql.
 *
 *     2. **Caller drift** — settle-challenge, challenge-withdraw, and
 *        any future caller each shaped their entry payload differently
 *        (some passed `group_id`, others `issuer_group_id`, others
 *        nothing). Without a typed contract, a typo on the caller side
 *        silently dropped the field on the floor (jsonb extraction
 *        returns NULL for missing keys; the RPC happily ignored it).
 *
 *     3. **Error opacity** — every caller wrote its own try/catch
 *        around the RPC and decided whether to log, fail closed, or
 *        return 500. There was no standard mapping from PG error code
 *        to result type, so two functions could disagree on whether
 *        the same RPC failure was retryable or terminal.
 *
 * Design
 * ──────
 *   • A single typed entry-point: `creditWallets(adminDb, entries, ctx)`.
 *   • Pre-flight validation (shape + UUIDs + non-zero deltas + reason
 *     allowlist) before any RPC roundtrip — fail-fast saves a network
 *     round trip and produces a typed error the caller can branch on.
 *   • Structured JSON log per call (one line, parseable by the
 *     existing log-shipper) with `request_id`, `fn`, `entry_count`,
 *     `total_delta`, `outcome`, and (on failure) `pg_code` + `pg_msg`.
 *   • Returns a discriminated-union result `{ ok: true, processed }`
 *     or `{ ok: false, code, message, details? }` — callers unwrap and
 *     respond with their own HTTP shape (this helper is transport-
 *     agnostic).
 *
 *   The L18-01 trigger guard remains the source of truth at the DB
 *   layer: any direct UPDATE to `wallets.balance_coins` from this
 *   helper would be rejected with `WALLET_MUTATION_FORBIDDEN` (P0007).
 *   This helper exists to make the "right thing" (route → RPC → trigger)
 *   the obvious thing on the Edge Function side.
 */

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

/**
 * One row in a batch. `delta` is the net coin movement for `user_id`:
 *
 *   • positive → credit (e.g. challenge prize, refund)
 *   • negative → debit  (e.g. challenge entry-fee, slashing)
 *
 * `ref_id` is the canonical correlation key (challenge.id, swap.id,
 * etc.) — written verbatim into `coin_ledger.ref_id` (TEXT post-L19-01).
 * `issuer_group_id` is OPTIONAL and used for issuer attribution when
 * the credit comes from a coaching group's pool; when absent (most
 * settlement payouts) the ledger row carries NULL there.
 */
export interface WalletCreditEntry {
  user_id: string;
  delta: number;
  reason: string;
  ref_id?: string | null;
  issuer_group_id?: string | null;
}

export interface WalletCreditContext {
  request_id: string;
  fn: string;
  /** Optional free-form metadata merged into the structured log line. */
  meta?: Record<string, unknown>;
}

export type WalletCreditResult =
  | { ok: true; processed: number }
  | {
      ok: false;
      code: WalletCreditErrorCode;
      message: string;
      details?: Record<string, unknown>;
    };

export type WalletCreditErrorCode =
  | "EMPTY_BATCH"
  | "INVALID_ENTRY"
  | "INVALID_USER_ID"
  | "INVALID_DELTA"
  | "INVALID_REASON"
  | "INVALID_REF_ID"
  | "INVALID_ISSUER_GROUP"
  | "RPC_ERROR";

// ─────────────────────────────────────────────────────────────────────────────
// Validation primitives
// ─────────────────────────────────────────────────────────────────────────────

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/**
 * Reasons the wallet-credit path is allowed to record. Mirrors the
 * `coin_ledger_reason_check` CHECK constraint added by L19-01 — keeping
 * the allowlist client-side too means a typo fails before hitting the
 * RPC (cheaper round-trip and clearer error).
 *
 * Add a new reason here AND in the SQL CHECK constraint in lockstep.
 */
export const ALLOWED_REASONS = new Set<string>([
  "batch_credit",
  "challenge_entry_fee",
  "challenge_entry_refund",
  "challenge_withdrawal_refund",
  "challenge_one_vs_one_won",
  "challenge_one_vs_one_completed",
  "challenge_team_won",
  "challenge_group_completed",
  "admin_adjustment",
]);

export function isValidUuid(v: unknown): v is string {
  return typeof v === "string" && UUID_RE.test(v);
}

/**
 * Validate one entry shape WITHOUT doing the network call. Returns null
 * on success or a typed error code with a human message on failure.
 * Indices are 0-based for log readability.
 */
export function validateEntry(
  entry: unknown,
  index: number,
):
  | null
  | {
      code: Extract<
        WalletCreditErrorCode,
        | "INVALID_ENTRY"
        | "INVALID_USER_ID"
        | "INVALID_DELTA"
        | "INVALID_REASON"
        | "INVALID_REF_ID"
        | "INVALID_ISSUER_GROUP"
      >;
      message: string;
    } {
  if (entry === null || typeof entry !== "object") {
    return {
      code: "INVALID_ENTRY",
      message: `entry[${index}] is not an object`,
    };
  }
  const e = entry as Record<string, unknown>;

  if (!isValidUuid(e.user_id)) {
    return {
      code: "INVALID_USER_ID",
      message: `entry[${index}].user_id must be a UUID`,
    };
  }

  if (
    typeof e.delta !== "number" ||
    !Number.isInteger(e.delta) ||
    e.delta === 0
  ) {
    return {
      code: "INVALID_DELTA",
      message: `entry[${index}].delta must be a non-zero integer`,
    };
  }

  if (typeof e.reason !== "string" || e.reason.length === 0) {
    return {
      code: "INVALID_REASON",
      message: `entry[${index}].reason must be a non-empty string`,
    };
  }
  if (!ALLOWED_REASONS.has(e.reason)) {
    return {
      code: "INVALID_REASON",
      message: `entry[${index}].reason "${e.reason}" not in ALLOWED_REASONS`,
    };
  }

  // ref_id is optional but, when present, must be a non-empty string
  // (the column is text in coin_ledger). We don't enforce UUID shape
  // here — composite keys like 'idem:user:nonce' are valid by design.
  if (e.ref_id !== undefined && e.ref_id !== null) {
    if (
      typeof e.ref_id !== "string" ||
      e.ref_id.length === 0 ||
      e.ref_id.length > 200
    ) {
      return {
        code: "INVALID_REF_ID",
        message: `entry[${index}].ref_id must be a non-empty string ≤ 200 chars`,
      };
    }
  }

  if (e.issuer_group_id !== undefined && e.issuer_group_id !== null) {
    if (!isValidUuid(e.issuer_group_id)) {
      return {
        code: "INVALID_ISSUER_GROUP",
        message: `entry[${index}].issuer_group_id must be a UUID when present`,
      };
    }
  }

  return null;
}

/**
 * Validate the full batch. Returns null on success or the FIRST
 * problem it found (callers get one clear error rather than a wall).
 */
export function validateBatch(
  entries: unknown[],
):
  | null
  | { code: WalletCreditErrorCode; message: string; details?: Record<string, unknown> } {
  if (!Array.isArray(entries) || entries.length === 0) {
    return {
      code: "EMPTY_BATCH",
      message: "creditWallets called with empty or non-array entries",
    };
  }
  for (let i = 0; i < entries.length; i++) {
    const err = validateEntry(entries[i], i);
    if (err) return { ...err, details: { index: i } };
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Public entry point
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Minimal client surface this helper uses — enables clean unit tests.
 *
 * Note: supabase-js `rpc()` returns a `PostgrestFilterBuilder` which is
 * a thenable rather than a strict `Promise`. We type the return as
 * `PromiseLike` so both real `SupabaseClient` instances AND test mocks
 * satisfy the interface.
 */
// deno-lint-ignore no-explicit-any
export type WalletCreditRpcResult = PromiseLike<{ data: any; error: any }>;
export interface WalletCreditClient {
  rpc(fn: string, params: Record<string, unknown>): WalletCreditRpcResult;
}

/** Optional logger interface — defaults to console.log/console.error. */
export interface WalletCreditLogger {
  info: (line: string) => void;
  error: (line: string) => void;
}

const defaultLogger: WalletCreditLogger = {
  info: (line) => console.log(line),
  error: (line) => console.error(line),
};

/**
 * Credit (or debit, with negative deltas) a batch of wallets through
 * the canonical `fn_increment_wallets_batch` RPC. The RPC sets the
 * L18-01 wallet-mutation-guard GUC and pairs each wallet UPDATE with
 * a `coin_ledger` INSERT in the same transaction.
 *
 * On any pre-flight validation failure NO RPC call is made.
 *
 * On RPC error the result carries the PG SQLSTATE in `details.pg_code`
 * so the caller can branch (e.g. retry on lock_not_available, fail
 * closed on others). The structured log line includes the same fields
 * so post-mortem grep-by-request-id is trivial.
 */
export async function creditWallets(
  client: WalletCreditClient,
  entries: WalletCreditEntry[],
  ctx: WalletCreditContext,
  logger: WalletCreditLogger = defaultLogger,
): Promise<WalletCreditResult> {
  const validation = validateBatch(entries);
  if (validation) {
    logger.error(
      JSON.stringify({
        request_id: ctx.request_id,
        fn: ctx.fn,
        event: "wallet_credit.validation_failed",
        code: validation.code,
        message: validation.message,
        details: validation.details ?? null,
        ...ctx.meta,
      }),
    );
    return { ok: false, ...validation };
  }

  const totalDelta = entries.reduce((s, e) => s + e.delta, 0);

  const { data, error } = await client.rpc("fn_increment_wallets_batch", {
    p_entries: entries.map((e) => ({
      user_id: e.user_id,
      delta: e.delta,
      reason: e.reason,
      ref_id: e.ref_id ?? null,
      issuer_group_id: e.issuer_group_id ?? null,
    })),
  });

  if (error) {
    logger.error(
      JSON.stringify({
        request_id: ctx.request_id,
        fn: ctx.fn,
        event: "wallet_credit.rpc_failed",
        entry_count: entries.length,
        total_delta: totalDelta,
        pg_code: error.code ?? null,
        pg_msg: error.message ?? String(error),
        ...ctx.meta,
      }),
    );
    return {
      ok: false,
      code: "RPC_ERROR",
      message: error.message ?? "wallet credit RPC failed",
      details: {
        pg_code: error.code ?? null,
        entry_count: entries.length,
      },
    };
  }

  const processed =
    typeof data === "number" ? data : Number(data ?? entries.length);

  logger.info(
    JSON.stringify({
      request_id: ctx.request_id,
      fn: ctx.fn,
      event: "wallet_credit.ok",
      entry_count: entries.length,
      processed,
      total_delta: totalDelta,
      ...ctx.meta,
    }),
  );

  return { ok: true, processed };
}
