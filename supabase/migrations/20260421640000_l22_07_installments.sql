-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ L22-07 — Parcelado BR (installment plans) + gateway preference             ║
-- ║                                                                            ║
-- ║ Context:                                                                   ║
-- ║   Brazilian shoppers default to `parcelado` (split payment). A 10×         ║
-- ║   boleto/PIX flow is the baseline checkout experience for every mid-       ║
-- ║   tier SaaS in BR, and coaching groups routinely buy credit packages      ║
-- ║   via "Cartão em 10× sem juros" or "PIX mensal". The existing             ║
-- ║   `public.billing_purchases` row only captures a lump-sum charge —         ║
-- ║   there is no schedule, no per-installment status, and no policy to       ║
-- ║   prefer Asaas (BR) over Stripe (international).                           ║
-- ║                                                                            ║
-- ║ Delivers:                                                                  ║
-- ║   1. public.billing_gateway_preferences — per-group default gateway       ║
-- ║      with CHECK-enforced allowlist and RLS for admin_master.              ║
-- ║   2. public.billing_installment_plans — schedule header, state             ║
-- ║      machine (active → completed|cancelled), idempotent via unique        ║
-- ║      (purchase_id). Aggregate invariants: SUM of installments ==          ║
-- ║      purchase price; installment count in [1, 12].                        ║
-- ║   3. public.billing_installments — per-installment rows with state         ║
-- ║      (pending → paid|overdue|cancelled), due_date ordering, partial       ║
-- ║      unique index on (plan_id, sequence_no).                              ║
-- ║   4. fn_validate_installment_config(count, total_cents) — IMMUTABLE       ║
-- ║      PARALLEL SAFE. Enforces count ∈ [1, 12], total_cents > 0,            ║
-- ║      per-installment minimum R$ 5.00 (500 cents) to avoid Stripe          ║
-- ║      declining micro-charges.                                             ║
-- ║   5. fn_recommend_gateway(country_code) — IMMUTABLE. Returns              ║
-- ║      'asaas' for BR, 'stripe' otherwise. Used by the checkout.            ║
-- ║   6. RPCs:                                                                ║
-- ║      - fn_create_installment_plan (admin-only) — creates plan and         ║
-- ║        generates schedule atomically, enforcing SUM invariant.            ║
-- ║      - fn_mark_installment_paid (service-role-only) — idempotent,         ║
-- ║        transitions last pending → paid and promotes plan to               ║
-- ║        completed on final installment.                                    ║
-- ║      - fn_mark_installments_overdue (service-role-only) — sweep for       ║
-- ║        cron, flags pending installments past due_date.                    ║
-- ║      - fn_cancel_installment_plan (admin-only) — terminal cancel,         ║
-- ║        transitions plan → cancelled and all pending installments.         ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

BEGIN;

-- ─── 1. Per-group gateway preference ──────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.billing_gateway_preferences (
  group_id          UUID PRIMARY KEY REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  preferred_gateway TEXT NOT NULL DEFAULT 'asaas',
  allow_stripe      BOOLEAN NOT NULL DEFAULT TRUE,
  allow_asaas       BOOLEAN NOT NULL DEFAULT TRUE,
  allow_mercadopago BOOLEAN NOT NULL DEFAULT FALSE,
  updated_by        UUID REFERENCES auth.users(id),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT billing_gateway_preferences_gateway_check
    CHECK (preferred_gateway IN ('asaas', 'stripe', 'mercadopago')),
  CONSTRAINT billing_gateway_preferences_at_least_one_gateway
    CHECK (allow_stripe OR allow_asaas OR allow_mercadopago)
);

COMMENT ON TABLE public.billing_gateway_preferences IS
  'Per-group default billing gateway. BR groups default to asaas, international groups can switch to stripe.';

ALTER TABLE public.billing_gateway_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY billing_gateway_preferences_admin_read ON public.billing_gateway_preferences
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = billing_gateway_preferences.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

CREATE POLICY billing_gateway_preferences_admin_write ON public.billing_gateway_preferences
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = billing_gateway_preferences.group_id
        AND cm.user_id = auth.uid()
        AND cm.role = 'admin_master'
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = billing_gateway_preferences.group_id
        AND cm.user_id = auth.uid()
        AND cm.role = 'admin_master'
    )
  );

