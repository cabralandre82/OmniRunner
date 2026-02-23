-- ============================================================================
-- Omni Runner — Billing Portal tables
-- Date: 2026-02-21
-- Sprint: 30.2.0
-- Origin: DECISAO 047 (Portal Stack) + DECISAO 048 (Auth Model)
-- ============================================================================
-- B2B-only tables for the Billing Portal. These tables are NEVER read by
-- the mobile app. They store commercial information (plans, invoices) that
-- is visible only to assessoria staff via the web portal.
--
-- Relationship with existing tables:
--   billing_purchases.fulfilled_credit_id → institution_credit_purchases.id
--   (links a paid invoice to the actual credit allocation in the app ecosystem)
--
-- RLS pattern: staff of the group can SELECT; all mutations via service_role
-- (Edge Functions / API Routes). Follows clearing_tables.sql pattern.
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. billing_customers — assessoria as a billing entity
-- ═══════════════════════════════════════════════════════════════════════════
-- One row per coaching_group that has billing info registered.
-- Not every group needs a row here (only those that buy credits via portal).

CREATE TABLE IF NOT EXISTS public.billing_customers (
  group_id        UUID PRIMARY KEY REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  legal_name      TEXT NOT NULL CHECK (length(legal_name) >= 2),
  tax_id          TEXT,
  email           TEXT NOT NULL,
  phone           TEXT,
  address_line    TEXT,
  address_city    TEXT,
  address_state   TEXT,
  address_zip     TEXT,
  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.billing_customers IS
  'B2B billing entity for assessorias. Portal-only. See DECISAO 047.';

COMMENT ON COLUMN public.billing_customers.tax_id IS
  'CNPJ or CPF of the assessoria (Brazilian tax identifier).';

ALTER TABLE public.billing_customers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "billing_customers_admin_read" ON public.billing_customers
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = billing_customers.group_id
        AND cm.user_id  = auth.uid()
        AND cm.role = 'admin_master'
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. billing_products — credit packages available for purchase
-- ═══════════════════════════════════════════════════════════════════════════
-- Platform-managed catalog of purchasable credit bundles.
-- Only platform admins create/update products (via service_role).

CREATE TABLE IF NOT EXISTS public.billing_products (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name            TEXT NOT NULL CHECK (length(name) >= 2),
  description     TEXT NOT NULL DEFAULT '',
  credits_amount  INTEGER NOT NULL CHECK (credits_amount > 0),
  price_cents     INTEGER NOT NULL CHECK (price_cents > 0),
  currency        TEXT NOT NULL DEFAULT 'BRL' CHECK (length(currency) = 3),
  is_active       BOOLEAN NOT NULL DEFAULT true,
  sort_order      INTEGER NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.billing_products IS
  'Credit packages for B2B purchase. Portal-only catalog. See DECISAO 047.';

COMMENT ON COLUMN public.billing_products.price_cents IS
  'Price in minor currency units (e.g. centavos for BRL). '
  'NEVER shown in the mobile app — portal only.';

ALTER TABLE public.billing_products ENABLE ROW LEVEL SECURITY;

-- Any authenticated staff can browse the product catalog
CREATE POLICY "billing_products_staff_read" ON public.billing_products
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'professor', 'assistente')
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. billing_purchases — purchase orders / invoices
-- ═══════════════════════════════════════════════════════════════════════════
-- Lifecycle: pending → paid → fulfilled (credits allocated) | cancelled
-- When status becomes 'fulfilled', fn_credit_institution is called to
-- atomically credit the assessoria's coaching_token_inventory.

CREATE TABLE IF NOT EXISTS public.billing_purchases (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id              UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  product_id            UUID REFERENCES public.billing_products(id),
  credits_amount        INTEGER NOT NULL CHECK (credits_amount > 0),
  price_cents           INTEGER NOT NULL CHECK (price_cents > 0),
  currency              TEXT NOT NULL DEFAULT 'BRL' CHECK (length(currency) = 3),
  status                TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'paid', 'fulfilled', 'cancelled')),
  payment_method        TEXT,
  payment_reference     TEXT,
  invoice_url           TEXT,
  fulfilled_credit_id   UUID REFERENCES public.institution_credit_purchases(id),
  requested_by          UUID REFERENCES auth.users(id),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.billing_purchases IS
  'Purchase orders for credit packages. Portal-only. See DECISAO 047.';

