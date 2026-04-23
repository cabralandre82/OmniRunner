-- L05-05 — Zero-winner challenge settlement.
--
-- The audit flagged that when a challenge reaches `ends_at_ms`
-- with no accepted participants (they all withdrew), or with
-- accepted participants who never actually ran, the current
-- `settle-challenge` edge function just marks the challenge as
-- `expired`. Two consequences:
--
--   1. Any entry fees that were collected from participants who
--      later withdrew but paid up front remain pinned against the
--      challenge with no refund path. Empirically rare today (see
--      the branches in `supabase/functions/settle-challenge/`
--      that DO refund when a game was played but nobody ran) but
--      structurally unsafe.
--   2. The diagnostic status `'expired'` collapses two different
--      outcomes — "the clock ran out" vs "nobody even showed up" —
--      making retrospective analytics lossy.
--
-- This migration installs two primitives:
--
--   A. Extend `public.challenges.status` CHECK to add
--      `'expired_no_winners'`.
--   B. `public.fn_settle_challenge_no_winners(p_challenge_id uuid)`
--      — an atomic RPC the edge function calls when it detects the
--      zero-winner condition. It:
--        - Collects all `coin_ledger` rows tagged with
--          `reason = 'challenge_entry_fee'` and
--          `ref_id = p_challenge_id` (those are the actual
--          collected fees, echoing the `pool` heuristic in the
--          edge function).
--        - For each such ledger entry, enqueues a compensating
--          credit using the canonical `fn_increment_wallets_batch`
--          (so the L18-01 wallet-mutation guard is honoured and
--          the ledger ↔ wallet write is transactional).
--        - Sets `challenges.status = 'expired_no_winners'`.
--        - Returns a jsonb report { refunded_users, refunded_coins,
--          ledger_entry_count }.
--
--   Idempotent: calling it twice is harmless because the second
--   call finds status <> 'active' and returns a no-op report; the
--   lookup for ledger entries is filtered to
--   `delta_coins < 0` so we never "refund a refund".
--
-- The edge function change that calls this helper is shipped in
-- the same PR. See `supabase/functions/settle-challenge/index.ts`.

BEGIN;

ALTER TABLE public.challenges
  DROP CONSTRAINT IF EXISTS challenges_status_check;

ALTER TABLE public.challenges
  ADD CONSTRAINT challenges_status_check
  CHECK (status IN (
    'pending',
    'active',
    'completing',
    'completed',
    'cancelled',
    'expired',
    'expired_no_winners'
  ));

COMMENT ON CONSTRAINT challenges_status_check ON public.challenges IS
  'L05-05 adds ''expired_no_winners'' for challenges that ended ' ||
  'with nobody running. Distinct from ''expired'' for retrospective ' ||
  'analytics.';

