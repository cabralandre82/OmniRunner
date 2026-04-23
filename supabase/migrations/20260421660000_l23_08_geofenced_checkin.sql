-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ L23-08 — Geofenced auto-check-in for coletivo sessions                     ║
-- ║                                                                            ║
-- ║ Context:                                                                   ║
-- ║   QR flow + manual attendance already exist                              ║
-- ║   (`coaching_training_sessions`, `coaching_training_attendance`,          ║
-- ║   `fn_mark_attendance`, `fn_issue_checkin_token`). The coletivo runs     ║
-- ║   at a fixed park at 06:00. If every athlete has to queue for the       ║
-- ║   coach to scan a QR, the first 10 minutes of the session are eaten by  ║
-- ║   the check-in line. The fix is a server-validated auto-check-in: the   ║
-- ║   app sends the athlete's GPS, we verify it is inside the session       ║
-- ║   geofence and inside the time window, and we write attendance         ║
-- ║   directly.                                                               ║
-- ║                                                                            ║
-- ║ Delivers:                                                                  ║
-- ║   1. Adds `location_radius_meters`, `checkin_early_seconds`,             ║
-- ║      `checkin_late_seconds`, `geofence_enabled` to                       ║
-- ║      public.coaching_training_sessions. Defensive CHECK bounds.          ║
-- ║   2. Extends `coaching_training_attendance.method` CHECK to include     ║
-- ║      'auto_geo' + `checkin_lat`/`checkin_lng`/`checkin_accuracy_m`.     ║
-- ║   3. fn_session_checkin_window(session_id) STABLE SECURITY INVOKER —    ║
-- ║      returns (window_open_at, window_close_at, is_open) derived from    ║
-- ║      starts_at, ends_at, checkin_early/late seconds.                    ║
-- ║   4. fn_auto_checkin(session_id, lat, lng, accuracy_m) SECURITY         ║
-- ║      DEFINER — athlete-self: verifies geofence via fn_haversine_m,      ║
-- ║      time window, membership, cancellation. Idempotent via              ║
-- ║      ON CONFLICT. Refuses when accuracy_m > 100 (low-signal GPS).       ║
-- ║   5. public.coaching_attendance_audit append-only log of accepted +     ║
-- ║      rejected attempts, platform_admin-readable.                        ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

BEGIN;

-- ─── 1. Session geofence columns ──────────────────────────────────────────────

ALTER TABLE public.coaching_training_sessions
  ADD COLUMN IF NOT EXISTS location_radius_meters INT,
  ADD COLUMN IF NOT EXISTS checkin_early_seconds INT NOT NULL DEFAULT 1800,
  ADD COLUMN IF NOT EXISTS checkin_late_seconds INT NOT NULL DEFAULT 5400,
  ADD COLUMN IF NOT EXISTS geofence_enabled BOOLEAN NOT NULL DEFAULT FALSE;

DO $cm$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'coaching_training_sessions_radius_range'
  ) THEN
    ALTER TABLE public.coaching_training_sessions
      ADD CONSTRAINT coaching_training_sessions_radius_range
      CHECK (
        location_radius_meters IS NULL
        OR (location_radius_meters BETWEEN 25 AND 5000)
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'coaching_training_sessions_checkin_early_range'
  ) THEN
    ALTER TABLE public.coaching_training_sessions
      ADD CONSTRAINT coaching_training_sessions_checkin_early_range
      CHECK (checkin_early_seconds BETWEEN 0 AND 86400);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'coaching_training_sessions_checkin_late_range'
  ) THEN
    ALTER TABLE public.coaching_training_sessions
      ADD CONSTRAINT coaching_training_sessions_checkin_late_range
      CHECK (checkin_late_seconds BETWEEN 0 AND 86400);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'coaching_training_sessions_geofence_requires_location'
  ) THEN
    ALTER TABLE public.coaching_training_sessions
      ADD CONSTRAINT coaching_training_sessions_geofence_requires_location
      CHECK (
        geofence_enabled = FALSE
        OR (
          location_lat IS NOT NULL
          AND location_lng IS NOT NULL
          AND location_radius_meters IS NOT NULL
        )
      );
  END IF;