-- ─── 2. Validators ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_validate_installment_config(
  p_count INT,
  p_total_cents INT
) RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
BEGIN
  IF p_count IS NULL OR p_count < 1 OR p_count > 12 THEN
    RETURN FALSE;
  END IF;
  IF p_total_cents IS NULL OR p_total_cents <= 0 THEN
    RETURN FALSE;
  END IF;
  -- Per-installment minimum R$ 5.00 (500 cents) — Stripe refuses micro-charges,
  -- and Asaas boleto has a R$ 3.00 floor; R$ 5.00 is the safe intersection.
  IF (p_total_cents / p_count) < 500 THEN
    RETURN FALSE;
  END IF;
  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_validate_installment_config(INT, INT) TO PUBLIC;

CREATE OR REPLACE FUNCTION public.fn_recommend_gateway(
  p_country_code TEXT
) RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
BEGIN
  IF p_country_code IS NULL THEN
    RETURN 'stripe';
  END IF;
  IF upper(p_country_code) = 'BR' THEN
    RETURN 'asaas';
  END IF;
  RETURN 'stripe';
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_recommend_gateway(TEXT) TO PUBLIC;

-- ─── 3. Installment plan + installments ───────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.billing_installment_plans (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_id        UUID NOT NULL UNIQUE
                       REFERENCES public.billing_purchases(id) ON DELETE CASCADE,
  group_id           UUID NOT NULL
                       REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  installment_count  INT NOT NULL,
  total_cents        INT NOT NULL,
  currency           TEXT NOT NULL DEFAULT 'BRL',
  gateway            TEXT NOT NULL,
  payment_method     TEXT NOT NULL,
  status             TEXT NOT NULL DEFAULT 'active',
  created_by         UUID REFERENCES auth.users(id),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at       TIMESTAMPTZ,
  cancelled_at       TIMESTAMPTZ,
  CONSTRAINT billing_installment_plans_status_check
    CHECK (status IN ('active', 'completed', 'cancelled')),
  CONSTRAINT billing_installment_plans_gateway_check
    CHECK (gateway IN ('asaas', 'stripe', 'mercadopago')),
  CONSTRAINT billing_installment_plans_method_check
    CHECK (payment_method IN ('credit_card', 'boleto', 'pix', 'bank_slip')),
  CONSTRAINT billing_installment_plans_config_valid
    CHECK (public.fn_validate_installment_config(installment_count, total_cents)),
  CONSTRAINT billing_installment_plans_terminal_timestamps
    CHECK (
      (status = 'completed' AND completed_at IS NOT NULL AND cancelled_at IS NULL)
      OR (status = 'cancelled' AND cancelled_at IS NOT NULL AND completed_at IS NULL)
      OR (status = 'active' AND completed_at IS NULL AND cancelled_at IS NULL)
    )
);

COMMENT ON TABLE public.billing_installment_plans IS
  'Header for installment schedules attached to a billing_purchase. One plan per purchase (UNIQUE), enforced to avoid double-billing.';

CREATE INDEX IF NOT EXISTS billing_installment_plans_group_idx
  ON public.billing_installment_plans(group_id, created_at DESC);

CREATE INDEX IF NOT EXISTS billing_installment_plans_active_idx
  ON public.billing_installment_plans(status)
  WHERE status = 'active';

ALTER TABLE public.billing_installment_plans ENABLE ROW LEVEL SECURITY;

CREATE POLICY billing_installment_plans_admin_read ON public.billing_installment_plans
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = billing_installment_plans.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

CREATE TABLE IF NOT EXISTS public.billing_installments (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id       UUID NOT NULL
                  REFERENCES public.billing_installment_plans(id) ON DELETE CASCADE,
  sequence_no   INT NOT NULL,
  amount_cents  INT NOT NULL,
  due_date      DATE NOT NULL,
  status        TEXT NOT NULL DEFAULT 'pending',
  paid_at       TIMESTAMPTZ,
  external_charge_id TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT billing_installments_status_check
    CHECK (status IN ('pending', 'paid', 'overdue', 'cancelled')),
  CONSTRAINT billing_installments_amount_positive
    CHECK (amount_cents > 0),
  CONSTRAINT billing_installments_sequence_positive
    CHECK (sequence_no > 0),
  CONSTRAINT billing_installments_paid_timestamp
    CHECK ((status = 'paid') = (paid_at IS NOT NULL))
);

CREATE UNIQUE INDEX IF NOT EXISTS billing_installments_plan_seq_uniq
  ON public.billing_installments(plan_id, sequence_no);

