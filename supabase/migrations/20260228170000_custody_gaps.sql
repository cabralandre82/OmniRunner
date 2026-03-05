-- ============================================================================
-- Migration: Custody Gaps — revenue, withdrawal, FX, idempotency, invariants
-- Covers: PASSO 2 (idempotency+FX), PASSO 4 (UNIQUE burn_ref), PASSO 5 (revenue),
--         PASSO 8 (withdrawal), PASSO 9 (R=M invariant)
-- ============================================================================

-- 1. Platform revenue table (fee destination)
CREATE TABLE IF NOT EXISTS public.platform_revenue (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fee_type      text NOT NULL CHECK (fee_type IN ('clearing', 'swap', 'fx_spread', 'maintenance')),
  amount_usd    numeric(14,2) NOT NULL CHECK (amount_usd > 0),
  source_ref_id text,
  group_id      uuid REFERENCES public.coaching_groups(id),
  description   text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.platform_revenue ENABLE ROW LEVEL SECURITY;
CREATE POLICY "platform_revenue_admin_read" ON public.platform_revenue
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND platform_role = 'admin')
  );

CREATE INDEX idx_platform_revenue_type ON public.platform_revenue(fee_type, created_at DESC);

GRANT ALL ON TABLE public.platform_revenue TO service_role;
GRANT SELECT ON TABLE public.platform_revenue TO authenticated;

-- 2. Idempotency: UNIQUE constraint on custody_deposits.payment_reference
--    (only for non-null references to allow multiple pending deposits)
CREATE UNIQUE INDEX IF NOT EXISTS idx_custody_deposits_payment_ref
  ON public.custody_deposits(payment_reference)
  WHERE payment_reference IS NOT NULL;

-- 3. Idempotency: UNIQUE constraint on clearing_events.burn_ref_id
CREATE UNIQUE INDEX IF NOT EXISTS idx_clearing_events_burn_ref
  ON public.clearing_events(burn_ref_id);

-- 4. FX spread config (add to platform_fee_config)
INSERT INTO public.platform_fee_config (fee_type, rate_pct) VALUES
  ('fx_spread', 0.75)
ON CONFLICT (fee_type) DO NOTHING;

-- 5. Custody deposits: add FX fields
ALTER TABLE public.custody_deposits
  ADD COLUMN IF NOT EXISTS original_currency text DEFAULT 'USD',
  ADD COLUMN IF NOT EXISTS original_amount numeric(14,2),
  ADD COLUMN IF NOT EXISTS fx_rate numeric(10,6),
  ADD COLUMN IF NOT EXISTS fx_spread_pct numeric(5,2) DEFAULT 0;

-- 6. Custody withdrawals table
CREATE TABLE IF NOT EXISTS public.custody_withdrawals (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  amount_usd      numeric(14,2) NOT NULL CHECK (amount_usd > 0),
  target_currency text NOT NULL DEFAULT 'BRL',
  fx_rate         numeric(10,6) NOT NULL,
  fx_spread_pct   numeric(5,2) NOT NULL,
  fx_spread_usd   numeric(14,2) NOT NULL DEFAULT 0,
  provider_fee_usd numeric(14,2) NOT NULL DEFAULT 0,
  net_local_amount numeric(14,2) NOT NULL,
  payout_reference text,
  status          text NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  completed_at    timestamptz
);

ALTER TABLE public.custody_withdrawals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "withdrawals_own_group_read" ON public.custody_withdrawals
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = custody_withdrawals.group_id
        AND cm.user_id = auth.uid()
        AND cm.role = 'admin_master'
    )
  );

CREATE INDEX idx_custody_withdrawals_group ON public.custody_withdrawals(group_id, created_at DESC);
GRANT ALL ON TABLE public.custody_withdrawals TO service_role;
GRANT SELECT ON TABLE public.custody_withdrawals TO authenticated;

-- 7. Withdrawal execution function (atomic, available-only)
CREATE OR REPLACE FUNCTION public.execute_withdrawal(
  p_withdrawal_id uuid
)
  RETURNS void
  LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_group_id  uuid;
  v_amount    numeric(14,2);
  v_available numeric(14,2);
  v_fx_spread numeric(14,2);
