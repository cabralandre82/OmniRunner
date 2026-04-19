-- ============================================================================
-- L18-08 — Canonical wallet-credit RPC for Edge Functions
--
-- Audit reference:
--   docs/audit/findings/L18-08-edge-functions-vs-route-handlers-responsabilidade-duplicada.md
--   docs/audit/parts/07-vp-principal-dba-sre.md  (anchor [18.8])
--
-- Problem:
--   Two financial code-paths exist side-by-side:
--     (a) portal/src/app/api/distribute-coins/route.ts  → emit_coins_atomic
--     (b) Edge Functions settle-challenge + challenge-withdraw
--          → fn_increment_wallets_batch
--   The two never crossed in production because the business operations
--   differ (institutional issuance vs challenge settlement), but the
--   `fn_increment_wallets_batch` body was last touched in L18-01 and
--   carries TWO latent bugs introduced when L19-01 partitioned
--   `coin_ledger`:
--
--     1. INSERT writes `created_at` (timestamptz) but L19-01 made
--        `created_at_ms` (bigint) NOT NULL with no default — so any
--        caller in a fresh schema (or post-`pg_dump`-restore) would
--        hit `null value in column "created_at_ms" violates not-null
--        constraint` on the very first settled challenge.
--     2. `(v_entry->>'ref_id')::uuid` cast: L19-01 made ref_id `text`
--        (canonical) so the cast is unnecessary and FAIL-CLOSED on any
--        future caller passing a non-UUID ref_id (e.g. composite key
--        like 'idem:user:nonce').
--
-- Defence (this migration):
--   • Re-create `fn_increment_wallets_batch` with the canonical column
--     names (`created_at_ms`) and TEXT ref_id semantics.
--   • Forward-compat: accept optional `issuer_group_id` in each entry
--     so callers can attribute credit to the issuing coaching group
--     when relevant (currently unused by callers; callers pass
--     `group_id: null` so the change is a no-op for them).
--   • Preserve the existing surface strictly: still positive-or-
--     negative integer delta, still single-pass UPSERT semantics, still
--     returns rows-processed integer. The L18-01 wallet mutation guard
--     remains the source of truth — `set_config(...,true)` stays in
--     place at function entry.
--
--   Behavior unchanged:
--     • lifetime_earned_coins / lifetime_spent_coins NOT bumped — the
--       legacy callers (settle-challenge refunds, withdrawal refunds)
--       didn't bump them either; changing that here would be a silent
--       semantic shift outside the scope of L18-08. A follow-up may
--       audit lifetime_* parity for challenge settlements separately.
-- ============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.fn_increment_wallets_batch(jsonb);

CREATE OR REPLACE FUNCTION public.fn_increment_wallets_batch(p_entries jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_entry  jsonb;
  v_user   uuid;
  v_delta  integer;
  v_reason text;
  v_ref    text;
  v_issuer uuid;
  v_now_ms bigint := (extract(epoch from now()) * 1000)::bigint;
  v_count  integer := 0;
BEGIN
  IF p_entries IS NULL OR jsonb_typeof(p_entries) <> 'array' THEN
    RAISE EXCEPTION 'INVALID_ENTRIES: p_entries must be a JSON array'
      USING ERRCODE = 'P0001';
  END IF;

  PERFORM set_config('app.wallet_mutation_authorized', 'yes', true);

  FOR v_entry IN SELECT * FROM jsonb_array_elements(p_entries)
  LOOP
    -- Extract + validate per-row.
    v_user   := NULLIF(v_entry->>'user_id', '')::uuid;
    v_delta  := (v_entry->>'delta')::int;
    v_reason := COALESCE(NULLIF(v_entry->>'reason', ''), 'batch_credit');
    v_ref    := v_entry->>'ref_id';
    v_issuer := NULLIF(v_entry->>'issuer_group_id', '')::uuid;

    IF v_user IS NULL THEN
      RAISE EXCEPTION 'INVALID_USER_ID: missing user_id at entry'
        USING ERRCODE = 'P0001';
    END IF;
    IF v_delta IS NULL OR v_delta = 0 THEN
      RAISE EXCEPTION 'INVALID_DELTA: delta must be non-zero integer'
        USING ERRCODE = 'P0001';
    END IF;

    -- Wallet upsert (guard authorises both branches).
    UPDATE public.wallets
       SET balance_coins = balance_coins + v_delta,
           updated_at    = now()
     WHERE user_id = v_user;

    IF NOT FOUND THEN
      INSERT INTO public.wallets (user_id, balance_coins, updated_at)
      VALUES (v_user, v_delta, now());
    END IF;

    -- Paired ledger row (canonical schema: text ref_id + created_at_ms).
    INSERT INTO public.coin_ledger
      (user_id, delta_coins, reason, ref_id, issuer_group_id, created_at_ms)
    VALUES
      (v_user, v_delta, v_reason, v_ref, v_issuer, v_now_ms);

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.fn_increment_wallets_batch(jsonb) IS
  'L18-01 + L18-08-hardened: batch wallet credit/debit. Sets the wallet-'
  'mutation guard once per call, then iterates entries. Each entry must '
  'have user_id (uuid), delta (non-zero integer), reason (defaults to '
  'batch_credit), and may include ref_id (text — canonical schema) and '
  'issuer_group_id (uuid). Errors: INVALID_ENTRIES, INVALID_USER_ID, '
  'INVALID_DELTA (P0001).';

REVOKE ALL ON FUNCTION public.fn_increment_wallets_batch(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_increment_wallets_batch(jsonb) TO service_role;

COMMIT;
