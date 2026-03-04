-- =============================================================================
-- SCALE FIX MIGRATION — Sprint 1+4: Indexes, RLS optimization, partitioning prep
-- Target: 10,000 groups / 800K athletes
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- SPRINT 1 — P0 INDEXES (zero-risk, highest impact)
-- ─────────────────────────────────────────────────────────────────────────────

-- R1: THE most important index in the entire database.
-- Every RLS policy does EXISTS(SELECT 1 FROM coaching_members WHERE user_id=auth.uid() AND group_id=...).
-- Without this, every authenticated query does a seq scan on 850K rows.
CREATE INDEX IF NOT EXISTS idx_coaching_members_user_group
  ON public.coaching_members (user_id, group_id) INCLUDE (role);

-- R2: KPI cron scans WHERE group_id = X AND role = 'athlete'
CREATE INDEX IF NOT EXISTS idx_coaching_members_group_role
  ON public.coaching_members (group_id, role);

-- R3: KPI cron _kpi_sessions temp table creation filters on status+verified+time
CREATE INDEX IF NOT EXISTS idx_sessions_verified_time
  ON public.sessions (start_time_ms)
  WHERE status >= 3 AND is_verified = true;

-- R4: settle-challenge fee lookup by ref_id+reason on 104M-row coin_ledger
CREATE INDEX IF NOT EXISTS idx_coin_ledger_ref_reason
  ON public.coin_ledger (ref_id, reason);

-- R5: Strava webhook athlete lookup (200K/day)
CREATE INDEX IF NOT EXISTS idx_strava_connections_athlete_id
  ON public.strava_connections (strava_athlete_id);

-- R6: Strava dedup check
CREATE INDEX IF NOT EXISTS idx_sessions_strava_activity
  ON public.sessions (strava_activity_id)
  WHERE strava_activity_id IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- P1 INDEXES (required before 5K groups)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_athlete_kpis_user_group_day
  ON public.coaching_athlete_kpis_daily (user_id, group_id, day DESC);

CREATE INDEX IF NOT EXISTS idx_challenge_participants_challenge_status
  ON public.challenge_participants (challenge_id, status);

