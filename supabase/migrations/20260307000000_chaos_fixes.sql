-- ============================================================================
-- Chaos-testing fixes: M14, M15, M16
-- Date: 2026-03-07
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- M14: billing_events — MercadoPago dedup constraint
-- ═══════════════════════════════════════════════════════════════════════════
-- Prevents double-processing of the same MP webhook notification.
-- Partial unique index on (purchase_id, event_type, mp_payment_id).

CREATE UNIQUE INDEX IF NOT EXISTS idx_billing_events_mp_dedup
  ON billing_events (purchase_id, event_type, (metadata->>'mp_payment_id'))
  WHERE metadata->>'mp_payment_id' IS NOT NULL;

-- ═══════════════════════════════════════════════════════════════════════════
-- M15: fn_create_delivery_batch — idempotency guard
-- ═══════════════════════════════════════════════════════════════════════════
-- If a batch already exists for the same group + period, return the existing
-- batch ID instead of creating a duplicate.

CREATE OR REPLACE FUNCTION public.fn_create_delivery_batch(
  p_group_id uuid,
  p_period_start date DEFAULT NULL,
  p_period_end date DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_batch_id uuid;
  v_role text;
BEGIN
  SELECT cm.role INTO v_role
  FROM coaching_members cm
  WHERE cm.group_id = p_group_id AND cm.user_id = auth.uid()
  LIMIT 1;

  IF v_role IS NULL OR v_role NOT IN ('admin_master','coach') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Idempotency: check for existing batch with same group + period
  SELECT id INTO v_batch_id
  FROM workout_delivery_batches
  WHERE group_id = p_group_id
    AND period_start IS NOT DISTINCT FROM p_period_start
    AND period_end IS NOT DISTINCT FROM p_period_end
    AND status NOT IN ('cancelled')
  LIMIT 1;

  IF v_batch_id IS NOT NULL THEN
    RETURN v_batch_id;
  END IF;

  INSERT INTO workout_delivery_batches (group_id, created_by, period_start, period_end)
  VALUES (p_group_id, auth.uid(), p_period_start, p_period_end)
  RETURNING id INTO v_batch_id;

  RETURN v_batch_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_create_delivery_batch FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_create_delivery_batch TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- M16: fn_assign_workout — fix TOCTOU race on weekly limit
-- ═══════════════════════════════════════════════════════════════════════════
-- The weekly limit check (SELECT count) followed by INSERT has a race window.
-- Fix: lock the athlete's existing assignments FOR UPDATE before counting,
-- so concurrent calls are serialized.

CREATE OR REPLACE FUNCTION public.fn_assign_workout(
  p_template_id    uuid,
  p_athlete_user_id uuid,
  p_scheduled_date  date,
  p_notes           text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_uid              uuid := auth.uid();
  v_group_id         uuid;
  v_caller_role      text;
  v_athlete_role     text;
  v_sub_status       text;
  v_max_per_week     int;
  v_week_count       int;
  v_assignment_id    uuid;
  v_week_start       date;
BEGIN
  -- Get template group
  SELECT t.group_id INTO v_group_id
  FROM coaching_workout_templates t WHERE t.id = p_template_id;

  IF v_group_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'TEMPLATE_NOT_FOUND', 'message', 'Template não encontrado');
  END IF;

  -- Check caller is staff
  SELECT cm.role INTO v_caller_role
  FROM coaching_members cm WHERE cm.group_id = v_group_id AND cm.user_id = v_uid;

  IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin_master', 'coach') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'NOT_STAFF', 'message', 'Apenas coach/admin pode atribuir treinos');
  END IF;

  -- Check athlete is member
  SELECT cm.role INTO v_athlete_role
  FROM coaching_members cm WHERE cm.group_id = v_group_id AND cm.user_id = p_athlete_user_id;

  IF v_athlete_role IS NULL OR v_athlete_role != 'athlete' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'ATHLETE_NOT_MEMBER', 'message', 'Atleta não é membro do grupo');
  END IF;

  -- Check subscription status
  SELECT s.status INTO v_sub_status
  FROM coaching_subscriptions s
  WHERE s.group_id = v_group_id AND s.athlete_user_id = p_athlete_user_id;

  IF v_sub_status = 'late' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'SUBSCRIPTION_LATE', 'message', 'Atleta com assinatura em atraso. Regularize antes de atribuir treinos.');
  END IF;

  IF v_sub_status IN ('cancelled', 'paused') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'SUBSCRIPTION_INACTIVE', 'message', 'Atleta sem assinatura ativa.');
  END IF;

  -- Check weekly limit with row-level locking to prevent TOCTOU race
  IF v_sub_status = 'active' THEN
    SELECT p.max_workouts_per_week INTO v_max_per_week
    FROM coaching_subscriptions s
    JOIN coaching_plans p ON p.id = s.plan_id
    WHERE s.group_id = v_group_id AND s.athlete_user_id = p_athlete_user_id;

    IF v_max_per_week IS NOT NULL THEN
      v_week_start := date_trunc('week', p_scheduled_date)::date;

      -- FOR UPDATE locks the rows so concurrent transactions must wait,
      -- eliminating the TOCTOU window between count and insert.
      SELECT count(*) INTO v_week_count
      FROM coaching_workout_assignments a
      WHERE a.athlete_user_id = p_athlete_user_id
        AND a.scheduled_date >= v_week_start
        AND a.scheduled_date < v_week_start + 7
      FOR UPDATE;

      IF v_week_count >= v_max_per_week THEN
        RETURN jsonb_build_object('ok', false, 'code', 'WEEKLY_LIMIT_REACHED',
          'message', format('Limite de %s treinos/semana atingido.', v_max_per_week));
      END IF;
    END IF;
  END IF;

  -- Insert with idempotent upsert
  INSERT INTO coaching_workout_assignments (group_id, athlete_user_id, template_id, scheduled_date, notes, created_by)
  VALUES (v_group_id, p_athlete_user_id, p_template_id, p_scheduled_date, p_notes, v_uid)
  ON CONFLICT (athlete_user_id, scheduled_date) DO UPDATE SET
    template_id = EXCLUDED.template_id,
    notes = EXCLUDED.notes,
    version = coaching_workout_assignments.version + 1,
    updated_at = now()
  RETURNING id INTO v_assignment_id;

  RETURN jsonb_build_object('ok', true, 'code', 'ASSIGNED', 'data', jsonb_build_object('assignment_id', v_assignment_id));
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_assign_workout(uuid, uuid, date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_assign_workout(uuid, uuid, date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_assign_workout(uuid, uuid, date, text) TO service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- M20: coaching_workout_templates — auto-update updated_at for optimistic locking
-- ═══════════════════════════════════════════════════════════════════════════
-- Ensures updated_at is always set by the database, so the client-side
-- optimistic lock (WHERE updated_at = :last_known) works reliably even if
-- the caller forgets to send it.

CREATE OR REPLACE FUNCTION public.trg_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trg_coaching_workout_templates_updated_at'
  ) THEN
    CREATE TRIGGER trg_coaching_workout_templates_updated_at
      BEFORE UPDATE ON coaching_workout_templates
      FOR EACH ROW
      EXECUTE FUNCTION public.trg_set_updated_at();
  END IF;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- M26: Missing indexes for coin_ledger and billing_purchases
-- ═══════════════════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_coin_ledger_issuer_group_id
  ON coin_ledger (issuer_group_id);

CREATE INDEX IF NOT EXISTS idx_billing_purchases_payment_reference
  ON billing_purchases (payment_reference);

-- ═══════════════════════════════════════════════════════════════════════════
-- m11: fn_athlete_confirm_item — reject confirmation unless item is 'published'
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_athlete_confirm_item(
  p_item_id uuid,
  p_result text,
  p_reason text DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_group_id uuid;
  v_athlete uuid;
  v_status text;
BEGIN
  IF p_result NOT IN ('confirmed','failed') THEN
    RAISE EXCEPTION 'invalid_result';
  END IF;

  SELECT di.group_id, di.athlete_user_id, di.status
  INTO v_group_id, v_athlete, v_status
  FROM workout_delivery_items di WHERE di.id = p_item_id;

  IF v_group_id IS NULL THEN RAISE EXCEPTION 'item_not_found'; END IF;
  IF v_athlete <> auth.uid() THEN RAISE EXCEPTION 'forbidden'; END IF;

  IF v_status IN ('confirmed','failed') THEN RETURN 'already_' || v_status; END IF;

  IF v_status <> 'published' THEN
    RAISE EXCEPTION 'item_not_published: only published items can be confirmed (current status: %)', v_status;
  END IF;

  UPDATE workout_delivery_items
  SET status = p_result,
      confirmed_at = CASE WHEN p_result = 'confirmed' THEN now() ELSE confirmed_at END,
      last_error = CASE WHEN p_result = 'failed' THEN COALESCE(p_reason, 'unknown') ELSE last_error END
  WHERE id = p_item_id AND status = 'published';

  INSERT INTO workout_delivery_events (group_id, item_id, actor_user_id, type, meta)
  VALUES (v_group_id, p_item_id, auth.uid(),
          CASE WHEN p_result = 'confirmed' THEN 'ATHLETE_CONFIRMED' ELSE 'ATHLETE_FAILED' END,
          jsonb_build_object('reason', p_reason, 'note', p_note));

  RETURN p_result;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_athlete_confirm_item FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_athlete_confirm_item TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- m12: fn_close_delivery_batch — prevent closing with pending items
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_close_delivery_batch(
  p_batch_id uuid
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_group_id uuid;
  v_status text;
  v_role text;
  v_pending_count int;
BEGIN
  SELECT b.group_id, b.status INTO v_group_id, v_status
  FROM workout_delivery_batches b WHERE b.id = p_batch_id;

  IF v_group_id IS NULL THEN RAISE EXCEPTION 'batch_not_found'; END IF;

  SELECT cm.role INTO v_role
  FROM coaching_members cm
  WHERE cm.group_id = v_group_id AND cm.user_id = auth.uid()
  LIMIT 1;

  IF v_role IS NULL OR v_role NOT IN ('admin_master','coach') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF v_status = 'closed' THEN RETURN 'already_closed'; END IF;
  IF v_status = 'cancelled' THEN RETURN 'already_cancelled'; END IF;

  SELECT count(*) INTO v_pending_count
  FROM workout_delivery_items
  WHERE batch_id = p_batch_id AND status = 'pending';

  IF v_pending_count > 0 THEN
    RAISE EXCEPTION 'cannot_close: batch has % pending item(s) — publish or cancel them first', v_pending_count;
  END IF;

  UPDATE workout_delivery_batches
  SET status = 'closed', closed_at = now()
  WHERE id = p_batch_id;

  RETURN 'closed';
END;
$$;

REVOKE ALL ON FUNCTION public.fn_close_delivery_batch FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_close_delivery_batch TO authenticated;

-- Fix fn_mark_item_published: guard event INSERT with IF FOUND
CREATE OR REPLACE FUNCTION public.fn_mark_item_published(
  p_item_id uuid,
  p_note text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_group_id uuid;
  v_role text;
  v_status text;
BEGIN
  SELECT di.group_id, di.status INTO v_group_id, v_status
  FROM workout_delivery_items di WHERE di.id = p_item_id;

  IF v_group_id IS NULL THEN RAISE EXCEPTION 'item_not_found'; END IF;

  SELECT cm.role INTO v_role
  FROM coaching_members cm
  WHERE cm.group_id = v_group_id AND cm.user_id = auth.uid()
  LIMIT 1;

  IF v_role IS NULL OR v_role NOT IN ('admin_master','coach') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF v_status = 'published' THEN RETURN 'already_published'; END IF;

  UPDATE workout_delivery_items
  SET status = 'published', published_at = now()
  WHERE id = p_item_id AND status = 'pending';

  IF FOUND THEN
    INSERT INTO workout_delivery_events (group_id, item_id, actor_user_id, type, meta)
    VALUES (v_group_id, p_item_id, auth.uid(), 'MARK_PUBLISHED',
            CASE WHEN p_note IS NOT NULL THEN jsonb_build_object('note', p_note) END);
  END IF;

  RETURN 'published';
END;
$$;

REVOKE ALL ON FUNCTION public.fn_mark_item_published FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_mark_item_published TO authenticated;

COMMIT;