CREATE OR REPLACE FUNCTION public.fn_settle_challenge_no_winners(p_challenge_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_challenge record;
  v_entries jsonb;
  v_entry_count int := 0;
  v_refunded_coins int := 0;
  v_refunded_users int := 0;
  v_batch_count int := 0;
BEGIN
  IF p_challenge_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_CHALLENGE_ID: p_challenge_id must not be null'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT id, status, entry_fee_coins
    INTO v_challenge
    FROM public.challenges
   WHERE id = p_challenge_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'CHALLENGE_NOT_FOUND: %', p_challenge_id
      USING ERRCODE = 'P0001';
  END IF;

  -- Idempotency: if we have already closed this challenge in a
  -- no-winners posture, return a no-op report. Also short-circuit
  -- if someone else already moved it to 'completed' via the
  -- standard settlement path — that means some runner DID finish
  -- after all and we should not second-guess.
  IF v_challenge.status IN ('expired_no_winners', 'completed', 'cancelled') THEN
    RETURN jsonb_build_object(
      'refunded_users', 0,
      'refunded_coins', 0,
      'ledger_entry_count', 0,
      'status', v_challenge.status,
      'noop', true
    );
  END IF;

  -- Collect original entry-fee charges. delta_coins < 0 narrows to
  -- the collection side of the ledger (refunds, if any prior run
  -- created them, are delta_coins > 0 and are excluded here).
  WITH fees AS (
    SELECT user_id, SUM(-delta_coins)::int AS coins_to_refund
    FROM public.coin_ledger
    WHERE ref_id = p_challenge_id::text
      AND reason = 'challenge_entry_fee'
      AND delta_coins < 0
    GROUP BY user_id
  ),
  already_refunded AS (
    SELECT user_id, SUM(delta_coins)::int AS refunded_already
    FROM public.coin_ledger
    WHERE ref_id = p_challenge_id::text
      AND reason = 'challenge_entry_refund'
      AND delta_coins > 0
    GROUP BY user_id
  ),
  net AS (
    SELECT
      f.user_id,
      (f.coins_to_refund - COALESCE(a.refunded_already, 0)) AS net_coins
    FROM fees f
    LEFT JOIN already_refunded a ON a.user_id = f.user_id
  )
  SELECT
    COALESCE(jsonb_agg(jsonb_build_object(
      'user_id', n.user_id,
      'delta', n.net_coins,
      'reason', 'challenge_entry_refund',
      'ref_id', p_challenge_id::text
    )) FILTER (WHERE n.net_coins > 0), '[]'::jsonb),
    COALESCE(COUNT(*) FILTER (WHERE n.net_coins > 0), 0),
    COALESCE(SUM(n.net_coins) FILTER (WHERE n.net_coins > 0), 0)
  INTO v_entries, v_entry_count, v_refunded_coins
  FROM net n;

  v_refunded_users := v_entry_count;

  IF v_entry_count > 0 THEN
    v_batch_count := public.fn_increment_wallets_batch(v_entries);
    IF v_batch_count <> v_entry_count THEN
      RAISE EXCEPTION
        'L05-05: fn_increment_wallets_batch wrote % of % entries (challenge=%)',
        v_batch_count, v_entry_count, p_challenge_id
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  UPDATE public.challenges
     SET status = 'expired_no_winners'
   WHERE id = p_challenge_id;

  RETURN jsonb_build_object(
    'refunded_users', v_refunded_users,
    'refunded_coins', v_refunded_coins,
    'ledger_entry_count', v_entry_count,
    'status', 'expired_no_winners',
    'noop', false
  );
END;
$$;

COMMENT ON FUNCTION public.fn_settle_challenge_no_winners(uuid) IS
  'L05-05 — atomic zero-winner settlement: refunds collected entry ' ||
  'fees and marks the challenge expired_no_winners. Idempotent.';

REVOKE ALL ON FUNCTION public.fn_settle_challenge_no_winners(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_settle_challenge_no_winners(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.fn_settle_challenge_no_winners(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_settle_challenge_no_winners(uuid) TO service_role;

-- Self-test. Runs a minimal scenario inside the migration
-- transaction so assertion failures roll back the whole migration.
DO $$
DECLARE
  v_status text;
  v_report jsonb;
  v_fail boolean;
BEGIN
  -- (a) Helper is SECURITY DEFINER with pinned search_path.
  SELECT prosecdef
    INTO v_fail
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'fn_settle_challenge_no_winners'
   LIMIT 1;
  IF NOT v_fail THEN
    RAISE EXCEPTION 'L05-05 self-test: helper not SECURITY DEFINER';
  END IF;

  -- (b) New status is part of CHECK.
  BEGIN
    INSERT INTO public.challenges (
      creator_user_id, type, metric, window_ms,
      created_at_ms, status
    ) VALUES (
      '00000000-0000-0000-0000-000000000000',
      'group', 'distance', 604800000, 1700000000000,
      'expired_no_winners'
    );
    v_fail := false;  -- accepted: ok
  EXCEPTION WHEN check_violation THEN
    v_fail := true;
  END;
  IF v_fail THEN
    RAISE EXCEPTION
      'L05-05 self-test: CHECK rejected expired_no_winners';
  END IF;
  -- Roll back the probe insert.
  DELETE FROM public.challenges
   WHERE creator_user_id = '00000000-0000-0000-0000-000000000000'
     AND status = 'expired_no_winners';

  -- (c) Calling helper on a completed challenge is a no-op.
  INSERT INTO public.challenges (
    id,
    creator_user_id, type, metric, window_ms,
    created_at_ms, status
  ) VALUES (
    '00000000-0000-0000-0000-00000000AAAA',
    '00000000-0000-0000-0000-000000000000',
    'group', 'distance', 604800000, 1700000000000, 'completed'
  );
  v_report := public.fn_settle_challenge_no_winners(
    '00000000-0000-0000-0000-00000000AAAA'::uuid
  );
  IF (v_report->>'noop')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION
      'L05-05 self-test: helper should have no-op''d on completed challenge (report=%)',
      v_report;
  END IF;
  IF v_report->>'status' <> 'completed' THEN
    RAISE EXCEPTION
      'L05-05 self-test: helper should have reported existing status=completed';
  END IF;
  DELETE FROM public.challenges
   WHERE id = '00000000-0000-0000-0000-00000000AAAA';

  -- (d) CHALLENGE_NOT_FOUND surfaces cleanly.
  BEGIN
    PERFORM public.fn_settle_challenge_no_winners(
      '00000000-0000-0000-0000-00000000BBBB'::uuid
    );
    v_fail := true;
  EXCEPTION WHEN others THEN
    v_fail := false;
  END;
  IF v_fail THEN
    RAISE EXCEPTION
      'L05-05 self-test: helper should have raised on unknown id';
  END IF;

  RAISE NOTICE 'L05-05 self-test: OK';
END
$$;

COMMIT;
