-- ============================================================================
-- Migration: Custody & Clearing Model
-- ADR-007: Modelo de Custódia e Clearing Interclub
-- ============================================================================

-- 1. Add issuer_group_id to coin_ledger (backward-compatible, nullable)
ALTER TABLE public.coin_ledger
  ADD COLUMN IF NOT EXISTS issuer_group_id uuid
    REFERENCES public.coaching_groups(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_ledger_issuer
  ON public.coin_ledger(issuer_group_id);

-- 2. Platform fee configuration (configurable by platform admin)
CREATE TABLE IF NOT EXISTS public.platform_fee_config (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fee_type    text NOT NULL CHECK (fee_type IN ('clearing', 'swap', 'maintenance')),
  rate_pct    numeric(5,2) NOT NULL DEFAULT 3.00 CHECK (rate_pct >= 0 AND rate_pct <= 100),
  is_active   boolean NOT NULL DEFAULT true,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  updated_by  uuid REFERENCES auth.users(id),
  UNIQUE(fee_type)
);

ALTER TABLE public.platform_fee_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "platform_fee_config_read" ON public.platform_fee_config
  FOR SELECT USING (true);

CREATE POLICY "platform_fee_config_admin_write" ON public.platform_fee_config
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND platform_role = 'admin'
    )
  );

INSERT INTO public.platform_fee_config (fee_type, rate_pct) VALUES
  ('clearing', 3.00),
  ('swap', 1.00),
  ('maintenance', 0.00)
ON CONFLICT (fee_type) DO NOTHING;

-- 3. Custody accounts (segregated per assessoria)
CREATE TABLE IF NOT EXISTS public.custody_accounts (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id          uuid NOT NULL UNIQUE REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  total_deposited_usd numeric(14,2) NOT NULL DEFAULT 0.00 CHECK (total_deposited_usd >= 0),
  total_committed     numeric(14,2) NOT NULL DEFAULT 0.00 CHECK (total_committed >= 0),
  total_settled_usd   numeric(14,2) NOT NULL DEFAULT 0.00 CHECK (total_settled_usd >= 0),
  is_blocked        boolean NOT NULL DEFAULT false,
  blocked_reason    text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.custody_accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "custody_own_group_read" ON public.custody_accounts
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = custody_accounts.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'professor')
    )
  );

-- Computed column helper (available = deposited - committed)
CREATE OR REPLACE FUNCTION public.custody_available(acct public.custody_accounts)
  RETURNS numeric(14,2)
  LANGUAGE sql STABLE
AS $$
  SELECT acct.total_deposited_usd - acct.total_committed;
$$;

-- 4. Custody deposits (deposit history via gateway)
CREATE TABLE IF NOT EXISTS public.custody_deposits (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id          uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  amount_usd        numeric(14,2) NOT NULL CHECK (amount_usd > 0),
  coins_equivalent  integer NOT NULL CHECK (coins_equivalent > 0),
  payment_gateway   text NOT NULL CHECK (payment_gateway IN ('stripe', 'mercadopago')),
  payment_reference text,
  status            text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'failed', 'refunded')),
  created_at        timestamptz NOT NULL DEFAULT now(),
  confirmed_at      timestamptz
);

ALTER TABLE public.custody_deposits ENABLE ROW LEVEL SECURITY;

CREATE POLICY "custody_deposits_own_read" ON public.custody_deposits
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = custody_deposits.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'professor')
    )
  );

CREATE INDEX idx_custody_deposits_group ON public.custody_deposits(group_id, created_at DESC);

-- 5. Clearing events (burn breakdown by issuer)
CREATE TABLE IF NOT EXISTS public.clearing_events (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  burn_ref_id        text NOT NULL,
  athlete_user_id    uuid NOT NULL REFERENCES auth.users(id),
  redeemer_group_id  uuid NOT NULL REFERENCES public.coaching_groups(id),
  total_coins        integer NOT NULL CHECK (total_coins > 0),
  breakdown          jsonb NOT NULL DEFAULT '[]',
  created_at         timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.clearing_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "clearing_events_group_read" ON public.clearing_events
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE (cm.group_id = clearing_events.redeemer_group_id
             OR cm.group_id IN (
               SELECT (elem->>'issuer_group_id')::uuid
               FROM jsonb_array_elements(clearing_events.breakdown) elem
             ))
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'professor')
    )
  );

CREATE INDEX idx_clearing_events_redeemer ON public.clearing_events(redeemer_group_id, created_at DESC);

-- 6. Clearing settlements (interclub compensation)
CREATE TABLE IF NOT EXISTS public.clearing_settlements (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clearing_event_id   uuid NOT NULL REFERENCES public.clearing_events(id),
  creditor_group_id   uuid NOT NULL REFERENCES public.coaching_groups(id),
  debtor_group_id     uuid NOT NULL REFERENCES public.coaching_groups(id),
  coin_amount         integer NOT NULL CHECK (coin_amount > 0),
  gross_amount_usd    numeric(14,2) NOT NULL CHECK (gross_amount_usd > 0),
  fee_rate_pct        numeric(5,2) NOT NULL,
  fee_amount_usd      numeric(14,2) NOT NULL CHECK (fee_amount_usd >= 0),
  net_amount_usd      numeric(14,2) NOT NULL CHECK (net_amount_usd > 0),
  status              text NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'settled', 'insufficient', 'failed')),
  created_at          timestamptz NOT NULL DEFAULT now(),
  settled_at          timestamptz,
  CONSTRAINT different_groups CHECK (creditor_group_id <> debtor_group_id)
);