COMMENT ON COLUMN public.billing_purchases.fulfilled_credit_id IS
  'Links to institution_credit_purchases after credits are allocated. '
  'Set when status transitions to fulfilled.';

COMMENT ON COLUMN public.billing_purchases.payment_method IS
  'pix, boleto, transfer, or other external payment method.';

CREATE INDEX idx_billing_purchases_group
  ON public.billing_purchases(group_id, created_at DESC);

CREATE INDEX idx_billing_purchases_status
  ON public.billing_purchases(status)
  WHERE status IN ('pending', 'paid');

ALTER TABLE public.billing_purchases ENABLE ROW LEVEL SECURITY;

-- admin_master can see their group's purchases
CREATE POLICY "billing_purchases_admin_read" ON public.billing_purchases
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = billing_purchases.group_id
        AND cm.user_id  = auth.uid()
        AND cm.role = 'admin_master'
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. billing_events — lifecycle event log for purchases
-- ═══════════════════════════════════════════════════════════════════════════
-- Append-only audit trail for purchase state transitions.

CREATE TABLE IF NOT EXISTS public.billing_events (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_id   UUID NOT NULL REFERENCES public.billing_purchases(id) ON DELETE CASCADE,
  event_type    TEXT NOT NULL
    CHECK (event_type IN (
      'created',
      'payment_confirmed',
      'fulfilled',
      'cancelled',
      'refunded',
      'note_added'
    )),
  actor_id      UUID REFERENCES auth.users(id),
  metadata      JSONB NOT NULL DEFAULT '{}',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.billing_events IS
  'Append-only audit log for billing purchase lifecycle. Portal-only.';

CREATE INDEX idx_billing_events_purchase
  ON public.billing_events(purchase_id, created_at DESC);

ALTER TABLE public.billing_events ENABLE ROW LEVEL SECURITY;

-- admin_master can see events for their group's purchases
CREATE POLICY "billing_events_admin_read" ON public.billing_events
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.billing_purchases bp
      JOIN public.coaching_members cm
        ON cm.group_id = bp.group_id
       AND cm.user_id  = auth.uid()
       AND cm.role = 'admin_master'
      WHERE bp.id = billing_events.purchase_id
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. RPC: fn_fulfill_purchase — atomic fulfill + credit allocation
-- ═══════════════════════════════════════════════════════════════════════════
-- Transitions a purchase from 'paid' → 'fulfilled', calls
-- fn_credit_institution to allocate credits, and links the result.
-- SECURITY DEFINER — service_role only.

CREATE OR REPLACE FUNCTION public.fn_fulfill_purchase(
  p_purchase_id   UUID,
  p_admin_user_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_purchase    RECORD;
  v_credit_id   UUID;
BEGIN
  SELECT id, group_id, credits_amount, status
  INTO v_purchase
  FROM public.billing_purchases
  WHERE id = p_purchase_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'purchase not found: %', p_purchase_id;
  END IF;

  IF v_purchase.status != 'paid' THEN
    RAISE EXCEPTION 'purchase must be in paid status, got: %', v_purchase.status;
  END IF;

  -- Allocate credits via existing fn_credit_institution
  v_credit_id := public.fn_credit_institution(
    v_purchase.group_id,
    v_purchase.credits_amount,
    'billing_purchase:' || p_purchase_id::TEXT,
    NULL,
    p_admin_user_id
  );

  -- Transition purchase to fulfilled
  UPDATE public.billing_purchases
  SET status              = 'fulfilled',
      fulfilled_credit_id = v_credit_id,
      updated_at          = now()
  WHERE id = p_purchase_id;

  -- Append event
  INSERT INTO public.billing_events (purchase_id, event_type, actor_id, metadata)
  VALUES (p_purchase_id, 'fulfilled', p_admin_user_id, jsonb_build_object(
    'credit_id', v_credit_id,
    'credits_amount', v_purchase.credits_amount
  ));

  RETURN v_credit_id;
END;
$$;

COMMENT ON FUNCTION public.fn_fulfill_purchase IS
  'Atomic: paid → fulfilled + credit allocation via fn_credit_institution. '
  'Service-role only. See DECISAO 047.';

COMMIT;
