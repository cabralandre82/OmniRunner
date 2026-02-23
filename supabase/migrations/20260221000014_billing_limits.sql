-- ============================================================================
-- Omni Runner — billing_limits
-- Date: 2026-02-21
-- Sprint: 35.4.1
-- Origin: DECISAO 052 — Limites Operacionais do Sistema
-- ============================================================================
-- Per-group configurable operational limits for token issuance and redemption.
-- One row per group (group_id PK). Defaults align with DECISAO 052 §2-§3.
-- Edge Functions consult this table before executing token operations.
-- ============================================================================

BEGIN;

-- ── 1. Table ────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.billing_limits (
  group_id              UUID PRIMARY KEY REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  daily_token_limit     INTEGER NOT NULL DEFAULT 5000
                        CHECK (daily_token_limit >= 100 AND daily_token_limit <= 100000),
  daily_redemption_limit INTEGER NOT NULL DEFAULT 5000
                        CHECK (daily_redemption_limit >= 100 AND daily_redemption_limit <= 100000),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.billing_limits IS
  'Per-group daily operational limits for token issuance and redemption. '
  'Defaults: 5000/day each. See DECISAO 052.';

COMMENT ON COLUMN public.billing_limits.daily_token_limit IS
  'Max tokens that staff can issue (ISSUE_TO_ATHLETE) per group per UTC day.';

COMMENT ON COLUMN public.billing_limits.daily_redemption_limit IS
  'Max tokens that can be burned (BURN_FROM_ATHLETE) per group per UTC day.';

-- ── 2. RLS ──────────────────────────────────────────────────────────────────

ALTER TABLE public.billing_limits ENABLE ROW LEVEL SECURITY;

CREATE POLICY "billing_limits_staff_read" ON public.billing_limits
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = billing_limits.group_id
        AND cm.user_id  = auth.uid()
        AND cm.role IN ('admin_master', 'professor', 'assistente')
    )
  );

CREATE POLICY "billing_limits_admin_update" ON public.billing_limits
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = billing_limits.group_id
        AND cm.user_id  = auth.uid()
        AND cm.role = 'admin_master'
    )
  );

-- Insert and delete via service_role only (auto-provisioned when group is created)

-- ── 3. Helper: get effective limits ─────────────────────────────────────────
-- Returns the group's limits or defaults if no row exists yet.

CREATE OR REPLACE FUNCTION public.get_billing_limits(p_group_id uuid)
RETURNS TABLE (daily_token_limit int, daily_redemption_limit int)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    COALESCE(bl.daily_token_limit, 5000)   AS daily_token_limit,
    COALESCE(bl.daily_redemption_limit, 5000) AS daily_redemption_limit
  FROM (SELECT 1) AS dummy
  LEFT JOIN public.billing_limits bl ON bl.group_id = p_group_id;
$$;

COMMENT ON FUNCTION public.get_billing_limits(uuid) IS
  'Returns effective daily limits for a group. Falls back to defaults (5000) if no row exists.';

-- ── 4. Helper: check daily usage against limit ──────────────────────────────
-- Counts today''s token intents of a given type for a group and compares to the limit.
-- Returns remaining capacity (0 = at limit, negative = should never happen).

CREATE OR REPLACE FUNCTION public.check_daily_token_usage(
  p_group_id uuid,
  p_type     text
)
RETURNS int
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit   int;
  v_used    int;
BEGIN
  IF p_type = 'ISSUE_TO_ATHLETE' THEN
    SELECT daily_token_limit INTO v_limit
      FROM public.billing_limits WHERE group_id = p_group_id;
    v_limit := COALESCE(v_limit, 5000);
  ELSIF p_type = 'BURN_FROM_ATHLETE' THEN
    SELECT daily_redemption_limit INTO v_limit
      FROM public.billing_limits WHERE group_id = p_group_id;
    v_limit := COALESCE(v_limit, 5000);
  ELSE
    RETURN 999999;
  END IF;

  SELECT COALESCE(SUM(amount), 0) INTO v_used
    FROM public.token_intents
    WHERE group_id = p_group_id
      AND type = p_type
      AND status IN ('OPEN', 'CONSUMED')
      AND created_at >= date_trunc('day', now() AT TIME ZONE 'UTC');

  RETURN v_limit - v_used;
END;
$$;

COMMENT ON FUNCTION public.check_daily_token_usage(uuid, text) IS
  'Returns remaining daily capacity for token issuance or redemption. '
  'Checks token_intents created today (UTC) against billing_limits. '
  'Returns 999999 for unknown types (no limit enforced).';

COMMIT;
