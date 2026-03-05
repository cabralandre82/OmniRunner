-- Fix fn_delete_user_data: remove references to non-existent columns on profiles
-- profiles only has: id, display_name, avatar_url, created_at, updated_at,
-- active_coaching_group_id, onboarding_state, user_role, created_via,
-- platform_role, instagram_handle, tiktok_handle
CREATE OR REPLACE FUNCTION fn_delete_user_data(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  BEGIN UPDATE coin_ledger SET user_id = '00000000-0000-0000-0000-000000000000'::uuid WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;

  BEGIN DELETE FROM sessions WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM challenge_participants WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM badge_awards WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM profile_progress WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM coaching_athlete_kpis_daily WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM wallets WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM notification_log WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM strava_connections WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM coaching_members WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM leaderboard_entries WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM workout_delivery_items WHERE athlete_user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; END;
  BEGIN DELETE FROM support_tickets WHERE user_id = p_user_id; EXCEPTION WHEN undefined_table THEN NULL; WHEN undefined_column THEN NULL; END;

  UPDATE profiles SET
    display_name = 'Conta Removida',
    avatar_url = NULL,
    instagram_handle = NULL,
    tiktok_handle = NULL,
    active_coaching_group_id = NULL,
    updated_at = now()
  WHERE id = p_user_id;
END;
$$;

-- Fix fn_compute_kpis_batch: sessions.duration_seconds does not exist, use moving_ms / 1000
CREATE OR REPLACE FUNCTION public.fn_compute_kpis_batch(p_day date, p_group_ids uuid[])
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_group_id uuid;
  v_count    integer := 0;
  v_rec      RECORD;
BEGIN
  FOREACH v_group_id IN ARRAY p_group_ids
  LOOP
    SELECT
      COUNT(DISTINCT s.id)                                AS total_sessions,
      COALESCE(SUM(s.total_distance_m), 0)                AS total_distance_m,
      COALESCE(SUM(s.moving_ms / 1000.0), 0)              AS total_duration_s,
      COUNT(DISTINCT s.user_id)                           AS active_athletes,
      COUNT(DISTINCT CASE WHEN s.is_verified THEN s.id END) AS verified_sessions
    INTO v_rec
    FROM sessions s
    JOIN coaching_members cm ON cm.user_id = s.user_id AND cm.group_id = v_group_id
    WHERE cm.role IN ('athlete', 'atleta')
      AND s.status >= 3
      AND to_timestamp(s.start_time_ms / 1000.0)::date = p_day;

    INSERT INTO coaching_kpis_daily (group_id, day,
      total_sessions, total_distance_m, total_duration_s,
      active_athletes, verified_sessions)
    VALUES (v_group_id, p_day,
      v_rec.total_sessions, v_rec.total_distance_m, v_rec.total_duration_s,
      v_rec.active_athletes, v_rec.verified_sessions)
    ON CONFLICT (group_id, day) DO UPDATE SET
      total_sessions    = EXCLUDED.total_sessions,
      total_distance_m  = EXCLUDED.total_distance_m,
      total_duration_s  = EXCLUDED.total_duration_s,
      active_athletes   = EXCLUDED.active_athletes,
      verified_sessions = EXCLUDED.verified_sessions;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_compute_kpis_batch(date, uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_compute_kpis_batch(date, uuid[]) TO service_role;

-- Fix fn_compute_skill_bracket: sessions.duration_ms does not exist, use moving_ms
CREATE OR REPLACE FUNCTION public.fn_compute_skill_bracket(p_user_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_avg_pace  DOUBLE PRECISION;
  v_total_km  DOUBLE PRECISION;
  v_run_count INTEGER;
BEGIN
  SELECT
    AVG(
      CASE WHEN total_distance_m > 0 AND moving_ms > 0
           THEN (moving_ms / 1000.0) / (total_distance_m / 1000.0)
           ELSE NULL
      END
    ),
    COALESCE(SUM(total_distance_m) / 1000.0, 0),
    COUNT(*)
  INTO v_avg_pace, v_total_km, v_run_count
  FROM (
    SELECT total_distance_m, moving_ms
    FROM sessions
    WHERE user_id = p_user_id AND status >= 3 AND is_verified = true
    ORDER BY start_time_ms DESC
    LIMIT 20
  ) recent;

  IF v_run_count < 3 THEN RETURN 'beginner'; END IF;

  IF v_avg_pace IS NULL THEN RETURN 'beginner'; END IF;

  IF v_avg_pace < 270 THEN RETURN 'elite';
  ELSIF v_avg_pace < 330 THEN RETURN 'advanced';
  ELSIF v_avg_pace < 390 THEN RETURN 'intermediate';
  ELSE RETURN 'beginner';
  END IF;
END;
$$;

-- Fix fn_increment_wallets_batch: coin_ledger.issuer_group_id does not exist
CREATE OR REPLACE FUNCTION public.fn_increment_wallets_batch(p_entries jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_entry jsonb;
  v_count integer := 0;
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

    INSERT INTO coin_ledger (user_id, delta_coins, reason, ref_id, created_at)
    VALUES (
      (v_entry->>'user_id')::uuid,
      (v_entry->>'delta')::int,
      COALESCE(v_entry->>'reason', 'batch_credit'),
      (v_entry->>'ref_id')::uuid,
      now()
    );

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_increment_wallets_batch(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_increment_wallets_batch(jsonb) TO service_role;

-- Fix fn_sum_coin_ledger_by_group: coin_ledger.issuer_group_id does not exist
-- This function cannot work without the column, so provide a stub that returns 0
CREATE OR REPLACE FUNCTION public.fn_sum_coin_ledger_by_group(p_group_id uuid)
RETURNS bigint
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_sum bigint;
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='coin_ledger'
             AND column_name='issuer_group_id') THEN
    EXECUTE 'SELECT COALESCE(SUM(delta_coins), 0)::bigint FROM coin_ledger WHERE issuer_group_id = $1'
      INTO v_sum USING p_group_id;
    RETURN v_sum;
  ELSE
    RETURN 0;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_sum_coin_ledger_by_group(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_sum_coin_ledger_by_group(uuid) TO authenticated;