END;
$cm$;

-- ─── 2. Attendance columns ────────────────────────────────────────────────────

ALTER TABLE public.coaching_training_attendance
  ADD COLUMN IF NOT EXISTS checkin_lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS checkin_lng DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS checkin_accuracy_m INT;

DO $att$
DECLARE
  v_method_check_name TEXT;
BEGIN
  SELECT conname INTO v_method_check_name
  FROM pg_constraint
  WHERE conrelid = 'public.coaching_training_attendance'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) ILIKE '%method IN%';

  IF v_method_check_name IS NOT NULL THEN
    EXECUTE format(
      'ALTER TABLE public.coaching_training_attendance DROP CONSTRAINT %I',
      v_method_check_name
    );
  END IF;

  ALTER TABLE public.coaching_training_attendance
    ADD CONSTRAINT coaching_training_attendance_method_check
    CHECK (method IN ('qr', 'manual', 'auto_geo'));

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'coaching_training_attendance_accuracy_positive'
  ) THEN
    ALTER TABLE public.coaching_training_attendance
      ADD CONSTRAINT coaching_training_attendance_accuracy_positive
      CHECK (checkin_accuracy_m IS NULL OR checkin_accuracy_m > 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'coaching_training_attendance_auto_geo_has_coords'
  ) THEN
    ALTER TABLE public.coaching_training_attendance
      ADD CONSTRAINT coaching_training_attendance_auto_geo_has_coords
      CHECK (
        method <> 'auto_geo'
        OR (checkin_lat IS NOT NULL AND checkin_lng IS NOT NULL)
      );
  END IF;
END;
$att$;

-- ─── 3. Attendance audit log ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.coaching_attendance_audit (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id       UUID NOT NULL
                     REFERENCES public.coaching_training_sessions(id) ON DELETE CASCADE,
  athlete_user_id  UUID NOT NULL REFERENCES auth.users(id),
  outcome          TEXT NOT NULL,
  reason_code      TEXT,
  distance_m       INT,
  accuracy_m       INT,
  checked_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT coaching_attendance_audit_outcome_check
    CHECK (outcome IN ('accepted', 'rejected')),
  CONSTRAINT coaching_attendance_audit_reason_shape
    CHECK (reason_code IS NULL OR reason_code ~ '^[A-Z][A-Z0-9_]{2,48}$')
);

CREATE INDEX IF NOT EXISTS coaching_attendance_audit_session_idx
  ON public.coaching_attendance_audit(session_id, checked_at DESC);

CREATE INDEX IF NOT EXISTS coaching_attendance_audit_athlete_idx
  ON public.coaching_attendance_audit(athlete_user_id, checked_at DESC);

ALTER TABLE public.coaching_attendance_audit ENABLE ROW LEVEL SECURITY;

CREATE POLICY coaching_attendance_audit_self_read ON public.coaching_attendance_audit
  FOR SELECT USING (athlete_user_id = auth.uid());

CREATE POLICY coaching_attendance_audit_staff_read ON public.coaching_attendance_audit
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_training_sessions ts
      JOIN public.coaching_members cm ON cm.group_id = ts.group_id
      WHERE ts.id = coaching_attendance_audit.session_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  );

CREATE POLICY coaching_attendance_audit_platform_admin ON public.coaching_attendance_audit
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND platform_role = 'admin'
    )
  );

