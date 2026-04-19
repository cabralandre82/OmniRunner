-- ============================================================================
-- L02-06 — Withdrawal lifecycle: complete + fail + stale alerting
--
-- Audit reference:
--   docs/audit/findings/L02-06-execute-withdrawal-estado-processing-sem-transicao-final.md
--   docs/audit/parts/02-cto-cfo.md  (anchor [2.6])
--
-- Problem
-- ───────
--   `custody_withdrawals.status` enum is `(pending, processing, completed,
--   failed, cancelled)` but only `pending → processing` is reachable
--   programmatically (via `execute_withdrawal`). The reverse / forward
--   transitions are documented in `docs/runbooks/WITHDRAW_STUCK_RUNBOOK.md`
--   as **manual SQL** ops have to copy-paste — error-prone, no audit
--   trail beyond a hand-typed jsonb, no invariant re-validation, no
--   atomicity with the platform_revenue rollback for fx_spread.
--
--   Result: real withdrawals sit in `processing` forever after the
--   external TED is paid; reconciliation by `getWithdrawals()` never
--   reflects truth; if the bank rejects the TED, ops have to remember
--   to manually `total_deposited_usd += amount_usd` AND delete the
--   `platform_revenue` fx_spread row in the same TX — easy to miss.
--
-- Defence (this migration)
--   • `complete_withdrawal(p_id, p_payout_reference, p_actor_user_id,
--                          p_note)` → atomic processing → completed.
--   • `fail_withdrawal(p_id, p_reason, p_actor_user_id)` → atomic
--     processing → failed; reverses custody balance + deletes
--     fx_spread platform_revenue row in the SAME transaction; raises
--     P0008 if invariants would break.
--   • `fn_stale_withdrawals(p_threshold_hours)` → returns rows stuck in
--     processing past the threshold (default 168h = 7d, matches
--     runbook). SECURITY DEFINER, service-role only.
--   • `fn_alert_stale_withdrawals_safe()` → cron-safe wrapper using
--     L12-03 cron-state pattern (`fn_cron_should_run` +
--     `fn_cron_mark_*`). Logs structured RAISE NOTICE on any stuck
--     row; downstream log-shipper can grep `[L02-06.alert]` and page.
--   • Schedules cron `stale-withdrawals-alert` at `45 6 * * *` UTC
--     (slot engineered by L12-02 — no clash with existing 12 jobs).
--   • Seeds `cron_run_state('stale-withdrawals-alert','never_run')`
--     for immediate ops visibility.
--
-- Notes
--   • Both `complete_withdrawal` and `fail_withdrawal` are idempotent
--     against repeat calls on already-terminal rows (no-op + return
--     `was_terminal=true`) — protects against double-clicks in the
--     ops UI and replay from the L18-02 idempotency layer at the
--     route handler.
--   • `fail_withdrawal` writes the reason into `payout_reference`
--     (suffix `| reverted: <reason> @ <ts>`), preserving any prior
--     gateway reference. This mirrors the runbook §3.3 manual block
--     and keeps the column the single source of truth for ops.
-- ============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. complete_withdrawal — processing → completed
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.complete_withdrawal(
  p_withdrawal_id    uuid,
  p_payout_reference text,
  p_actor_user_id    uuid,
  p_note             text DEFAULT NULL
)
RETURNS TABLE (
  withdrawal_id uuid,
  status        text,
  was_terminal  boolean,
  completed_at  timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_status        text;
  v_existing_ref  text;
  v_completed_at  timestamptz;
BEGIN
  IF p_withdrawal_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_WITHDRAWAL_ID' USING ERRCODE = 'P0001';
  END IF;
  IF p_payout_reference IS NULL OR length(trim(p_payout_reference)) = 0 THEN
    RAISE EXCEPTION 'PAYOUT_REFERENCE_REQUIRED'
      USING ERRCODE = 'P0001',
            HINT = 'complete_withdrawal needs the gateway transfer ID for postmortem traceability';
  END IF;
  IF p_actor_user_id IS NULL THEN
    RAISE EXCEPTION 'ACTOR_REQUIRED'
      USING ERRCODE = 'P0001',
            HINT = 'pass the platform_admin auth.uid() so audit log is attributable';
  END IF;

  SELECT status, payout_reference, completed_at
    INTO v_status, v_existing_ref, v_completed_at
    FROM public.custody_withdrawals
   WHERE id = p_withdrawal_id
   FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'WITHDRAWAL_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  -- Idempotent against re-clicks: if already completed, return as-is.
  IF v_status = 'completed' THEN
    RETURN QUERY SELECT p_withdrawal_id, 'completed'::text, true, v_completed_at;
    RETURN;
  END IF;

  IF v_status <> 'processing' THEN
    RAISE EXCEPTION 'INVALID_TRANSITION: % → completed (only processing allowed)', v_status
      USING ERRCODE = 'P0008';
  END IF;

  UPDATE public.custody_withdrawals
     SET status           = 'completed',
         completed_at     = now(),
         payout_reference = p_payout_reference
   WHERE id = p_withdrawal_id;

  -- Audit trail (append-only, RLS-readable by platform admins +
  -- group admin_master).
  INSERT INTO public.portal_audit_log
    (actor_id, group_id, action, target_type, target_id, metadata)
  SELECT
    p_actor_user_id,
    w.group_id,
    'custody.withdrawal.completed',
    'custody_withdrawal',
    p_withdrawal_id::text,
    jsonb_build_object(
      'payout_reference',         p_payout_reference,
      'previous_payout_reference', v_existing_ref,
      'amount_usd',               w.amount_usd,
      'target_currency',          w.target_currency,
      'note',                     p_note,
      'runbook',                  'WITHDRAW_STUCK_RUNBOOK#3.1'
    )
    FROM public.custody_withdrawals w WHERE w.id = p_withdrawal_id;

  RETURN QUERY SELECT p_withdrawal_id, 'completed'::text, false, now();
END;
$$;

COMMENT ON FUNCTION public.complete_withdrawal(uuid, text, uuid, text) IS
  'L02-06: ops-driven processing → completed transition for a custody '
  'withdrawal. Idempotent against re-clicks. Writes portal_audit_log '
  'with prior payout_reference for forensics.';

REVOKE ALL ON FUNCTION public.complete_withdrawal(uuid, text, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_withdrawal(uuid, text, uuid, text)
  TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. fail_withdrawal — processing → failed (atomic refund + revenue rollback)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fail_withdrawal(
  p_withdrawal_id uuid,
  p_reason        text,
  p_actor_user_id uuid
)
RETURNS TABLE (
  withdrawal_id    uuid,
  status           text,
  was_terminal     boolean,
  refunded_usd     numeric,
  revenue_reversed numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_status      text;
  v_group_id    uuid;
  v_amount      numeric(14,2);
  v_fx_spread   numeric(14,2);
  v_existing_ref text;
  v_revenue_sum numeric(14,2);
BEGIN
  IF p_withdrawal_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_WITHDRAWAL_ID' USING ERRCODE = 'P0001';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'REASON_REQUIRED'
      USING ERRCODE = 'P0001',
            HINT = 'pass the gateway-rejection reason (e.g. "invalid_bank_account") for postmortem';
  END IF;
  IF p_actor_user_id IS NULL THEN
    RAISE EXCEPTION 'ACTOR_REQUIRED' USING ERRCODE = 'P0001';
  END IF;

  SELECT status, group_id, amount_usd, fx_spread_usd, payout_reference
    INTO v_status, v_group_id, v_amount, v_fx_spread, v_existing_ref
    FROM public.custody_withdrawals
   WHERE id = p_withdrawal_id
   FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'WITHDRAWAL_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  -- Idempotent against re-clicks: if already failed, no-op.
  IF v_status = 'failed' THEN
    RETURN QUERY SELECT p_withdrawal_id, 'failed'::text, true, 0::numeric, 0::numeric;
    RETURN;
  END IF;

  IF v_status <> 'processing' THEN
    RAISE EXCEPTION 'INVALID_TRANSITION: % → failed (only processing allowed)', v_status
      USING ERRCODE = 'P0008';
  END IF;

  -- Refund the custody account: execute_withdrawal subtracted
  -- amount_usd from total_deposited_usd; reverse it in the same TX.
  UPDATE public.custody_accounts
     SET total_deposited_usd = total_deposited_usd + v_amount,
         updated_at          = now()
   WHERE group_id = v_group_id;

  -- Reverse the fx_spread platform_revenue row (if any) so the
  -- platform doesn't book revenue on a failed withdrawal.
  -- source_ref_id is stored as text in platform_revenue.
  SELECT COALESCE(SUM(amount_usd), 0)
    INTO v_revenue_sum
    FROM public.platform_revenue
   WHERE source_ref_id = p_withdrawal_id::text
     AND fee_type      = 'fx_spread';

  DELETE FROM public.platform_revenue
   WHERE source_ref_id = p_withdrawal_id::text
     AND fee_type      = 'fx_spread';

  UPDATE public.custody_withdrawals
     SET status           = 'failed',
         completed_at     = now(),
         payout_reference = COALESCE(v_existing_ref, '')
                            || ' | reverted: ' || p_reason
                            || ' @ ' || now()::text
   WHERE id = p_withdrawal_id;

  -- Re-validate the cross-table invariant (total_deposited_usd
  -- must remain ≥ total_committed). check_custody_invariants is a
  -- read-only system function; if it returns a violating row for
  -- this group, abort the TX.
  IF EXISTS (
    SELECT 1 FROM public.check_custody_invariants() v
    WHERE v.group_id = v_group_id
  ) THEN
    RAISE EXCEPTION 'INVARIANT_VIOLATION: refund would unbalance custody for group %', v_group_id
      USING ERRCODE = 'P0008',
            HINT = 'inspect check_custody_invariants() and reconcile manually before retrying';
  END IF;

  INSERT INTO public.portal_audit_log
    (actor_id, group_id, action, target_type, target_id, metadata)
  VALUES (
    p_actor_user_id,
    v_group_id,
    'custody.withdrawal.failed',
    'custody_withdrawal',
    p_withdrawal_id::text,
    jsonb_build_object(
      'reason',                   p_reason,
      'refunded_usd',             v_amount,
      'revenue_reversed_usd',     v_revenue_sum,
      'previous_payout_reference', v_existing_ref,
      'runbook',                  'WITHDRAW_STUCK_RUNBOOK#3.3'
    )
  );

  RETURN QUERY SELECT p_withdrawal_id, 'failed'::text, false, v_amount, v_revenue_sum;
END;
$$;

COMMENT ON FUNCTION public.fail_withdrawal(uuid, text, uuid) IS
  'L02-06: ops-driven processing → failed transition. Atomically '
  'refunds total_deposited_usd, deletes any fx_spread platform_revenue '
  'row tied to this withdrawal, re-validates check_custody_invariants() '
  'and aborts (P0008) if the refund would unbalance custody. Idempotent.';

REVOKE ALL ON FUNCTION public.fail_withdrawal(uuid, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fail_withdrawal(uuid, text, uuid)
  TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. fn_stale_withdrawals — read-only diagnostic + cron source
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_stale_withdrawals(
  p_threshold_hours integer DEFAULT 168
)
RETURNS TABLE (
  id              uuid,
  group_id        uuid,
  amount_usd      numeric,
  target_currency text,
  payout_reference text,
  created_at      timestamptz,
  age_hours       numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    w.id,
    w.group_id,
    w.amount_usd,
    w.target_currency,
    w.payout_reference,
    w.created_at,
    ROUND(EXTRACT(EPOCH FROM (now() - w.created_at)) / 3600.0, 2)::numeric AS age_hours
  FROM public.custody_withdrawals w
  WHERE w.status = 'processing'
    AND w.created_at < now() - make_interval(hours => p_threshold_hours)
  ORDER BY w.created_at ASC;
$$;

COMMENT ON FUNCTION public.fn_stale_withdrawals(integer) IS
  'L02-06: returns withdrawals stuck in processing past p_threshold_hours '
  '(default 168h = 7d). Read by fn_alert_stale_withdrawals_safe and by '
  'the WITHDRAW_STUCK runbook diagnostics.';

REVOKE ALL ON FUNCTION public.fn_stale_withdrawals(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_stale_withdrawals(integer) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. fn_alert_stale_withdrawals_safe — L12-03 cron wrapper
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_alert_stale_withdrawals_safe()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  k_job_name    constant text := 'stale-withdrawals-alert';
  k_max_runtime constant int  := 60;
  v_should_run  boolean;
  v_lock        boolean;
  v_count       integer := 0;
  v_total_usd   numeric(14,2) := 0;
  v_oldest_age  numeric;
BEGIN
  v_should_run := public.fn_cron_should_run(k_job_name, k_max_runtime);
  IF NOT v_should_run THEN
    RETURN;
  END IF;

  v_lock := pg_try_advisory_xact_lock(hashtext('cron:' || k_job_name));
  IF NOT v_lock THEN
    PERFORM public.fn_cron_mark_failed(
      k_job_name,
      'advisory lock unavailable',
      jsonb_build_object('reason', 'advisory_lock_busy')
    );
    RETURN;
  END IF;

  PERFORM public.fn_cron_mark_started(k_job_name);

  BEGIN
    -- Aggregate, log, and finish. We avoid emailing/paging from inside
    -- the DB — the log-shipper consumes RAISE NOTICE and routes per
    -- ALERT_POLICY.md. Threshold 168h = 7 days (runbook canonical).
    SELECT COUNT(*), COALESCE(SUM(amount_usd), 0), COALESCE(MAX(age_hours), 0)
      INTO v_count, v_total_usd, v_oldest_age
      FROM public.fn_stale_withdrawals(168);

    IF v_count > 0 THEN
      RAISE NOTICE
        '[L02-06.alert] stale_withdrawals=% total_usd=% oldest_age_h=% runbook=WITHDRAW_STUCK_RUNBOOK',
        v_count, v_total_usd, v_oldest_age;
    END IF;

    PERFORM public.fn_cron_mark_completed(
      k_job_name,
      jsonb_build_object(
        'stale_count',   v_count,
        'total_usd',     v_total_usd,
        'oldest_age_h',  v_oldest_age,
        'threshold_h',   168
      )
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.fn_cron_mark_failed(
      k_job_name,
      SQLERRM,
      jsonb_build_object('sqlstate', SQLSTATE)
    );
    RAISE;
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_alert_stale_withdrawals_safe() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_alert_stale_withdrawals_safe() FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_alert_stale_withdrawals_safe()
  TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Schedule + seed cron_run_state
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'stale-withdrawals-alert') THEN
    PERFORM cron.unschedule('stale-withdrawals-alert');
  END IF;
  -- 06:45 UTC daily — slot engineered to avoid clash with the 12 jobs
  -- enumerated in CRON_HEALTH_RUNBOOK.md (L12-02 redistribution).
  PERFORM cron.schedule(
    'stale-withdrawals-alert',
    '45 6 * * *',
    $job$SELECT public.fn_alert_stale_withdrawals_safe();$job$
  );
END $$;

INSERT INTO public.cron_run_state (name, last_status)
VALUES ('stale-withdrawals-alert', 'never_run')
ON CONFLICT (name) DO NOTHING;

COMMIT;
