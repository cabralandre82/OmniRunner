-- ============================================================================
-- Omni Runner — billing_auto_topup_settings
-- Date: 2026-02-21
-- Sprint: 35.1.1
-- Origin: DECISAO 050 — Auto Top-Up: Recarga Automática de Créditos
-- ============================================================================
-- Per-group opt-in configuration for automatic credit replenishment.
-- When available_tokens drops below threshold_tokens, the system triggers
-- a Stripe PaymentIntent (off-session, card only) for the configured product.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.billing_auto_topup_settings (
  group_id          UUID PRIMARY KEY REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  enabled           BOOLEAN NOT NULL DEFAULT false,
  threshold_tokens  INTEGER NOT NULL DEFAULT 50
                    CHECK (threshold_tokens >= 10 AND threshold_tokens <= 10000),
  product_id        UUID NOT NULL REFERENCES public.billing_products(id),
  max_per_month     INTEGER NOT NULL DEFAULT 3
                    CHECK (max_per_month >= 1 AND max_per_month <= 10),
  last_triggered_at TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.billing_auto_topup_settings IS
  'Per-group auto top-up configuration. Opt-in only. See DECISAO 050.';

COMMENT ON COLUMN public.billing_auto_topup_settings.threshold_tokens IS
  'When available_tokens drops below this value, auto top-up triggers.';

COMMENT ON COLUMN public.billing_auto_topup_settings.product_id IS
  'The billing_products package purchased on each auto top-up.';

COMMENT ON COLUMN public.billing_auto_topup_settings.max_per_month IS
  'Safety cap: maximum auto top-ups allowed per calendar month.';

COMMENT ON COLUMN public.billing_auto_topup_settings.last_triggered_at IS
  'Timestamp of last auto top-up execution. Used for 24h cooldown enforcement.';

-- ── RLS ─────────────────────────────────────────────────────────────────────

ALTER TABLE public.billing_auto_topup_settings ENABLE ROW LEVEL SECURITY;

-- admin_master can read their group's settings
CREATE POLICY "auto_topup_admin_read" ON public.billing_auto_topup_settings
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = billing_auto_topup_settings.group_id
        AND cm.user_id  = auth.uid()
        AND cm.role = 'admin_master'
    )
  );

-- admin_master can update (toggle enabled, change threshold/product)
CREATE POLICY "auto_topup_admin_update" ON public.billing_auto_topup_settings
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = billing_auto_topup_settings.group_id
        AND cm.user_id  = auth.uid()
        AND cm.role = 'admin_master'
    )
  );

-- admin_master can insert initial config for their group
CREATE POLICY "auto_topup_admin_insert" ON public.billing_auto_topup_settings
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = billing_auto_topup_settings.group_id
        AND cm.user_id  = auth.uid()
        AND cm.role = 'admin_master'
    )
  );

-- No DELETE policy — settings are never deleted, only disabled (enabled=false)

COMMIT;
