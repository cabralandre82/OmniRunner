-- Medium severity fixes: batch championship progress + unique constraints
SET search_path = public, pg_temp;

-- ============================================================
-- M-03: Batch championship progress update (eliminates N+1)
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_batch_update_champ_progress(p_championship_id uuid)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_metric text;
  v_start_at timestamptz;
  v_end_at   timestamptz;
  v_updated  int;
BEGIN
  SELECT metric, start_at, end_at
    INTO v_metric, v_start_at, v_end_at
    FROM public.championships
   WHERE id = p_championship_id AND status = 'active';

  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  WITH agg AS (
    SELECT
      cp.id AS participant_id,
      CASE v_metric
        WHEN 'distance'  THEN COALESCE(SUM(s.total_distance_m), 0)
        WHEN 'time'      THEN COALESCE(SUM(s.moving_ms), 0)
        WHEN 'sessions'  THEN COUNT(s.id)::numeric
        WHEN 'elevation' THEN COALESCE(SUM(s.total_elevation_m), 0)
        WHEN 'pace'      THEN COALESCE(
          MIN(NULLIF(s.avg_pace_sec_km, 0)), 0
        )
        ELSE COALESCE(SUM(s.total_distance_m), 0)
      END AS progress_value
    FROM public.championship_participants cp
    LEFT JOIN public.sessions s
      ON s.user_id = cp.user_id
     AND s.is_verified = true
     AND s.start_time_ms >= (EXTRACT(EPOCH FROM v_start_at) * 1000)::bigint
     AND s.start_time_ms <= (EXTRACT(EPOCH FROM v_end_at) * 1000)::bigint
    WHERE cp.championship_id = p_championship_id
      AND cp.status IN ('enrolled', 'active')
    GROUP BY cp.id
  )
  UPDATE public.championship_participants cp2
     SET progress_value = agg.progress_value,
         status = 'active',
         updated_at = NOW()
    FROM agg
   WHERE cp2.id = agg.participant_id
     AND cp2.progress_value IS DISTINCT FROM agg.progress_value;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated;
END;
$$;

-- ============================================================
-- M-10: Unique composite constraints for dedup
-- ============================================================

-- billing_events: prevent duplicate processing of same payment
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'billing_events_mp_payment_id_key'
  ) THEN
    ALTER TABLE public.billing_events
      ADD CONSTRAINT billing_events_mp_payment_id_key UNIQUE (mp_payment_id);
  END IF;
EXCEPTION WHEN undefined_table OR undefined_column THEN NULL;
END $$;

-- sessions: prevent duplicate session uploads per user
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'sessions_user_start_unique'
  ) THEN
    ALTER TABLE public.sessions
      ADD CONSTRAINT sessions_user_start_unique UNIQUE (user_id, start_time_ms);
  END IF;
EXCEPTION WHEN undefined_table OR undefined_column THEN NULL;
END $$;
