-- ============================================================================
-- Omni Runner — Progression idempotency + daily XP cap tracking
-- Date: 2026-02-26
-- Sprint: 20.1.2
-- ============================================================================
-- A) sessions.progression_applied — prevents double XP per run
-- B) fn_get_daily_session_xp — returns XP already awarded today (for cap)
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- A) sessions — idempotency flag
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS progression_applied BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_sessions_progression_pending
  ON public.sessions(user_id)
  WHERE is_verified = true AND progression_applied = false;

-- ═══════════════════════════════════════════════════════════════════════════
-- B) fn_get_daily_session_xp — sum of session XP awarded today (UTC)
-- ═══════════════════════════════════════════════════════════════════════════
-- Used by calculate-progression to enforce the 1000 XP/day session cap.

CREATE OR REPLACE FUNCTION public.fn_get_daily_session_xp(p_user_id UUID)
RETURNS INTEGER AS $$
DECLARE
  _today_start BIGINT;
  _today_end   BIGINT;
  _total       INTEGER;
BEGIN
  _today_start := EXTRACT(EPOCH FROM DATE_TRUNC('day', NOW() AT TIME ZONE 'UTC'))::BIGINT * 1000;
  _today_end   := _today_start + 86400000 - 1;

  SELECT COALESCE(SUM(xp), 0) INTO _total
  FROM public.xp_transactions
  WHERE user_id = p_user_id
    AND source = 'session'
    AND created_at_ms BETWEEN _today_start AND _today_end;

  RETURN _total;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ═══════════════════════════════════════════════════════════════════════════
-- C) fn_count_daily_sessions — sessions with progression applied today
-- ═══════════════════════════════════════════════════════════════════════════
-- Enforces the 10 sessions/day cap from GAMIFICATION_POLICY §8.

CREATE OR REPLACE FUNCTION public.fn_count_daily_sessions(p_user_id UUID)
RETURNS INTEGER AS $$
DECLARE
  _today_start BIGINT;
  _today_end   BIGINT;
  _count       INTEGER;
BEGIN
  _today_start := EXTRACT(EPOCH FROM DATE_TRUNC('day', NOW() AT TIME ZONE 'UTC'))::BIGINT * 1000;
  _today_end   := _today_start + 86400000 - 1;

  SELECT COUNT(*)::INTEGER INTO _count
  FROM public.sessions
  WHERE user_id = p_user_id
    AND progression_applied = true
    AND start_time_ms BETWEEN _today_start AND _today_end;

  RETURN _count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ═══════════════════════════════════════════════════════════════════════════
-- D) fn_mark_progression_applied — set flag + return session data
-- ═══════════════════════════════════════════════════════════════════════════
-- Atomically marks the session and returns its data, preventing races.

CREATE OR REPLACE FUNCTION public.fn_mark_progression_applied(
  p_session_id UUID,
  p_user_id    UUID
)
RETURNS TABLE (
  session_id          UUID,
  total_distance_m    DOUBLE PRECISION,
  moving_ms           BIGINT,
  avg_bpm             INTEGER,
  start_time_ms       BIGINT,
  was_already_applied BOOLEAN,
  is_verified         BOOLEAN
) AS $$
DECLARE
  _rec RECORD;
BEGIN
  UPDATE public.sessions
  SET progression_applied = true
  WHERE id = p_session_id
    AND user_id = p_user_id
    AND sessions.is_verified = true
    AND progression_applied = false
  RETURNING
    sessions.id,
    sessions.total_distance_m,
    sessions.moving_ms,
    sessions.avg_bpm,
    sessions.start_time_ms
  INTO _rec;

  IF FOUND THEN
    session_id          := _rec.id;
    total_distance_m    := _rec.total_distance_m;
    moving_ms           := _rec.moving_ms;
    avg_bpm             := _rec.avg_bpm;
    start_time_ms       := _rec.start_time_ms;
    was_already_applied := false;
    is_verified         := true;
    RETURN NEXT;
  ELSE
    SELECT s.id, s.total_distance_m, s.moving_ms, s.avg_bpm,
           s.start_time_ms, s.is_verified
    INTO _rec
    FROM public.sessions s
    WHERE s.id = p_session_id AND s.user_id = p_user_id;

    IF NOT FOUND THEN
      RETURN;
    END IF;

    session_id          := _rec.id;
    total_distance_m    := _rec.total_distance_m;
    moving_ms           := _rec.moving_ms;
    avg_bpm             := _rec.avg_bpm;
    start_time_ms       := _rec.start_time_ms;
    was_already_applied := true;
    is_verified         := _rec.is_verified;
    RETURN NEXT;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