-- ─── 4. fn_session_checkin_window ─────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_session_checkin_window(
  p_session_id UUID
) RETURNS TABLE (
  window_open_at  TIMESTAMPTZ,
  window_close_at TIMESTAMPTZ,
  is_open         BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT
    (ts.starts_at - (ts.checkin_early_seconds * INTERVAL '1 second')) AS window_open_at,
    (COALESCE(ts.ends_at, ts.starts_at + INTERVAL '4 hour')
       + (ts.checkin_late_seconds * INTERVAL '1 second'))             AS window_close_at,
    (
      ts.status <> 'cancelled'
      AND now() >= (ts.starts_at - (ts.checkin_early_seconds * INTERVAL '1 second'))
      AND now() <= (COALESCE(ts.ends_at, ts.starts_at + INTERVAL '4 hour')
                     + (ts.checkin_late_seconds * INTERVAL '1 second'))
    ) AS is_open
  FROM public.coaching_training_sessions ts
  WHERE ts.id = p_session_id;
$$;

GRANT EXECUTE ON FUNCTION public.fn_session_checkin_window(UUID) TO authenticated;

-- ─── 5. fn_auto_checkin ───────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_auto_checkin(
  p_session_id UUID,
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_accuracy_m INT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_uid         UUID;
  v_session     RECORD;
  v_distance_m  INT;
  v_window_open TIMESTAMPTZ;
  v_window_close TIMESTAMPTZ;
  v_att_id      UUID;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  IF p_lat IS NULL OR p_lng IS NULL
     OR p_lat < -90 OR p_lat > 90
     OR p_lng < -180 OR p_lng > 180 THEN
    PERFORM public.fn_record_attendance_audit(
      p_session_id, v_uid, 'rejected', 'COORDS_INVALID', NULL, p_accuracy_m
    );
    RETURN jsonb_build_object('ok', false, 'reason', 'COORDS_INVALID');
  END IF;

  IF p_accuracy_m IS NOT NULL AND p_accuracy_m > 100 THEN
    PERFORM public.fn_record_attendance_audit(
      p_session_id, v_uid, 'rejected', 'GPS_ACCURACY_LOW', NULL, p_accuracy_m
    );
    RETURN jsonb_build_object('ok', false, 'reason', 'GPS_ACCURACY_LOW');
  END IF;

  SELECT ts.id, ts.group_id, ts.status, ts.starts_at, ts.ends_at,
         ts.location_lat, ts.location_lng, ts.location_radius_meters,
         ts.geofence_enabled, ts.checkin_early_seconds, ts.checkin_late_seconds
    INTO v_session
    FROM public.coaching_training_sessions ts
    WHERE ts.id = p_session_id;

  IF v_session IS NULL THEN
    PERFORM public.fn_record_attendance_audit(
      p_session_id, v_uid, 'rejected', 'SESSION_NOT_FOUND', NULL, p_accuracy_m
    );
    RETURN jsonb_build_object('ok', false, 'reason', 'SESSION_NOT_FOUND');
  END IF;

  IF v_session.status = 'cancelled' THEN
    PERFORM public.fn_record_attendance_audit(
      p_session_id, v_uid, 'rejected', 'SESSION_CANCELLED', NULL, p_accuracy_m
    );
    RETURN jsonb_build_object('ok', false, 'reason', 'SESSION_CANCELLED');
  END IF;

  IF NOT v_session.geofence_enabled THEN
    PERFORM public.fn_record_attendance_audit(
      p_session_id, v_uid, 'rejected', 'GEOFENCE_DISABLED', NULL, p_accuracy_m
    );
    RETURN jsonb_build_object('ok', false, 'reason', 'GEOFENCE_DISABLED');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.coaching_members
    WHERE group_id = v_session.group_id AND user_id = v_uid
  ) THEN
    PERFORM public.fn_record_attendance_audit(
      p_session_id, v_uid, 'rejected', 'NOT_IN_GROUP', NULL, p_accuracy_m
    );
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_IN_GROUP');
  END IF;

  v_window_open  := v_session.starts_at - (v_session.checkin_early_seconds * INTERVAL '1 second');
  v_window_close := COALESCE(v_session.ends_at, v_session.starts_at + INTERVAL '4 hour')
                     + (v_session.checkin_late_seconds * INTERVAL '1 second');

  IF now() < v_window_open OR now() > v_window_close THEN
    PERFORM public.fn_record_attendance_audit(
      p_session_id, v_uid, 'rejected', 'WINDOW_CLOSED', NULL, p_accuracy_m
    );
    RETURN jsonb_build_object(
      'ok', false, 'reason', 'WINDOW_CLOSED',
      'window_open_at', v_window_open,
      'window_close_at', v_window_close
    );
  END IF;

  v_distance_m := public.fn_haversine_m(
    v_session.location_lat, v_session.location_lng, p_lat, p_lng
  )::INT;

  IF v_distance_m > v_session.location_radius_meters THEN
    PERFORM public.fn_record_attendance_audit(
      p_session_id, v_uid, 'rejected', 'OUTSIDE_GEOFENCE',
      v_distance_m, p_accuracy_m
    );
    RETURN jsonb_build_object(
      'ok', false, 'reason', 'OUTSIDE_GEOFENCE',
      'distance_m', v_distance_m,
      'radius_m', v_session.location_radius_meters
    );
  END IF;

  INSERT INTO public.coaching_training_attendance
    (group_id, session_id, athlete_user_id, checked_by, method,
     checkin_lat, checkin_lng, checkin_accuracy_m)
  VALUES
    (v_session.group_id, p_session_id, v_uid, v_uid, 'auto_geo',
     p_lat, p_lng, p_accuracy_m)
  ON CONFLICT (session_id, athlete_user_id) DO NOTHING
  RETURNING id INTO v_att_id;

  PERFORM public.fn_record_attendance_audit(
    p_session_id, v_uid, 'accepted', NULL, v_distance_m, p_accuracy_m
  );

  IF v_att_id IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'status', 'already_present',
                              'distance_m', v_distance_m);
  END IF;

  RETURN jsonb_build_object('ok', true, 'status', 'checked_in',
                            'attendance_id', v_att_id,
                            'distance_m', v_distance_m);
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_auto_checkin(UUID, DOUBLE PRECISION, DOUBLE PRECISION, INT)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_auto_checkin(UUID, DOUBLE PRECISION, DOUBLE PRECISION, INT)
  FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_auto_checkin(UUID, DOUBLE PRECISION, DOUBLE PRECISION, INT)
  TO authenticated;

