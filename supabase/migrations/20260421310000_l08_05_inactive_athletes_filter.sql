-- ============================================================================
-- L08-05 — Filter inactive athletes from progression views
-- ============================================================================
--
-- Finding (docs/audit/findings/L08-05-views-de-progressao-sem-filtro-de-atletas-inativos.md):
--   "v_user_progression, v_weekly_progress (em 20260221000030). Atletas que
--    pararam há 1 ano continuam sendo agregados no ranking de 'atleta mais
--    evoluído', distorcendo baselines."
--
-- Design decision (2026-04-21):
--   Modificar v_user_progression/v_weekly_progress IN-PLACE para adicionar
--   WHERE last_session_at > now() - 90 days quebraria consumidores atuais:
--     - supabase/functions/notify-rules/index.ts (busca users com streak >= 3)
--     - omni_runner/…/streaks_leaderboard_screen.dart (leaderboard interno)
--     - omni_runner/…/staff_weekly_report_screen.dart (relatório semanal)
--   Nenhum desses tem intenção de listar apenas atletas ativos — é legítimo
--   mostrar um atleta com streak=0 ("cold start") no leaderboard do staff.
--
--   Estratégia forward-compatível:
--     1. EXPANDIR v_user_progression com a nova coluna `last_session_at`
--        timestamptz NULLABLE (projeção derivada de MAX(sessions.start_time_ms)).
--        Backward-compat: schema é strict superset, nenhum consumidor quebra.
--     2. NOVA view v_user_progression_active_90d — mesmo shape, filtrada por
--        last_session_at > now() - 90 days. É a fonte canônica para rankings
--        de "atleta mais evoluído" / baselines.
--     3. Helper fn_is_athlete_active_90d(p_user_id) — STABLE SECURITY DEFINER,
--        RETURNS boolean, usado em filtros pontuais de agregação.
--
--   Consequências:
--     - Rankings que dependem de progresso agregado precisam migrar para a
--       view _active_90d (seguinte PR de UX).
--     - Para UIs que precisam diferenciar "cold athlete" vs "inactive athlete"
--       (ex.: staff_weekly_report), o flag booleano é exposto via
--       is_active_90d na view expandida (COALESCE(last_session_at > now()-90d, false)).
--
-- Performance:
--   - O MAX(start_time_ms) por user usa idx_sessions_user(user_id, start_time_ms DESC)
--     → single index-only scan. Custo irrelevante para < 50k profiles.
-- ============================================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────────────────
-- 1. Helper: fn_is_athlete_active_90d
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_is_athlete_active_90d(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $fn$
  SELECT EXISTS (
    SELECT 1
      FROM public.sessions s
     WHERE s.user_id = p_user_id
       AND s.is_verified = true
       AND s.start_time_ms >= (EXTRACT(EPOCH FROM (now() - interval '90 days')) * 1000)::bigint
  );
$fn$;

COMMENT ON FUNCTION public.fn_is_athlete_active_90d(uuid) IS
  'L08-05: TRUE iff user_id has at least one verified session in the past 90 days. '
  'Uses idx_sessions_user index-only scan (user_id, start_time_ms DESC).';

REVOKE ALL ON FUNCTION public.fn_is_athlete_active_90d(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_is_athlete_active_90d(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_is_athlete_active_90d(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_is_athlete_active_90d(uuid) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 2. v_user_progression — EXPAND com last_session_at + is_active_90d
-- ──────────────────────────────────────────────────────────────────────────
-- Mantém TODAS as colunas originais na mesma ordem; apenas adiciona as 2
-- colunas derivadas no final. Safe para consumidores que usam .select('col1,col2').

CREATE OR REPLACE VIEW public.v_user_progression
WITH (security_invoker = on)
AS
SELECT
  p.id                                                AS user_id,
  p.display_name,
  p.avatar_url,
  pp.total_xp,
  pp.level,
  GREATEST(0,
    FLOOR(100.0 * POWER((pp.level + 1)::DOUBLE PRECISION, 1.5))::INTEGER - pp.total_xp
  )                                                   AS xp_to_next_level,
  pp.season_xp,
  pp.daily_streak_count                               AS streak_current,
  pp.streak_best,
  pp.has_freeze_available,
  pp.weekly_session_count,
  pp.monthly_session_count,
  pp.lifetime_session_count,
  pp.lifetime_distance_m,
  pp.lifetime_moving_ms,
  pp.updated_at,
  -- L08-05: last verified session as timestamptz
  (
    SELECT to_timestamp(MAX(s.start_time_ms) / 1000.0) AT TIME ZONE 'UTC'
      FROM public.sessions s
     WHERE s.user_id = p.id
       AND s.is_verified = true
  )                                                   AS last_session_at,
  -- L08-05: has at least one verified session in the past 90 days
  COALESCE((
    SELECT (MAX(s.start_time_ms) >= (EXTRACT(EPOCH FROM (now() - interval '90 days')) * 1000)::bigint)
      FROM public.sessions s
     WHERE s.user_id = p.id
       AND s.is_verified = true
  ), false)                                           AS is_active_90d
FROM public.profiles p
LEFT JOIN public.profile_progress pp ON pp.user_id = p.id;

COMMENT ON VIEW public.v_user_progression IS
  'L08-05 (2026-04-21): expanded with last_session_at + is_active_90d. '
  'SECURITY INVOKER — RLS on profiles/profile_progress/sessions is enforced '
  'per-query. For rankings/baselines, use v_user_progression_active_90d.';

-- ──────────────────────────────────────────────────────────────────────────
-- 3. v_user_progression_active_90d — canonical source for rankings
-- ──────────────────────────────────────────────────────────────────────────
-- Mesmo shape da v_user_progression (incluindo is_active_90d, sempre true aqui).
-- Consumidores de ranking/baseline devem migrar para esta view.

CREATE OR REPLACE VIEW public.v_user_progression_active_90d
WITH (security_invoker = on)
AS
SELECT *
  FROM public.v_user_progression
 WHERE is_active_90d = true;

COMMENT ON VIEW public.v_user_progression_active_90d IS
  'L08-05 (2026-04-21): filtered view, only athletes with at least one verified '
  'session in the past 90 days. Use as canonical source for rankings and baselines '
  'to prevent inactive athletes from distorting "atleta mais evoluído" queries.';

-- ──────────────────────────────────────────────────────────────────────────
-- 4. v_weekly_progress_active_90d — aggregated progress from active athletes only
-- ──────────────────────────────────────────────────────────────────────────
-- v_weekly_progress é usada por fn_generate_weekly_goal / fn_check_weekly_goal
-- para compute de baseline nos últimos 28 dias — inerentemente restrito, sem risco.
-- Mesmo assim, expomos um mirror 90d-filtrado para consumidores de analytics que
-- agreguem além do horizon semanal (ex.: dashboards staff).

CREATE OR REPLACE VIEW public.v_weekly_progress_active_90d
WITH (security_invoker = on)
AS
SELECT
  s.user_id,
  DATE_TRUNC('week', TO_TIMESTAMP(s.start_time_ms / 1000.0) AT TIME ZONE 'UTC')::DATE
                                                      AS week_start,
  COUNT(*)::INTEGER                                   AS session_count,
  COALESCE(SUM(s.total_distance_m), 0)                AS total_distance_m,
  COALESCE(SUM(s.moving_ms), 0)                       AS total_moving_ms,
  ROUND(COALESCE(SUM(s.moving_ms), 0) / 1000.0 / 60.0, 1)
                                                      AS total_moving_min,
  MIN(s.start_time_ms)                                AS first_session_ms,
  MAX(s.start_time_ms)                                AS last_session_ms
FROM public.sessions s
WHERE s.is_verified = true
  AND s.total_distance_m >= 200
  AND s.start_time_ms >= (EXTRACT(EPOCH FROM (now() - interval '90 days')) * 1000)::bigint
GROUP BY s.user_id, DATE_TRUNC('week', TO_TIMESTAMP(s.start_time_ms / 1000.0) AT TIME ZONE 'UTC')::DATE;

COMMENT ON VIEW public.v_weekly_progress_active_90d IS
  'L08-05 (2026-04-21): mirror of v_weekly_progress but filtered to sessions '
  'in the past 90 days. Use for analytics dashboards / staff reports; for '
  'short-term goal baselines keep using v_weekly_progress (already restricted '
  'via week_start >= _week_start - 28 days in fn_generate_weekly_goal).';

-- ──────────────────────────────────────────────────────────────────────────
-- 5. Self-test
-- ──────────────────────────────────────────────────────────────────────────
DO $selftest$
DECLARE
  v_count  integer;
  v_col_present boolean;
BEGIN
  -- (a) fn_is_athlete_active_90d registered, STABLE, SECURITY DEFINER
  SELECT count(*)::int INTO v_count
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'fn_is_athlete_active_90d'
     AND p.prosecdef = true
     AND p.provolatile = 's';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'L08-05 selftest: expected 1 STABLE SECURITY DEFINER fn, got %', v_count;
  END IF;

  -- (b) v_user_progression has new columns
  SELECT EXISTS (
    SELECT 1 FROM pg_attribute a
    JOIN pg_class c ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'v_user_progression'
      AND a.attname = 'last_session_at'
      AND a.attnum > 0
  ) INTO v_col_present;
  IF NOT v_col_present THEN
    RAISE EXCEPTION 'L08-05 selftest: v_user_progression.last_session_at not found';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM pg_attribute a
    JOIN pg_class c ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'v_user_progression'
      AND a.attname = 'is_active_90d'
      AND a.attnum > 0
  ) INTO v_col_present;
  IF NOT v_col_present THEN
    RAISE EXCEPTION 'L08-05 selftest: v_user_progression.is_active_90d not found';
  END IF;

  -- (c) 3 views existem
  SELECT count(*)::int INTO v_count
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public'
     AND c.relkind = 'v'
     AND c.relname IN (
       'v_user_progression',
       'v_user_progression_active_90d',
       'v_weekly_progress_active_90d'
     );
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'L08-05 selftest: expected 3 views, got %', v_count;
  END IF;

  -- (d) security_invoker = on nas 3 views (evita L01-46 / L10-04 REGRESSION)
  SELECT count(*)::int INTO v_count
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public'
     AND c.relkind = 'v'
     AND c.relname IN (
       'v_user_progression',
       'v_user_progression_active_90d',
       'v_weekly_progress_active_90d'
     )
     AND c.reloptions @> ARRAY['security_invoker=on']::text[];
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'L08-05 selftest: expected 3 security_invoker=on views, got %', v_count;
  END IF;

  RAISE NOTICE '[L08-05.selftest] OK — 4 phases pass';
END $selftest$;

COMMIT;
