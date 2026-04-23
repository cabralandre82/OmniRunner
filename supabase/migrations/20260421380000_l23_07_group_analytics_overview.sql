-- L23-07 — Análise coletiva (grupo) limitada
-- =====================================================================
-- Problem
-- -------
-- `coaching_kpis_daily` carries per-day totals per group, but coaches
-- asking for group-level coaching questions have to pivot SQL by hand:
--   (1) weekly volume distribution ("who is carrying / falling behind")
--   (2) over-trained athletes ("who is doing more than I prescribed")
--   (3) attrition risk ("who stopped showing up")
--   (4) month-over-month collective progress
-- The finding proposes materialised views. We opt instead for an on-
-- demand `SECURITY DEFINER` RPC that computes the four cuts from the
-- existing `sessions` + `coaching_members` tables — this avoids a
-- refresh job, keeps cardinality bounded (one group × 1-2 windows),
-- and reuses the existing L08-03 btree on `sessions(user_id, start_time_ms)`
-- which is already tuned for this exact access pattern.
--
-- Fix layers (all forward-only, additive)
-- ---------------------------------------
-- (a) `fn_group_analytics_overview(p_group_id uuid, p_window_days int)` —
--     SECURITY DEFINER, STABLE. Caller MUST be coach or assistant of
--     the group (coaching_members role IN ('coach','assistant')). Raises
--     P0010 UNAUTHORIZED otherwise. Returns a jsonb with the four cuts.
--
-- (b) `fn_group_analytics_assert_shape()` — CI-only shape guard. Raises
--     P0010 with `L23-07` marker on any drift (missing function,
--     wrong volatility, missing EXECUTE grant, wrong SECURITY DEFINER).
--
-- Privacy / security posture
-- --------------------------
-- - Coach identity gate: coaching_members.role IN ('coach','assistant').
--   Athletes calling the RPC get UNAUTHORIZED.
-- - Return surface includes `user_id` and `display_name` by design —
--   coaches need to identify the athlete. This is fine because the
--   coach-member relationship already implies the coach knows the
--   athlete's identity within the group.
-- - No timestamp leakage beyond the window chosen by the caller.
-- - `window_days` clamped to [7, 180] to bound query cost.
--
-- Cross-refs
-- ----------
-- L08-03 — `idx_sessions_user_time` is the exact index this RPC
-- needs; without it the per-athlete window scan would be quadratic.
-- L04-07 — coin_ledger.reason PII guard. Not applicable here; this
-- RPC returns coaching-only display_name which is already in
-- coaching_members.
-- L22-05 — same SECURITY DEFINER + caller-auth gate pattern.
-- =====================================================================

BEGIN;

