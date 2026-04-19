-- ============================================================================
-- L18-01 — Wallet Mutation Guard + Unified Gateway
--
-- Audit reference:
--   docs/audit/findings/L18-01-duas-fontes-da-verdade-para-balance-de-wallet.md
--   docs/audit/parts/18-principal-eng.md  (anchor [18.1])
--
-- Problem (current architecture):
--   `coin_ledger` is the canonical, append-only source of truth, while
--   `wallets.balance_coins` is a denormalised cache. ~9 RPCs across 9
--   migrations mutate `wallets` directly; if a future migration forgets
--   to also INSERT into `coin_ledger`, balance silently drifts.
--   `reconcile_wallet` exists but is reactive — drift can persist for
--   hours before the cron picks it up.
--
-- Defence (this migration):
--   (1) BEFORE INSERT/UPDATE trigger on `wallets` blocks any mutation
--       of balance_coins / pending_coins / lifetime_* columns unless the
--       transaction has set the session GUC `app.wallet_mutation_authorized`
--       to `'yes'`. The GUC is `LOCAL` (rolled back at txn end), so a
--       leaked authorisation cannot propagate.
--   (2) Every existing wallet-mutator RPC is recreated to set the GUC at
--       its first executable statement. Behavioural surface is unchanged.
--   (3) New `fn_mutate_wallet` gateway is the recommended path going
--       forward: a single atomic call inserts the ledger row, sets the
--       GUC, and updates the wallet — guaranteeing pairing.
--
-- Operational impact:
--   • No ABI break: all existing RPC signatures preserved.
--   • New code that does `UPDATE wallets SET balance_coins = ...` outside
--     of an authorised RPC fails fast with a clear message.
--   • Auto-create trigger (handle_new_user) inserts a zero-balance row;
--     guard exempts INSERTs whose tracked counters are all zero.
--   • Reconcile path still works: `reconcile_wallet` sets the GUC.
-- ============================================================================

BEGIN;

-- ── 1. Trigger function ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_forbid_direct_wallet_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_authorized text;
BEGIN
  -- Allow zero-balance INSERTs (e.g. handle_new_user signup trigger).
  -- Anything that pre-loads a non-zero counter must go through an
  -- authorised RPC just like an UPDATE would.
  IF TG_OP = 'INSERT' THEN
    IF COALESCE(NEW.balance_coins, 0) = 0
       AND COALESCE(NEW.pending_coins, 0) = 0
       AND COALESCE(NEW.lifetime_earned_coins, 0) = 0
       AND COALESCE(NEW.lifetime_spent_coins, 0) = 0 THEN
      RETURN NEW;
    END IF;
  END IF;

  v_authorized := COALESCE(current_setting('app.wallet_mutation_authorized', true), '');

  IF v_authorized <> 'yes' THEN
    RAISE EXCEPTION
      'WALLET_MUTATION_FORBIDDEN: direct mutation of public.wallets blocked. '
      'Use fn_mutate_wallet() or call an authorised RPC '
      '(e.g. increment_wallet_balance, debit_wallet_checked, execute_burn_atomic).'
      USING ERRCODE = 'P0007',
            HINT    = 'Authorised RPCs set GUC app.wallet_mutation_authorized=yes (LOCAL) before mutating.';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.fn_forbid_direct_wallet_mutation() IS
  'L18-01: BEFORE trigger on public.wallets. Blocks any INSERT/UPDATE that '
  'changes balance_coins, pending_coins, or lifetime_* unless the calling '
  'transaction has set app.wallet_mutation_authorized=yes (LOCAL).';

REVOKE ALL ON FUNCTION public.fn_forbid_direct_wallet_mutation() FROM PUBLIC;

