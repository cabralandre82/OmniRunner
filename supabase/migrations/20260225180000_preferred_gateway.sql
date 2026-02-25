-- ============================================================================
-- Omni Runner — Add preferred_gateway to billing_customers
-- Date: 2026-02-25
-- Sprint: 35.5.1
-- ============================================================================
-- Allows each assessoria to choose their default payment gateway.
-- 'mercadopago' = Pix, Boleto, Cartão via MercadoPago (default)
-- 'stripe'      = Cartão internacional via Stripe (enables auto-topup)

ALTER TABLE public.billing_customers
  ADD COLUMN IF NOT EXISTS preferred_gateway TEXT NOT NULL DEFAULT 'mercadopago'
    CHECK (preferred_gateway IN ('mercadopago', 'stripe'));

COMMENT ON COLUMN public.billing_customers.preferred_gateway IS
  'Default payment gateway for this group. mercadopago or stripe.';