CREATE INDEX IF NOT EXISTS billing_installments_due_idx
  ON public.billing_installments(due_date)
  WHERE status = 'pending';

COMMENT ON TABLE public.billing_installments IS
  'Per-installment row. Composite unique (plan_id, sequence_no) blocks double-generation from concurrent fn_create_installment_plan calls.';

ALTER TABLE public.billing_installments ENABLE ROW LEVEL SECURITY;

CREATE POLICY billing_installments_admin_read ON public.billing_installments
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.billing_installment_plans pl
      JOIN public.coaching_members cm ON cm.group_id = pl.group_id
      WHERE pl.id = billing_installments.plan_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- ─── 4. RPC: create installment plan ──────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_create_installment_plan(
  p_purchase_id UUID,
  p_installment_count INT,
  p_gateway TEXT,
  p_payment_method TEXT,
  p_first_due DATE DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_purchase     public.billing_purchases%ROWTYPE;
  v_plan_id      UUID;
  v_is_admin     BOOLEAN;
  v_per_cents    INT;
  v_remainder    INT;
  v_due          DATE;
  v_amount       INT;
  v_seq          INT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_purchase
  FROM public.billing_purchases
  WHERE id = p_purchase_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'purchase not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.coaching_members cm
    WHERE cm.group_id = v_purchase.group_id
      AND cm.user_id = auth.uid()
      AND cm.role = 'admin_master'
  ) INTO v_is_admin;

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'only admin_master can create installment plans'
      USING ERRCODE = '42501';
  END IF;

  IF NOT public.fn_validate_installment_config(p_installment_count, v_purchase.price_cents) THEN
    RAISE EXCEPTION 'invalid installment config (count=%, total=%)',
      p_installment_count, v_purchase.price_cents
      USING ERRCODE = 'P0001';
  END IF;

  IF p_gateway NOT IN ('asaas', 'stripe', 'mercadopago') THEN
    RAISE EXCEPTION 'unsupported gateway: %', p_gateway USING ERRCODE = 'P0003';
  END IF;
  IF p_payment_method NOT IN ('credit_card', 'boleto', 'pix', 'bank_slip') THEN
    RAISE EXCEPTION 'unsupported payment method: %', p_payment_method USING ERRCODE = 'P0003';
  END IF;

  INSERT INTO public.billing_installment_plans
    (purchase_id, group_id, installment_count, total_cents, currency,
     gateway, payment_method, created_by)
  VALUES
    (p_purchase_id, v_purchase.group_id, p_installment_count,
     v_purchase.price_cents, v_purchase.currency, p_gateway,
     p_payment_method, auth.uid())
  RETURNING id INTO v_plan_id;

  -- Integer-exact schedule: per-installment = total / count, remainder added
  -- to the first installment. Guarantees SUM(amount_cents) == total_cents.
  v_per_cents := v_purchase.price_cents / p_installment_count;
  v_remainder := v_purchase.price_cents - (v_per_cents * p_installment_count);
  v_due := COALESCE(p_first_due, (CURRENT_DATE + INTERVAL '30 day')::DATE);

  FOR v_seq IN 1..p_installment_count LOOP
    v_amount := v_per_cents + (CASE WHEN v_seq = 1 THEN v_remainder ELSE 0 END);
    INSERT INTO public.billing_installments
      (plan_id, sequence_no, amount_cents, due_date)
    VALUES
      (v_plan_id, v_seq, v_amount,
       (v_due + ((v_seq - 1) * INTERVAL '30 day'))::DATE);
  END LOOP;

  RETURN v_plan_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_create_installment_plan(
  UUID, INT, TEXT, TEXT, DATE
) TO authenticated;

