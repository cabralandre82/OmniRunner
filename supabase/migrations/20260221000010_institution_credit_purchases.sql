-- ============================================================================
-- Omni Runner — institution_credit_purchases (B2B audit trail)
-- Date: 2026-03-01
-- Sprint: 21.1.1
-- Origin: DECISAO 046 — Modelo de Monetização Loja-Safe
-- ============================================================================
-- Append-only audit table for platform → assessoria credit allocations.
-- Records ONLY credit amounts and provenance — never monetary values.
-- Completely separate from coin_ledger (athlete-level).
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.institution_credit_purchases (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id          UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  credits_amount    INTEGER NOT NULL CHECK (credits_amount > 0),
  source_reference  TEXT NOT NULL,
  notes             TEXT,
  created_by        UUID REFERENCES auth.users(id),
  purchased_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.institution_credit_purchases IS
  'B2B audit trail: platform credits allocated to assessorias. '
  'Append-only. No monetary values stored. See DECISAO 046.';

COMMENT ON COLUMN public.institution_credit_purchases.credits_amount IS
  'Number of OmniCoins credited to the group inventory.';

COMMENT ON COLUMN public.institution_credit_purchases.source_reference IS
  'Opaque reference for reconciliation (e.g. invoice number, batch ID). '
  'Never a monetary value or price.';

COMMENT ON COLUMN public.institution_credit_purchases.notes IS
  'Optional free-text note from the platform admin.';

COMMENT ON COLUMN public.institution_credit_purchases.created_by IS
  'Platform admin who executed the credit allocation. NULL for automated batch.';

CREATE INDEX idx_icp_group ON public.institution_credit_purchases(group_id);
CREATE INDEX idx_icp_purchased_at ON public.institution_credit_purchases(purchased_at DESC);

-- ── RLS ─────────────────────────────────────────────────────────────────────
-- This table is for platform-level audit only.
-- No client-side writes. Reads restricted to admin_master of the group.

ALTER TABLE public.institution_credit_purchases ENABLE ROW LEVEL SECURITY;

CREATE POLICY "icp_admin_master_read" ON public.institution_credit_purchases
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = institution_credit_purchases.group_id
        AND cm.user_id = auth.uid()
        AND cm.role = 'admin_master'
    )
  );

-- ── RPC: credit_institution ─────────────────────────────────────────────────
-- Atomic: inserts audit row + increments inventory in one transaction.
-- SECURITY DEFINER — callable only with service_role key (Edge Function / admin).

CREATE OR REPLACE FUNCTION public.fn_credit_institution(
  p_group_id        UUID,
  p_credits_amount  INTEGER,
  p_source_ref      TEXT,
  p_notes           TEXT DEFAULT NULL,
  p_admin_user_id   UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_purchase_id UUID;
BEGIN
  IF p_credits_amount <= 0 THEN
    RAISE EXCEPTION 'credits_amount must be positive';
  END IF;

  INSERT INTO public.institution_credit_purchases
    (group_id, credits_amount, source_reference, notes, created_by)
  VALUES
    (p_group_id, p_credits_amount, p_source_ref, p_notes, p_admin_user_id)
  RETURNING id INTO v_purchase_id;

  INSERT INTO public.coaching_token_inventory (group_id, available_tokens, lifetime_issued)
  VALUES (p_group_id, p_credits_amount, p_credits_amount)
  ON CONFLICT (group_id) DO UPDATE SET
    available_tokens = coaching_token_inventory.available_tokens + EXCLUDED.available_tokens,
    lifetime_issued  = coaching_token_inventory.lifetime_issued  + EXCLUDED.lifetime_issued,
    updated_at       = now();

  RETURN v_purchase_id;
END;
$$;

COMMENT ON FUNCTION public.fn_credit_institution IS
  'Atomic credit allocation: audit row + inventory increment. '
  'Service-role only. See DECISAO 046.';

COMMIT;
