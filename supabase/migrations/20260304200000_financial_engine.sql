-- ============================================================================
-- BLOCO B: Engine Financeiro
-- Tables, indexes, RLS, and RPCs for plans, subscriptions, financial ledger.
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. TABLES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.coaching_plans (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  name            text NOT NULL CHECK (length(trim(name)) >= 2),
  description     text,
  monthly_price   numeric(10,2) NOT NULL CHECK (monthly_price >= 0),
  billing_cycle   text NOT NULL DEFAULT 'monthly'
    CHECK (billing_cycle IN ('monthly', 'quarterly')),
  max_workouts_per_week int,
  status          text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'inactive')),
  created_by      uuid NOT NULL REFERENCES auth.users(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.coaching_subscriptions (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id          uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  athlete_user_id   uuid NOT NULL REFERENCES auth.users(id),
  plan_id           uuid NOT NULL REFERENCES public.coaching_plans(id),
  status            text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'late', 'paused', 'cancelled')),
  next_due_date     date,
  last_payment_at   timestamptz,
  started_at        timestamptz NOT NULL DEFAULT now(),
  cancelled_at      timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_subscription_athlete_group UNIQUE (athlete_user_id, group_id)
);

CREATE TABLE IF NOT EXISTS public.coaching_financial_ledger (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  type            text NOT NULL CHECK (type IN ('revenue', 'expense')),
  category        text NOT NULL,
  amount          numeric(12,2) NOT NULL CHECK (amount > 0),
  description     text,
  reference_id    uuid,
  date            date NOT NULL DEFAULT current_date,
  created_by      uuid NOT NULL REFERENCES auth.users(id),
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. INDEXES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_plans_group
  ON public.coaching_plans (group_id);

CREATE INDEX IF NOT EXISTS idx_subscriptions_group
  ON public.coaching_subscriptions (group_id, status);

CREATE INDEX IF NOT EXISTS idx_subscriptions_athlete
  ON public.coaching_subscriptions (athlete_user_id);

CREATE INDEX IF NOT EXISTS idx_ledger_group_date
  ON public.coaching_financial_ledger (group_id, date DESC);

CREATE INDEX IF NOT EXISTS idx_ledger_group_type
  ON public.coaching_financial_ledger (group_id, type);

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. RLS
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.coaching_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coaching_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coaching_financial_ledger ENABLE ROW LEVEL SECURITY;

-- 3.1 Plans: staff can read
CREATE POLICY "staff_plans_select"
  ON public.coaching_plans FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_plans.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- 3.2 Plans: staff can insert
CREATE POLICY "staff_plans_insert"
  ON public.coaching_plans FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_plans.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- 3.3 Plans: staff can update
CREATE POLICY "staff_plans_update"
  ON public.coaching_plans FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_plans.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- 3.4 Plans: staff can delete
CREATE POLICY "staff_plans_delete"
  ON public.coaching_plans FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_plans.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- 3.5 Plans: athlete can see available plans for their group
CREATE POLICY "athlete_plans_select"
  ON public.coaching_plans FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_plans.group_id
        AND cm.user_id = auth.uid()
    )
  );

-- 3.6 Subscriptions: staff full access
CREATE POLICY "staff_subscriptions_all"
  ON public.coaching_subscriptions FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_subscriptions.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- 3.7 Subscriptions: athlete can read own subscription
CREATE POLICY "athlete_subscription_select"
  ON public.coaching_subscriptions FOR SELECT USING (
    athlete_user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_subscriptions.group_id
        AND cm.user_id = auth.uid()
    )
  );

-- 3.8 Ledger: staff full access (no athlete access)
CREATE POLICY "staff_ledger_all"
  ON public.coaching_financial_ledger FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_financial_ledger.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. RPCs
-- ═══════════════════════════════════════════════════════════════════════════

-- 4.1 fn_update_subscription_status: change subscription status with validation
CREATE OR REPLACE FUNCTION public.fn_update_subscription_status(
  p_subscription_id uuid,
  p_new_status      text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_uid         uuid := auth.uid();
  v_group_id    uuid;
  v_caller_role text;
  v_old_status  text;
BEGIN
  -- Get subscription group and current status
  SELECT s.group_id, s.status INTO v_group_id, v_old_status
    FROM coaching_subscriptions s
    WHERE s.id = p_subscription_id;

  IF v_group_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'SUBSCRIPTION_NOT_FOUND', 'message', 'Assinatura não encontrada');
  END IF;

  -- Check caller is staff
  SELECT cm.role INTO v_caller_role
    FROM coaching_members cm
    WHERE cm.group_id = v_group_id AND cm.user_id = v_uid;

  IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin_master', 'coach') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'NOT_STAFF', 'message', 'Apenas coach/admin pode alterar assinaturas');
  END IF;

  -- Validate new status
  IF p_new_status NOT IN ('active', 'late', 'paused', 'cancelled') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'INVALID_STATUS', 'message', 'Status inválido');
  END IF;

  -- Update subscription
  UPDATE coaching_subscriptions SET
    status       = p_new_status,
    cancelled_at = CASE WHEN p_new_status = 'cancelled' THEN now() ELSE cancelled_at END,
    updated_at   = now()
  WHERE id = p_subscription_id;

  RETURN jsonb_build_object('ok', true, 'code', 'UPDATED', 'data', jsonb_build_object(
    'subscription_id', p_subscription_id,
    'old_status', v_old_status,
    'new_status', p_new_status
  ));
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_update_subscription_status(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_update_subscription_status(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_update_subscription_status(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_update_subscription_status(uuid, text) TO service_role;

-- 4.2 fn_create_ledger_entry: insert a financial ledger entry with validation
CREATE OR REPLACE FUNCTION public.fn_create_ledger_entry(
  p_group_id     uuid,
  p_type         text,
  p_category     text,
  p_amount       numeric,
  p_description  text DEFAULT NULL,
  p_reference_id uuid DEFAULT NULL,
  p_date         date DEFAULT current_date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_uid         uuid := auth.uid();
  v_caller_role text;
  v_entry_id    uuid;
BEGIN
  -- Check caller is staff
  SELECT cm.role INTO v_caller_role
    FROM coaching_members cm
    WHERE cm.group_id = p_group_id AND cm.user_id = v_uid;

  IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin_master', 'coach') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'NOT_STAFF', 'message', 'Apenas coach/admin pode criar lançamentos');
  END IF;

  -- Validate type
  IF p_type NOT IN ('revenue', 'expense') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'INVALID_TYPE', 'message', 'Tipo deve ser revenue ou expense');
  END IF;

  -- Validate amount
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RETURN jsonb_build_object('ok', false, 'code', 'INVALID_AMOUNT', 'message', 'Valor deve ser maior que zero');
  END IF;

  -- Insert ledger entry
  INSERT INTO coaching_financial_ledger
    (group_id, type, category, amount, description, reference_id, date, created_by)
  VALUES
    (p_group_id, p_type, p_category, p_amount, p_description, p_reference_id, p_date, v_uid)
  RETURNING id INTO v_entry_id;

  RETURN jsonb_build_object('ok', true, 'code', 'CREATED', 'data', jsonb_build_object('entry_id', v_entry_id));
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_create_ledger_entry(uuid, text, text, numeric, text, uuid, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_create_ledger_entry(uuid, text, text, numeric, text, uuid, date) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_create_ledger_entry(uuid, text, text, numeric, text, uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_create_ledger_entry(uuid, text, text, numeric, text, uuid, date) TO service_role;

COMMIT;