BEGIN
  SELECT group_id, amount_usd, fx_spread_usd
  INTO v_group_id, v_amount, v_fx_spread
  FROM public.custody_withdrawals
  WHERE id = p_withdrawal_id AND status = 'pending'
  FOR UPDATE;

  IF v_group_id IS NULL THEN
    RAISE EXCEPTION 'Withdrawal not found or not pending';
  END IF;

  SELECT total_deposited_usd - total_committed INTO v_available
  FROM public.custody_accounts
  WHERE group_id = v_group_id
  FOR UPDATE;

  IF v_available IS NULL OR v_available < v_amount THEN
    UPDATE public.custody_withdrawals
    SET status = 'failed'
    WHERE id = p_withdrawal_id;
    RAISE EXCEPTION 'Insufficient available: available=%, requested=%',
      COALESCE(v_available, 0), v_amount;
  END IF;

  UPDATE public.custody_accounts
  SET total_deposited_usd = total_deposited_usd - v_amount,
      updated_at = now()
  WHERE group_id = v_group_id;

  UPDATE public.custody_withdrawals
  SET status = 'processing'
  WHERE id = p_withdrawal_id;

  IF v_fx_spread > 0 THEN
    INSERT INTO public.platform_revenue (fee_type, amount_usd, source_ref_id, group_id, description)
    VALUES ('fx_spread', v_fx_spread, p_withdrawal_id::text, v_group_id, 'FX spread on withdrawal');
  END IF;
END;
$$;

-- 8. Updated settle_clearing: credit fee to platform_revenue
CREATE OR REPLACE FUNCTION public.settle_clearing(p_settlement_id uuid)
  RETURNS void
  LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_debtor      uuid;
  v_creditor    uuid;
  v_coin_amount integer;
  v_net         numeric(14,2);
  v_fee         numeric(14,2);
  v_gross       numeric(14,2);
  v_committed   numeric(14,2);
BEGIN
  SELECT debtor_group_id, creditor_group_id, coin_amount,
         net_amount_usd, fee_amount_usd, gross_amount_usd
  INTO v_debtor, v_creditor, v_coin_amount, v_net, v_fee, v_gross
  FROM public.clearing_settlements
  WHERE id = p_settlement_id AND status = 'pending'
  FOR UPDATE;

  IF v_debtor IS NULL THEN
    RAISE EXCEPTION 'Settlement not found or not pending';
  END IF;

  SELECT total_committed INTO v_committed
  FROM public.custody_accounts
  WHERE group_id = v_debtor
  FOR UPDATE;

  IF v_committed IS NULL OR v_committed < v_coin_amount THEN
    UPDATE public.clearing_settlements
    SET status = 'insufficient'
    WHERE id = p_settlement_id;
    RETURN;
  END IF;

  UPDATE public.custody_accounts
  SET total_committed = total_committed - v_coin_amount,
      total_deposited_usd = total_deposited_usd - v_gross,
      total_settled_usd = total_settled_usd + v_gross,
      updated_at = now()
  WHERE group_id = v_debtor;

  UPDATE public.custody_accounts
  SET total_deposited_usd = total_deposited_usd + v_net,
      updated_at = now()
  WHERE group_id = v_creditor;

  -- Credit fee to platform revenue
  IF v_fee > 0 THEN
    INSERT INTO public.platform_revenue (fee_type, amount_usd, source_ref_id, group_id, description)
    VALUES ('clearing', v_fee, p_settlement_id::text, v_debtor,
            format('Clearing fee: %s coins from %s to %s', v_coin_amount, v_debtor, v_creditor));
  END IF;

  UPDATE public.clearing_settlements
  SET status = 'settled', settled_at = now()
  WHERE id = p_settlement_id;
END;
$$;

-- 9. Updated execute_swap: credit fee to platform_revenue
CREATE OR REPLACE FUNCTION public.execute_swap(
  p_order_id uuid,
  p_buyer_group_id uuid
)
  RETURNS void
  LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_seller       uuid;
  v_amount       numeric(14,2);
  v_fee          numeric(14,2);
  v_net          numeric(14,2);
  v_seller_avail numeric(14,2);
