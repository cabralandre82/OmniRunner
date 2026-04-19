# Wallet Mutation Guard Runbook (L18-01)

Operational guide for the wallet mutation guard + unified gateway
introduced in
`supabase/migrations/20260419130000_l18_wallet_mutation_guard.sql`.

> Audience: backend on-call + platform admins + anyone touching
> `public.wallets` from SQL or RPC code. Read time ~ 6 min.

## When to use this runbook

- A new RPC fails with **`WALLET_MUTATION_FORBIDDEN` (SQLSTATE P0007)**.
- You added a migration that mutates `wallets` directly and CI rejected it.
- An operator reports a wallet drift alert (balance ≠ ledger sum).
- You're authoring a new credit/debit code-path and need to know the
  preferred pattern.

## Architecture — 30-second recap

```
                ┌──────────────────────────────────────┐
SQL / RPC ───▶  │ trg_wallet_mutation_guard_{ins,upd}  │ ─┐
                │   (BEFORE INSERT/UPDATE on wallets)  │  │
                └──────────────────────────────────────┘  │
                                                          │
       reads `app.wallet_mutation_authorized` GUC ────────┤
                                                          │
              'yes'   ──▶ allow row through              │
              else    ──▶ RAISE EXCEPTION P0007          │
                                                          ▼
                            public.wallets
                            (balance_coins, pending_coins,
                             lifetime_earned_coins, lifetime_spent_coins)
```

- The guard fires for `UPDATE OF balance_coins, pending_coins,
  lifetime_earned_coins, lifetime_spent_coins` and for any non-zero
  `INSERT` into `wallets`.
- The signup-trigger insert (`handle_new_user`) creates a zero-balance
  row → exempted (`COALESCE(...)=0` check inside the trigger function).
- Authorisation is a **session-LOCAL GUC**: it lives only inside the
  current transaction (`is_local=true`) and rolls back on commit.
- The preferred entry-point for new code is `fn_mutate_wallet(...)`,
  which atomically inserts the ledger row, sets the GUC, and updates the
  wallet — guaranteeing the ledger/wallet pairing.

## Diagnostics

### Was a direct write blocked?

```sql
-- The error message identifies the culprit. Examples:
-- ERROR:  WALLET_MUTATION_FORBIDDEN: direct mutation of public.wallets
--         blocked. Use fn_mutate_wallet() or call an authorised RPC ...
-- SQLSTATE: P0007
SELECT pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'fn_forbid_direct_wallet_mutation';
```

### Is a wallet drifting?

```sql
-- Drift snapshot for one user
SELECT
  w.user_id,
  w.balance_coins                                AS wallet_balance,
  COALESCE(SUM(l.delta_coins), 0)                AS ledger_sum,
  w.balance_coins - COALESCE(SUM(l.delta_coins), 0) AS drift
FROM public.wallets w
LEFT JOIN public.coin_ledger l ON l.user_id = w.user_id
WHERE w.user_id = '<USER>'
GROUP BY w.user_id, w.balance_coins;

-- Top-N drifters (slow on large tables; use cron output preferentially)
SELECT
  w.user_id,
  w.balance_coins,
  COALESCE(SUM(l.delta_coins), 0) AS ledger_sum,
  w.balance_coins - COALESCE(SUM(l.delta_coins), 0) AS drift
FROM public.wallets w
LEFT JOIN public.coin_ledger l ON l.user_id = w.user_id
GROUP BY w.user_id, w.balance_coins
HAVING w.balance_coins <> COALESCE(SUM(l.delta_coins), 0)
ORDER BY ABS(w.balance_coins - COALESCE(SUM(l.delta_coins), 0)) DESC
LIMIT 50;
```

### Is the cron reconciliation healthy?

```sql
-- See cron-health runbook (L12-03) for context.
SELECT name, last_status, last_run_at, error_text
FROM public.cron_run_state
WHERE name LIKE '%reconcile%'
ORDER BY last_run_at DESC NULLS LAST;
```

## Mitigation — when a guard fires unexpectedly

### Scenario 1 — new RPC blocked by the guard

**Symptom**: `ERROR: WALLET_MUTATION_FORBIDDEN ... use fn_mutate_wallet()`
in your CI or staging logs.

