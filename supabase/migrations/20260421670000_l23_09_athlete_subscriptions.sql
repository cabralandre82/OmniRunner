-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ L23-09 — Athlete subscriptions + integrated monthly billing                ║
-- ║                                                                            ║
-- ║ Context:                                                                   ║
-- ║   The assessoria economics depend on a monthly fee per athlete            ║
-- ║   (typically R$ 150-300) plus occasional extras (camps, races). The      ║
-- ║   existing `public.billing_purchases` table only models one-off credit  ║
-- ║   package buys by the admin; there is no recurring charge rail for     ║
-- ║   athletes, and coaches end up cobrar-ing outside the product (WhatsApp ║
-- ║   + Pix por fora), which means:                                          ║
-- ║     (1) we do not see the ROI of the coletivo,                           ║
-- ║     (2) churn is invisible (an athlete who stopped paying only shows up ║
-- ║         weeks later when the coach realises),                            ║
-- ║     (3) the custody → coin distribution → staff payout loop cannot      ║
-- ║         close.                                                            ║
-- ║                                                                            ║
-- ║ Delivers:                                                                  ║
-- ║   1. public.athlete_subscriptions — per (group, athlete) subscription    ║
-- ║      with price_cents, billing_day_of_month, gateway, state machine     ║
-- ║      (active → paused → cancelled).                                     ║
-- ║   2. public.athlete_subscription_invoices — per-invoice row, CHECK      ║
-- ║      state machine, UNIQUE per (subscription, period_month).            ║
-- ║   3. fn_subscription_start / _pause / _cancel RPCs (admin).             ║
-- ║   4. fn_subscription_generate_cycle (service-role cron) — idempotent    ║
-- ║      per period_month via unique index + ON CONFLICT DO NOTHING.        ║
-- ║   5. fn_subscription_mark_invoice_paid (service-role) — closes the      ║
-- ║      invoice and emits an outbox event so the coin-credit pipeline      ║
-- ║      can fulfil the group's custody deposit asynchronously.             ║
-- ║   6. fn_subscription_mark_overdue (service-role cron) — sweep.          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

BEGIN;

