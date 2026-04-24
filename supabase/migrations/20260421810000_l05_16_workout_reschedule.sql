-- L05-16 — workout reschedule (athlete-initiated)
--
-- Antes: workout_delivery_items só permite coach-side scheduling.
-- Atleta machucado tinha que ligar/whatsapp para a assessoria
-- mover o treino. UX ruim e fluxo não-auditado.
--
-- Depois: athlete pode propor nova data via fn_request_reschedule
-- (RPC SECURITY DEFINER). Coach aprova/rejeita via fn_resolve_reschedule.
-- Estado registrado em workout_delivery_events para auditoria completa.
--
-- Modelo de dados:
--   workout_delivery_items.athlete_requested_date date NULL
--   workout_delivery_items.athlete_requested_at   timestamptz NULL
--   workout_delivery_items.athlete_request_reason text NULL
--   workout_delivery_items.coach_response         text CHECK ('accepted','rejected') NULL
--   workout_delivery_items.coach_responded_at     timestamptz NULL
--   workout_delivery_items.coach_responded_by     uuid NULL → auth.users
--
-- OmniCoin policy: zero writes a coin_ledger ou wallets.
-- L04-07-OK

BEGIN;

ALTER TABLE public.workout_delivery_items
  ADD COLUMN IF NOT EXISTS athlete_requested_date  date,
  ADD COLUMN IF NOT EXISTS athlete_requested_at    timestamptz,
  ADD COLUMN IF NOT EXISTS athlete_request_reason  text,
  ADD COLUMN IF NOT EXISTS coach_response          text,
  ADD COLUMN IF NOT EXISTS coach_responded_at      timestamptz,
  ADD COLUMN IF NOT EXISTS coach_responded_by      uuid REFERENCES auth.users(id);

DO $cnstr$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'wdi_coach_response_chk'
  ) THEN
    ALTER TABLE public.workout_delivery_items
      ADD CONSTRAINT wdi_coach_response_chk
      CHECK (coach_response IS NULL OR coach_response IN ('accepted','rejected'));
  END IF;
END;
$cnstr$;

CREATE INDEX IF NOT EXISTS idx_wdi_athlete_pending_request
  ON public.workout_delivery_items (group_id, athlete_requested_at DESC)
  WHERE athlete_requested_date IS NOT NULL AND coach_response IS NULL;

CREATE OR REPLACE FUNCTION public.fn_request_reschedule(
  p_item_id uuid,
  p_new_date date,
  p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_item   public.workout_delivery_items;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'P0010 unauthenticated' USING ERRCODE = 'P0010';
  END IF;
  IF p_item_id IS NULL OR p_new_date IS NULL THEN
    RAISE EXCEPTION 'P0001 item_id and new_date required' USING ERRCODE = 'P0001';
  END IF;
  IF p_new_date < CURRENT_DATE THEN
    RAISE EXCEPTION 'P0001 new_date cannot be in the past' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_item
  FROM public.workout_delivery_items
  WHERE id = p_item_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'P0002 item not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_item.athlete_user_id <> v_caller THEN
    RAISE EXCEPTION 'P0010 only the assigned athlete may request a reschedule'
      USING ERRCODE = 'P0010';
  END IF;
  IF v_item.status NOT IN ('pending','published') THEN
    RAISE EXCEPTION 'P0003 cannot reschedule item in status %', v_item.status
      USING ERRCODE = 'P0003';
  END IF;

  UPDATE public.workout_delivery_items
  SET athlete_requested_date  = p_new_date,
      athlete_requested_at    = now(),
      athlete_request_reason  = p_reason,
      coach_response          = NULL,
      coach_responded_at      = NULL,
      coach_responded_by      = NULL
  WHERE id = p_item_id;

  INSERT INTO public.workout_delivery_events
    (group_id, item_id, actor_user_id, type, meta)
  VALUES
    (v_item.group_id, p_item_id, v_caller, 'reschedule_requested',
     jsonb_build_object('new_date', p_new_date, 'reason', p_reason));

  RETURN jsonb_build_object(
    'item_id',  p_item_id,
    'new_date', p_new_date,
    'status',   'pending_coach_review'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_resolve_reschedule(
  p_item_id uuid,
  p_decision text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_item   public.workout_delivery_items;
  v_role   text;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'P0010 unauthenticated' USING ERRCODE = 'P0010';
  END IF;
  IF p_decision NOT IN ('accepted','rejected') THEN
    RAISE EXCEPTION 'P0001 decision must be accepted or rejected'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_item
  FROM public.workout_delivery_items
  WHERE id = p_item_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'P0002 item not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_item.athlete_requested_date IS NULL THEN
    RAISE EXCEPTION 'P0003 no pending reschedule request'
      USING ERRCODE = 'P0003';
  END IF;

  SELECT cm.role INTO v_role
  FROM public.coaching_members cm
  WHERE cm.user_id = v_caller AND cm.group_id = v_item.group_id;

  IF v_role NOT IN ('admin_master','coach','assistant') THEN
    RAISE EXCEPTION 'P0010 only group staff may resolve a reschedule'
      USING ERRCODE = 'P0010';
  END IF;

  UPDATE public.workout_delivery_items
  SET coach_response     = p_decision,
      coach_responded_at = now(),
      coach_responded_by = v_caller
  WHERE id = p_item_id;

  INSERT INTO public.workout_delivery_events
    (group_id, item_id, actor_user_id, type, meta)
  VALUES
    (v_item.group_id, p_item_id, v_caller, 'reschedule_' || p_decision,
     jsonb_build_object(
       'requested_date', v_item.athlete_requested_date,
       'reason',         v_item.athlete_request_reason
     ));

  RETURN jsonb_build_object(
    'item_id',  p_item_id,
    'decision', p_decision
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_request_reschedule(uuid, date, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_resolve_reschedule(uuid, text)       FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_request_reschedule(uuid, date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_resolve_reschedule(uuid, text)       TO authenticated;

DO $self$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='workout_delivery_items'
      AND column_name='athlete_requested_date'
  ) THEN
    RAISE EXCEPTION 'L05-16 self-test: athlete_requested_date column missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_request_reschedule'
  ) THEN
    RAISE EXCEPTION 'L05-16 self-test: fn_request_reschedule missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_resolve_reschedule'
  ) THEN
    RAISE EXCEPTION 'L05-16 self-test: fn_resolve_reschedule missing';
  END IF;

  RAISE NOTICE 'L05-16 self-test PASSED';
END;
$self$;

COMMIT;