**Cause**: your function does `UPDATE wallets SET balance_coins ...`
without authorising the mutation.

**Fix (preferred)**: rewrite the function to call `fn_mutate_wallet`.
Example:

```sql
-- BEFORE (will fail)
INSERT INTO public.coin_ledger (user_id, delta_coins, reason, created_at_ms)
VALUES (uid, 50, 'session_completed', t);
UPDATE public.wallets SET balance_coins = balance_coins + 50
  WHERE user_id = uid;

-- AFTER (atomic gateway)
PERFORM public.fn_mutate_wallet(
  p_user_id     => uid,
  p_delta_coins => 50,
  p_reason      => 'session_completed'
);
```

**Fix (legacy compatible)**: if rewriting is infeasible (e.g. complex
multi-step RPC like `execute_burn_atomic`), prepend the GUC inside the
function:

```sql
CREATE OR REPLACE FUNCTION public.my_legacy_rpc(...) RETURNS ... AS $$
BEGIN
  PERFORM set_config('app.wallet_mutation_authorized', 'yes', true);
  -- ... ledger INSERT + wallet UPDATE here ...
END; $$ LANGUAGE plpgsql SECURITY DEFINER;
```

The GUC scope is the **entire transaction**, so all subsequent UPDATEs
inside the same call are authorised. It rolls back on commit/abort.

### Scenario 2 — operator needs an emergency manual UPDATE

A production incident requires a one-off correction (e.g. compensating a
bug). DO NOT bypass the guard at the trigger level. Do this inside a
single transaction:

```sql
BEGIN;
SET LOCAL app.wallet_mutation_authorized = 'yes';

-- Audit trail FIRST (always)
INSERT INTO public.coin_ledger
  (user_id, delta_coins, reason, ref_id, created_at_ms)
VALUES
  ('<USER>', <DELTA>, 'admin_adjustment',
   'incident:INC-12345:operator=jane', (extract(epoch from now())*1000)::bigint);

UPDATE public.wallets
SET balance_coins = balance_coins + <DELTA>,
    updated_at    = now()
WHERE user_id = '<USER>';

COMMIT;
```

Always file a post-mortem and reference the `ref_id` so audit can trace
the manual correction.

### Scenario 3 — drift reported by reconcile

If `reconcile_wallet` reports `drift != 0` it has already fixed the
wallet (using `LEAST(SUM(ledger), wallet)` semantics in the legacy
versions, or `GREATEST(SUM(ledger), 0)` in the new one) and inserted a
zero-delta `admin_adjustment` ledger row with context in `ref_id`. Steps:

1. Find the offending RPC by binary-searching ledger writes around the
   first observed drift timestamp.
2. Confirm whether the RPC ran inside the guard (it must; otherwise the
   trigger would have raised). If it ran but skipped the ledger INSERT,
   the bug is in the RPC body — patch it to use `fn_mutate_wallet`.
3. Re-run `SELECT public.reconcile_all_wallets();` to verify drift==0
   across the fleet.

## Adding the guard pattern to a NEW route

Two paths, in order of preference:

### Preferred — go through `fn_mutate_wallet`

```typescript
// portal/src/app/api/some-route/route.ts
const { data, error } = await serviceClient.rpc("fn_mutate_wallet", {
  p_user_id:     userId,
  p_delta_coins: amount,         // positive = credit, negative = debit
  p_reason:      "challenge_pool_won",
  p_ref_id:      `challenge:${challengeId}:winner:${userId}`,
});
if (error) throw error;
const { ledger_id, new_balance } = data[0];
```

### When the gateway is not enough

(e.g. you need a multi-row burn-plan with custody side-effects). Wrap
your existing RPC in `SECURITY DEFINER` and add the GUC line:

```sql
CREATE OR REPLACE FUNCTION public.my_complex_rpc(...) RETURNS ... AS $$
BEGIN
  PERFORM set_config('app.wallet_mutation_authorized', 'yes', true);
  -- ... your custom multi-row logic ...
END; $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;
```

CI gates: `tools/test_l18_wallet_guard.ts` will catch any new direct
`UPDATE wallets SET balance_coins ...` that lacks the GUC, because the
trigger will refuse the test write.