-- ----- fn_group_analytics_overview ----------------------------------------
CREATE OR REPLACE FUNCTION public.fn_group_analytics_overview(
  p_group_id uuid,
  p_window_days integer DEFAULT 28
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
  v_window_days integer;
  v_now_ms bigint;
  v_window_start_ms bigint;
  v_prev_window_start_ms bigint;
  v_short_window_start_ms bigint;
  v_result jsonb;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0010',
      MESSAGE = 'UNAUTHORIZED',
      DETAIL = 'L23-07: caller must be authenticated';
  END IF;

  IF p_group_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'INVALID_GROUP_ID',
      DETAIL = 'L23-07: p_group_id must not be null';
  END IF;

  -- Clamp window to [7, 180] days. We accept NULL → 28.
  v_window_days := COALESCE(p_window_days, 28);
  IF v_window_days < 7 THEN
    v_window_days := 7;
  ELSIF v_window_days > 180 THEN
    v_window_days := 180;
  END IF;

  SELECT role INTO v_role
  FROM public.coaching_members
  WHERE group_id = p_group_id
    AND user_id = v_caller
  LIMIT 1;

  IF v_role IS NULL OR v_role NOT IN ('coach', 'assistant') THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0010',
      MESSAGE = 'UNAUTHORIZED',
      DETAIL = 'L23-07: caller is not coach/assistant of the group';
  END IF;

  v_now_ms := (EXTRACT(EPOCH FROM now()) * 1000)::bigint;
  v_window_start_ms := v_now_ms - (v_window_days::bigint * 86400000);
  v_prev_window_start_ms := v_window_start_ms - (v_window_days::bigint * 86400000);
  v_short_window_start_ms := v_now_ms - (7::bigint * 86400000);

  WITH roster AS (
    SELECT cm.user_id, cm.display_name
    FROM public.coaching_members cm
    WHERE cm.group_id = p_group_id
      AND cm.role = 'athlete'
  ),
  athlete_sessions AS (
    SELECT
      r.user_id,
      r.display_name,
      s.start_time_ms,
      s.total_distance_m
    FROM roster r
    LEFT JOIN public.sessions s
      ON s.user_id = r.user_id
     AND s.start_time_ms >= v_prev_window_start_ms
     AND s.is_verified = true
  ),
  per_athlete AS (
    SELECT
      r.user_id,
      r.display_name,
      COALESCE(SUM(
        CASE WHEN s.start_time_ms >= v_window_start_ms
             THEN s.total_distance_m ELSE 0 END
      ), 0) / 1000.0 AS km_window,
      COALESCE(SUM(
        CASE WHEN s.start_time_ms >= v_prev_window_start_ms
              AND s.start_time_ms < v_window_start_ms
             THEN s.total_distance_m ELSE 0 END
      ), 0) / 1000.0 AS km_prev_window,
      COALESCE(SUM(
        CASE WHEN s.start_time_ms >= v_short_window_start_ms
             THEN s.total_distance_m ELSE 0 END
      ), 0) / 1000.0 AS km_last7,
      COALESCE(COUNT(
        CASE WHEN s.start_time_ms >= v_window_start_ms
             THEN 1 END
      ), 0) AS sessions_window,
      MAX(s.start_time_ms) AS last_session_ms
    FROM roster r
    LEFT JOIN athlete_sessions s USING (user_id)
    GROUP BY r.user_id, r.display_name
  ),
  collective AS (
    SELECT
      SUM(km_window) AS total_km_window,
      SUM(km_prev_window) AS total_km_prev_window,
      COUNT(*) FILTER (WHERE sessions_window > 0) AS active_athletes,
      COUNT(*) AS total_athletes
    FROM per_athlete
  )
  SELECT jsonb_build_object(
    'window_days', v_window_days,
    'generated_at_ms', v_now_ms,
    'volume_distribution', (
      SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
          'user_id', p.user_id,
          'display_name', p.display_name,
          'km_window', ROUND(p.km_window::numeric, 2),
          'sessions_window', p.sessions_window
        ) ORDER BY p.km_window DESC
      ), '[]'::jsonb)
      FROM per_athlete p
    ),
    'overtraining', (
      SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
          'user_id', p.user_id,
          'display_name', p.display_name,
          'km_last7', ROUND(p.km_last7::numeric, 2),
          'km_window', ROUND(p.km_window::numeric, 2),
          'ratio', ROUND((p.km_last7 / NULLIF(p.km_window / (v_window_days / 7.0), 0))::numeric, 2)
        ) ORDER BY p.km_last7 DESC
      ), '[]'::jsonb)
      FROM per_athlete p
      WHERE p.km_window > 0
        AND p.km_last7 > 1.5 * (p.km_window / (v_window_days / 7.0))
        AND p.km_last7 >= 20
    ),
    'attrition_risk', (
      SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
          'user_id', p.user_id,
          'display_name', p.display_name,
          'sessions_window', p.sessions_window,
          'last_session_ms', p.last_session_ms
        ) ORDER BY COALESCE(p.last_session_ms, 0) ASC
      ), '[]'::jsonb)
      FROM per_athlete p
      WHERE p.sessions_window = 0
         OR (p.last_session_ms IS NOT NULL
             AND v_now_ms - p.last_session_ms > 14 * 86400000)
    ),
    'collective_progress', (
      SELECT jsonb_build_object(
        'total_km_window', ROUND(COALESCE(c.total_km_window, 0)::numeric, 2),
        'total_km_prev_window', ROUND(COALESCE(c.total_km_prev_window, 0)::numeric, 2),
        'delta_pct', CASE
          WHEN COALESCE(c.total_km_prev_window, 0) = 0 THEN NULL
          ELSE ROUND(((c.total_km_window - c.total_km_prev_window)
                     / c.total_km_prev_window * 100)::numeric, 2)
        END,
        'active_athletes', c.active_athletes,
        'total_athletes', c.total_athletes
      )
      FROM collective c
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_group_analytics_overview(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_group_analytics_overview(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_group_analytics_overview(uuid, integer) TO service_role;

COMMENT ON FUNCTION public.fn_group_analytics_overview(uuid, integer)
IS 'L23-07: coach-facing group analytics. Returns jsonb with volume_distribution, overtraining, attrition_risk, collective_progress. Caller must be coach/assistant of the group.';

-- ----- fn_group_analytics_assert_shape ------------------------------------
CREATE OR REPLACE FUNCTION public.fn_group_analytics_assert_shape()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_volatility text;
  v_secdef boolean;
  v_has_exec boolean;
BEGIN
  SELECT p.provolatile::text, p.prosecdef
    INTO v_volatility, v_secdef
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'fn_group_analytics_overview';

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0010',
      MESSAGE = 'L23-07 DRIFT:function_missing:fn_group_analytics_overview';
  END IF;

  IF v_volatility <> 's' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0010',
      MESSAGE = format('L23-07 DRIFT:wrong_volatility:%s_got_%s', 's', v_volatility);
  END IF;

  IF v_secdef IS NOT TRUE THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0010',
      MESSAGE = 'L23-07 DRIFT:not_security_definer';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_roles r ON true
    WHERE n.nspname = 'public'
      AND p.proname = 'fn_group_analytics_overview'
      AND r.rolname = 'authenticated'
      AND has_function_privilege(r.rolname, p.oid, 'EXECUTE')
  ) INTO v_has_exec;

  IF v_has_exec IS NOT TRUE THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0010',
      MESSAGE = 'L23-07 DRIFT:authenticated_missing_execute';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_group_analytics_assert_shape() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_group_analytics_assert_shape() TO service_role;

COMMENT ON FUNCTION public.fn_group_analytics_assert_shape()
IS 'L23-07: CI shape guard. Raises P0010 with L23-07 DRIFT:<reason> on any drift.';

-- Self-test: the function itself must be callable as a shape guard now.
DO $$
BEGIN
  PERFORM public.fn_group_analytics_assert_shape();
  RAISE NOTICE 'L23-07 migration self-test passed';
END;
$$;

COMMIT;
