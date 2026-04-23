-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ L23-10 — Paired / grouped workouts                                         ║
-- ║                                                                            ║
-- ║ Context:                                                                   ║
-- ║   Each `coaching_workout_assignment` is a contract between the coach      ║
-- ║   and one athlete. But real-life assessorias run pair/group workouts —  ║
-- ║   "João e Maria, 10 km ritmo base às 06:00". Currently that becomes two ║
-- ║   independent assignments: if João decides not to go, Maria only finds  ║
-- ║   out at the park at 06:05.                                              ║
-- ║                                                                            ║
-- ║ Delivers:                                                                  ║
-- ║   1. public.coaching_workout_pairings — pairs/groups of assignments      ║
-- ║      with aggregate status (`pending`, `all_confirmed`,                 ║
-- ║      `partially_confirmed`, `dissolved`, `completed`).                  ║
-- ║   2. public.coaching_workout_pairing_members — per-athlete confirmation ║
-- ║      state; unique on (pairing_id, assignment_id).                      ║
-- ║   3. fn_pairing_create — coach-only; validates all assignments share    ║
-- ║      group + scheduled_date; minimum 2 members; dedup via              ║
-- ║      UNIQUE(assignment_id).                                             ║
-- ║   4. fn_pairing_respond — athlete-self; sets member confirmation;       ║
-- ║      recomputes aggregate status.                                       ║
-- ║   5. fn_pairing_recompute_status — internal helper invoked from        ║
-- ║      responses.                                                         ║
-- ║   6. Outbox emission on decline so partners can be notified.            ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

BEGIN;

