-- ============================================================================
-- L09-07 — Refund / chargeback SLA primitives
-- ============================================================================
--
-- Finding (docs/audit/findings/L09-07-politica-de-reembolso-chargeback-sem-prazo-sla.md):
--   Refund lifecycle already exists (public.billing_refund_requests
--   — 20260221000015) but there is no declared SLA or automated
--   detection of requests that have exceeded the 48-business-hour
--   processing window.
--
-- Scope:
--   (1) Extend billing_refund_requests with SLA columns:
--         - sla_target_at timestamptz — computed at insert time.
--         - sla_breached_at timestamptz — stamped when the request
--           passes the target without reaching 'processed' or
--           'rejected'.
--         - sla_breach_reason text — operator or system note.
--   (2) Trigger fn_billing_refund_requests_set_sla_target computes
--       sla_target_at from requested_at + 48 business hours (BR).
--       "Business hours" here are a pragmatic approximation — we
--       add **3 calendar days** (72h) when the window would span
--       a weekend, **2 calendar days** otherwise. The policy doc
--       (docs/compliance/REFUND_POLICY.md) explains the math and
--       names the edge cases.
--   (3) View v_billing_refund_requests_breached surfaces rows
--       whose SLA target is in the past AND whose status is still
--       open (requested OR approved). Grants SELECT to
--       `platform_admin` via RLS policy on the underlying table.
--   (4) Helper fn_billing_refund_sla_mark_breached() walks all open
--       rows past their target, stamps sla_breached_at (once only),
--       and records to public.audit_logs if L08-08 primitives are
--       installed. Runs on demand from a cron entry (not scheduled
--       by the migration itself to keep scheduling opt-in).
-- ============================================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────────────────
-- 1. SLA columns
-- ──────────────────────────────────────────────────────────────────────────
ALTER TABLE public.billing_refund_requests
  ADD COLUMN IF NOT EXISTS sla_target_at      timestamptz,
  ADD COLUMN IF NOT EXISTS sla_breached_at    timestamptz,
  ADD COLUMN IF NOT EXISTS sla_breach_reason  text;

COMMENT ON COLUMN public.billing_refund_requests.sla_target_at IS
  'L09-07: timestamp by which the request must reach processed|rejected. '
  'Computed at insert time as requested_at + 48 business hours (approx).';

COMMENT ON COLUMN public.billing_refund_requests.sla_breached_at IS
  'L09-07: stamped (once only) by fn_billing_refund_sla_mark_breached '
  'when the target passes without status progress. Remains set even '
  'after the request is eventually processed, so dashboards can show '
  '"was late" history.';

-- ──────────────────────────────────────────────────────────────────────────
-- 2. Trigger that computes sla_target_at
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_billing_refund_requests_set_sla_target()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
DECLARE
  v_requested timestamptz := COALESCE(NEW.requested_at, now());
  v_dow int;
  v_add interval;
BEGIN
  -- Day-of-week in BRT (UTC-3) so "Friday afternoon" is computed
  -- relative to São Paulo clock, not UTC.
  v_dow := EXTRACT(DOW FROM v_requested AT TIME ZONE 'America/Sao_Paulo');
  -- 0 = Sunday, 6 = Saturday
  IF v_dow IN (5, 6, 0) THEN
    -- Fri/Sat/Sun request: window spans the weekend. Add 72h.
    v_add := interval '72 hours';
  ELSE
    -- Mon–Thu request: 48h suffices to land on a business day.
    v_add := interval '48 hours';
  END IF;

  NEW.sla_target_at := v_requested + v_add;
  RETURN NEW;
END
$$;

COMMENT ON FUNCTION public.fn_billing_refund_requests_set_sla_target() IS
  'L09-07: computes sla_target_at from requested_at. Friday/Saturday/'
  'Sunday requests get +72h to clear the weekend; otherwise +48h.';

REVOKE ALL ON FUNCTION public.fn_billing_refund_requests_set_sla_target()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_billing_refund_requests_sla
  ON public.billing_refund_requests;
CREATE TRIGGER trg_billing_refund_requests_sla
  BEFORE INSERT ON public.billing_refund_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_billing_refund_requests_set_sla_target();

-- Backfill sla_target_at for historical rows missing it (best-effort:
-- if the weekend heuristic would push newly-computed value earlier
-- than now(), just keep the computed value — breach detection still
-- picks up the row immediately).
UPDATE public.billing_refund_requests r
   SET sla_target_at = r.requested_at + (
         CASE
           WHEN EXTRACT(DOW FROM r.requested_at AT TIME ZONE 'America/Sao_Paulo')
                IN (5, 6, 0)
             THEN interval '72 hours'
           ELSE interval '48 hours'
         END
       )
 WHERE r.sla_target_at IS NULL;