BEGIN
  SELECT seller_group_id, amount_usd, fee_amount_usd
  INTO v_seller, v_amount, v_fee
  FROM public.swap_orders
  WHERE id = p_order_id AND status = 'open'
  FOR UPDATE;

  IF v_seller IS NULL THEN
    RAISE EXCEPTION 'Swap order not found or no longer open';
  END IF;

  IF v_seller = p_buyer_group_id THEN
    RAISE EXCEPTION 'Cannot buy your own swap offer';
  END IF;

  v_net := v_amount - v_fee;

  INSERT INTO public.custody_accounts (group_id, total_deposited_usd)
  VALUES (p_buyer_group_id, 0)
  ON CONFLICT (group_id) DO NOTHING;

  IF v_seller < p_buyer_group_id THEN
    SELECT total_deposited_usd - total_committed INTO v_seller_avail
    FROM public.custody_accounts WHERE group_id = v_seller FOR UPDATE;
    PERFORM 1 FROM public.custody_accounts WHERE group_id = p_buyer_group_id FOR UPDATE;
  ELSE
    PERFORM 1 FROM public.custody_accounts WHERE group_id = p_buyer_group_id FOR UPDATE;
    SELECT total_deposited_usd - total_committed INTO v_seller_avail
    FROM public.custody_accounts WHERE group_id = v_seller FOR UPDATE;
  END IF;

  IF v_seller_avail IS NULL OR v_seller_avail < v_amount THEN
    RAISE EXCEPTION 'Seller insufficient available backing: avail=%, needed=%',
      COALESCE(v_seller_avail, 0), v_amount;
  END IF;

  UPDATE public.custody_accounts
  SET total_deposited_usd = total_deposited_usd - v_amount,
      updated_at = now()
  WHERE group_id = v_seller;

  UPDATE public.custody_accounts
  SET total_deposited_usd = total_deposited_usd + v_net,
      updated_at = now()
  WHERE group_id = p_buyer_group_id;

  -- Credit swap fee to platform revenue
  IF v_fee > 0 THEN
    INSERT INTO public.platform_revenue (fee_type, amount_usd, source_ref_id, group_id, description)
    VALUES ('swap', v_fee, p_order_id::text, v_seller,
            format('Swap fee: %s sells %s USD to %s', v_seller, v_amount, p_buyer_group_id));
  END IF;

  UPDATE public.swap_orders
  SET buyer_group_id = p_buyer_group_id,
      status = 'settled',
      settled_at = now()
  WHERE id = p_order_id;
END;
$$;

-- 10. Enhanced invariant check: R_i = M_i (reserved == coins alive per issuer)
CREATE OR REPLACE FUNCTION public.check_custody_invariants()
  RETURNS TABLE(
    group_id uuid,
    total_deposited numeric,
    total_committed numeric,
    computed_available numeric,
    violation text
  )
  LANGUAGE sql STABLE
AS $$
  -- Check 1: basic accounting invariants
  SELECT
    ca.group_id,
    ca.total_deposited_usd,
    ca.total_committed,
    ca.total_deposited_usd - ca.total_committed,
    CASE
      WHEN ca.total_committed < 0 THEN 'committed_negative'
      WHEN ca.total_deposited_usd < 0 THEN 'deposited_negative'
      WHEN ca.total_deposited_usd < ca.total_committed THEN 'deposited_less_than_committed'
    END
  FROM public.custody_accounts ca
  WHERE ca.total_committed < 0
     OR ca.total_deposited_usd < 0
     OR ca.total_deposited_usd < ca.total_committed

  UNION ALL

  -- Check 2: R_i = M_i (reserved should match coins in circulation per issuer)
  SELECT
    COALESCE(ca.group_id, cl_agg.issuer_group_id),
    ca.total_deposited_usd,
    ca.total_committed,
    COALESCE(cl_agg.coins_alive, 0),
    format('committed_mismatch: reserved=%s coins_alive=%s diff=%s',
           COALESCE(ca.total_committed, 0),
           COALESCE(cl_agg.coins_alive, 0),
           COALESCE(ca.total_committed, 0) - COALESCE(cl_agg.coins_alive, 0))
  FROM (
    SELECT issuer_group_id, SUM(delta_coins)::numeric AS coins_alive
    FROM public.coin_ledger
    WHERE issuer_group_id IS NOT NULL
    GROUP BY issuer_group_id
    HAVING SUM(delta_coins) <> 0
  ) cl_agg
  FULL OUTER JOIN public.custody_accounts ca
    ON ca.group_id = cl_agg.issuer_group_id
  WHERE ABS(COALESCE(ca.total_committed, 0) - COALESCE(cl_agg.coins_alive, 0)) > 0.01;
$$;

-- 11. Confirm deposit with FX conversion (idempotent by payment_reference)
CREATE OR REPLACE FUNCTION public.confirm_custody_deposit(p_deposit_id uuid)
  RETURNS void
  LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_group_id uuid;
  v_amount   numeric(14,2);
BEGIN
  SELECT group_id, amount_usd INTO v_group_id, v_amount
  FROM public.custody_deposits
  WHERE id = p_deposit_id AND status = 'pending'
  FOR UPDATE;

  IF v_group_id IS NULL THEN
    RAISE EXCEPTION 'Deposit not found or already processed';
  END IF;

  UPDATE public.custody_deposits
  SET status = 'confirmed', confirmed_at = now()
  WHERE id = p_deposit_id;

  INSERT INTO public.custody_accounts (group_id, total_deposited_usd)
  VALUES (v_group_id, v_amount)
  ON CONFLICT (group_id) DO UPDATE
  SET total_deposited_usd = custody_accounts.total_deposited_usd + v_amount,
      updated_at = now();
END;
$$;

-- Grants for new functions/tables
GRANT EXECUTE ON FUNCTION public.execute_withdrawal TO service_role;