-- ─── 1. athlete_subscriptions ────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.athlete_subscriptions (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id               UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  athlete_user_id        UUID NOT NULL REFERENCES auth.users(id),
  price_cents            INT NOT NULL,
  currency               TEXT NOT NULL DEFAULT 'BRL',
  billing_day_of_month   INT NOT NULL DEFAULT 5,
  gateway                TEXT NOT NULL DEFAULT 'asaas',
  status                 TEXT NOT NULL DEFAULT 'active',
  started_at             DATE NOT NULL DEFAULT CURRENT_DATE,
  paused_at              TIMESTAMPTZ,
  cancelled_at           TIMESTAMPTZ,
  cancellation_reason    TEXT,
  external_customer_id   TEXT,
  created_by             UUID REFERENCES auth.users(id),
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT athlete_subscriptions_price_positive
    CHECK (price_cents > 0),
  CONSTRAINT athlete_subscriptions_currency_len
    CHECK (length(currency) = 3),
  CONSTRAINT athlete_subscriptions_day_range
    CHECK (billing_day_of_month BETWEEN 1 AND 28),
  CONSTRAINT athlete_subscriptions_gateway_check
    CHECK (gateway IN ('asaas', 'stripe', 'mercadopago')),
  CONSTRAINT athlete_subscriptions_status_check
    CHECK (status IN ('active', 'paused', 'cancelled')),
  CONSTRAINT athlete_subscriptions_state_timestamps
    CHECK (
      (status = 'active'    AND cancelled_at IS NULL)
      OR (status = 'paused'    AND paused_at IS NOT NULL AND cancelled_at IS NULL)
      OR (status = 'cancelled' AND cancelled_at IS NOT NULL)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS athlete_subscriptions_active_uniq
  ON public.athlete_subscriptions(group_id, athlete_user_id)
  WHERE status IN ('active', 'paused');

CREATE INDEX IF NOT EXISTS athlete_subscriptions_group_idx
  ON public.athlete_subscriptions(group_id, status);

CREATE INDEX IF NOT EXISTS athlete_subscriptions_athlete_idx
  ON public.athlete_subscriptions(athlete_user_id, status);

ALTER TABLE public.athlete_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY athlete_subscriptions_athlete_read ON public.athlete_subscriptions
  FOR SELECT USING (athlete_user_id = auth.uid());

CREATE POLICY athlete_subscriptions_staff_read ON public.athlete_subscriptions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = athlete_subscriptions.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- ─── 2. athlete_subscription_invoices ────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.athlete_subscription_invoices (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id        UUID NOT NULL
                           REFERENCES public.athlete_subscriptions(id) ON DELETE CASCADE,
  group_id               UUID NOT NULL,
  athlete_user_id        UUID NOT NULL,
  period_month           DATE NOT NULL,
  amount_cents           INT NOT NULL,
  currency               TEXT NOT NULL DEFAULT 'BRL',
  status                 TEXT NOT NULL DEFAULT 'pending',
  due_date               DATE NOT NULL,
  external_charge_id     TEXT,
  external_invoice_url   TEXT,
  paid_at                TIMESTAMPTZ,
  overdue_at             TIMESTAMPTZ,
  cancelled_at           TIMESTAMPTZ,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT athlete_sub_invoices_amount_positive
    CHECK (amount_cents > 0),
  CONSTRAINT athlete_sub_invoices_status_check
    CHECK (status IN ('pending', 'paid', 'overdue', 'cancelled')),
  CONSTRAINT athlete_sub_invoices_paid_timestamp
    CHECK ((status = 'paid') = (paid_at IS NOT NULL)),
  CONSTRAINT athlete_sub_invoices_cancelled_timestamp
    CHECK ((status = 'cancelled') = (cancelled_at IS NOT NULL)),
  CONSTRAINT athlete_sub_invoices_period_first_of_month
    CHECK (date_trunc('month', period_month)::date = period_month)
);

CREATE UNIQUE INDEX IF NOT EXISTS athlete_sub_invoices_period_uniq
  ON public.athlete_subscription_invoices(subscription_id, period_month);

CREATE INDEX IF NOT EXISTS athlete_sub_invoices_status_due_idx
  ON public.athlete_subscription_invoices(status, due_date)
  WHERE status IN ('pending', 'overdue');

CREATE INDEX IF NOT EXISTS athlete_sub_invoices_group_idx
  ON public.athlete_subscription_invoices(group_id, period_month DESC);

ALTER TABLE public.athlete_subscription_invoices ENABLE ROW LEVEL SECURITY;

CREATE POLICY athlete_sub_invoices_athlete_read ON public.athlete_subscription_invoices
  FOR SELECT USING (athlete_user_id = auth.uid());

CREATE POLICY athlete_sub_invoices_staff_read ON public.athlete_subscription_invoices
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = athlete_subscription_invoices.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- ─── 3. fn_subscription_start ────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_subscription_start(
  p_group_id UUID,
  p_athlete_user_id UUID,
  p_price_cents INT,
  p_billing_day INT DEFAULT 5,
  p_gateway TEXT DEFAULT 'asaas',
  p_external_customer_id TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_admin BOOLEAN;
  v_sub_id   UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.coaching_members cm
    WHERE cm.group_id = p_group_id
      AND cm.user_id = auth.uid()
      AND cm.role IN ('admin_master', 'coach')
  ) INTO v_is_admin;

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'only admin_master or coach can start subscription'
      USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.coaching_members
    WHERE group_id = p_group_id AND user_id = p_athlete_user_id
  ) THEN
    RAISE EXCEPTION 'athlete is not a member of this group' USING ERRCODE = 'P0002';
  END IF;

  IF p_price_cents IS NULL OR p_price_cents < 500 THEN
    RAISE EXCEPTION 'price must be at least R$ 5,00 (500 cents)'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_billing_day IS NULL OR p_billing_day < 1 OR p_billing_day > 28 THEN
    RAISE EXCEPTION 'billing_day must be in [1, 28]' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.athlete_subscriptions
    (group_id, athlete_user_id, price_cents, billing_day_of_month,
     gateway, external_customer_id, created_by)
  VALUES
    (p_group_id, p_athlete_user_id, p_price_cents, p_billing_day,
     p_gateway, p_external_customer_id, auth.uid())
  RETURNING id INTO v_sub_id;

  RETURN v_sub_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_subscription_start(
  UUID, UUID, INT, INT, TEXT, TEXT
) TO authenticated;

-- ─── 4. fn_subscription_pause / _resume / _cancel ────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_subscription_pause(
  p_subscription_id UUID
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub public.athlete_subscriptions%ROWTYPE;
  v_is_staff BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_sub
  FROM public.athlete_subscriptions
  WHERE id = p_subscription_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'subscription not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.coaching_members
    WHERE group_id = v_sub.group_id AND user_id = auth.uid()
      AND role IN ('admin_master', 'coach')
  ) INTO v_is_staff;

  IF NOT v_is_staff THEN
    RAISE EXCEPTION 'only admin_master or coach can pause subscription'
      USING ERRCODE = '42501';
  END IF;

  IF v_sub.status <> 'active' THEN
    RAISE EXCEPTION 'subscription not active (current %)', v_sub.status
      USING ERRCODE = 'P0005';
  END IF;

  UPDATE public.athlete_subscriptions
  SET status = 'paused', paused_at = now(), updated_at = now()
  WHERE id = p_subscription_id;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_subscription_pause(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_subscription_cancel(
  p_subscription_id UUID,
  p_reason TEXT DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub public.athlete_subscriptions%ROWTYPE;
  v_allowed BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_sub
  FROM public.athlete_subscriptions
  WHERE id = p_subscription_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'subscription not found' USING ERRCODE = 'P0002';
  END IF;

  v_allowed := (v_sub.athlete_user_id = auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.coaching_members
      WHERE group_id = v_sub.group_id AND user_id = auth.uid()
        AND role IN ('admin_master', 'coach')
    );

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'only athlete self or group staff can cancel'
      USING ERRCODE = '42501';
  END IF;

  IF v_sub.status = 'cancelled' THEN
    RETURN FALSE;
  END IF;

  UPDATE public.athlete_subscriptions
  SET status = 'cancelled',
      cancelled_at = now(),
      cancellation_reason = p_reason,
      updated_at = now()
  WHERE id = p_subscription_id;

  UPDATE public.athlete_subscription_invoices
  SET status = 'cancelled',
      cancelled_at = now(),
      updated_at = now()
  WHERE subscription_id = p_subscription_id
    AND status = 'pending';

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_subscription_cancel(UUID, TEXT) TO authenticated;

-- ─── 5. fn_subscription_generate_cycle (cron, service-role) ──────────────────

CREATE OR REPLACE FUNCTION public.fn_subscription_generate_cycle(
  p_period_month DATE DEFAULT NULL
) RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_period DATE;
  v_count  INT := 0;
  v_inserted INT;
BEGIN
  IF current_setting('role', true) IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'fn_subscription_generate_cycle is service-role only'
      USING ERRCODE = '42501';
  END IF;

  v_period := COALESCE(p_period_month, date_trunc('month', now())::date);

  IF date_trunc('month', v_period)::date <> v_period THEN
    RAISE EXCEPTION 'p_period_month must be the first day of a month'
      USING ERRCODE = 'P0001';
  END IF;

  WITH candidate AS (
    SELECT sub.id AS subscription_id, sub.group_id, sub.athlete_user_id,
           sub.price_cents, sub.currency, sub.billing_day_of_month
    FROM public.athlete_subscriptions sub
    WHERE sub.status = 'active'
      AND sub.started_at <= (v_period + INTERVAL '1 month' - INTERVAL '1 day')::date
  ),
  ins AS (
    INSERT INTO public.athlete_subscription_invoices
      (subscription_id, group_id, athlete_user_id, period_month,
       amount_cents, currency, due_date, status)
    SELECT c.subscription_id, c.group_id, c.athlete_user_id, v_period,
           c.price_cents, c.currency,
           (v_period + ((c.billing_day_of_month - 1) * INTERVAL '1 day'))::date,
           'pending'
    FROM candidate c
    ON CONFLICT (subscription_id, period_month) DO NOTHING
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_inserted FROM ins;

  v_count := COALESCE(v_inserted, 0);
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_subscription_generate_cycle(DATE) TO service_role;

-- ─── 6. fn_subscription_mark_invoice_paid (service-role) ─────────────────────

CREATE OR REPLACE FUNCTION public.fn_subscription_mark_invoice_paid(
  p_invoice_id UUID,
  p_external_charge_id TEXT DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inv public.athlete_subscription_invoices%ROWTYPE;
BEGIN
  IF current_setting('role', true) IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'fn_subscription_mark_invoice_paid is service-role only'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_inv
  FROM public.athlete_subscription_invoices
  WHERE id = p_invoice_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invoice not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_inv.status = 'paid' THEN
    RETURN FALSE;
  END IF;

  IF v_inv.status = 'cancelled' THEN
    RAISE EXCEPTION 'cannot pay cancelled invoice' USING ERRCODE = 'P0005';
  END IF;

  UPDATE public.athlete_subscription_invoices
  SET status = 'paid',
      paid_at = now(),
      overdue_at = NULL,
      external_charge_id = COALESCE(p_external_charge_id, external_charge_id),
      updated_at = now()
  WHERE id = p_invoice_id;

  -- Emit an outbox event so the custody-credit pipeline picks this up
  -- asynchronously; fail-open so a missing outbox does not block the
  -- invoice close.
  BEGIN
    IF to_regproc('public.fn_outbox_emit(text,text,uuid,jsonb,text)') IS NOT NULL THEN
      PERFORM public.fn_outbox_emit(
        'subscription.invoice.paid',
        'athlete_subscription_invoice',
        p_invoice_id,
        jsonb_build_object(
          'subscription_id', v_inv.subscription_id,
          'group_id', v_inv.group_id,
          'athlete_user_id', v_inv.athlete_user_id,
          'period_month', v_inv.period_month,
          'amount_cents', v_inv.amount_cents,
          'currency', v_inv.currency
        ),
        'subscription.invoice.paid:' || p_invoice_id::text
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'outbox emit failed for subscription invoice %: %',
      p_invoice_id, SQLERRM;
  END;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_subscription_mark_invoice_paid(UUID, TEXT)
  TO service_role;

-- ─── 7. fn_subscription_mark_overdue (cron) ──────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_subscription_mark_overdue()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_affected INT;
BEGIN
  IF current_setting('role', true) IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'fn_subscription_mark_overdue is service-role only'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.athlete_subscription_invoices
  SET status = 'overdue',
      overdue_at = now(),
      updated_at = now()
  WHERE status = 'pending'
    AND due_date < CURRENT_DATE;

  GET DIAGNOSTICS v_affected = ROW_COUNT;
  RETURN v_affected;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_subscription_mark_overdue() TO service_role;

-- ─── 8. Self-tests ────────────────────────────────────────────────────────────

DO $selftest$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'athlete_subscriptions_state_timestamps'
  ) THEN
    RAISE EXCEPTION 'self-test: state_timestamps CHECK missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'athlete_sub_invoices_period_first_of_month'
  ) THEN
    RAISE EXCEPTION 'self-test: period_first_of_month CHECK missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'athlete_sub_invoices_paid_timestamp'
  ) THEN
    RAISE EXCEPTION 'self-test: paid_timestamp CHECK missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname = 'athlete_subscriptions_active_uniq'
  ) THEN
    RAISE EXCEPTION 'self-test: active_uniq partial index missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname = 'athlete_sub_invoices_period_uniq'
  ) THEN
    RAISE EXCEPTION 'self-test: invoices period_uniq index missing';
  END IF;
END;
$selftest$;

COMMIT;