-- ─── 5. RPC: mark installment paid ────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_mark_installment_paid(
  p_installment_id UUID,
  p_external_charge_id TEXT DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inst   public.billing_installments%ROWTYPE;
  v_pending INT;
BEGIN
  IF current_setting('role', true) IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'fn_mark_installment_paid is service-role only'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_inst
  FROM public.billing_installments
  WHERE id = p_installment_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'installment not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_inst.status = 'paid' THEN
    RETURN FALSE; -- idempotent no-op
  END IF;

  IF v_inst.status = 'cancelled' THEN
    RAISE EXCEPTION 'cannot pay cancelled installment' USING ERRCODE = 'P0005';
  END IF;

  UPDATE public.billing_installments
  SET status = 'paid',
      paid_at = now(),
      external_charge_id = COALESCE(p_external_charge_id, external_charge_id),
      updated_at = now()
  WHERE id = p_installment_id;

  SELECT COUNT(*) INTO v_pending
  FROM public.billing_installments
  WHERE plan_id = v_inst.plan_id
    AND status IN ('pending', 'overdue');

  IF v_pending = 0 THEN
    UPDATE public.billing_installment_plans
    SET status = 'completed',
        completed_at = now(),
        updated_at = now()
    WHERE id = v_inst.plan_id
      AND status = 'active';
  END IF;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_mark_installment_paid(UUID, TEXT) TO service_role;

-- ─── 6. RPC: overdue sweep (cron target) ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_mark_installments_overdue()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_affected INT;
BEGIN
  IF current_setting('role', true) IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'fn_mark_installments_overdue is service-role only'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.billing_installments
  SET status = 'overdue',
      updated_at = now()
  WHERE status = 'pending'
    AND due_date < CURRENT_DATE;

  GET DIAGNOSTICS v_affected = ROW_COUNT;
  RETURN v_affected;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_mark_installments_overdue() TO service_role;

-- ─── 7. RPC: cancel plan ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_cancel_installment_plan(
  p_plan_id UUID,
  p_reason TEXT DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plan public.billing_installment_plans%ROWTYPE;
  v_is_admin BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_plan
  FROM public.billing_installment_plans
  WHERE id = p_plan_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plan not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.coaching_members cm
    WHERE cm.group_id = v_plan.group_id
      AND cm.user_id = auth.uid()
      AND cm.role = 'admin_master'
  ) INTO v_is_admin;

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'only admin_master can cancel installment plans'
      USING ERRCODE = '42501';
  END IF;

  IF v_plan.status <> 'active' THEN
    RAISE EXCEPTION 'plan already %', v_plan.status USING ERRCODE = 'P0005';
  END IF;

  UPDATE public.billing_installments
  SET status = 'cancelled',
      updated_at = now()
  WHERE plan_id = p_plan_id
    AND status IN ('pending', 'overdue');

  UPDATE public.billing_installment_plans
  SET status = 'cancelled',
      cancelled_at = now(),
      updated_at = now()
  WHERE id = p_plan_id;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_cancel_installment_plan(UUID, TEXT) TO authenticated;

-- ─── 8. Self-tests ────────────────────────────────────────────────────────────

DO $selftest$
DECLARE
  v_ok BOOLEAN;
BEGIN
  -- Gateway recommender.
  IF public.fn_recommend_gateway('BR') <> 'asaas' THEN
    RAISE EXCEPTION 'self-test: BR must recommend asaas';
  END IF;
  IF public.fn_recommend_gateway('US') <> 'stripe' THEN
    RAISE EXCEPTION 'self-test: US must recommend stripe';
  END IF;
  IF public.fn_recommend_gateway(NULL) <> 'stripe' THEN
    RAISE EXCEPTION 'self-test: NULL country must fall back to stripe';
  END IF;

  -- Installment validator.
  IF public.fn_validate_installment_config(10, 12500) IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'self-test: 10x R$ 12,50 must validate';
  END IF;
  IF public.fn_validate_installment_config(13, 999900) IS DISTINCT FROM FALSE THEN
    RAISE EXCEPTION 'self-test: 13 installments must reject (max 12)';
  END IF;
  IF public.fn_validate_installment_config(0, 10000) IS DISTINCT FROM FALSE THEN
    RAISE EXCEPTION 'self-test: 0 installments must reject';
  END IF;
  IF public.fn_validate_installment_config(10, 4999) IS DISTINCT FROM FALSE THEN
    RAISE EXCEPTION 'self-test: per-installment < R$ 5,00 must reject';
  END IF;
  IF public.fn_validate_installment_config(NULL, 10000) IS DISTINCT FROM FALSE THEN
    RAISE EXCEPTION 'self-test: NULL count must reject';
  END IF;

  -- CHECK assertions.
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'billing_installment_plans_config_valid'
  ) THEN
    RAISE EXCEPTION 'self-test: billing_installment_plans_config_valid CHECK missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'billing_installments_paid_timestamp'
  ) THEN
    RAISE EXCEPTION 'self-test: billing_installments_paid_timestamp CHECK missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname = 'billing_installments_plan_seq_uniq'
  ) THEN
    RAISE EXCEPTION 'self-test: billing_installments_plan_seq_uniq index missing';
  END IF;
END;
$selftest$;

COMMIT;
