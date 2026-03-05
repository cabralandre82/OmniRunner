-- ============================================================================
-- Auto-attendance: replace QR-based check-in with automatic workout matching.
--
-- Flow:
--   1. Staff assigns workout with distance_target_m + optional pace range
--   2. Athlete runs (session synced to Supabase)
--   3. Trigger evaluates the 2 next runs after training creation
--   4. If a run matches → 'completed'; ran but no match → 'partial'
--   5. When next training is created → athletes with no runs → 'absent'
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. ADD WORKOUT PARAMETERS TO TRAINING SESSIONS
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.coaching_training_sessions
  ADD COLUMN IF NOT EXISTS distance_target_m  double precision,
  ADD COLUMN IF NOT EXISTS pace_min_sec_km    double precision,
  ADD COLUMN IF NOT EXISTS pace_max_sec_km    double precision;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. EXTEND ATTENDANCE TABLE
-- ═══════════════════════════════════════════════════════════════════════════

-- Add 'completed' and 'partial' to status
ALTER TABLE public.coaching_training_attendance
  DROP CONSTRAINT IF EXISTS coaching_training_attendance_status_check;
ALTER TABLE public.coaching_training_attendance
  ADD CONSTRAINT coaching_training_attendance_status_check
  CHECK (status IN ('present', 'late', 'excused', 'absent', 'completed', 'partial'));

-- Add 'auto' to method
ALTER TABLE public.coaching_training_attendance
  DROP CONSTRAINT IF EXISTS coaching_training_attendance_method_check;
ALTER TABLE public.coaching_training_attendance
  ADD CONSTRAINT coaching_training_attendance_method_check
  CHECK (method IN ('qr', 'manual', 'auto'));

-- Track which running session was matched
ALTER TABLE public.coaching_training_attendance
  ADD COLUMN IF NOT EXISTS matched_run_id uuid;

-- Auto-inserted rows use a system caller; allow NULL checked_by for auto
ALTER TABLE public.coaching_training_attendance
  ALTER COLUMN checked_by DROP NOT NULL;

-- Allow system (service_role/trigger) to insert attendance
DROP POLICY IF EXISTS "attendance_system_insert" ON public.coaching_training_attendance;
CREATE POLICY "attendance_system_insert"
  ON public.coaching_training_attendance FOR INSERT WITH CHECK (true);