CREATE INDEX IF NOT EXISTS idx_coin_ledger_user_created
  ON public.coin_ledger (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_workout_assignments_group_status_date
  ON public.coaching_workout_assignments (group_id, status, scheduled_date)
  WHERE status = 'planned';

CREATE INDEX IF NOT EXISTS idx_notification_log_sent_at
  ON public.notification_log (sent_at);

CREATE INDEX IF NOT EXISTS idx_api_rate_limits_window_start
  ON public.api_rate_limits (window_start);

-- park_activities dedup (L-5)
CREATE UNIQUE INDEX IF NOT EXISTS idx_park_activities_session_park
  ON public.park_activities (session_id, park_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- SPRINT 4 — RLS OPTIMIZATION: auth.user_group_roles()
-- Replaces per-row EXISTS subquery on coaching_members with a STABLE function
-- that Postgres caches for the duration of the transaction.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION auth.user_group_roles()
RETURNS TABLE(group_id uuid, role text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT cm.group_id, cm.role
  FROM public.coaching_members cm
  WHERE cm.user_id = auth.uid();
$$;

REVOKE ALL ON FUNCTION auth.user_group_roles() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION auth.user_group_roles() TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- SPRINT 4 — Batch wallet operations
-- Replaces N individual increment_wallet_balance calls with a single batch RPC
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_increment_wallets_batch(
  p_entries jsonb
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count integer := 0;
  v_entry jsonb;
BEGIN
  FOR v_entry IN SELECT * FROM jsonb_array_elements(p_entries)
  LOOP
    UPDATE wallets
    SET balance_coins = balance_coins + (v_entry->>'delta')::int,
        updated_at = now()
    WHERE user_id = (v_entry->>'user_id')::uuid;

    IF NOT FOUND THEN
      INSERT INTO wallets (user_id, balance_coins, updated_at)
      VALUES ((v_entry->>'user_id')::uuid, (v_entry->>'delta')::int, now());
    END IF;

    INSERT INTO coin_ledger (user_id, delta_coins, reason, ref_id, issuer_group_id, created_at)
    VALUES (
      (v_entry->>'user_id')::uuid,
      (v_entry->>'delta')::int,
      COALESCE(v_entry->>'reason', 'batch_credit'),
      (v_entry->>'ref_id')::uuid,
      CASE WHEN v_entry->>'group_id' IS NOT NULL
           THEN (v_entry->>'group_id')::uuid
           ELSE NULL
      END,
      now()
    );

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_increment_wallets_batch(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_increment_wallets_batch(jsonb) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- SPRINT 2 — League snapshot: single SQL aggregation replaces N+1
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_compute_league_snapshots(
  p_season_id uuid,
  p_window_start_ms bigint,
  p_window_end_ms bigint
)
RETURNS TABLE(
  group_id uuid,
  total_distance_m numeric,
  total_duration_s numeric,
  total_sessions bigint,
  active_members bigint,
  challenge_wins bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    le.group_id,
    COALESCE(SUM(s.total_distance_m), 0) AS total_distance_m,
    COALESCE(SUM(s.duration_seconds), 0) AS total_duration_s,
    COUNT(DISTINCT s.id) AS total_sessions,
    COUNT(DISTINCT s.user_id) AS active_members,
    COALESCE(cw.wins, 0) AS challenge_wins
  FROM league_enrollments le
  JOIN coaching_members cm ON cm.group_id = le.group_id AND cm.role = 'athlete'
  LEFT JOIN sessions s ON s.user_id = cm.user_id
    AND s.status >= 3 AND s.is_verified = true
    AND s.start_time_ms >= p_window_start_ms
    AND s.start_time_ms < p_window_end_ms
  LEFT JOIN LATERAL (
    SELECT COUNT(*) AS wins
    FROM challenge_results cr
    JOIN challenge_participants cp ON cp.id = cr.participant_id
    WHERE cp.user_id = cm.user_id AND cr.rank = 1
      AND cr.created_at >= to_timestamp(p_window_start_ms / 1000.0)
  ) cw ON true
  WHERE le.season_id = p_season_id
  GROUP BY le.group_id, cw.wins;
$$;

REVOKE ALL ON FUNCTION public.fn_compute_league_snapshots(uuid, bigint, bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_compute_league_snapshots(uuid, bigint, bigint) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- SPRINT 2 — KPI batching: process groups in chunks
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_compute_kpis_batch(
  p_day date,
  p_group_ids uuid[]
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count integer := 0;
  v_gid uuid;
  v_month_start_ms bigint;
  v_day_start_ms bigint;
  v_day_end_ms bigint;
BEGIN
  v_month_start_ms := (EXTRACT(epoch FROM date_trunc('month', p_day)) * 1000)::bigint;
  v_day_start_ms   := (EXTRACT(epoch FROM p_day) * 1000)::bigint;
  v_day_end_ms     := (EXTRACT(epoch FROM p_day + interval '1 day') * 1000)::bigint;

  FOREACH v_gid IN ARRAY p_group_ids
  LOOP
    INSERT INTO coaching_kpis_daily (group_id, day,
      total_sessions, total_distance_m, total_duration_s,
      active_athletes, avg_sessions_per_athlete)
    SELECT
      v_gid,
      p_day,
      COUNT(DISTINCT s.id),
      COALESCE(SUM(s.total_distance_m), 0),
      COALESCE(SUM(s.duration_seconds), 0),
      COUNT(DISTINCT s.user_id),
      CASE WHEN COUNT(DISTINCT s.user_id) > 0
           THEN COUNT(DISTINCT s.id)::numeric / COUNT(DISTINCT s.user_id)
           ELSE 0
      END
    FROM coaching_members cm
    JOIN sessions s ON s.user_id = cm.user_id
      AND s.status >= 3 AND s.is_verified = true
      AND s.start_time_ms >= v_day_start_ms
      AND s.start_time_ms < v_day_end_ms
    WHERE cm.group_id = v_gid AND cm.role = 'athlete'
    ON CONFLICT (group_id, day)
    DO UPDATE SET
      total_sessions = EXCLUDED.total_sessions,
      total_distance_m = EXCLUDED.total_distance_m,
      total_duration_s = EXCLUDED.total_duration_s,
      active_athletes = EXCLUDED.active_athletes,
      avg_sessions_per_athlete = EXCLUDED.avg_sessions_per_athlete,
      updated_at = now();

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_compute_kpis_batch(date, uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_compute_kpis_batch(date, uuid[]) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- SPRINT 2 — Inactivity nudge: SQL set-difference replaces client-side
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_inactive_users(
  p_active_window_days integer DEFAULT 30,
  p_recent_window_days integer DEFAULT 5,
  p_limit integer DEFAULT 500
)
RETURNS TABLE(user_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT DISTINCT s30.user_id
  FROM sessions s30
  WHERE s30.is_verified = true
    AND s30.start_time_ms >= (EXTRACT(epoch FROM now() - (p_active_window_days || ' days')::interval) * 1000)::bigint
  EXCEPT
  SELECT DISTINCT s5.user_id
  FROM sessions s5
  WHERE s5.is_verified = true
    AND s5.start_time_ms >= (EXTRACT(epoch FROM now() - (p_recent_window_days || ' days')::interval) * 1000)::bigint
  LIMIT p_limit;
$$;

REVOKE ALL ON FUNCTION public.fn_inactive_users(integer, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_inactive_users(integer, integer, integer) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- SPRINT 4 — Strava event queue table (for rate-limited processing)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.strava_event_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id bigint NOT NULL,
  object_type text NOT NULL,
  object_id bigint NOT NULL,
  aspect_type text NOT NULL,
  event_time bigint NOT NULL,
  subscription_id bigint,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  attempts integer NOT NULL DEFAULT 0,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz
);

ALTER TABLE public.strava_event_queue ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_strava_event_queue_status
  ON public.strava_event_queue (status, created_at)
  WHERE status IN ('pending', 'failed');

CREATE UNIQUE INDEX IF NOT EXISTS idx_strava_event_queue_dedup
  ON public.strava_event_queue (owner_id, object_id, aspect_type);

-- ─────────────────────────────────────────────────────────────────────────────
-- SPRINT 4 — Leaderboard upsert function (replaces DELETE+INSERT WAL storm)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_upsert_leaderboard_entries(
  p_leaderboard_id uuid,
  p_entries jsonb
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count integer := 0;
BEGIN
  -- Mark all existing entries for this leaderboard as stale
  UPDATE leaderboard_entries
  SET is_active = false
  WHERE leaderboard_id = p_leaderboard_id;

  -- Upsert new entries
  INSERT INTO leaderboard_entries (
    leaderboard_id, user_id, rank, score, metric_value, is_active, updated_at
  )
  SELECT
    p_leaderboard_id,
    (e->>'user_id')::uuid,
    (e->>'rank')::integer,
    (e->>'score')::numeric,
    (e->>'metric_value')::numeric,
    true,
    now()
  FROM jsonb_array_elements(p_entries) e
  ON CONFLICT (leaderboard_id, user_id)
  DO UPDATE SET
    rank = EXCLUDED.rank,
    score = EXCLUDED.score,
    metric_value = EXCLUDED.metric_value,
    is_active = true,
    updated_at = now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_upsert_leaderboard_entries(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_upsert_leaderboard_entries(uuid, jsonb) TO service_role;

-- Add is_active column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'leaderboard_entries' AND column_name = 'is_active'
  ) THEN
    ALTER TABLE leaderboard_entries ADD COLUMN is_active boolean NOT NULL DEFAULT true;
  END IF;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- SPRINT 5 — Custody aggregate RPC (replaces loading 10K+ rows client-side)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_sum_coin_ledger_by_group(
  p_group_id uuid
)
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(SUM(delta_coins), 0)::bigint
  FROM coin_ledger
  WHERE issuer_group_id = p_group_id;
$$;

REVOKE ALL ON FUNCTION public.fn_sum_coin_ledger_by_group(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_sum_coin_ledger_by_group(uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- SPRINT 5 — Athletes aggregate RPC (replaces unbounded session load)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_athlete_session_stats(
  p_user_ids uuid[]
)
RETURNS TABLE(
  user_id uuid,
  session_count bigint,
  total_distance_m numeric,
  total_duration_s numeric,
  last_session_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    s.user_id,
    COUNT(*) AS session_count,
    COALESCE(SUM(s.total_distance_m), 0) AS total_distance_m,
    COALESCE(SUM(s.duration_seconds), 0) AS total_duration_s,
    MAX(to_timestamp(s.start_time_ms / 1000.0)) AS last_session_at
  FROM sessions s
  WHERE s.user_id = ANY(p_user_ids)
    AND s.status >= 3
  GROUP BY s.user_id;
$$;

REVOKE ALL ON FUNCTION public.fn_athlete_session_stats(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_athlete_session_stats(uuid[]) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Notification log cleanup helper
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_cleanup_notification_log(
  p_retention_days integer DEFAULT 90
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_deleted bigint;
BEGIN
  DELETE FROM notification_log
  WHERE sent_at < now() - (p_retention_days || ' days')::interval;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_cleanup_notification_log(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_cleanup_notification_log(integer) TO service_role;

-- Rate limits cleanup via batched delete
CREATE OR REPLACE FUNCTION public.fn_cleanup_rate_limits_batch(
  p_batch_size integer DEFAULT 10000
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_deleted bigint := 0;
  v_batch bigint;
BEGIN
  LOOP
    DELETE FROM api_rate_limits
    WHERE id IN (
      SELECT id FROM api_rate_limits
      WHERE window_start < now() - interval '1 hour'
      LIMIT p_batch_size
      FOR UPDATE SKIP LOCKED
    );
    GET DIAGNOSTICS v_batch = ROW_COUNT;
    v_deleted := v_deleted + v_batch;
    EXIT WHEN v_batch < p_batch_size;
  END LOOP;
  RETURN v_deleted;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_cleanup_rate_limits_batch(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_cleanup_rate_limits_batch(integer) TO service_role;

COMMIT;
