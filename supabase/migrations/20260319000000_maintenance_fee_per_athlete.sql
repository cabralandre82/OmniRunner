-- ============================================================================
-- Maintenance Fee: USD per active athlete, deducted from subscription payment
-- Date: 2026-03-19
--
-- The fee is charged via Asaas Split (fixedValue) when the athlete pays.
-- Recorded in platform_revenue when the PAYMENT_CONFIRMED webhook fires.
-- No cron needed — it piggybacks on the existing billing flow.
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Ensure platform_revenue table exists
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.platform_revenue (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fee_type      text NOT NULL CHECK (fee_type IN ('clearing', 'swap', 'fx_spread', 'maintenance', 'billing_split')),
  amount_usd    numeric(14,2) NOT NULL CHECK (amount_usd > 0),
  source_ref_id text,
  group_id      uuid REFERENCES public.coaching_groups(id),
  description   text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.platform_revenue ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  CREATE POLICY "platform_revenue_admin_read" ON public.platform_revenue
    FOR SELECT USING (
      EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND platform_role = 'admin')
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_platform_revenue_type
  ON public.platform_revenue(fee_type, created_at DESC);

GRANT ALL ON TABLE public.platform_revenue TO service_role;
GRANT SELECT ON TABLE public.platform_revenue TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Add rate_usd column to platform_fee_config
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.platform_fee_config
  ADD COLUMN IF NOT EXISTS rate_usd NUMERIC(6,2) DEFAULT NULL;

DO $$
BEGIN
  ALTER TABLE public.platform_fee_config
    ADD CONSTRAINT chk_rate_usd_range
    CHECK (rate_usd IS NULL OR (rate_usd >= 0 AND rate_usd <= 10));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

UPDATE public.platform_fee_config
SET rate_usd = 2.00, rate_pct = 0.00
WHERE fee_type = 'maintenance';

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. Idempotency index: one maintenance record per payment
-- ═══════════════════════════════════════════════════════════════════════════

CREATE UNIQUE INDEX IF NOT EXISTS idx_platform_revenue_maint_idempotent
  ON public.platform_revenue (fee_type, source_ref_id)
  WHERE fee_type = 'maintenance';

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. Remove cron-based fn_charge_maintenance_fees (wrong approach, replaced
--    by webhook-driven deduction via Asaas Split)
-- ═══════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.fn_charge_maintenance_fees();

DO $$
BEGIN
  PERFORM cron.unschedule('maintenance-fee-monthly');
EXCEPTION WHEN undefined_function THEN NULL;
WHEN OTHERS THEN NULL;
END $$;

COMMIT;