-- ─── 1. coaching_workout_pairings ────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.coaching_workout_pairings (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id                UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  scheduled_date          DATE NOT NULL,
  title                   TEXT,
  min_confirmations       INT NOT NULL DEFAULT 2,
  status                  TEXT NOT NULL DEFAULT 'pending',
  created_by              UUID NOT NULL REFERENCES auth.users(id),
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  dissolved_at            TIMESTAMPTZ,
  completed_at            TIMESTAMPTZ,
  CONSTRAINT coaching_workout_pairings_status_check
    CHECK (status IN ('pending', 'all_confirmed', 'partially_confirmed',
                      'dissolved', 'completed')),
  CONSTRAINT coaching_workout_pairings_min_confirmations_range
    CHECK (min_confirmations BETWEEN 2 AND 20),
  CONSTRAINT coaching_workout_pairings_title_length
    CHECK (title IS NULL OR length(trim(title)) BETWEEN 2 AND 120),
  CONSTRAINT coaching_workout_pairings_dissolved_timestamp
    CHECK ((status = 'dissolved') = (dissolved_at IS NOT NULL)),
  CONSTRAINT coaching_workout_pairings_completed_timestamp
    CHECK ((status = 'completed') = (completed_at IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS coaching_workout_pairings_group_date_idx
  ON public.coaching_workout_pairings(group_id, scheduled_date DESC);

CREATE INDEX IF NOT EXISTS coaching_workout_pairings_group_status_idx
  ON public.coaching_workout_pairings(group_id, status)
  WHERE status IN ('pending', 'partially_confirmed');

ALTER TABLE public.coaching_workout_pairings ENABLE ROW LEVEL SECURITY;

CREATE POLICY coaching_workout_pairings_group_read ON public.coaching_workout_pairings
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_workout_pairings.group_id
        AND cm.user_id = auth.uid()
    )
  );

CREATE POLICY coaching_workout_pairings_staff_write ON public.coaching_workout_pairings
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_workout_pairings.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- ─── 2. coaching_workout_pairing_members ─────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.coaching_workout_pairing_members (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pairing_id              UUID NOT NULL
                            REFERENCES public.coaching_workout_pairings(id) ON DELETE CASCADE,
  assignment_id           UUID NOT NULL
                            REFERENCES public.coaching_workout_assignments(id) ON DELETE CASCADE,
  athlete_user_id         UUID NOT NULL REFERENCES auth.users(id),
  confirmation_status     TEXT NOT NULL DEFAULT 'pending',
  responded_at            TIMESTAMPTZ,
  decline_reason          TEXT,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT coaching_workout_pairing_members_confirmation_check
    CHECK (confirmation_status IN ('pending', 'confirmed', 'declined')),
  CONSTRAINT coaching_workout_pairing_members_responded_timestamp
    CHECK (
      (confirmation_status = 'pending' AND responded_at IS NULL)
      OR (confirmation_status IN ('confirmed', 'declined')
          AND responded_at IS NOT NULL)
    ),
  CONSTRAINT coaching_workout_pairing_members_decline_has_reason_shape
    CHECK (
      decline_reason IS NULL
      OR (confirmation_status = 'declined'
          AND length(trim(decline_reason)) BETWEEN 1 AND 280)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS coaching_workout_pairing_members_assignment_uniq
  ON public.coaching_workout_pairing_members(assignment_id);

CREATE UNIQUE INDEX IF NOT EXISTS coaching_workout_pairing_members_pairing_athlete_uniq
  ON public.coaching_workout_pairing_members(pairing_id, athlete_user_id);

CREATE INDEX IF NOT EXISTS coaching_workout_pairing_members_athlete_idx
  ON public.coaching_workout_pairing_members(athlete_user_id, confirmation_status);

ALTER TABLE public.coaching_workout_pairing_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY coaching_workout_pairing_members_group_read ON public.coaching_workout_pairing_members
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_workout_pairings p
      JOIN public.coaching_members cm ON cm.group_id = p.group_id
      WHERE p.id = coaching_workout_pairing_members.pairing_id
        AND cm.user_id = auth.uid()
    )
  );

-- ─── 3. fn_pairing_recompute_status (internal) ───────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_pairing_recompute_status(
  p_pairing_id UUID
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total      INT;
  v_confirmed  INT;
  v_declined   INT;
  v_min_conf   INT;
  v_new_status TEXT;
  v_completed  BOOLEAN;
BEGIN
  SELECT p.min_confirmations,
         COUNT(m.*),
         COUNT(*) FILTER (WHERE m.confirmation_status = 'confirmed'),
         COUNT(*) FILTER (WHERE m.confirmation_status = 'declined'),
         BOOL_AND(a.status = 'completed')
    INTO v_min_conf, v_total, v_confirmed, v_declined, v_completed
    FROM public.coaching_workout_pairings p
    LEFT JOIN public.coaching_workout_pairing_members m ON m.pairing_id = p.id
    LEFT JOIN public.coaching_workout_assignments a ON a.id = m.assignment_id
    WHERE p.id = p_pairing_id
    GROUP BY p.min_confirmations;

  IF v_total IS NULL THEN
    RAISE EXCEPTION 'pairing not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_completed THEN
    v_new_status := 'completed';
  ELSIF v_total - v_declined < v_min_conf THEN
    v_new_status := 'dissolved';
  ELSIF v_confirmed = v_total THEN
    v_new_status := 'all_confirmed';
  ELSIF v_confirmed > 0 THEN
    v_new_status := 'partially_confirmed';
  ELSE
    v_new_status := 'pending';
  END IF;

  UPDATE public.coaching_workout_pairings
  SET status = v_new_status,
      dissolved_at = CASE WHEN v_new_status = 'dissolved' THEN COALESCE(dissolved_at, now()) ELSE NULL END,
      completed_at = CASE WHEN v_new_status = 'completed' THEN COALESCE(completed_at, now()) ELSE NULL END,
      updated_at = now()
  WHERE id = p_pairing_id;

  RETURN v_new_status;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_pairing_recompute_status(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_pairing_recompute_status(UUID) TO authenticated;

-- ─── 4. fn_pairing_create ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_pairing_create(
  p_group_id UUID,
  p_scheduled_date DATE,
  p_assignment_ids UUID[],
  p_title TEXT DEFAULT NULL,
  p_min_confirmations INT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_staff     BOOLEAN;
  v_count        INT;
  v_bad          INT;
  v_min_conf     INT;
  v_pairing_id   UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.coaching_members
    WHERE group_id = p_group_id AND user_id = auth.uid()
      AND role IN ('admin_master', 'coach')
  ) INTO v_is_staff;

  IF NOT v_is_staff THEN
    RAISE EXCEPTION 'only admin_master or coach can create pairing'
      USING ERRCODE = '42501';
  END IF;

  IF p_assignment_ids IS NULL OR array_length(p_assignment_ids, 1) IS NULL
     OR array_length(p_assignment_ids, 1) < 2 THEN
    RAISE EXCEPTION 'pairing requires at least two assignments'
      USING ERRCODE = 'P0001';
  END IF;

  IF array_length(p_assignment_ids, 1) > 20 THEN
    RAISE EXCEPTION 'pairing cannot exceed 20 members'
      USING ERRCODE = 'P0001';
  END IF;

  -- All assignments must belong to p_group_id + share p_scheduled_date.
  SELECT COUNT(*), COUNT(*) FILTER (
           WHERE a.group_id <> p_group_id OR a.scheduled_date <> p_scheduled_date
         )
    INTO v_count, v_bad
    FROM public.coaching_workout_assignments a
    WHERE a.id = ANY(p_assignment_ids);

  IF v_count <> array_length(p_assignment_ids, 1) THEN
    RAISE EXCEPTION 'one or more assignments not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_bad > 0 THEN
    RAISE EXCEPTION 'all assignments must share group + scheduled_date'
      USING ERRCODE = 'P0001';
  END IF;

  -- Refuse re-pairing an assignment already bound to another pairing.
  IF EXISTS (
    SELECT 1 FROM public.coaching_workout_pairing_members m
    WHERE m.assignment_id = ANY(p_assignment_ids)
  ) THEN
    RAISE EXCEPTION 'one or more assignments already belong to a pairing'
      USING ERRCODE = '23505';
  END IF;

  v_min_conf := LEAST(
    array_length(p_assignment_ids, 1),
    COALESCE(p_min_confirmations, array_length(p_assignment_ids, 1))
  );
  IF v_min_conf < 2 THEN
    v_min_conf := 2;
  END IF;

  INSERT INTO public.coaching_workout_pairings
    (group_id, scheduled_date, title, min_confirmations, created_by)
  VALUES
    (p_group_id, p_scheduled_date, p_title, v_min_conf, auth.uid())
  RETURNING id INTO v_pairing_id;

  INSERT INTO public.coaching_workout_pairing_members
    (pairing_id, assignment_id, athlete_user_id)
  SELECT v_pairing_id, a.id, a.athlete_user_id
  FROM public.coaching_workout_assignments a
  WHERE a.id = ANY(p_assignment_ids);

  PERFORM public.fn_pairing_recompute_status(v_pairing_id);

  RETURN v_pairing_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_pairing_create(UUID, DATE, UUID[], TEXT, INT)
  TO authenticated;

-- ─── 5. fn_pairing_respond ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_pairing_respond(
  p_pairing_id UUID,
  p_confirmation TEXT,
  p_reason TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid         UUID;
  v_member      public.coaching_workout_pairing_members%ROWTYPE;
  v_pairing     public.coaching_workout_pairings%ROWTYPE;
  v_new_status  TEXT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;

  IF p_confirmation NOT IN ('confirmed', 'declined') THEN
    RAISE EXCEPTION 'confirmation must be confirmed or declined'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_confirmation = 'declined' AND (p_reason IS NULL OR length(trim(p_reason)) = 0) THEN
    RAISE EXCEPTION 'decline requires a reason' USING ERRCODE = 'P0001';
  END IF;

  SELECT m.* INTO v_member
  FROM public.coaching_workout_pairing_members m
  WHERE m.pairing_id = p_pairing_id AND m.athlete_user_id = v_uid
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not a member of this pairing' USING ERRCODE = '42501';
  END IF;

  SELECT p.* INTO v_pairing
  FROM public.coaching_workout_pairings p
  WHERE p.id = p_pairing_id;

  IF v_pairing.status IN ('dissolved', 'completed') THEN
    RAISE EXCEPTION 'pairing already terminal (%)', v_pairing.status
      USING ERRCODE = 'P0005';
  END IF;

  UPDATE public.coaching_workout_pairing_members
  SET confirmation_status = p_confirmation,
      responded_at = now(),
      decline_reason = CASE WHEN p_confirmation = 'declined' THEN p_reason ELSE NULL END,
      updated_at = now()
  WHERE id = v_member.id;

  v_new_status := public.fn_pairing_recompute_status(p_pairing_id);

  -- Notify other members on decline (best-effort outbox emission).
  IF p_confirmation = 'declined' THEN
    BEGIN
      IF to_regproc('public.fn_outbox_emit(text,text,uuid,jsonb,text)') IS NOT NULL THEN
        PERFORM public.fn_outbox_emit(
          'workout.pairing.partner_declined',
          'workout_pairing',
          p_pairing_id,
          jsonb_build_object(
            'pairing_id', p_pairing_id,
            'group_id', v_pairing.group_id,
            'scheduled_date', v_pairing.scheduled_date,
            'declined_by', v_uid,
            'decline_reason', p_reason,
            'new_status', v_new_status
          ),
          'pairing.decline:' || p_pairing_id::text || ':' || v_uid::text
        );
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'outbox emit failed for pairing decline %: %',
        p_pairing_id, SQLERRM;
    END;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'pairing_id', p_pairing_id,
    'confirmation', p_confirmation,
    'pairing_status', v_new_status
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_pairing_respond(UUID, TEXT, TEXT) TO authenticated;

-- ─── 6. Self-tests ────────────────────────────────────────────────────────────

DO $selftest$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'coaching_workout_pairings_status_check'
  ) THEN
    RAISE EXCEPTION 'self-test: pairings status_check missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'coaching_workout_pairings_dissolved_timestamp'
  ) THEN
    RAISE EXCEPTION 'self-test: dissolved_timestamp CHECK missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'coaching_workout_pairing_members_responded_timestamp'
  ) THEN
    RAISE EXCEPTION 'self-test: responded_timestamp CHECK missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname = 'coaching_workout_pairing_members_assignment_uniq'
  ) THEN
    RAISE EXCEPTION 'self-test: assignment uniq index missing';
  END IF;
END;
$selftest$;

COMMIT;
