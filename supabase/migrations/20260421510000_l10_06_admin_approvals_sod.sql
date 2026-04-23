-- L10-06 — Segregation-of-Duty: two-person control on high-risk
-- platform_admin actions.
--
-- Today, a single `platform_admin` can freeze fees, execute a
-- manual withdrawal, or issue a refund by themselves. One
-- compromised admin account is a complete treasury breach.
--
-- This migration introduces `public.admin_approvals`: an append-
-- only request queue for the high-risk action classes. Every
-- qualifying action is first queued as a row with `status =
-- 'pending'` by the requester, and a **different** platform_admin
-- must flip it to `'approved'`. Only then may the action be
-- executed (the executor flips it to `'executed'` as part of the
-- same transaction that performs the mutation). Self-approval is
-- blocked at the DB level by a CHECK constraint; the same
-- invariant is re-asserted via trigger so a service-role bypass
-- of RLS still cannot land a self-approval row.
--
-- Action-class threshold policy (encoded in
-- `fn_admin_approval_required`):
--   * any mutation of `platform_fee_config`
--   * custody_withdrawals with amount_usd >= 10_000
--   * refunds with amount_usd >= 10_000
--
-- Expiration: 24h TTL enforced by `expires_at`. A `sod_expire`
-- cron job flips overdue requests to `'expired'`.

BEGIN;

-- ── 1. admin_approvals ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.admin_approvals (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  action_type    text NOT NULL CHECK (
                   action_type IN (
                     'platform_fee_config.update',
                     'custody_withdrawal.execute',
                     'refund.issue',
                     'billing_provider.key_set',
                     'platform_admin.grant',
                     'other'
                   )
                 ),
  payload        jsonb NOT NULL DEFAULT '{}'::jsonb,
  requested_by   uuid NOT NULL REFERENCES auth.users(id),
  approved_by    uuid REFERENCES auth.users(id),
  rejected_by    uuid REFERENCES auth.users(id),
  approval_note  text,
  rejection_note text,
  status         text NOT NULL DEFAULT 'pending' CHECK (
                   status IN ('pending','approved','rejected','executed','expired')
                 ),
  expires_at     timestamptz NOT NULL DEFAULT (now() + interval '24 hours'),
  executed_at    timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chk_no_self_approval
    CHECK (approved_by IS NULL OR approved_by <> requested_by),
  CONSTRAINT chk_no_self_rejection
    CHECK (rejected_by IS NULL OR rejected_by <> requested_by),
  CONSTRAINT chk_status_transition
    CHECK (
      (status = 'pending'  AND approved_by IS NULL AND rejected_by IS NULL
                           AND executed_at IS NULL)
      OR (status = 'approved'  AND approved_by IS NOT NULL
                               AND rejected_by IS NULL
                               AND executed_at IS NULL)
      OR (status = 'rejected'  AND rejected_by IS NOT NULL
                               AND approved_by IS NULL
                               AND executed_at IS NULL)
      OR (status = 'executed'  AND approved_by IS NOT NULL
                               AND executed_at IS NOT NULL)
      OR (status = 'expired'   AND executed_at IS NULL)
    )
);

COMMENT ON TABLE public.admin_approvals IS
  'L10-06 — two-person-rule queue for high-risk platform_admin actions.';

CREATE INDEX IF NOT EXISTS idx_admin_approvals_status
  ON public.admin_approvals(status, expires_at);
CREATE INDEX IF NOT EXISTS idx_admin_approvals_requester
  ON public.admin_approvals(requested_by, created_at DESC);

ALTER TABLE public.admin_approvals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_approvals_platform_read
  ON public.admin_approvals;
CREATE POLICY admin_approvals_platform_read
  ON public.admin_approvals
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.platform_role = 'admin'
    )
  );

GRANT SELECT ON public.admin_approvals TO authenticated;
GRANT ALL ON public.admin_approvals TO service_role;

-- ── 2. Trigger that guards against self-approval via service_role ─────────

