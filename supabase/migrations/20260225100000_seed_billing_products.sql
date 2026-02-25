-- ============================================================================
-- Omni Runner — Seed billing_products with credit packages
-- Date: 2026-02-25
-- ============================================================================

INSERT INTO public.billing_products (name, description, credits_amount, price_cents, currency, is_active, sort_order)
VALUES
  ('Starter',      '50 OmniCoins — ideal para começar',                       50,   2990, 'BRL', true, 1),
  ('Basic',        '120 OmniCoins — 20% de bônus',                           120,   5990, 'BRL', true, 2),
  ('Plus',         '300 OmniCoins — melhor custo-benefício',                  300,  12990, 'BRL', true, 3),
  ('Pro',          '700 OmniCoins — para assessorias em crescimento',         700,  24990, 'BRL', true, 4),
  ('Enterprise',   '1.500 OmniCoins — volume máximo com desconto exclusivo', 1500,  44990, 'BRL', true, 5)
ON CONFLICT DO NOTHING;
