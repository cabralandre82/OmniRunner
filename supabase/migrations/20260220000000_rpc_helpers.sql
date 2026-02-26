-- ============================================================================
-- Omni Runner — RPC Helper Functions
-- Generated: 2026-02-18
-- These are server-side functions callable via supabase.rpc()
-- ============================================================================

-- ── increment_wallet_balance ─────────────────────────────────────────────────
-- Atomically adjusts a user's wallet. Used by Edge Functions (service_role).

CREATE OR REPLACE FUNCTION public.increment_wallet_balance(
  p_user_id UUID,
  p_delta   INTEGER
)
RETURNS VOID AS $$
BEGIN
  UPDATE public.wallets
  SET
    balance_coins         = balance_coins + p_delta,
    lifetime_earned_coins = CASE WHEN p_delta > 0
                              THEN lifetime_earned_coins + p_delta
                              ELSE lifetime_earned_coins END,
    lifetime_spent_coins  = CASE WHEN p_delta < 0
                              THEN lifetime_spent_coins + ABS(p_delta)
                              ELSE lifetime_spent_coins END,
    updated_at = now()
  WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    INSERT INTO public.wallets (user_id, balance_coins, lifetime_earned_coins, lifetime_spent_coins)
    VALUES (
      p_user_id,
      GREATEST(0, p_delta),
      CASE WHEN p_delta > 0 THEN p_delta ELSE 0 END,
      CASE WHEN p_delta < 0 THEN ABS(p_delta) ELSE 0 END
    );
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── increment_profile_progress ───────────────────────────────────────────────
-- Atomically adds XP and stats after a verified session.

CREATE OR REPLACE FUNCTION public.increment_profile_progress(
  p_user_id       UUID,
  p_xp            INTEGER,
  p_distance_m    DOUBLE PRECISION,
  p_moving_ms     BIGINT
)
RETURNS VOID AS $$
BEGIN
  UPDATE public.profile_progress
  SET
    total_xp              = total_xp + p_xp,
    season_xp             = season_xp + p_xp,
    lifetime_session_count = lifetime_session_count + 1,
    lifetime_distance_m   = lifetime_distance_m + p_distance_m,
    lifetime_moving_ms    = lifetime_moving_ms + p_moving_ms,
    updated_at            = now()
  WHERE user_id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── compute_leaderboard_global_weekly ────────────────────────────────────────
-- Materializes the global weekly leaderboard for a given period key.

CREATE OR REPLACE FUNCTION public.compute_leaderboard_global_weekly(
  p_period_key TEXT,
  p_start_ms   BIGINT,
  p_end_ms     BIGINT
)
RETURNS INTEGER AS $$
DECLARE
  lb_id TEXT;
  row_count INTEGER;
BEGIN
  lb_id := 'global_weekly_distance_' || p_period_key;

  INSERT INTO public.leaderboards (id, scope, period, metric, period_key, computed_at_ms, is_final)
  VALUES (lb_id, 'global', 'weekly', 'distance', p_period_key, EXTRACT(EPOCH FROM now())::BIGINT * 1000, false)
  ON CONFLICT (id) DO UPDATE SET computed_at_ms = EXTRACT(EPOCH FROM now())::BIGINT * 1000;

  DELETE FROM public.leaderboard_entries WHERE leaderboard_id = lb_id;

  INSERT INTO public.leaderboard_entries (leaderboard_id, user_id, display_name, avatar_url, level, value, rank, period_key)
  SELECT
    lb_id,
    s.user_id,
    p.display_name,
    p.avatar_url,
    COALESCE(FLOOR(POWER(pp.total_xp::DOUBLE PRECISION / 100, 2.0/3.0))::INTEGER, 0),
    SUM(s.total_distance_m),
    ROW_NUMBER() OVER (ORDER BY SUM(s.total_distance_m) DESC),
    p_period_key
  FROM public.sessions s
  JOIN public.profiles p ON p.id = s.user_id
  LEFT JOIN public.profile_progress pp ON pp.user_id = s.user_id
  WHERE s.is_verified = true
    AND s.start_time_ms BETWEEN p_start_ms AND p_end_ms
    AND s.total_distance_m > 0
  GROUP BY s.user_id, p.display_name, p.avatar_url, pp.total_xp
  ORDER BY SUM(s.total_distance_m) DESC
  LIMIT 200;

  GET DIAGNOSTICS row_count = ROW_COUNT;
  RETURN row_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