-- ── 2. Triggers on wallets ─────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_wallet_mutation_guard_update ON public.wallets;
CREATE TRIGGER trg_wallet_mutation_guard_update
  BEFORE UPDATE OF balance_coins, pending_coins, lifetime_earned_coins, lifetime_spent_coins
  ON public.wallets
  FOR EACH ROW EXECUTE FUNCTION public.fn_forbid_direct_wallet_mutation();

DROP TRIGGER IF EXISTS trg_wallet_mutation_guard_insert ON public.wallets;
CREATE TRIGGER trg_wallet_mutation_guard_insert
  BEFORE INSERT
  ON public.wallets
  FOR EACH ROW EXECUTE FUNCTION public.fn_forbid_direct_wallet_mutation();

-- ── 3. Recreate existing mutator RPCs with GUC authorisation ───────────────
--     Each function starts by calling set_config(..., true) so the trigger
--     accepts the subsequent UPDATE/INSERT. Behavioural surface unchanged.

-- 3.1 increment_wallet_balance(uuid, integer)
CREATE OR REPLACE FUNCTION public.increment_wallet_balance(
  p_user_id uuid,
  p_delta   integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM set_config('app.wallet_mutation_authorized', 'yes', true);

  INSERT INTO public.wallets (user_id, balance_coins, lifetime_earned_coins, lifetime_spent_coins, updated_at)
  VALUES (
    p_user_id,
    GREATEST(0, p_delta),
    CASE WHEN p_delta > 0 THEN p_delta ELSE 0 END,
    CASE WHEN p_delta < 0 THEN ABS(p_delta) ELSE 0 END,
    now()
  )
  ON CONFLICT (user_id)
  DO UPDATE SET
    balance_coins         = public.wallets.balance_coins + p_delta,
    lifetime_earned_coins = CASE WHEN p_delta > 0
                              THEN public.wallets.lifetime_earned_coins + p_delta
                              ELSE public.wallets.lifetime_earned_coins END,
    lifetime_spent_coins  = CASE WHEN p_delta < 0
                              THEN public.wallets.lifetime_spent_coins + ABS(p_delta)
                              ELSE public.wallets.lifetime_spent_coins END,
    updated_at            = now();
END;
$$;

COMMENT ON FUNCTION public.increment_wallet_balance(uuid, integer) IS
  'L18-01-hardened: sets app.wallet_mutation_authorized=yes (LOCAL) before '
  'upserting wallets row. Caller is responsible for the paired coin_ledger '
  'INSERT. Prefer fn_mutate_wallet() for new code.';

-- 3.2 increment_wallet_pending(uuid, integer)
CREATE OR REPLACE FUNCTION public.increment_wallet_pending(
  p_user_id uuid,
  p_delta   integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM set_config('app.wallet_mutation_authorized', 'yes', true);

  UPDATE public.wallets
  SET pending_coins = pending_coins + p_delta,
      updated_at    = now()
  WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    INSERT INTO public.wallets (user_id, pending_coins)
    VALUES (p_user_id, GREATEST(0, p_delta));
  END IF;
END;
$$;

COMMENT ON FUNCTION public.increment_wallet_pending(uuid, integer) IS
  'L18-01-hardened: sets wallet-mutation guard before adjusting pending_coins.';

-- 3.3 release_pending_to_balance(uuid, integer)
CREATE OR REPLACE FUNCTION public.release_pending_to_balance(
  p_user_id uuid,
  p_amount  integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM set_config('app.wallet_mutation_authorized', 'yes', true);

  UPDATE public.wallets
  SET pending_coins         = pending_coins - p_amount,
      balance_coins         = balance_coins + p_amount,
      lifetime_earned_coins = lifetime_earned_coins + p_amount,
      updated_at            = now()
  WHERE user_id = p_user_id;
END;
$$;

COMMENT ON FUNCTION public.release_pending_to_balance(uuid, integer) IS
  'L18-01-hardened: sets wallet-mutation guard before moving pending → balance.';

-- 3.4 debit_wallet_checked(uuid, integer)
CREATE OR REPLACE FUNCTION public.debit_wallet_checked(
  p_user_id uuid,
  p_amount  integer
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_amount <= 0 THEN
    RETURN true;
  END IF;

  PERFORM set_config('app.wallet_mutation_authorized', 'yes', true);

  UPDATE public.wallets
  SET balance_coins        = balance_coins - p_amount,
      lifetime_spent_coins = lifetime_spent_coins + p_amount,
      updated_at           = now()
  WHERE user_id = p_user_id
    AND balance_coins >= p_amount;

  RETURN FOUND;
END;
$$;

COMMENT ON FUNCTION public.debit_wallet_checked(uuid, integer) IS
  'L18-01-hardened: sets wallet-mutation guard before conditional debit.';

GRANT EXECUTE ON FUNCTION public.debit_wallet_checked(uuid, integer)
  TO authenticated, service_role;

-- 3.5 fn_increment_wallets_batch(jsonb)
CREATE OR REPLACE FUNCTION public.fn_increment_wallets_batch(p_entries jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_entry jsonb;
  v_count integer := 0;
BEGIN
  PERFORM set_config('app.wallet_mutation_authorized', 'yes', true);

  FOR v_entry IN SELECT * FROM jsonb_array_elements(p_entries)
  LOOP
    UPDATE public.wallets
    SET balance_coins = balance_coins + (v_entry->>'delta')::int,
        updated_at    = now()
    WHERE user_id = (v_entry->>'user_id')::uuid;

    IF NOT FOUND THEN
      INSERT INTO public.wallets (user_id, balance_coins, updated_at)
      VALUES ((v_entry->>'user_id')::uuid, (v_entry->>'delta')::int, now());
    END IF;

    INSERT INTO public.coin_ledger (user_id, delta_coins, reason, ref_id, created_at)
    VALUES (
      (v_entry->>'user_id')::uuid,
      (v_entry->>'delta')::int,
      COALESCE(v_entry->>'reason', 'batch_credit'),
      (v_entry->>'ref_id')::uuid,
      now()
    );

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.fn_increment_wallets_batch(jsonb) IS
  'L18-01-hardened: sets wallet-mutation guard before batch credit. '
  'Inserts paired coin_ledger row per entry.';

-- 3.6 reconcile_wallet(uuid)
CREATE OR REPLACE FUNCTION public.reconcile_wallet(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_ledger_sum   integer;
  v_current_bal  integer;
  v_drift        integer;
BEGIN
  PERFORM set_config('app.wallet_mutation_authorized', 'yes', true);

  SELECT COALESCE(SUM(delta_coins), 0)
    INTO v_ledger_sum
    FROM public.coin_ledger
   WHERE user_id = p_user_id;

  SELECT balance_coins
    INTO v_current_bal
    FROM public.wallets
   WHERE user_id = p_user_id
     FOR UPDATE;

  IF v_current_bal IS NULL THEN
    RETURN jsonb_build_object(
      'reconciled', false,
      'error', 'WALLET_NOT_FOUND'
    );
  END IF;

  v_drift := v_ledger_sum - v_current_bal;

  IF v_drift = 0 THEN
    UPDATE public.wallets
       SET last_reconciled_at_ms = (EXTRACT(EPOCH FROM now()) * 1000)::bigint,
           updated_at            = now()
     WHERE user_id = p_user_id;

    RETURN jsonb_build_object(
      'reconciled', true,
      'drift', 0,
      'new_balance', v_current_bal
    );
  END IF;

  UPDATE public.wallets
     SET balance_coins         = GREATEST(v_ledger_sum, 0),
         last_reconciled_at_ms = (EXTRACT(EPOCH FROM now()) * 1000)::bigint,
         updated_at            = now()
   WHERE user_id = p_user_id;

  -- Audit trail: zero-delta correction row. The L19-01 partitioning
  -- migration removed the legacy `note` column AND restricted the reason
  -- enum (no longer accepts 'admin_correction'), so we use the surviving
  -- 'admin_adjustment' reason and stuff the drift context into ref_id.
  INSERT INTO public.coin_ledger (user_id, delta_coins, reason, ref_id, created_at_ms)
  VALUES (
    p_user_id,
    0,
    'admin_adjustment',
    format('reconcile:drift=%s:old=%s:sum=%s', v_drift, v_current_bal, v_ledger_sum),
    (EXTRACT(EPOCH FROM now()) * 1000)::bigint
  );

  RAISE NOTICE '[L18-01] reconcile drift=% old_bal=% ledger_sum=% user=%',
    v_drift, v_current_bal, v_ledger_sum, p_user_id;

  RETURN jsonb_build_object(
    'reconciled', true,
    'drift', v_drift,
    'new_balance', GREATEST(v_ledger_sum, 0)
  );
END;
$$;

COMMENT ON FUNCTION public.reconcile_wallet(uuid) IS
  'L18-01-hardened: sets wallet-mutation guard before reconciling. '
  'Compares wallet.balance_coins against SUM(coin_ledger.delta_coins) and '
  'fixes drift, logging a zero-delta admin_correction row.';

-- 3.7 reconcile_all_wallets()
--     No direct wallet UPDATE; loops calling reconcile_wallet which already
--     sets the GUC. Recreated only to keep the comment trail consistent.
CREATE OR REPLACE FUNCTION public.reconcile_all_wallets()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_total   integer := 0;
  v_drifted integer := 0;
  v_result  jsonb;
  r         record;
BEGIN
  FOR r IN SELECT user_id FROM public.wallets LOOP
    v_result := public.reconcile_wallet(r.user_id);
    v_total := v_total + 1;
    IF (v_result ->> 'drift')::integer != 0 THEN
      v_drifted := v_drifted + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'total_wallets', v_total,
    'drifted',       v_drifted,
    'run_at',        now()
  );
END;
$$;

COMMENT ON FUNCTION public.reconcile_all_wallets() IS
  'L18-01: batch wrapper over reconcile_wallet. GUC is set inside each '
  'inner call.';

-- 3.8 execute_burn_atomic(uuid, uuid, integer, uuid)
--     Faithful re-creation of the L02-02-hardened version, with GUC set
--     before the wallet UPDATE.
CREATE OR REPLACE FUNCTION public.execute_burn_atomic(
  p_user_id           uuid,
  p_redeemer_group_id uuid,
  p_amount            integer,
  p_ref_id            uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_wallet_balance integer;
  v_breakdown      jsonb := '[]'::jsonb;
  v_issuer         uuid;
  v_issuer_balance integer;
  v_now_ms         bigint := (extract(epoch from now()) * 1000)::bigint;
  v_event_id       uuid;
  v_fee_rate       numeric(5,2);
  v_gross          numeric(14,2);
  v_fee            numeric(14,2);
  v_net            numeric(14,2);
  v_settlement_id  uuid;
  v_has_custody    boolean;
  v_sqlstate       text;
  v_sqlerrm        text;
BEGIN
  PERFORM set_config('app.wallet_mutation_authorized', 'yes', true);

  -- 1. Lock wallet and verify balance
  SELECT balance_coins INTO v_wallet_balance
  FROM public.wallets
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF v_wallet_balance IS NULL OR v_wallet_balance < p_amount THEN
    RAISE EXCEPTION 'INSUFFICIENT_BALANCE: balance=%, requested=%',
      COALESCE(v_wallet_balance, 0), p_amount;
  END IF;

  -- 2. Compute burn plan and insert per-issuer ledger entries
  FOR v_issuer, v_issuer_balance IN
    SELECT bp.issuer_group_id, bp.amount
    FROM public.compute_burn_plan(p_user_id, p_redeemer_group_id, p_amount) bp
  LOOP
    v_breakdown := v_breakdown || jsonb_build_object(
      'issuer_group_id', v_issuer,
      'amount', v_issuer_balance
    );

    INSERT INTO public.coin_ledger
      (user_id, delta_coins, reason, ref_id, issuer_group_id, created_at_ms)
    VALUES
      (p_user_id, -v_issuer_balance, 'institution_token_burn',
       p_ref_id, v_issuer, v_now_ms);
  END LOOP;

  -- 3. Debit wallet (total)
  UPDATE public.wallets
  SET balance_coins = balance_coins - p_amount
  WHERE user_id = p_user_id;

  -- 4. Create clearing event
  INSERT INTO public.clearing_events
    (burn_ref_id, athlete_user_id, redeemer_group_id, total_coins, breakdown)
  VALUES
    (p_ref_id, p_user_id, p_redeemer_group_id, p_amount, v_breakdown)
  RETURNING id INTO v_event_id;

  -- 5. Get clearing fee rate
  SELECT rate_pct INTO v_fee_rate
  FROM public.platform_fee_config
  WHERE fee_type = 'clearing' AND is_active = true;
  v_fee_rate := COALESCE(v_fee_rate, 3.0);

  -- 6. Per-issuer custody + settlement (L02-02-hardened semantics preserved)
  FOR v_issuer, v_issuer_balance IN
    SELECT
      (entry->>'issuer_group_id')::uuid,
      (entry->>'amount')::integer
    FROM jsonb_array_elements(v_breakdown) AS entry
    WHERE entry->>'issuer_group_id' IS NOT NULL
  LOOP
    IF v_issuer = p_redeemer_group_id THEN
      SELECT EXISTS(
        SELECT 1 FROM public.custody_accounts WHERE group_id = v_issuer
      ) INTO v_has_custody;

      IF v_has_custody THEN
        BEGIN
          PERFORM public.custody_release_committed(v_issuer, v_issuer_balance);
        EXCEPTION
          WHEN undefined_function THEN
            INSERT INTO public.clearing_failure_log
              (failure_type, burn_ref_id, clearing_event_id,
               issuer_group_id, amount, sqlstate, sqlerrm, context)
            VALUES
              ('custody_release', p_ref_id, v_event_id,
               v_issuer, v_issuer_balance, 'P0004',
               'custody_release_committed RPC not deployed',
               jsonb_build_object('note', 'undefined_function — pre-deploy environment'));
          WHEN OTHERS THEN
            v_sqlstate := SQLSTATE;
            v_sqlerrm  := SQLERRM;
            RAISE EXCEPTION
              'CUSTODY_RELEASE_FAILED: group=% amount=% sqlstate=% err=%',
              v_issuer, v_issuer_balance, v_sqlstate, v_sqlerrm
              USING ERRCODE = 'P0005';
        END;
      END IF;
    ELSE
      v_gross := v_issuer_balance::numeric;
      v_fee := ROUND(v_gross * v_fee_rate / 100, 2);
      v_net := v_gross - v_fee;

      INSERT INTO public.clearing_settlements
        (clearing_event_id, creditor_group_id, debtor_group_id,
         coin_amount, gross_amount_usd, fee_rate_pct,
         fee_amount_usd, net_amount_usd, status)
      VALUES
        (v_event_id, p_redeemer_group_id, v_issuer,
         v_issuer_balance, v_gross, v_fee_rate,
         v_fee, v_net, 'pending')
      RETURNING id INTO v_settlement_id;

      BEGIN
        PERFORM public.settle_clearing(v_settlement_id);
      EXCEPTION WHEN OTHERS THEN
        v_sqlstate := SQLSTATE;
        v_sqlerrm  := SQLERRM;
        INSERT INTO public.clearing_failure_log
          (failure_type, burn_ref_id, clearing_event_id, settlement_id,
           issuer_group_id, amount, sqlstate, sqlerrm, context)
        VALUES
          ('settle_clearing', p_ref_id, v_event_id, v_settlement_id,
           v_issuer, v_issuer_balance, v_sqlstate, v_sqlerrm,
           jsonb_build_object(
             'creditor_group_id', p_redeemer_group_id,
             'debtor_group_id',   v_issuer,
             'gross',             v_gross,
             'fee',               v_fee,
             'net',               v_net
           ));
        RAISE NOTICE 'settle_clearing failed (logged to clearing_failure_log): settlement=% sqlstate=% err=%',
          v_settlement_id, v_sqlstate, v_sqlerrm;
      END;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'event_id',     v_event_id,
    'breakdown',    v_breakdown,
    'total_burned', p_amount
  );
END;
$$;

COMMENT ON FUNCTION public.execute_burn_atomic(uuid, uuid, integer, uuid) IS
  'L02-02 + L18-01-hardened: sets wallet-mutation guard before debiting; '
  'preserves custody_release re-raise + settle_clearing best-effort logging.';

GRANT EXECUTE ON FUNCTION public.execute_burn_atomic(uuid, uuid, integer, uuid) TO service_role;

-- 3.9 fn_switch_assessoria(uuid)
--     Calls increment_wallet_balance (already guarded) AND directly
--     UPDATEs pending_coins. Set GUC before the direct UPDATE.
CREATE OR REPLACE FUNCTION public.fn_switch_assessoria(p_new_group_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid          uuid;
  v_balance      integer;
  v_pending      integer;
  v_old_group_id uuid;
  v_display_name text;
  v_now_ms       bigint;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.coaching_groups WHERE id = p_new_group_id) THEN
    RAISE EXCEPTION 'GROUP_NOT_FOUND';
  END IF;

  SELECT active_coaching_group_id, display_name
    INTO v_old_group_id, v_display_name
    FROM public.profiles
    WHERE id = v_uid;

  IF v_old_group_id IS NOT DISTINCT FROM p_new_group_id THEN
    RETURN jsonb_build_object('status', 'already_member', 'burned', 0, 'pending_burned', 0);
  END IF;

  v_now_ms := EXTRACT(EPOCH FROM now())::bigint * 1000;

  SELECT COALESCE(balance_coins, 0), COALESCE(pending_coins, 0)
    INTO v_balance, v_pending
    FROM public.wallets
    WHERE user_id = v_uid;
  v_balance := COALESCE(v_balance, 0);
  v_pending := COALESCE(v_pending, 0);

  IF v_balance > 0 THEN
    INSERT INTO public.coin_ledger (user_id, delta_coins, reason, ref_id, created_at_ms)
    VALUES (v_uid, -v_balance, 'institution_switch_burn', p_new_group_id::text, v_now_ms);

    PERFORM public.increment_wallet_balance(v_uid, -v_balance);
  END IF;

  IF v_pending > 0 THEN
    INSERT INTO public.coin_ledger (user_id, delta_coins, reason, ref_id, created_at_ms)
    VALUES (v_uid, -v_pending, 'institution_switch_burn', 'pending_burn:' || p_new_group_id::text, v_now_ms);

    PERFORM set_config('app.wallet_mutation_authorized', 'yes', true);

    UPDATE public.wallets
    SET pending_coins = 0,
        updated_at    = now()
    WHERE user_id = v_uid;
  END IF;

  DELETE FROM public.coaching_members
    WHERE user_id = v_uid AND role = 'atleta';

  INSERT INTO public.coaching_members (user_id, group_id, display_name, role, joined_at_ms)
  VALUES (v_uid, p_new_group_id, COALESCE(v_display_name, 'Runner'), 'atleta', v_now_ms)
  ON CONFLICT (group_id, user_id)
  DO UPDATE SET role = 'atleta', joined_at_ms = EXCLUDED.joined_at_ms;

  UPDATE public.profiles
    SET active_coaching_group_id = p_new_group_id,
        updated_at               = now()
    WHERE id = v_uid;

  RETURN jsonb_build_object('status', 'switched', 'burned', v_balance, 'pending_burned', v_pending);
END;
$$;

COMMENT ON FUNCTION public.fn_switch_assessoria(uuid) IS
  'L18-01-hardened: sets wallet-mutation guard before zeroing pending_coins. '
  'Balance burn delegates to increment_wallet_balance which sets its own guard.';

-- ── 4. fn_mutate_wallet — preferred gateway for new code ───────────────────
--     Atomic: ledger INSERT + wallet UPSERT, behind the guard. Caller passes
--     the reason; ref_id is forwarded verbatim for cross-table joins.
CREATE OR REPLACE FUNCTION public.fn_mutate_wallet(
  p_user_id          uuid,
  p_delta_coins      integer,
  p_reason           text,
  p_ref_id           text    DEFAULT NULL,
  p_issuer_group_id  uuid    DEFAULT NULL
)
RETURNS TABLE (ledger_id uuid, new_balance integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_ledger_id   uuid;
  v_new_balance integer;
  v_now_ms      bigint := (extract(epoch from now()) * 1000)::bigint;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_USER_ID' USING ERRCODE = 'P0001';
  END IF;
  IF p_delta_coins IS NULL OR p_delta_coins = 0 THEN
    RAISE EXCEPTION 'INVALID_DELTA: delta_coins must be non-zero' USING ERRCODE = 'P0001';
  END IF;
  IF p_reason IS NULL OR length(p_reason) = 0 THEN
    RAISE EXCEPTION 'MISSING_REASON' USING ERRCODE = 'P0001';
  END IF;

  PERFORM set_config('app.wallet_mutation_authorized', 'yes', true);

  -- Lock wallet row (upsert with zero balance row first if missing).
  INSERT INTO public.wallets (user_id, balance_coins, updated_at)
  VALUES (p_user_id, 0, now())
  ON CONFLICT (user_id) DO NOTHING;

  PERFORM 1 FROM public.wallets WHERE user_id = p_user_id FOR UPDATE;

  -- Append ledger row first (immutable canonical truth). The L19-01
  -- partitioning migration dropped the optional `note` column; if a caller
  -- needs free-text context, encode it into ref_id (text type).
  INSERT INTO public.coin_ledger
    (user_id, delta_coins, reason, ref_id, issuer_group_id, created_at_ms)
  VALUES
    (p_user_id, p_delta_coins, p_reason, p_ref_id, p_issuer_group_id, v_now_ms)
  RETURNING id INTO v_ledger_id;

  -- Apply derived effect to wallet.
  UPDATE public.wallets
  SET balance_coins         = balance_coins + p_delta_coins,
      lifetime_earned_coins = CASE WHEN p_delta_coins > 0
                                THEN lifetime_earned_coins + p_delta_coins
                                ELSE lifetime_earned_coins END,
      lifetime_spent_coins  = CASE WHEN p_delta_coins < 0
                                THEN lifetime_spent_coins + ABS(p_delta_coins)
                                ELSE lifetime_spent_coins END,
      updated_at            = now()
  WHERE user_id = p_user_id
  RETURNING balance_coins INTO v_new_balance;

  RETURN QUERY SELECT v_ledger_id, v_new_balance;
END;
$$;

COMMENT ON FUNCTION public.fn_mutate_wallet(uuid, integer, text, text, uuid) IS
  'L18-01: preferred gateway for wallet mutations. Atomically inserts a '
  'coin_ledger row and updates wallets behind the mutation guard. '
  'Errors: INVALID_USER_ID, INVALID_DELTA, MISSING_REASON (P0001). '
  'Throws non-negative-balance check_violation if debit exceeds balance.';

REVOKE ALL ON FUNCTION public.fn_mutate_wallet(uuid, integer, text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_mutate_wallet(uuid, integer, text, text, uuid) TO service_role;

COMMIT;