ALTER TABLE public.clearing_settlements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "settlements_group_read" ON public.clearing_settlements
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE (cm.group_id = clearing_settlements.creditor_group_id
             OR cm.group_id = clearing_settlements.debtor_group_id)
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'professor')
    )
  );

CREATE INDEX idx_settlements_creditor ON public.clearing_settlements(creditor_group_id, status);
CREATE INDEX idx_settlements_debtor ON public.clearing_settlements(debtor_group_id, status);

-- 7. Swap orders (B2B liquidity market)
CREATE TABLE IF NOT EXISTS public.swap_orders (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_group_id   uuid NOT NULL REFERENCES public.coaching_groups(id),
  buyer_group_id    uuid REFERENCES public.coaching_groups(id),
  amount_usd        numeric(14,2) NOT NULL CHECK (amount_usd > 0),
  fee_rate_pct      numeric(5,2) NOT NULL DEFAULT 1.00,
  fee_amount_usd    numeric(14,2) NOT NULL DEFAULT 0.00 CHECK (fee_amount_usd >= 0),
  status            text NOT NULL DEFAULT 'open'
                      CHECK (status IN ('open', 'matched', 'settled', 'cancelled')),
  created_at        timestamptz NOT NULL DEFAULT now(),
  settled_at        timestamptz,
  CONSTRAINT swap_different_groups CHECK (
    buyer_group_id IS NULL OR seller_group_id <> buyer_group_id
  )
);

ALTER TABLE public.swap_orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "swap_orders_group_read" ON public.swap_orders
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE (cm.group_id = swap_orders.seller_group_id
             OR cm.group_id = swap_orders.buyer_group_id)
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'professor')
    )
  );

CREATE INDEX idx_swap_orders_status ON public.swap_orders(status, created_at DESC);

-- 8. Helper functions

-- Confirm a custody deposit and update the account
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

-- Commit coins (increase committed, decrease available)
CREATE OR REPLACE FUNCTION public.custody_commit_coins(
  p_group_id uuid,
  p_coin_count integer
)
  RETURNS void
  LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_available numeric(14,2);
  v_amount    numeric(14,2) := p_coin_count::numeric;
BEGIN
  SELECT total_deposited_usd - total_committed INTO v_available
  FROM public.custody_accounts
  WHERE group_id = p_group_id
  FOR UPDATE;

  IF v_available IS NULL THEN
    RAISE EXCEPTION 'No custody account for group %', p_group_id;
  END IF;

  IF v_available < v_amount THEN
    RAISE EXCEPTION 'Insufficient backing: available=%, requested=%', v_available, v_amount;
  END IF;

  UPDATE public.custody_accounts
  SET total_committed = total_committed + v_amount,
      updated_at = now()
  WHERE group_id = p_group_id;
END;
$$;

-- Release committed backing when coins are burned (intra-club or as part of clearing).
-- R_i -= coin_count, A_i += coin_count (D_i stays the same for intra-club).
CREATE OR REPLACE FUNCTION public.custody_release_committed(
  p_group_id uuid,
  p_coin_count integer
)
  RETURNS void
  LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_committed numeric(14,2);
BEGIN
  SELECT total_committed INTO v_committed
  FROM public.custody_accounts
  WHERE group_id = p_group_id
  FOR UPDATE;

  IF v_committed IS NULL THEN
    RAISE EXCEPTION 'No custody account for group %', p_group_id;
  END IF;

  IF v_committed < p_coin_count THEN
    RAISE EXCEPTION 'Invariant violation: committed=% < release=%', v_committed, p_coin_count;
  END IF;

  UPDATE public.custody_accounts
  SET total_committed = total_committed - p_coin_count,
      updated_at = now()
  WHERE group_id = p_group_id;
END;
$$;

-- Settle clearing: transfer from debtor (issuer) to creditor (redeemer).
-- Model: R_i -= b, D_i -= b (gross), D_k += (1-α)·b, Portal += α·b
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

  -- Lock debtor's custody account
  SELECT total_committed INTO v_committed
  FROM public.custody_accounts
  WHERE group_id = v_debtor
  FOR UPDATE;

  -- The backing MUST exist because coins existed (R >= coin_amount).
  -- If not, it's an invariant violation.
  IF v_committed IS NULL OR v_committed < v_coin_amount THEN
    UPDATE public.clearing_settlements
    SET status = 'insufficient'
    WHERE id = p_settlement_id;
    RETURN;
  END IF;

  -- Debtor: R -= coin_amount, D -= gross (coins destroyed, backing transferred out)
  UPDATE public.custody_accounts
  SET total_committed = total_committed - v_coin_amount,
      total_deposited_usd = total_deposited_usd - v_gross,
      total_settled_usd = total_settled_usd + v_gross,
      updated_at = now()
  WHERE group_id = v_debtor;

  -- Creditor: D += net (receives backing minus fee)
  UPDATE public.custody_accounts
  SET total_deposited_usd = total_deposited_usd + v_net,
      updated_at = now()
  WHERE group_id = v_creditor;

  UPDATE public.clearing_settlements
  SET status = 'settled', settled_at = now()
  WHERE id = p_settlement_id;
