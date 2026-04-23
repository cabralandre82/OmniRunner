-- L23-11 — Relatórios para atleta (resumo mensal do coach)
-- =====================================================================
-- Problem
-- -------
-- Coaches currently hand-write monthly athlete summaries in Google
-- Docs and ship the PDF through WhatsApp — ~1h per athlete per
-- month. The product does not automate the *data extraction*, which
-- is where most of that hour is spent: pulling volume, pace trend,
-- longest run, adherence from the app and transcribing them into
-- the doc. The coach narrative on top ("your progress looks like
-- X, focus Y next month") is genuinely valuable and should stay
-- human-written.
--
-- Fix
-- ---
-- Ship the *data pipeline* here. PDF rendering is a downstream
-- concern (follow-up L23-11-pdf) that consumes the jsonb produced
-- by `fn_athlete_monthly_report` and the coach's `coaching_monthly_notes`
-- row. The jsonb contract below is stable — the PDF renderer never
-- re-derives metrics.
--
-- Fix layers (all forward-only, additive)
-- ---------------------------------------
-- (a) `coaching_monthly_notes` — (group_id, user_id, month_start)
--     unique row holding the three coach-editable free-text fields
--     (`highlights`, `improvements`, `personal_note`) plus `approved_at`
--     guard. RLS is deferred: all reads/writes flow through the
--     SECURITY DEFINER RPCs below which enforce coach-membership.
--
-- (b) `fn_athlete_monthly_report(p_group_id, p_user_id, p_month_start)`
--     — STABLE SECURITY DEFINER. Caller must be coach/assistant of
--     the group. Computes the month window, produces a jsonb with
--     `metrics` (volume/sessions/pace_trend/longest_run/avg_pace/
--     days_active) + `coach_notes` (from coaching_monthly_notes) +
--     `generated_at_ms` + `month_start`.
--
-- (c) `fn_upsert_monthly_note(p_group_id, p_user_id, p_month_start,
--     p_highlights, p_improvements, p_personal_note)` — VOLATILE
--     SECURITY DEFINER. Same auth gate. Upserts the free-text
--     fields; sets `approved_at = now()` when all three fields are
--     non-empty (coach-explicit signal the report is ready to send).
--
-- (d) `fn_athlete_monthly_report_assert_shape()` — CI shape guard.
--     Raises `P0010 L23-11 DRIFT:<reason>` on any drift.
--
-- Privacy / security posture
-- --------------------------
-- - Auth gate: caller must be coach or assistant of the group and
--   the athlete (user_id) must be a member of that group (prevents
--   cross-group leak of another group's athlete data by spoofing
--   group_id).
-- - Month window is quantised to month boundaries server-side; the
--   `month_start` parameter is normalised to `date_trunc('month')`.
-- - Free-text fields are bounded (2 KB each) to avoid storing
--   coach-sized essays that wedge the UI.
-- =====================================================================

BEGIN;

-- ----- coaching_monthly_notes ---------------------------------------------
CREATE TABLE IF NOT EXISTS public.coaching_monthly_notes (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id       uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  user_id        uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  month_start    date NOT NULL,
  highlights     text,
  improvements   text,
  personal_note  text,
  approved_at    timestamptz,
  coach_user_id  uuid REFERENCES auth.users(id),
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_coaching_monthly_notes UNIQUE (group_id, user_id, month_start),
  CONSTRAINT chk_coaching_monthly_notes_month_trunc
    CHECK (month_start = date_trunc('month', month_start)::date),
  CONSTRAINT chk_coaching_monthly_notes_highlights_len
    CHECK (highlights IS NULL OR length(highlights) <= 2048),
  CONSTRAINT chk_coaching_monthly_notes_improvements_len
    CHECK (improvements IS NULL OR length(improvements) <= 2048),
  CONSTRAINT chk_coaching_monthly_notes_personal_note_len
    CHECK (personal_note IS NULL OR length(personal_note) <= 2048)
);

CREATE INDEX IF NOT EXISTS idx_coaching_monthly_notes_group_month
  ON public.coaching_monthly_notes (group_id, month_start);

ALTER TABLE public.coaching_monthly_notes ENABLE ROW LEVEL SECURITY;

-- Deliberately no SELECT/INSERT/UPDATE policies. All access goes
-- through the SECURITY DEFINER RPCs below, which enforce the coach
-- membership gate. This is the same pattern used by L22-05.

-- ----- fn_athlete_monthly_report ------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_athlete_monthly_report(
  p_group_id uuid,
  p_user_id uuid,
  p_month_start date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_role text;
  v_member_exists boolean;
  v_month_start date;
  v_month_end date;
  v_window_start_ms bigint;
  v_window_end_ms bigint;
  v_half_ms bigint;
  v_result jsonb;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0010', MESSAGE = 'UNAUTHORIZED',
      DETAIL = 'L23-11: caller must be authenticated';
  END IF;

  IF p_group_id IS NULL OR p_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'INVALID_INPUT',
      DETAIL = 'L23-11: p_group_id and p_user_id required';
  END IF;

  v_month_start := COALESCE(date_trunc('month', p_month_start)::date,
                            date_trunc('month', now())::date);
  v_month_end := (v_month_start + interval '1 month')::date;
  v_window_start_ms := (EXTRACT(EPOCH FROM v_month_start::timestamptz) * 1000)::bigint;
  v_window_end_ms := (EXTRACT(EPOCH FROM v_month_end::timestamptz) * 1000)::bigint;
  v_half_ms := v_window_start_ms + (v_window_end_ms - v_window_start_ms) / 2;

  SELECT role INTO v_role
  FROM public.coaching_members
  WHERE group_id = p_group_id AND user_id = v_caller
  LIMIT 1;

  IF v_role IS NULL OR v_role NOT IN ('coach', 'assistant') THEN
    RAISE EXCEPTION USING ERRCODE = 'P0010', MESSAGE = 'UNAUTHORIZED',
      DETAIL = 'L23-11: caller is not coach/assistant of the group';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.coaching_members
    WHERE group_id = p_group_id AND user_id = p_user_id
  ) INTO v_member_exists;

  IF NOT v_member_exists THEN
    RAISE EXCEPTION USING ERRCODE = 'P0010', MESSAGE = 'ATHLETE_NOT_IN_GROUP',
      DETAIL = 'L23-11: p_user_id is not a member of p_group_id';
  END IF;

  WITH month_sessions AS (
    SELECT
      s.total_distance_m,
      s.moving_ms,
      s.avg_pace_sec_km,
      s.avg_bpm,
      s.start_time_ms,
      (s.start_time_ms < v_half_ms) AS is_first_half
    FROM public.sessions s
    WHERE s.user_id = p_user_id
      AND s.start_time_ms >= v_window_start_ms
      AND s.start_time_ms <  v_window_end_ms
      AND s.is_verified = true
  ),
  agg AS (
    SELECT
      COALESCE(SUM(total_distance_m) / 1000.0, 0) AS volume_km,
      COUNT(*) AS sessions_count,
      COALESCE(MAX(total_distance_m) / 1000.0, 0) AS longest_run_km,
      AVG(avg_pace_sec_km) FILTER (WHERE avg_pace_sec_km IS NOT NULL) AS avg_pace_sec_km,
      AVG(avg_bpm) FILTER (WHERE avg_bpm IS NOT NULL) AS avg_bpm,
      COUNT(DISTINCT (to_timestamp(start_time_ms / 1000.0) AT TIME ZONE 'UTC')::date) AS days_active,
      AVG(avg_pace_sec_km) FILTER (WHERE is_first_half AND avg_pace_sec_km IS NOT NULL) AS first_half_pace,
      AVG(avg_pace_sec_km) FILTER (WHERE NOT is_first_half AND avg_pace_sec_km IS NOT NULL) AS second_half_pace
    FROM month_sessions
  )
  SELECT jsonb_build_object(
    'month_start', v_month_start,
    'generated_at_ms', (EXTRACT(EPOCH FROM now()) * 1000)::bigint,
    'metrics', jsonb_build_object(
      'volume_km', ROUND(a.volume_km::numeric, 2),
      'sessions_count', a.sessions_count,
      'longest_run_km', ROUND(a.longest_run_km::numeric, 2),
      'avg_pace_sec_km', CASE
        WHEN a.avg_pace_sec_km IS NULL THEN NULL
        ELSE ROUND(a.avg_pace_sec_km::numeric, 2)
      END,
      'avg_bpm', CASE
        WHEN a.avg_bpm IS NULL THEN NULL
        ELSE ROUND(a.avg_bpm::numeric, 1)
      END,
      'days_active', a.days_active,
      'pace_trend_sec_km', CASE
        WHEN a.first_half_pace IS NULL OR a.second_half_pace IS NULL THEN NULL
        ELSE ROUND((a.second_half_pace - a.first_half_pace)::numeric, 2)
      END
    ),
    'coach_notes', (
      SELECT jsonb_build_object(
        'highlights', n.highlights,
        'improvements', n.improvements,
        'personal_note', n.personal_note,
        'approved_at', n.approved_at,
        'updated_at', n.updated_at
      )
      FROM public.coaching_monthly_notes n
      WHERE n.group_id = p_group_id
        AND n.user_id = p_user_id
        AND n.month_start = v_month_start
    )
  ) INTO v_result
  FROM agg a;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_athlete_monthly_report(uuid, uuid, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_athlete_monthly_report(uuid, uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_athlete_monthly_report(uuid, uuid, date) TO service_role;

COMMENT ON FUNCTION public.fn_athlete_monthly_report(uuid, uuid, date)
IS 'L23-11: coach-facing athlete monthly report. Returns jsonb {metrics, coach_notes, month_start}. Caller must be coach/assistant.';

-- ----- fn_upsert_monthly_note ---------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_upsert_monthly_note(
  p_group_id uuid,
  p_user_id uuid,
  p_month_start date,
  p_highlights text,
  p_improvements text,
  p_personal_note text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_role text;
  v_member_exists boolean;
  v_month_start date;
  v_approved_at timestamptz;
  v_result jsonb;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0010', MESSAGE = 'UNAUTHORIZED',
      DETAIL = 'L23-11: caller must be authenticated';
  END IF;

  IF p_group_id IS NULL OR p_user_id IS NULL OR p_month_start IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'INVALID_INPUT',
      DETAIL = 'L23-11: p_group_id, p_user_id, p_month_start required';
  END IF;

  v_month_start := date_trunc('month', p_month_start)::date;

  SELECT role INTO v_role
  FROM public.coaching_members
  WHERE group_id = p_group_id AND user_id = v_caller
  LIMIT 1;

  IF v_role IS NULL OR v_role NOT IN ('coach', 'assistant') THEN
    RAISE EXCEPTION USING ERRCODE = 'P0010', MESSAGE = 'UNAUTHORIZED',
      DETAIL = 'L23-11: caller is not coach/assistant of the group';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.coaching_members
    WHERE group_id = p_group_id AND user_id = p_user_id
  ) INTO v_member_exists;

  IF NOT v_member_exists THEN
    RAISE EXCEPTION USING ERRCODE = 'P0010', MESSAGE = 'ATHLETE_NOT_IN_GROUP',
      DETAIL = 'L23-11: p_user_id is not a member of p_group_id';
  END IF;

  IF COALESCE(length(trim(p_highlights)), 0) > 0
     AND COALESCE(length(trim(p_improvements)), 0) > 0
     AND COALESCE(length(trim(p_personal_note)), 0) > 0 THEN
    v_approved_at := now();
  ELSE
    v_approved_at := NULL;
  END IF;

  INSERT INTO public.coaching_monthly_notes AS cmn (
    group_id, user_id, month_start, highlights, improvements,
    personal_note, approved_at, coach_user_id, updated_at
  )
  VALUES (
    p_group_id, p_user_id, v_month_start, p_highlights, p_improvements,
    p_personal_note, v_approved_at, v_caller, now()
  )
  ON CONFLICT (group_id, user_id, month_start) DO UPDATE SET
    highlights = EXCLUDED.highlights,
    improvements = EXCLUDED.improvements,
    personal_note = EXCLUDED.personal_note,
    approved_at = EXCLUDED.approved_at,
    coach_user_id = EXCLUDED.coach_user_id,
    updated_at = now()
  RETURNING jsonb_build_object(
    'group_id', cmn.group_id,
    'user_id', cmn.user_id,
    'month_start', cmn.month_start,
    'highlights', cmn.highlights,
    'improvements', cmn.improvements,
    'personal_note', cmn.personal_note,
    'approved_at', cmn.approved_at,
    'updated_at', cmn.updated_at
  ) INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_upsert_monthly_note(uuid, uuid, date, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_upsert_monthly_note(uuid, uuid, date, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_upsert_monthly_note(uuid, uuid, date, text, text, text) TO service_role;

COMMENT ON FUNCTION public.fn_upsert_monthly_note(uuid, uuid, date, text, text, text)
IS 'L23-11: upsert coach free-text for an athlete-month. approved_at is set iff all 3 fields are non-empty.';

-- ----- fn_athlete_monthly_report_assert_shape -----------------------------
CREATE OR REPLACE FUNCTION public.fn_athlete_monthly_report_assert_shape()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_report_volatility text;
  v_report_secdef boolean;
  v_upsert_volatility text;
  v_upsert_secdef boolean;
  v_rls_enabled boolean;
  v_unique_exists boolean;
BEGIN
  SELECT p.provolatile::text, p.prosecdef
    INTO v_report_volatility, v_report_secdef
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'fn_athlete_monthly_report';

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0010',
      MESSAGE = 'L23-11 DRIFT:function_missing:fn_athlete_monthly_report';
  END IF;

  IF v_report_volatility <> 's' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0010',
      MESSAGE = format('L23-11 DRIFT:report_wrong_volatility:s_got_%s', v_report_volatility);
  END IF;

  IF v_report_secdef IS NOT TRUE THEN
    RAISE EXCEPTION USING ERRCODE = 'P0010',
      MESSAGE = 'L23-11 DRIFT:report_not_security_definer';
  END IF;

  SELECT p.provolatile::text, p.prosecdef
    INTO v_upsert_volatility, v_upsert_secdef
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'fn_upsert_monthly_note';

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0010',
      MESSAGE = 'L23-11 DRIFT:function_missing:fn_upsert_monthly_note';
  END IF;

  IF v_upsert_volatility <> 'v' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0010',
      MESSAGE = format('L23-11 DRIFT:upsert_wrong_volatility:v_got_%s', v_upsert_volatility);
  END IF;

  IF v_upsert_secdef IS NOT TRUE THEN
    RAISE EXCEPTION USING ERRCODE = 'P0010',
      MESSAGE = 'L23-11 DRIFT:upsert_not_security_definer';
  END IF;

  SELECT c.relrowsecurity INTO v_rls_enabled
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'coaching_monthly_notes';

  IF v_rls_enabled IS NOT TRUE THEN
    RAISE EXCEPTION USING ERRCODE = 'P0010',
      MESSAGE = 'L23-11 DRIFT:coaching_monthly_notes_rls_disabled';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'uq_coaching_monthly_notes'
  ) INTO v_unique_exists;

  IF v_unique_exists IS NOT TRUE THEN
    RAISE EXCEPTION USING ERRCODE = 'P0010',
      MESSAGE = 'L23-11 DRIFT:unique_constraint_missing';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_athlete_monthly_report_assert_shape() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_athlete_monthly_report_assert_shape() TO service_role;

DO $$
BEGIN
  PERFORM public.fn_athlete_monthly_report_assert_shape();
  RAISE NOTICE 'L23-11 migration self-test passed';
END;
$$;

COMMIT;