-- Allow system to update attendance (for re-evaluation)
DROP POLICY IF EXISTS "attendance_system_update" ON public.coaching_training_attendance;
CREATE POLICY "attendance_system_update"
  ON public.coaching_training_attendance FOR UPDATE USING (true);

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. CORE EVALUATION FUNCTION
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_evaluate_athlete_training(
  p_training_id     uuid,
  p_athlete_user_id uuid,
  p_deadline_ms     bigint DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_training       RECORD;
  v_run            RECORD;
  v_training_ms    bigint;
  v_run_pace       double precision;
  v_distance_ok    boolean;
  v_pace_ok        boolean;
  v_result_status  text := NULL;
  v_matched_run_id uuid := NULL;
BEGIN
  SELECT id, group_id, distance_target_m, pace_min_sec_km, pace_max_sec_km,
         EXTRACT(EPOCH FROM created_at)::bigint * 1000 AS created_at_ms
    INTO v_training
    FROM public.coaching_training_sessions
    WHERE id = p_training_id AND status != 'cancelled';

  IF v_training IS NULL THEN RETURN NULL; END IF;
  IF v_training.distance_target_m IS NULL THEN RETURN NULL; END IF;

  v_training_ms := v_training.created_at_ms;

  -- Check the athlete's next 2 completed runs after training creation
  FOR v_run IN
    SELECT id, total_distance_m, moving_ms, start_time_ms
      FROM public.sessions
      WHERE user_id = p_athlete_user_id
        AND status = 3
        AND start_time_ms > v_training_ms
        AND (p_deadline_ms IS NULL OR start_time_ms < p_deadline_ms)
      ORDER BY start_time_ms ASC
      LIMIT 2
  LOOP
    IF v_run.total_distance_m IS NULL OR v_run.total_distance_m < 100 THEN
      CONTINUE;
    END IF;

    -- Distance check: ±15%
    v_distance_ok := v_run.total_distance_m >= v_training.distance_target_m * 0.85
                 AND v_run.total_distance_m <= v_training.distance_target_m * 1.15;

    -- Pace check (only if training specifies pace)
    v_pace_ok := true;
    IF v_training.pace_min_sec_km IS NOT NULL
       AND v_training.pace_max_sec_km IS NOT NULL
       AND v_run.moving_ms > 0
       AND v_run.total_distance_m > 0 THEN
      v_run_pace := (v_run.moving_ms / 1000.0) / (v_run.total_distance_m / 1000.0);
      v_pace_ok := v_run_pace >= v_training.pace_min_sec_km
               AND v_run_pace <= v_training.pace_max_sec_km;
    END IF;

    IF v_distance_ok AND v_pace_ok THEN
      v_result_status := 'completed';
      v_matched_run_id := v_run.id;
      EXIT;
    END IF;

    -- At least ran → partial (keep checking second run)
    IF v_result_status IS NULL THEN
      v_result_status := 'partial';
      v_matched_run_id := v_run.id;
    END IF;
  END LOOP;

  IF v_result_status IS NULL THEN
    RETURN NULL; -- no runs found yet; don't mark absent until deadline
  END IF;

  -- Upsert attendance
  INSERT INTO public.coaching_training_attendance
    (group_id, session_id, athlete_user_id, checked_by, status, method, matched_run_id, checked_at)
  VALUES
    (v_training.group_id, p_training_id, p_athlete_user_id, NULL, v_result_status, 'auto', v_matched_run_id, now())
  ON CONFLICT (session_id, athlete_user_id)
  DO UPDATE SET
    status = EXCLUDED.status,
    method = EXCLUDED.method,
    matched_run_id = EXCLUDED.matched_run_id,
    checked_at = EXCLUDED.checked_at
  WHERE coaching_training_attendance.method = 'auto';
  -- only overwrite auto-evaluated rows, never overwrite manual overrides

  RETURN v_result_status;
END;
$fn$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. TRIGGER: WHEN A RUN IS SYNCED → EVALUATE PENDING TRAININGS
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.trg_session_evaluate_attendance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_training RECORD;
  v_run_ms   bigint;
BEGIN
  IF NEW.status != 3 THEN RETURN NEW; END IF;

  v_run_ms := NEW.start_time_ms;

  FOR v_training IN
    SELECT ts.id
      FROM public.coaching_training_sessions ts
      JOIN public.coaching_members cm
        ON cm.group_id = ts.group_id AND cm.user_id = NEW.user_id
      WHERE ts.distance_target_m IS NOT NULL
        AND ts.status != 'cancelled'
        AND EXTRACT(EPOCH FROM ts.created_at)::bigint * 1000 < v_run_ms
        AND NOT EXISTS (
          SELECT 1 FROM public.coaching_training_attendance att
          WHERE att.session_id = ts.id
            AND att.athlete_user_id = NEW.user_id
            AND att.method = 'manual'
        )
        AND NOT EXISTS (
          SELECT 1 FROM public.coaching_training_attendance att
          WHERE att.session_id = ts.id
            AND att.athlete_user_id = NEW.user_id
            AND att.status = 'completed'
        )
  LOOP
    PERFORM public.fn_evaluate_athlete_training(v_training.id, NEW.user_id);
  END LOOP;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_session_auto_attendance ON public.sessions;
CREATE TRIGGER trg_session_auto_attendance
  AFTER INSERT OR UPDATE ON public.sessions
  FOR EACH ROW
  WHEN (NEW.status = 3)
  EXECUTE FUNCTION public.trg_session_evaluate_attendance();

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. TRIGGER: WHEN NEW TRAINING IS CREATED → CLOSE PREVIOUS AS ABSENT
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.trg_training_close_previous()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_prev_id    uuid;
  v_athlete    RECORD;
  v_deadline   bigint;
BEGIN
  -- Find the previous training in the same group with workout params
  SELECT id INTO v_prev_id
    FROM public.coaching_training_sessions
    WHERE group_id = NEW.group_id
      AND distance_target_m IS NOT NULL
      AND status != 'cancelled'
      AND id != NEW.id
      AND created_at < NEW.created_at
    ORDER BY created_at DESC
    LIMIT 1;

  IF v_prev_id IS NULL THEN RETURN NEW; END IF;

  v_deadline := EXTRACT(EPOCH FROM NEW.created_at)::bigint * 1000;

  -- For each athlete in the group with no attendance on the previous training
  FOR v_athlete IN
    SELECT cm.user_id
      FROM public.coaching_members cm
      WHERE cm.group_id = NEW.group_id
        AND cm.role IN ('athlete', 'atleta')
        AND NOT EXISTS (
          SELECT 1 FROM public.coaching_training_attendance att
          WHERE att.session_id = v_prev_id
            AND att.athlete_user_id = cm.user_id
        )
  LOOP
    -- Try to evaluate (might find runs → completed/partial)
    IF public.fn_evaluate_athlete_training(v_prev_id, v_athlete.user_id, v_deadline) IS NULL THEN
      -- No runs at all → mark absent
      INSERT INTO public.coaching_training_attendance
        (group_id, session_id, athlete_user_id, checked_by, status, method, checked_at)
      VALUES
        (NEW.group_id, v_prev_id, v_athlete.user_id, NULL, 'absent', 'auto', now())
      ON CONFLICT (session_id, athlete_user_id) DO NOTHING;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_training_close_prev ON public.coaching_training_sessions;
CREATE TRIGGER trg_training_close_prev
  AFTER INSERT ON public.coaching_training_sessions
  FOR EACH ROW
  WHEN (NEW.distance_target_m IS NOT NULL)
  EXECUTE FUNCTION public.trg_training_close_previous();

COMMIT;
