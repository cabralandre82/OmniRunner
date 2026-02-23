-- ============================================================================
-- Omni Runner — Add Stripe + auto-topup support columns
-- Date: 2026-02-21
-- Sprint: 35.1.2
-- Origin: DECISAO 050 — Auto Top-Up requires saved payment method
-- ============================================================================

-- Stripe fields on billing_customers for off-session charges
ALTER TABLE public.billing_customers
  ADD COLUMN IF NOT EXISTS stripe_customer_id   TEXT,
  ADD COLUMN IF NOT EXISTS stripe_default_pm    TEXT;

COMMENT ON COLUMN public.billing_customers.stripe_customer_id IS
  'Stripe Customer ID. Set via setup-auto-topup Edge Function.';

COMMENT ON COLUMN public.billing_customers.stripe_default_pm IS
  'Stripe default PaymentMethod ID (card) for off-session charges.';

-- Source column on billing_purchases to distinguish manual vs auto_topup (AT-6)
ALTER TABLE public.billing_purchases
  ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'manual'
    CHECK (source IN ('manual', 'auto_topup'));
