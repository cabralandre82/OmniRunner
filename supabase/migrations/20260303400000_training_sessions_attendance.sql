-- ============================================================================
-- OS-01: Agenda de Treinos + Presença via QR
-- Tables, indexes, RLS, and RPCs for training sessions and attendance.
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. TABLES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.coaching_training_sessions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id      uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  created_by    uuid NOT NULL REFERENCES auth.users(id),
  title         text NOT NULL CHECK (length(trim(title)) >= 2 AND length(trim(title)) <= 120),
  description   text,
  starts_at     timestamptz NOT NULL,
  ends_at       timestamptz CHECK (ends_at IS NULL OR ends_at > starts_at),
  location_name text,
  location_lat  double precision,
  location_lng  double precision,
  status        text NOT NULL DEFAULT 'scheduled'
    CHECK (status IN ('scheduled', 'cancelled', 'done')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.coaching_training_attendance (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id         uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  session_id       uuid NOT NULL REFERENCES public.coaching_training_sessions(id) ON DELETE CASCADE,
  athlete_user_id  uuid NOT NULL REFERENCES auth.users(id),
  checked_by       uuid NOT NULL REFERENCES auth.users(id),
  checked_at       timestamptz NOT NULL DEFAULT now(),
  status           text NOT NULL DEFAULT 'present'
    CHECK (status IN ('present', 'late', 'excused', 'absent')),
  method           text NOT NULL DEFAULT 'qr'
    CHECK (method IN ('qr', 'manual')),

  CONSTRAINT uq_attendance_session_athlete UNIQUE (session_id, athlete_user_id)
);

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. INDEXES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_training_sessions_group_starts
  ON public.coaching_training_sessions (group_id, starts_at DESC);

CREATE INDEX IF NOT EXISTS idx_training_sessions_group_status_starts
  ON public.coaching_training_sessions (group_id, status, starts_at DESC);

CREATE INDEX IF NOT EXISTS idx_attendance_group_session
  ON public.coaching_training_attendance (group_id, session_id);

CREATE INDEX IF NOT EXISTS idx_attendance_group_athlete_time
  ON public.coaching_training_attendance (group_id, athlete_user_id, checked_at DESC);

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. RLS
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.coaching_training_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coaching_training_attendance ENABLE ROW LEVEL SECURITY;

-- 3.1 Training sessions: any group member can read
DROP POLICY IF EXISTS "training_sessions_member_read" ON public.coaching_training_sessions;
CREATE POLICY "training_sessions_member_read"
  ON public.coaching_training_sessions FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_training_sessions.group_id
        AND cm.user_id = auth.uid()
    )
  );

-- 3.2 Training sessions: admin_master and coach can insert
DROP POLICY IF EXISTS "training_sessions_staff_insert" ON public.coaching_training_sessions;
CREATE POLICY "training_sessions_staff_insert"
  ON public.coaching_training_sessions FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_training_sessions.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- 3.3 Training sessions: admin_master and coach can update (edit/cancel)
DROP POLICY IF EXISTS "training_sessions_staff_update" ON public.coaching_training_sessions;
CREATE POLICY "training_sessions_staff_update"
  ON public.coaching_training_sessions FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_training_sessions.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- 3.4 Attendance: staff can read all attendance for their group
DROP POLICY IF EXISTS "attendance_staff_read" ON public.coaching_training_attendance;
CREATE POLICY "attendance_staff_read"
  ON public.coaching_training_attendance FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_training_attendance.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  );

-- 3.5 Attendance: athlete can read only their own records
DROP POLICY IF EXISTS "attendance_own_read" ON public.coaching_training_attendance;
CREATE POLICY "attendance_own_read"
  ON public.coaching_training_attendance FOR SELECT USING (
    athlete_user_id = auth.uid()
  );

-- 3.6 Attendance: staff can insert (mark attendance)
DROP POLICY IF EXISTS "attendance_staff_insert" ON public.coaching_training_attendance;
CREATE POLICY "attendance_staff_insert"
  ON public.coaching_training_attendance FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_training_attendance.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  );

-- 3.7 Platform admin read-all for both tables
DROP POLICY IF EXISTS "training_sessions_platform_admin_read" ON public.coaching_training_sessions;
CREATE POLICY "training_sessions_platform_admin_read"
  ON public.coaching_training_sessions FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profiles WHERE id = auth.uid() AND platform_role = 'admin'
    )
  );

