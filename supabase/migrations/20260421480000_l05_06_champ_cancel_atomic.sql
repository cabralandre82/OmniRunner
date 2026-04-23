-- L05-06 — Atomic championship-cancel RPC.
--
-- Before this migration `supabase/functions/champ-cancel/index.ts`
-- did four separate writes (withdraw participants, revoke invites,
-- refund badges, set championships.status = 'cancelled') without
-- wrapping them in a transaction. If the badge refund branch
-- raised, the catch block swallowed the error and the championship
-- still got flipped to 'cancelled'. The host's badge inventory
-- then had a permanent silent loss of N badges.
--
-- The fix: `public.fn_champ_cancel_atomic(p_championship_id,
-- p_caller_user_id)` — one SECURITY DEFINER RPC that does all four
-- writes inside a single PG transaction. Any error raises out;
-- the edge function no longer has a "refund failed but we
-- continue" path.
--
-- Authorization: because the RPC is SECURITY DEFINER the caller
-- identity cannot be derived from auth.uid() in a meaningful way
-- (the edge function uses the service role). We therefore receive
-- `p_caller_user_id` and re-check the `coaching_members.role`
-- invariant inside the function, matching the pre-RPC edge-function
-- gate.
--
-- Idempotency: if the championship is already 'cancelled' the RPC
-- returns { noop: true } with the current participant/badge counts
-- so callers can distinguish a real cancel from a retry.

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_champ_cancel_atomic(
  p_championship_id uuid,
  p_caller_user_id  uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_champ            record;
  v_role             text;
  v_withdrawn        int := 0;
  v_invites_revoked  int := 0;
  v_badges_refunded  int := 0;
  v_now              timestamptz := now();
BEGIN
  IF p_championship_id IS NULL OR p_caller_user_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_ARGS: championship_id and caller required'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT id, host_group_id, status
    INTO v_champ
    FROM public.championships
   WHERE id = p_championship_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND: championship %', p_championship_id
      USING ERRCODE = 'P0001';
  END IF;

  IF v_champ.status = 'cancelled' THEN
    SELECT
      COUNT(*) FILTER (WHERE status = 'withdrawn'),
      COUNT(*) FILTER (WHERE status IN ('enrolled','active'))
    INTO v_withdrawn, v_invites_revoked
    FROM public.championship_participants
    WHERE championship_id = p_championship_id;

    RETURN jsonb_build_object(
      'status', 'cancelled',
      'noop', true,
      'participants_withdrawn', v_withdrawn,
      'invites_revoked', 0,
      'badges_refunded', 0
    );
  END IF;

  IF v_champ.status NOT IN ('draft','open','active') THEN
    RAISE EXCEPTION 'INVALID_STATUS: championship is %', v_champ.status
      USING ERRCODE = 'P0001';
  END IF;

  SELECT role
    INTO v_role
    FROM public.coaching_members
   WHERE group_id = v_champ.host_group_id
     AND user_id = p_caller_user_id
   LIMIT 1;

  IF v_role IS NULL OR v_role NOT IN ('admin_master','coach') THEN
    RAISE EXCEPTION
      'FORBIDDEN: only admin_master / coach of host_group may cancel'
      USING ERRCODE = 'P0001';
  END IF;

  -- 1. Withdraw live participants.
  WITH updated AS (
    UPDATE public.championship_participants
       SET status = 'withdrawn',
           updated_at = v_now
     WHERE championship_id = p_championship_id
       AND status IN ('enrolled','active')
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_withdrawn FROM updated;

  -- 2. Revoke pending invites.
  WITH revoked AS (
    UPDATE public.championship_invites
       SET status = 'revoked',
           responded_at = v_now
     WHERE championship_id = p_championship_id
       AND status = 'pending'
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_invites_revoked FROM revoked;

  -- 3. Refund badges. The badge inventory helper RAISEs when
  --    amount <= 0, so we only invoke it when we have badges to
  --    refund. Any RAISE inside it propagates out of this RPC,
  --    which is the whole point of the fix.
  SELECT COUNT(*) INTO v_badges_refunded
    FROM public.championship_badges
   WHERE championship_id = p_championship_id;

  IF v_badges_refunded > 0 THEN
    PERFORM public.fn_credit_badge_inventory(
      v_champ.host_group_id,
      v_badges_refunded,
      format('champ_cancel_refund:%s', p_championship_id)
    );
  END IF;

  -- 4. Mark the championship cancelled. We already hold FOR UPDATE
  --    on the row so no double-write guard needed.
  UPDATE public.championships
     SET status = 'cancelled',
         updated_at = v_now
   WHERE id = p_championship_id;

  RETURN jsonb_build_object(
    'status', 'cancelled',
    'noop', false,
    'participants_withdrawn', v_withdrawn,
    'invites_revoked', v_invites_revoked,
    'badges_refunded', v_badges_refunded
  );
END;
$$;

COMMENT ON FUNCTION public.fn_champ_cancel_atomic(uuid, uuid) IS
  'L05-06 — cancel championship + refund badges atomically. ' ||
  'Raises on any failure; no silent catch. Idempotent on retry.';

REVOKE ALL ON FUNCTION public.fn_champ_cancel_atomic(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_champ_cancel_atomic(uuid, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.fn_champ_cancel_atomic(uuid, uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_champ_cancel_atomic(uuid, uuid) TO service_role;

-- Self-test inside the migration transaction.
DO $$
DECLARE
  v_report jsonb;
  v_raised boolean;
BEGIN
  -- (a) SECURITY DEFINER + pinned search_path.
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'fn_champ_cancel_atomic'
      AND p.prosecdef = true
  ) THEN
    RAISE EXCEPTION 'L05-06 self-test: helper not SECURITY DEFINER';
  END IF;

  -- (b) NULL arg raises INVALID_ARGS.
  BEGIN
    PERFORM public.fn_champ_cancel_atomic(
      NULL::uuid, '00000000-0000-0000-0000-000000000000'::uuid
    );
    v_raised := false;
  EXCEPTION WHEN others THEN
    v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION 'L05-06 self-test: NULL championship_id did not raise';
  END IF;

  -- (c) Unknown championship raises NOT_FOUND.
  BEGIN
    PERFORM public.fn_champ_cancel_atomic(
      '00000000-0000-0000-0000-00000000CCCC'::uuid,
      '00000000-0000-0000-0000-000000000000'::uuid
    );
    v_raised := false;
  EXCEPTION WHEN others THEN
    v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION
      'L05-06 self-test: unknown championship did not raise';
  END IF;

  RAISE NOTICE 'L05-06 self-test: OK';
END
$$;

COMMIT;