-- ─── 6. fn_record_attendance_audit (internal) ─────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_record_attendance_audit(
  p_session_id UUID,
  p_athlete_user_id UUID,
  p_outcome TEXT,
  p_reason_code TEXT,
  p_distance_m INT,
  p_accuracy_m INT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  BEGIN
    INSERT INTO public.coaching_attendance_audit
      (session_id, athlete_user_id, outcome, reason_code, distance_m, accuracy_m)
    VALUES
      (p_session_id, p_athlete_user_id, p_outcome, p_reason_code,
       p_distance_m, p_accuracy_m);
  EXCEPTION WHEN OTHERS THEN
    -- Fail-open: audit outage must not block the caller.
    RAISE WARNING 'attendance audit insert failed: %', SQLERRM;
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_record_attendance_audit(UUID, UUID, TEXT, TEXT, INT, INT)
  FROM PUBLIC;

-- ─── 7. Self-tests ────────────────────────────────────────────────────────────

DO $selftest$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'coaching_training_sessions'
      AND column_name = 'location_radius_meters'
  ) THEN
    RAISE EXCEPTION 'self-test: location_radius_meters column missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'coaching_training_sessions'
      AND column_name = 'geofence_enabled'
  ) THEN
    RAISE EXCEPTION 'self-test: geofence_enabled column missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'coaching_training_sessions_geofence_requires_location'
  ) THEN
    RAISE EXCEPTION 'self-test: geofence_requires_location CHECK missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'coaching_training_sessions_radius_range'
  ) THEN
    RAISE EXCEPTION 'self-test: radius_range CHECK missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'coaching_training_attendance_auto_geo_has_coords'
  ) THEN
    RAISE EXCEPTION 'self-test: auto_geo_has_coords CHECK missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'coaching_training_attendance_method_check'
      AND pg_get_constraintdef(oid) ILIKE '%auto_geo%'
  ) THEN
    RAISE EXCEPTION 'self-test: method CHECK must include auto_geo';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'fn_auto_checkin' AND pronamespace = 'public'::regnamespace
  ) THEN
    RAISE EXCEPTION 'self-test: fn_auto_checkin missing';
  END IF;
END;
$selftest$;

COMMIT;
