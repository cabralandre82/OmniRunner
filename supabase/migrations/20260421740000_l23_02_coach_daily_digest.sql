-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║ L23-02 — fn_coach_daily_digest                                           ║
-- ║                                                                           ║
-- ║ Bucketiza atletas de uma assessoria em 4 categorias prioritárias para   ║
-- ║ que o coach com 100-500 atletas não precise olhar lista alfabética.     ║
-- ║                                                                           ║
-- ║ Finding : docs/audit/findings/L23-02-dashboard-de-overview-diario-      ║
-- ║           para-coach-tem-100.md                                          ║
-- ║                                                                           ║
-- ║ Contract                                                                 ║
-- ║ --------                                                                 ║
-- ║ RPC `public.fn_coach_daily_digest(                                       ║
-- ║         p_group_id   uuid,                                               ║
-- ║         p_as_of      date     DEFAULT CURRENT_DATE,                      ║
-- ║         p_max_per_bucket int  DEFAULT 50)`                               ║
-- ║   • SECURITY DEFINER, STABLE (read-only; no writes to any table).        ║
-- ║   • Caller MUST be coach/assistant/admin_master of the group.           ║
-- ║   • Returns jsonb envelope with 4 prioritized buckets.                  ║
-- ║                                                                           ║
-- ║ Bucket priority (an athlete appears in AT MOST one bucket)              ║
-- ║ -------------------------------------------------------------           ║
-- ║   1. needs_attention — inactive_3d / plan_not_followed / integrity_flag ║
-- ║   2. at_risk         — declining_volume / overtraining_spike            ║
-- ║   3. new_prs         — best 7d pace beats 90-day baseline              ║
-- ║   4. performing_well — adherence_14d_pct ≥ 80                          ║
-- ║                                                                          ║
-- ║ Errors                                                                  ║
-- ║ ------                                                                  ║
-- ║   P0001 INVALID_INPUT     — p_group_id NULL ou p_max_per_bucket fora  ║
-- ║                              de [1, 200].                              ║
-- ║   P0002 GROUP_NOT_FOUND   — p_group_id não existe.                    ║
-- ║   P0010 UNAUTHORIZED      — caller não é staff do grupo.              ║
-- ║                                                                          ║
-- ║ OmniCoin policy                                                         ║
-- ║ ---------------                                                         ║
-- ║ Read-only; never touches public.coin_ledger / public.wallets.          ║
-- ║ L04-07-OK                                                               ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_coach_daily_digest(
  p_group_id        uuid,
  p_as_of           date    DEFAULT CURRENT_DATE,
  p_max_per_bucket  int     DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
DECLARE
  v_caller          uuid := auth.uid();
  v_role            text;
  v_window_now_lo   timestamptz;
  v_window_now_hi   timestamptz;
  v_window_prev_lo  timestamptz;
  v_window_prev_hi  timestamptz;
  v_inactive_cut    timestamptz;
  v_result          jsonb;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0010', MESSAGE = 'UNAUTHORIZED',
      DETAIL = 'L23-02: caller must be authenticated';
  END IF;

  IF p_group_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'INVALID_INPUT',
      DETAIL = 'L23-02: p_group_id is NULL';
  END IF;

  IF p_max_per_bucket IS NULL OR p_max_per_bucket < 1 OR p_max_per_bucket > 200 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'INVALID_INPUT',
      DETAIL = 'L23-02: p_max_per_bucket outside [1,200]';
  END IF;

  IF p_as_of IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'INVALID_INPUT',
      DETAIL = 'L23-02: p_as_of is NULL';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.coaching_groups WHERE id = p_group_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'GROUP_NOT_FOUND',
      DETAIL = 'L23-02: group does not exist';
  END IF;

  SELECT cm.role INTO v_role
  FROM public.coaching_members cm
  WHERE cm.user_id = v_caller
    AND cm.group_id = p_group_id;

  IF v_role IS NULL OR v_role NOT IN ('admin_master', 'coach', 'assistant') THEN
    RAISE EXCEPTION USING ERRCODE = 'P0010', MESSAGE = 'UNAUTHORIZED',
      DETAIL = 'L23-02: caller is not staff of the group';
  END IF;

  v_window_now_hi   := (p_as_of + 1)::timestamptz;
  v_window_now_lo   := v_window_now_hi - interval '7 days';
  v_window_prev_hi  := v_window_now_lo;
  v_window_prev_lo  := v_window_prev_hi - interval '7 days';
  v_inactive_cut    := v_window_now_hi - interval '3 days';

  WITH members AS (
    SELECT cm.user_id AS athlete_user_id,
           cm.display_name
    FROM public.coaching_members cm
    WHERE cm.group_id = p_group_id
      AND cm.role = 'athlete'
  ),
  sess_now AS (
    SELECT s.user_id,
           count(*) FILTER (WHERE s.is_verified) AS verified_n,
           sum(s.total_distance_m) FILTER (WHERE s.is_verified) AS dist_m,
           bool_or(coalesce(array_length(s.integrity_flags, 1), 0) > 0) AS has_integrity_flag
    FROM public.sessions s
    WHERE s.user_id IN (SELECT athlete_user_id FROM members)
      AND s.start_time_ms >= extract(epoch FROM v_window_now_lo) * 1000
      AND s.start_time_ms <  extract(epoch FROM v_window_now_hi) * 1000
      AND s.status >= 3
    GROUP BY s.user_id
  ),
  sess_prev AS (
    SELECT s.user_id,
           sum(s.total_distance_m) FILTER (WHERE s.is_verified) AS dist_m
    FROM public.sessions s
    WHERE s.user_id IN (SELECT athlete_user_id FROM members)
      AND s.start_time_ms >= extract(epoch FROM v_window_prev_lo) * 1000
      AND s.start_time_ms <  extract(epoch FROM v_window_prev_hi) * 1000
      AND s.status >= 3
    GROUP BY s.user_id
  ),
  sess_last AS (
    SELECT DISTINCT ON (s.user_id)
           s.user_id,
           to_timestamp(s.start_time_ms / 1000.0) AS last_started_at
    FROM public.sessions s
    WHERE s.user_id IN (SELECT athlete_user_id FROM members)
      AND s.status >= 3
    ORDER BY s.user_id, s.start_time_ms DESC
  ),
  sess_history_pace AS (
    SELECT s.user_id,
           min(s.avg_pace_sec_km) FILTER (
             WHERE s.is_verified
               AND s.avg_pace_sec_km IS NOT NULL
               AND s.avg_pace_sec_km > 0
               AND s.start_time_ms <  extract(epoch FROM v_window_now_lo) * 1000
               AND s.start_time_ms >= extract(epoch FROM v_window_now_hi - interval '90 days') * 1000
               AND s.total_distance_m >= 1000
           ) AS baseline_best_pace
    FROM public.sessions s
    WHERE s.user_id IN (SELECT athlete_user_id FROM members)
    GROUP BY s.user_id
  ),
  sess_best_recent AS (
    SELECT DISTINCT ON (s.user_id)
           s.user_id,
           s.avg_pace_sec_km AS best_recent_pace,
           s.total_distance_m AS best_recent_distance,
           to_timestamp(s.start_time_ms / 1000.0) AS best_recent_at
    FROM public.sessions s
    WHERE s.user_id IN (SELECT athlete_user_id FROM members)
      AND s.is_verified
      AND s.avg_pace_sec_km IS NOT NULL
      AND s.avg_pace_sec_km > 0
      AND s.start_time_ms >= extract(epoch FROM v_window_now_lo) * 1000
      AND s.start_time_ms <  extract(epoch FROM v_window_now_hi) * 1000
      AND s.status >= 3
      AND s.total_distance_m >= 1000
    ORDER BY s.user_id, s.avg_pace_sec_km ASC
  ),
  delivery AS (
    SELECT i.athlete_user_id,
           count(*) FILTER (
             WHERE i.status = 'confirmed'
               AND i.confirmed_at >= v_window_now_lo - interval '7 days'
               AND i.confirmed_at <  v_window_now_hi
           ) AS planned_14d,
           count(*) FILTER (
             WHERE i.status = 'confirmed'
               AND i.confirmed_at >= v_window_now_lo
               AND i.confirmed_at <  v_window_now_hi
           ) AS planned_7d
    FROM public.workout_delivery_items i
    WHERE i.group_id = p_group_id
      AND i.athlete_user_id IN (SELECT athlete_user_id FROM members)
    GROUP BY i.athlete_user_id
  ),
  rolled AS (
    SELECT m.athlete_user_id,
           m.display_name,
           coalesce(n.verified_n,         0)     AS verified_n_7d,
           coalesce(n.dist_m,             0)     AS dist_m_7d,
           coalesce(p.dist_m,             0)     AS dist_m_prev_7d,
           coalesce(d.planned_7d,         0)     AS planned_7d,
           coalesce(d.planned_14d,        0)     AS planned_14d,
           coalesce(n.has_integrity_flag, false) AS integrity_flag,
           sl.last_started_at,
           sbr.best_recent_pace,
           sbr.best_recent_distance,
           sbr.best_recent_at,
           shp.baseline_best_pace
    FROM members m
    LEFT JOIN sess_now            n   ON n.user_id   = m.athlete_user_id
    LEFT JOIN sess_prev           p   ON p.user_id   = m.athlete_user_id
    LEFT JOIN sess_last           sl  ON sl.user_id  = m.athlete_user_id
    LEFT JOIN sess_best_recent    sbr ON sbr.user_id = m.athlete_user_id
    LEFT JOIN sess_history_pace   shp ON shp.user_id = m.athlete_user_id
    LEFT JOIN delivery            d   ON d.athlete_user_id = m.athlete_user_id
  ),
  classified AS (
    SELECT
      r.athlete_user_id,
      r.display_name,
      r.last_started_at,
      r.verified_n_7d,
      r.planned_7d,
      r.planned_14d,
      r.dist_m_7d,
      r.dist_m_prev_7d,
      r.integrity_flag,
      r.best_recent_pace,
      r.best_recent_distance,
      r.best_recent_at,
      r.baseline_best_pace,
      CASE
        WHEN r.planned_14d = 0 THEN NULL
        ELSE round((100.0 * least(r.verified_n_7d * 2, r.planned_14d) / r.planned_14d)::numeric, 1)
      END AS adherence_14d_pct,
      (r.last_started_at IS NULL OR r.last_started_at < v_inactive_cut)
                                                            AS sig_inactive_3d,
      (r.planned_7d > 0 AND r.verified_n_7d = 0)            AS sig_plan_not_followed,
      r.integrity_flag                                      AS sig_integrity_flag,
      (r.dist_m_prev_7d > 0
        AND r.dist_m_7d  < (r.dist_m_prev_7d * 0.5))         AS sig_declining_volume,
      (r.dist_m_prev_7d > 0
        AND r.dist_m_7d  > (r.dist_m_prev_7d * 2.0))         AS sig_overtraining_spike,
      (r.best_recent_pace IS NOT NULL
        AND r.baseline_best_pace IS NOT NULL
        AND r.best_recent_pace < r.baseline_best_pace)       AS sig_new_pr
    FROM rolled r
  ),
  bucketed AS (
    SELECT
      c.*,
      CASE
        WHEN c.sig_inactive_3d
          OR c.sig_plan_not_followed
          OR c.sig_integrity_flag                          THEN 'needs_attention'
        WHEN c.sig_declining_volume
          OR c.sig_overtraining_spike                      THEN 'at_risk'
        WHEN c.sig_new_pr                                  THEN 'new_prs'
        WHEN coalesce(c.adherence_14d_pct, 0) >= 80        THEN 'performing_well'
        ELSE 'neutral'
      END AS bucket,
      (CASE WHEN c.sig_integrity_flag      THEN 100 ELSE 0 END
     + CASE WHEN c.sig_plan_not_followed   THEN  60 ELSE 0 END
     + CASE WHEN c.sig_inactive_3d         THEN  40 ELSE 0 END
     + CASE WHEN c.sig_overtraining_spike  THEN  30 ELSE 0 END
     + CASE WHEN c.sig_declining_volume    THEN  20 ELSE 0 END
     + CASE WHEN c.sig_new_pr              THEN  10 ELSE 0 END
      ) AS score
    FROM classified c
  ),
  capped AS (
    SELECT b.*,
           row_number() OVER (
             PARTITION BY b.bucket
             ORDER BY b.score DESC, b.last_started_at DESC NULLS LAST
           ) AS rk
    FROM bucketed b
  ),
  ordered AS (
    SELECT
      jsonb_build_object(
        'athlete_user_id',      c.athlete_user_id,
        'display_name',         c.display_name,
        'bucket',               c.bucket,
        'score',                c.score,
        'last_session_at',      c.last_started_at,
        'verified_sessions_7d', c.verified_n_7d,
        'planned_7d',           c.planned_7d,
        'planned_14d',          c.planned_14d,
        'dist_m_7d',            c.dist_m_7d,
        'dist_m_prev_7d',       c.dist_m_prev_7d,
        'adherence_14d_pct',    c.adherence_14d_pct,
        'best_recent_pace',     c.best_recent_pace,
        'best_recent_distance', c.best_recent_distance,
        'best_recent_at',       c.best_recent_at,
        'baseline_best_pace',   c.baseline_best_pace,
        'signals',              array_remove(ARRAY[
          CASE WHEN c.sig_inactive_3d        THEN 'inactive_3d'        END,
          CASE WHEN c.sig_plan_not_followed  THEN 'plan_not_followed'  END,
          CASE WHEN c.sig_integrity_flag     THEN 'integrity_flag'     END,
          CASE WHEN c.sig_declining_volume   THEN 'declining_volume'   END,
          CASE WHEN c.sig_overtraining_spike THEN 'overtraining_spike' END,
          CASE WHEN c.sig_new_pr             THEN 'new_pr'             END
        ], NULL)
      ) AS row_json,
      c.bucket,
      c.score,
      c.last_started_at,
      c.adherence_14d_pct,
      c.best_recent_at
    FROM capped c
    WHERE c.rk <= p_max_per_bucket
  )
  SELECT jsonb_build_object(
    'group_id',     p_group_id,
    'as_of',        p_as_of,
    'generated_at', now(),
    'window', jsonb_build_object(
      'now_lo',  v_window_now_lo,
      'now_hi',  v_window_now_hi,
      'prev_lo', v_window_prev_lo,
      'prev_hi', v_window_prev_hi
    ),
    'counts', jsonb_build_object(
      'total_athletes',  (SELECT count(*) FROM bucketed),
      'needs_attention', (SELECT count(*) FROM bucketed WHERE bucket = 'needs_attention'),
      'at_risk',         (SELECT count(*) FROM bucketed WHERE bucket = 'at_risk'),
      'new_prs',         (SELECT count(*) FROM bucketed WHERE bucket = 'new_prs'),
      'performing_well', (SELECT count(*) FROM bucketed WHERE bucket = 'performing_well'),
      'neutral',         (SELECT count(*) FROM bucketed WHERE bucket = 'neutral')
    ),
    'needs_attention', coalesce(
      (SELECT jsonb_agg(o.row_json ORDER BY o.score DESC, o.last_started_at DESC NULLS LAST)
         FROM ordered o WHERE o.bucket = 'needs_attention'),
      '[]'::jsonb),
    'at_risk', coalesce(
      (SELECT jsonb_agg(o.row_json ORDER BY o.score DESC, o.last_started_at DESC NULLS LAST)
         FROM ordered o WHERE o.bucket = 'at_risk'),
      '[]'::jsonb),
    'new_prs', coalesce(
      (SELECT jsonb_agg(o.row_json ORDER BY o.best_recent_at DESC NULLS LAST)
         FROM ordered o WHERE o.bucket = 'new_prs'),
      '[]'::jsonb),
    'performing_well', coalesce(
      (SELECT jsonb_agg(o.row_json ORDER BY o.adherence_14d_pct DESC NULLS LAST)
         FROM ordered o WHERE o.bucket = 'performing_well'),
      '[]'::jsonb)
  )
  INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_coach_daily_digest(uuid, date, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_coach_daily_digest(uuid, date, int) TO authenticated;

COMMENT ON FUNCTION public.fn_coach_daily_digest(uuid, date, int) IS
  'L23-02: bucketiza atletas em needs_attention/at_risk/new_prs/performing_well. '
  'Read-only (STABLE); nunca toca coin_ledger ou wallets (L04-07-OK).';

DO $self$
DECLARE
  v_proid    oid;
  v_secdef   boolean;
  v_volat    "char";
  v_cfg      text[];
  v_acl      text;
BEGIN
  SELECT p.oid, p.prosecdef, p.provolatile, p.proconfig
    INTO v_proid, v_secdef, v_volat, v_cfg
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'fn_coach_daily_digest';

  IF v_proid IS NULL THEN
    RAISE EXCEPTION 'self-test: fn_coach_daily_digest missing';
  END IF;

  IF v_secdef IS NOT TRUE THEN
    RAISE EXCEPTION 'self-test: fn_coach_daily_digest must be SECURITY DEFINER';
  END IF;

  IF v_volat <> 's' THEN
    RAISE EXCEPTION 'self-test: fn_coach_daily_digest must be STABLE';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM unnest(v_cfg) c WHERE c LIKE 'search_path=%'
  ) THEN
    RAISE EXCEPTION 'self-test: fn_coach_daily_digest must pin search_path';
  END IF;

  v_acl := pg_catalog.array_to_string(
             ARRAY(SELECT (aclexplode(p.proacl)).grantee::regrole::text
                     FROM pg_proc p WHERE p.oid = v_proid),
             ',');

  IF v_acl LIKE '%public%' THEN
    RAISE EXCEPTION 'self-test: fn_coach_daily_digest must REVOKE FROM PUBLIC';
  END IF;

  RAISE NOTICE 'L23-02 self-test PASSED';
END;
$self$;

COMMIT;