DROP POLICY IF EXISTS "attendance_platform_admin_read" ON public.coaching_training_attendance;
CREATE POLICY "attendance_platform_admin_read"
  ON public.coaching_training_attendance FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profiles WHERE id = auth.uid() AND platform_role = 'admin'
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. RPCs
-- ═══════════════════════════════════════════════════════════════════════════

-- 4.1 fn_mark_attendance: idempotent check-in with validation
CREATE OR REPLACE FUNCTION public.fn_mark_attendance(
  p_session_id     uuid,
  p_athlete_user_id uuid,
  p_nonce          text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_uid        uuid;
  v_session    RECORD;
  v_group_id   uuid;
  v_att_id     uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'status', 'forbidden', 'message', 'NOT_AUTHENTICATED');
  END IF;

  -- Fetch session
  SELECT id, group_id, status, starts_at, ends_at
    INTO v_session
    FROM public.coaching_training_sessions
    WHERE id = p_session_id;

  IF v_session IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'status', 'invalid', 'message', 'SESSION_NOT_FOUND');
  END IF;

  v_group_id := v_session.group_id;

  -- Caller must be staff of the same group
  IF NOT EXISTS (
    SELECT 1 FROM public.coaching_members
    WHERE group_id = v_group_id AND user_id = v_uid
      AND role IN ('admin_master', 'coach', 'assistant')
  ) THEN
    RETURN jsonb_build_object('ok', false, 'status', 'forbidden', 'message', 'NOT_STAFF');
  END IF;

  -- Session must be scheduled or done (not cancelled)
  IF v_session.status = 'cancelled' THEN
    RETURN jsonb_build_object('ok', false, 'status', 'invalid', 'message', 'SESSION_CANCELLED');
  END IF;

  -- Athlete must be a member of the group
  IF NOT EXISTS (
    SELECT 1 FROM public.coaching_members
    WHERE group_id = v_group_id AND user_id = p_athlete_user_id
  ) THEN
    RETURN jsonb_build_object('ok', false, 'status', 'invalid', 'message', 'ATHLETE_NOT_IN_GROUP');
  END IF;

  -- Idempotent insert
  INSERT INTO public.coaching_training_attendance
    (group_id, session_id, athlete_user_id, checked_by, method)
  VALUES
    (v_group_id, p_session_id, p_athlete_user_id, v_uid, 'qr')
  ON CONFLICT (session_id, athlete_user_id) DO NOTHING
  RETURNING id INTO v_att_id;

  IF v_att_id IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'status', 'already_present');
  END IF;

  RETURN jsonb_build_object('ok', true, 'status', 'inserted', 'attendance_id', v_att_id);
END;
$fn$;

-- Restrict fn_mark_attendance to authenticated users
REVOKE ALL ON FUNCTION public.fn_mark_attendance(uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_mark_attendance(uuid, uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_mark_attendance(uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_mark_attendance(uuid, uuid, text) TO service_role;

-- 4.2 fn_issue_checkin_token: generates a signed checkin payload for QR
--     Returns JSON with nonce + expiry for the athlete's QR code.
CREATE OR REPLACE FUNCTION public.fn_issue_checkin_token(
  p_session_id uuid,
  p_ttl_seconds int DEFAULT 120
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_uid       uuid;
  v_session   RECORD;
  v_nonce     text;
  v_expires   bigint;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  -- Fetch session and verify athlete membership
  SELECT ts.id, ts.group_id, ts.status
    INTO v_session
    FROM public.coaching_training_sessions ts
    WHERE ts.id = p_session_id;

  IF v_session IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'SESSION_NOT_FOUND');
  END IF;

  IF v_session.status = 'cancelled' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'SESSION_CANCELLED');
  END IF;

  -- Caller must be a member of the group (athlete generating their own QR)
  IF NOT EXISTS (
    SELECT 1 FROM public.coaching_members
    WHERE group_id = v_session.group_id AND user_id = v_uid
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'NOT_IN_GROUP');
  END IF;

  v_nonce   := encode(gen_random_bytes(24), 'hex');
  v_expires := (EXTRACT(EPOCH FROM now())::bigint + p_ttl_seconds) * 1000;

  RETURN jsonb_build_object(
    'ok', true,
    'session_id', p_session_id,
    'athlete_user_id', v_uid,
    'group_id', v_session.group_id,
    'nonce', v_nonce,
    'expires_at', v_expires
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_issue_checkin_token(uuid, int) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_issue_checkin_token(uuid, int) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_issue_checkin_token(uuid, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_issue_checkin_token(uuid, int) TO service_role;

COMMIT;