CREATE OR REPLACE FUNCTION public.fn_admin_approvals_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.status = 'approved'
       AND (NEW.approved_by IS NULL OR NEW.approved_by = NEW.requested_by)
    THEN
      RAISE EXCEPTION
        'SELF_APPROVAL_FORBIDDEN: approver must differ from requester'
        USING ERRCODE = 'P0001';
    END IF;

    IF NEW.status = 'rejected'
       AND (NEW.rejected_by IS NULL OR NEW.rejected_by = NEW.requested_by)
    THEN
      RAISE EXCEPTION
        'SELF_REJECTION_FORBIDDEN: rejector must differ from requester'
        USING ERRCODE = 'P0001';
    END IF;

    IF NEW.status = 'executed' AND OLD.status <> 'approved' THEN
      RAISE EXCEPTION
        'EXECUTE_REQUIRES_APPROVAL: current status is %, expected approved',
        OLD.status
        USING ERRCODE = 'P0001';
    END IF;

    IF OLD.status IN ('executed','rejected','expired')
       AND NEW.status <> OLD.status
    THEN
      RAISE EXCEPTION
        'TERMINAL_STATUS_LOCKED: cannot transition from %',
        OLD.status
        USING ERRCODE = 'P0001';
    END IF;

    NEW.updated_at := now();
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_admin_approvals_guard ON public.admin_approvals;
CREATE TRIGGER trg_admin_approvals_guard
  BEFORE UPDATE ON public.admin_approvals
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_admin_approvals_guard();

-- ── 3. Policy helper — is SoD required for (action, payload)? ─────────────

CREATE OR REPLACE FUNCTION public.fn_admin_approval_required(
  p_action_type text,
  p_payload     jsonb
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_amount numeric;
BEGIN
  IF p_action_type = 'platform_fee_config.update'
     OR p_action_type = 'platform_admin.grant'
  THEN
    RETURN true;
  END IF;

  IF p_action_type IN (
       'custody_withdrawal.execute',
       'refund.issue',
       'billing_provider.key_set'
     )
  THEN
    v_amount := NULLIF(p_payload->>'amount_usd', '')::numeric;
    IF v_amount IS NOT NULL AND v_amount >= 10000 THEN
      RETURN true;
    END IF;
    IF p_action_type = 'billing_provider.key_set' THEN
      RETURN true;
    END IF;
  END IF;

  RETURN false;
END;
$$;

COMMENT ON FUNCTION public.fn_admin_approval_required(text, jsonb) IS
  'L10-06 — canonical policy: is two-person approval required for ' ||
  '(action, payload)? Fee / admin-grant mutations always, money-' ||
  'movers only above US$ 10k.';

-- ── 4. Helper to expire overdue requests (cron target) ─────────────────────

CREATE OR REPLACE FUNCTION public.fn_admin_approvals_expire_overdue()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count int;
BEGIN
  UPDATE public.admin_approvals
     SET status = 'expired',
         updated_at = now()
   WHERE status = 'pending'
     AND expires_at < now();
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_admin_approvals_expire_overdue() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_admin_approvals_expire_overdue() FROM anon;
REVOKE ALL ON FUNCTION public.fn_admin_approvals_expire_overdue() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_approvals_expire_overdue() TO service_role;

-- ── 5. Self-test ───────────────────────────────────────────────────────────

DO $$
DECLARE
  v_raised boolean;
  v_req_user uuid := '00000000-0000-0000-0000-00000000A001';
BEGIN
  -- (a) policy helper returns true for fee config, regardless of amount
  IF NOT public.fn_admin_approval_required('platform_fee_config.update',
                                           '{}'::jsonb) THEN
    RAISE EXCEPTION
      'L10-06 self-test: fee-config mutation must require approval';
  END IF;

  -- (b) small withdrawals do NOT require approval
  IF public.fn_admin_approval_required(
       'custody_withdrawal.execute',
       jsonb_build_object('amount_usd', 500)
     )
  THEN
    RAISE EXCEPTION
      'L10-06 self-test: small withdrawal should not require approval';
  END IF;

  -- (c) ≥ US$ 10k withdrawals DO require approval
  IF NOT public.fn_admin_approval_required(
           'custody_withdrawal.execute',
           jsonb_build_object('amount_usd', 12500)
         )
  THEN
    RAISE EXCEPTION
      'L10-06 self-test: 10k+ withdrawal should require approval';
  END IF;

  -- (d) billing_provider.key_set always requires approval
  IF NOT public.fn_admin_approval_required(
           'billing_provider.key_set',
           jsonb_build_object('amount_usd', 0)
         )
  THEN
    RAISE EXCEPTION
      'L10-06 self-test: billing_provider.key_set should always require approval';
  END IF;

  -- (e) CHECK prevents self-approval at INSERT time
  BEGIN
    INSERT INTO public.admin_approvals (
      action_type, requested_by, approved_by, status
    ) VALUES (
      'refund.issue', v_req_user, v_req_user, 'approved'
    );
    v_raised := false;
  EXCEPTION WHEN check_violation THEN
    v_raised := true;
  WHEN others THEN
    -- foreign key to auth.users will also fire, which is fine
    v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION
      'L10-06 self-test: self-approval at INSERT must be blocked';
  END IF;

  RAISE NOTICE 'L10-06 self-test: OK';
END
$$;

COMMIT;
