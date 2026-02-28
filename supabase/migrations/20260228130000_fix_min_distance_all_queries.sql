-- ============================================================================
-- Fix minimum distance filter (>= 1 km) in fn_friends_activity_feed
-- Date: 2026-02-28
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_friends_activity_feed(
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0
)
RETURNS TABLE (
  session_id UUID,
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  start_time_ms BIGINT,
  end_time_ms BIGINT,
  total_distance_m DOUBLE PRECISION,
  is_verified BOOLEAN
)
LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  v_uid UUID;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;

  RETURN QUERY
  WITH my_friends AS (
    SELECT
      CASE
        WHEN f.user_id_a = v_uid THEN f.user_id_b
        ELSE f.user_id_a
      END AS friend_id
    FROM public.friendships f
    WHERE f.status = 'accepted'
      AND (f.user_id_a = v_uid OR f.user_id_b = v_uid)
  )
  SELECT
    s.id AS session_id,
    s.user_id,
    COALESCE(p.display_name, 'Atleta') AS display_name,
    p.avatar_url,
    s.start_time_ms,
    s.end_time_ms,
    s.total_distance_m,
    s.is_verified
  FROM public.sessions s
  INNER JOIN my_friends mf ON mf.friend_id = s.user_id
  LEFT JOIN public.profiles p ON p.id = s.user_id
  WHERE s.is_verified = TRUE
    AND s.status = 3
    AND s.total_distance_m >= 1000
  ORDER BY s.start_time_ms DESC
  LIMIT LEAST(p_limit, 100)
  OFFSET p_offset;
END;
$fn$;

COMMIT;