### Edge Functions — go through `creditWallets` (L18-08)

Edge Functions never speak SQL directly. The canonical pattern for
crediting (or debiting, with negative deltas) wallets from a Deno
`serve()` handler is the typed shared helper at
`supabase/functions/_shared/wallet_credit.ts`:

```typescript
import { creditWallets } from "../_shared/wallet_credit.ts";

const result = await creditWallets(
  adminDb,                 // service-role SupabaseClient
  [{
    user_id: user.id,
    delta: 100,
    reason: "challenge_one_vs_one_won",
    ref_id: `challenge:${challengeId}`,
    issuer_group_id: groupId ?? null,   // optional
  }],
  { request_id: requestId, fn: FN_NAME, meta: { challenge_id: challengeId } },
);

if (!result.ok) {
  // typed code: EMPTY_BATCH | INVALID_USER_ID | INVALID_DELTA |
  //             INVALID_REASON | INVALID_REF_ID |
  //             INVALID_ISSUER_GROUP | INVALID_ENTRY | RPC_ERROR
  return jsonErr(500, "REFUND_FAILED", result.message, requestId);
}
// result.processed === number of ledger rows written
```

Properties of the helper:

- **Pre-flight validation** — every entry is checked client-side
  (UUID shape, non-zero integer delta, reason ∈ `ALLOWED_REASONS`,
  ref_id text 1–200 chars, optional issuer_group_id UUID) BEFORE any
  RPC round-trip. A typo in `reason` returns `INVALID_REASON` in
  microseconds, not after a network hop.

- **Reason allowlist** — the helper's `ALLOWED_REASONS` mirrors the
  SQL-side `coin_ledger_reason_check` constraint. Adding a new reason
  is a two-line change: append to the helper's `Set` AND extend the
  CHECK constraint in the next migration.

- **Atomic via RPC** — the helper forwards to
  `fn_increment_wallets_batch`, which sets the
  `app.wallet_mutation_authorized` GUC once per call and pairs every
  wallet UPSERT with a `coin_ledger` INSERT inside a single PG
  transaction. There is no separate `coin_ledger.insert(...)` on the
  Deno side — that pattern (used historically by an older
  settle-challenge revision) caused the double-write bug documented
  in `docs/DISASTER_CONCURRENCY.md` C1 and is now structurally
  impossible.

- **Structured log line per call** — one JSON line on either path:

  ```json
  {"request_id":"...","fn":"settle-challenge","event":"wallet_credit.ok",
   "entry_count":3,"processed":3,"total_delta":1500,"challenge_id":"abc"}
  ```

  On RPC failure, the line carries `event:"wallet_credit.rpc_failed"`
  with `pg_code` (e.g. `55P03` for lock_not_available) so on-call can
  branch retry-vs-fail-closed without reading the function source.

CI gate: any new `adminDb.rpc("fn_increment_wallets_batch", ...)`
landing in `supabase/functions/**` should be flagged in code review —
the helper is mandatory. The 29-test Deno suite at
`supabase/functions/_shared/wallet_credit.test.ts` covers every typed
error branch and the RPC happy/error paths.

## Suggested observability

| Metric                                                    | Source                                | Alert threshold           |
| --------------------------------------------------------- | ------------------------------------- | ------------------------- |
| `wallet_guard_blocked_total`                              | log scan: `WALLET_MUTATION_FORBIDDEN` | > 0 in 5 min (warn)       |
| `wallet_drift_count` (rows where balance ≠ SUM(ledger))   | reconcile_all_wallets output          | > 0 sustained (page)      |
| `reconcile_wallet_drift_seconds` (max age of latest fix)  | `cron_run_state.last_run_at`          | > 24h (warn)              |
| `fn_mutate_wallet_p99_ms`                                 | RPC trace                             | > 50 ms (investigate)     |

## Related runbooks

- [Idempotency Runbook (L18-02)](./IDEMPOTENCY_RUNBOOK.md)
- [Cron Health Runbook (L12-03)](./CRON_HEALTH_RUNBOOK.md)
- [Reconcile Wallets Cron](./RECONCILE_WALLETS_CRON.md)