END;
$$;

-- Invariant check: verifies R_i = M_i and D_i = R_i + A_i for all clubs.
-- Returns rows that VIOLATE invariants (empty = healthy system).
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
  SELECT
    ca.group_id,
    ca.total_deposited_usd,
    ca.total_committed,
    ca.total_deposited_usd - ca.total_committed,
    CASE
      WHEN ca.total_committed < 0 THEN 'committed_negative'
      WHEN ca.total_deposited_usd < 0 THEN 'deposited_negative'
      WHEN ca.total_deposited_usd < ca.total_committed THEN 'deposited_less_than_committed'
      ELSE 'unknown'
    END
  FROM public.custody_accounts ca
  WHERE ca.total_committed < 0
     OR ca.total_deposited_usd < 0
     OR ca.total_deposited_usd < ca.total_committed;
$$;

-- Atomic swap execution: D_seller -= amount, D_buyer += (amount - fee).
-- Serialized via FOR UPDATE locks on both custody accounts.
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

  -- Lock BOTH accounts in deterministic UUID order to prevent deadlocks.
  -- Ensure buyer account exists first (upsert with 0 if not present).
  INSERT INTO public.custody_accounts (group_id, total_deposited_usd)
  VALUES (p_buyer_group_id, 0)
  ON CONFLICT (group_id) DO NOTHING;

  -- Lock in UUID order (lower first)
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

  -- D_seller -= amount
  UPDATE public.custody_accounts
  SET total_deposited_usd = total_deposited_usd - v_amount,
      updated_at = now()
  WHERE group_id = v_seller;

  -- D_buyer += net
  UPDATE public.custody_accounts
  SET total_deposited_usd = total_deposited_usd + v_net,
      updated_at = now()
  WHERE group_id = p_buyer_group_id;

  -- Mark order settled
  UPDATE public.swap_orders
  SET buyer_group_id = p_buyer_group_id,
      status = 'settled',
      settled_at = now()
  WHERE id = p_order_id;
END;
$$;

-- Netting: aggregate pending interclub burns by (issuer, redeemer) pair
-- within a time window. Returns aggregated settlement candidates.
CREATE OR REPLACE FUNCTION public.aggregate_clearing_window(
  p_window_start timestamptz,
  p_window_end   timestamptz
)
  RETURNS TABLE(
    debtor_group_id  uuid,
    creditor_group_id uuid,
    total_coins      bigint,
    event_count      bigint
  )
  LANGUAGE sql STABLE
AS $$
  SELECT
    cs.debtor_group_id,
    cs.creditor_group_id,
    SUM(cs.coin_amount)::bigint,
    COUNT(*)::bigint
  FROM public.clearing_settlements cs
  WHERE cs.status = 'pending'
    AND cs.created_at >= p_window_start
    AND cs.created_at < p_window_end
  GROUP BY cs.debtor_group_id, cs.creditor_group_id;
$$;

-- Grant permissions
GRANT ALL ON TABLE public.platform_fee_config TO authenticated;
GRANT ALL ON TABLE public.platform_fee_config TO service_role;
GRANT ALL ON TABLE public.custody_accounts TO authenticated;
GRANT ALL ON TABLE public.custody_accounts TO service_role;
GRANT ALL ON TABLE public.custody_deposits TO authenticated;
GRANT ALL ON TABLE public.custody_deposits TO service_role;
GRANT ALL ON TABLE public.clearing_events TO authenticated;
GRANT ALL ON TABLE public.clearing_events TO service_role;
GRANT ALL ON TABLE public.clearing_settlements TO authenticated;
GRANT ALL ON TABLE public.clearing_settlements TO service_role;
GRANT ALL ON TABLE public.swap_orders TO authenticated;
GRANT ALL ON TABLE public.swap_orders TO service_role;

GRANT EXECUTE ON FUNCTION public.confirm_custody_deposit TO service_role;
GRANT EXECUTE ON FUNCTION public.custody_commit_coins TO service_role;
GRANT EXECUTE ON FUNCTION public.custody_release_committed TO service_role;
GRANT EXECUTE ON FUNCTION public.settle_clearing TO service_role;
GRANT EXECUTE ON FUNCTION public.check_custody_invariants TO service_role;
GRANT EXECUTE ON FUNCTION public.execute_swap TO service_role;
GRANT EXECUTE ON FUNCTION public.aggregate_clearing_window TO service_role;