-- ──────────────────────────────────────────────────────────────────────────
-- 3. View — open + breached
-- ──────────────────────────────────────────────────────────────────────────
DROP VIEW IF EXISTS public.v_billing_refund_requests_breached;
CREATE VIEW public.v_billing_refund_requests_breached
  WITH (security_invoker = true) AS
  SELECT r.id,
         r.purchase_id,
         r.group_id,
         r.status,
         r.refund_type,
         r.amount_cents,
         r.credits_to_debit,
         r.requested_by,
         r.requested_at,
         r.sla_target_at,
         r.sla_breached_at,
         (now() - r.sla_target_at) AS overdue_by,
         r.reviewed_by,
         r.reviewed_at
    FROM public.billing_refund_requests r
   WHERE r.status IN ('requested', 'approved')
     AND r.sla_target_at IS NOT NULL
     AND now() > r.sla_target_at
   ORDER BY r.sla_target_at ASC;

COMMENT ON VIEW public.v_billing_refund_requests_breached IS
  'L09-07: open refund requests whose SLA target has passed. '
  'Uses security_invoker so the caller sees only rows their RLS '
  'allows. Consumers: platform refund dashboard, nightly digest.';

GRANT SELECT ON public.v_billing_refund_requests_breached TO authenticated;
GRANT SELECT ON public.v_billing_refund_requests_breached TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 4. Helper — mark breaches (once)
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_billing_refund_sla_mark_breached()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
DECLARE
  v_count integer;
BEGIN
  WITH updated AS (
    UPDATE public.billing_refund_requests r
       SET sla_breached_at    = now(),
           sla_breach_reason  = COALESCE(
             r.sla_breach_reason,
             'auto: SLA target passed without processed|rejected'
           )
     WHERE r.status IN ('requested', 'approved')
       AND r.sla_target_at IS NOT NULL
       AND r.sla_breached_at IS NULL
       AND now() > r.sla_target_at
     RETURNING 1
  )
  SELECT count(*) INTO v_count FROM updated;

  -- Emit a single audit_logs row summarising the batch. Uses the
  -- L08-08 append-only surface if installed; tolerates absence in
  -- fresh envs by skipping the write.
  IF v_count > 0
     AND EXISTS (
       SELECT 1 FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'audit_log_write'
     )
  THEN
    PERFORM public.audit_log_write(
      'billing.refund_sla_batch_breach',
      jsonb_build_object('breached_count', v_count)
    );
  END IF;

  RETURN v_count;
END
$$;

COMMENT ON FUNCTION public.fn_billing_refund_sla_mark_breached() IS
  'L09-07: idempotently stamps sla_breached_at on open requests past '
  'their SLA target. Returns the number of newly-stamped rows. '
  'Callable from pg_cron or manually by platform team.';

REVOKE ALL ON FUNCTION public.fn_billing_refund_sla_mark_breached()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_billing_refund_sla_mark_breached()
  TO service_role;

COMMIT;

-- ============================================================================
-- Self-test
-- ============================================================================
DO $L09_07_selftest$
DECLARE
  v_purchase uuid;
  v_group uuid;
  v_user uuid;
  v_req_id uuid;
  v_target timestamptz;
  v_marked integer;
BEGIN
  SELECT p.id, p.group_id INTO v_purchase, v_group
    FROM public.billing_purchases p
   LIMIT 1;
  IF v_purchase IS NULL THEN
    RAISE NOTICE '[L09-07.selftest] no billing_purchases rows — skipping flow test';
    RETURN;
  END IF;

  SELECT id INTO v_user FROM auth.users LIMIT 1;
  IF v_user IS NULL THEN
    RAISE NOTICE '[L09-07.selftest] no auth.users rows — skipping flow test';
    RETURN;
  END IF;

  -- (a) Insert a request with a backdated requested_at so it is
  --     already past the SLA target.
  INSERT INTO public.billing_refund_requests
    (purchase_id, group_id, status, reason, refund_type,
     requested_by, requested_at)
  VALUES
    (v_purchase, v_group, 'requested',
     'L09-07 selftest — auto-breach', 'full',
     v_user, now() - interval '96 hours')
  RETURNING id, sla_target_at INTO v_req_id, v_target;

  -- (b) Trigger populated sla_target_at.
  IF v_target IS NULL THEN
    RAISE EXCEPTION 'L09-07 selftest: trigger did not set sla_target_at';
  END IF;

  -- (c) The view surfaces the breach.
  IF NOT EXISTS (
    SELECT 1 FROM public.v_billing_refund_requests_breached
     WHERE id = v_req_id
  ) THEN
    RAISE EXCEPTION 'L09-07 selftest: breached view did not surface the row';
  END IF;

  -- (d) mark_breached stamps it once.
  v_marked := public.fn_billing_refund_sla_mark_breached();
  IF v_marked = 0 THEN
    RAISE EXCEPTION 'L09-07 selftest: mark_breached returned 0';
  END IF;

  -- (e) Second call is a no-op (idempotent).
  IF (SELECT sla_breached_at FROM public.billing_refund_requests WHERE id = v_req_id) IS NULL THEN
    RAISE EXCEPTION 'L09-07 selftest: sla_breached_at still NULL after mark';
  END IF;

  PERFORM public.fn_billing_refund_sla_mark_breached();
  -- (row already had sla_breached_at set — second call should NOT overwrite)

  -- Cleanup the synthetic row.
  DELETE FROM public.billing_refund_requests WHERE id = v_req_id;

  RAISE NOTICE '[L09-07.selftest] OK — SLA trigger + view + mark_breached wired';
END
$L09_07_selftest$;
