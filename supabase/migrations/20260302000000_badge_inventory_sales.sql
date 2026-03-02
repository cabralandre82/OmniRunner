-- ============================================================================
-- Omni Runner — Badge inventory, product types, and championship_id on intents
-- Date: 2026-03-02
-- Origin: Championship badge sales via billing gateway
-- ============================================================================

BEGIN;

-- ── 1. COACHING_BADGE_INVENTORY ─────────────────────────────────────────────
-- Per-group badge credit stock. Purchased via billing, consumed on activation.

CREATE TABLE IF NOT EXISTS public.coaching_badge_inventory (
  group_id            UUID PRIMARY KEY REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  available_badges    INTEGER NOT NULL DEFAULT 0 CHECK (available_badges >= 0),
  lifetime_purchased  INTEGER NOT NULL DEFAULT 0,
  lifetime_activated  INTEGER NOT NULL DEFAULT 0,
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.coaching_badge_inventory ENABLE ROW LEVEL SECURITY;

CREATE POLICY "badge_inventory_staff_read" ON public.coaching_badge_inventory
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_badge_inventory.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'professor', 'assistente')
    )
  );

-- ── 2. ADD product_type TO billing_products ─────────────────────────────────

ALTER TABLE public.billing_products
  ADD COLUMN IF NOT EXISTS product_type TEXT NOT NULL DEFAULT 'coins'
    CHECK (product_type IN ('coins', 'badges'));

COMMENT ON COLUMN public.billing_products.product_type IS
  'Differentiates OmniCoin credit packages from championship badge packages.';

-- ── 3. ADD championship_id TO token_intents ─────────────────────────────────

ALTER TABLE public.token_intents
  ADD COLUMN IF NOT EXISTS championship_id UUID REFERENCES public.championships(id);

CREATE INDEX IF NOT EXISTS idx_token_intents_championship
  ON public.token_intents(championship_id) WHERE championship_id IS NOT NULL;

-- ── 4. fn_credit_badge_inventory ────────────────────────────────────────────
-- Atomic credit allocation for badge purchases.

CREATE OR REPLACE FUNCTION public.fn_credit_badge_inventory(
  p_group_id   UUID,
  p_amount     INTEGER,
  p_source_ref TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'amount must be positive';
  END IF;

  INSERT INTO public.coaching_badge_inventory (group_id, available_badges, lifetime_purchased)
  VALUES (p_group_id, p_amount, p_amount)
  ON CONFLICT (group_id) DO UPDATE SET
    available_badges   = coaching_badge_inventory.available_badges + EXCLUDED.available_badges,
    lifetime_purchased = coaching_badge_inventory.lifetime_purchased + EXCLUDED.lifetime_purchased,
    updated_at         = now();
END;
$$;

-- ── 5. fn_decrement_badge_inventory ─────────────────────────────────────────
-- Atomic decrement on badge activation. CHECK constraint prevents negative.

CREATE OR REPLACE FUNCTION public.fn_decrement_badge_inventory(
  p_group_id UUID,
  p_amount   INTEGER DEFAULT 1
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.coaching_badge_inventory
  SET available_badges   = available_badges - p_amount,
      lifetime_activated = lifetime_activated + p_amount,
      updated_at         = now()
  WHERE group_id = p_group_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INSUFFICIENT_BADGE_INVENTORY: no inventory row for group %', p_group_id;
  END IF;
END;
$$;

-- ── 6. Update fn_fulfill_purchase to support badge products ─────────────────
-- Routes to fn_credit_institution (coins) or fn_credit_badge_inventory (badges)
-- based on billing_products.product_type.

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
  v_product     RECORD;
  v_credit_id   UUID;
BEGIN
  SELECT id, group_id, credits_amount, status, product_id
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

  -- Resolve product type (default to 'coins' for legacy purchases without product_id)
  SELECT product_type INTO v_product
  FROM public.billing_products
  WHERE id = v_purchase.product_id;

  IF v_product.product_type = 'badges' THEN
    PERFORM public.fn_credit_badge_inventory(
      v_purchase.group_id,
      v_purchase.credits_amount,
      'billing_purchase:' || p_purchase_id::TEXT
    );
    v_credit_id := gen_random_uuid();
  ELSE
    v_credit_id := public.fn_credit_institution(
      v_purchase.group_id,
      v_purchase.credits_amount,
      'billing_purchase:' || p_purchase_id::TEXT,
      NULL,
      p_admin_user_id
    );
  END IF;

  UPDATE public.billing_purchases
  SET status              = 'fulfilled',
      fulfilled_credit_id = v_credit_id,
      updated_at          = now()
  WHERE id = p_purchase_id;

  INSERT INTO public.billing_events (purchase_id, event_type, actor_id, metadata)
  VALUES (p_purchase_id, 'fulfilled', p_admin_user_id, jsonb_build_object(
    'credit_id', v_credit_id,
    'credits_amount', v_purchase.credits_amount,
    'product_type', COALESCE(v_product.product_type, 'coins')
  ));

  RETURN v_credit_id;
END;
$$;

-- ── 7. Seed: default badge product ──────────────────────────────────────────

INSERT INTO public.billing_products
  (name, description, credits_amount, price_cents, currency, is_active, sort_order, product_type)
VALUES
  ('Badge Campeonato (1 un.)',  'Badge de participação em campeonato — 1 unidade',   1,  1990, 'BRL', true, 10, 'badges'),
  ('Badge Campeonato (5 un.)',  'Pacote 5 badges de campeonato — economia de 10%',   5,  8990, 'BRL', true, 11, 'badges'),
  ('Badge Campeonato (20 un.)', 'Pacote 20 badges de campeonato — economia de 20%', 20, 31990, 'BRL', true, 12, 'badges')
ON CONFLICT DO NOTHING;

COMMIT;
