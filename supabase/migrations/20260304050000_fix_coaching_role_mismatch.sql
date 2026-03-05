-- Fix: coaching_join_requests uses Portuguese role names ('atleta', 'professor')
-- but coaching_members CHECK constraint requires English names ('athlete', 'coach').
-- fn_approve_join_request inserts v_req.requested_role directly, causing a CHECK
-- violation when the join request has role = 'atleta'. This also prevents
-- active_coaching_group_id from being updated on the athlete's profile.
--
-- Changes:
--   1. Backfill any stale Portuguese role values in coaching_members
--   2. Recreate fn_approve_join_request with role mapping
--   3. Recreate fn_request_join with English role names
--   4. Update coaching_join_requests CHECK + column default
--   5. Backfill active_coaching_group_id for athletes missing it
--   6. Fix partial unique index for athlete-per-group constraint

-- 1. Backfill any Portuguese role values that somehow made it into coaching_members
UPDATE public.coaching_members SET role = 'athlete'   WHERE role = 'atleta';
UPDATE public.coaching_members SET role = 'coach'     WHERE role = 'professor';
UPDATE public.coaching_members SET role = 'coach'     WHERE role = 'admin_master';
UPDATE public.coaching_members SET role = 'assistant' WHERE role = 'assistente';

-- 2. Recreate fn_approve_join_request with role mapping
CREATE OR REPLACE FUNCTION public.fn_approve_join_request(p_request_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  v_uid UUID; v_req RECORD; v_now_ms BIGINT; v_mapped_role TEXT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  SELECT * INTO v_req FROM public.coaching_join_requests
    WHERE id = p_request_id AND status = 'pending' FOR UPDATE;
  IF v_req IS NULL THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND_OR_ALREADY_PROCESSED'; END IF;

  -- Map Portuguese role names to English CHECK-constraint values
  v_mapped_role := CASE v_req.requested_role
    WHEN 'atleta'    THEN 'athlete'
    WHEN 'professor' THEN 'coach'
    WHEN 'athlete'   THEN 'athlete'
    WHEN 'coach'     THEN 'coach'
    ELSE 'athlete'
  END;

  -- Only admin/coach can approve coach requests; admin/coach can approve athletes
  IF v_mapped_role = 'coach' THEN
    IF NOT EXISTS (SELECT 1 FROM public.coaching_members
      WHERE group_id = v_req.group_id AND user_id = v_uid AND role IN ('coach', 'admin_master')) THEN
      RAISE EXCEPTION 'ONLY_ADMIN_CAN_APPROVE_COACH';
    END IF;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM public.coaching_members
      WHERE group_id = v_req.group_id AND user_id = v_uid AND role IN ('coach', 'admin_master', 'assistant')) THEN
      RAISE EXCEPTION 'NOT_AUTHORIZED';
    END IF;
  END IF;

  v_now_ms := EXTRACT(EPOCH FROM now())::BIGINT * 1000;

  -- Mark this request as approved
  UPDATE public.coaching_join_requests
    SET status = 'approved', reviewed_at = now(), reviewed_by = v_uid
    WHERE id = p_request_id;

  -- Cancel all other pending requests for same user + same role
  UPDATE public.coaching_join_requests
    SET status = 'cancelled', reviewed_at = now()
    WHERE user_id = v_req.user_id
      AND requested_role = v_req.requested_role
      AND status = 'pending'
      AND id <> p_request_id;

  -- Remove previous membership of same mapped role (if switching groups)
  DELETE FROM public.coaching_members
    WHERE user_id = v_req.user_id AND role = v_mapped_role;

  -- Insert with the mapped (English) role
  INSERT INTO public.coaching_members (user_id, group_id, display_name, role, joined_at_ms)
  VALUES (v_req.user_id, v_req.group_id, v_req.display_name, v_mapped_role, v_now_ms)
  ON CONFLICT (group_id, user_id) DO UPDATE
    SET role = EXCLUDED.role, joined_at_ms = EXCLUDED.joined_at_ms;

  -- Update athlete profile with active coaching group
  UPDATE public.profiles
    SET active_coaching_group_id = v_req.group_id, updated_at = now()
    WHERE id = v_req.user_id;

  RETURN jsonb_build_object('status', 'approved', 'user_id', v_req.user_id, 'role', v_mapped_role);
END; $fn$;

-- 3. Recreate fn_request_join to accept both Portuguese and English role names
CREATE OR REPLACE FUNCTION public.fn_request_join(p_group_id UUID, p_role TEXT DEFAULT 'atleta')
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  v_uid UUID; v_display TEXT; v_req_id UUID; v_role TEXT;
  v_cancelled INT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  v_role := COALESCE(p_role, 'atleta');
  IF v_role NOT IN ('atleta', 'professor', 'athlete', 'coach') THEN
    RAISE EXCEPTION 'INVALID_ROLE';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.coaching_groups WHERE id = p_group_id) THEN
    RAISE EXCEPTION 'GROUP_NOT_FOUND';
  END IF;

  IF EXISTS (SELECT 1 FROM public.coaching_members WHERE group_id = p_group_id AND user_id = v_uid) THEN
    RETURN jsonb_build_object('status', 'already_member');
  END IF;

  IF EXISTS (SELECT 1 FROM public.coaching_join_requests WHERE group_id = p_group_id AND user_id = v_uid AND status = 'pending') THEN
    RETURN jsonb_build_object('status', 'already_requested');
  END IF;

  -- Cancel any other pending requests for the same role
  UPDATE public.coaching_join_requests
    SET status = 'cancelled', reviewed_at = now()
    WHERE user_id = v_uid
      AND requested_role = v_role
      AND status = 'pending'
      AND group_id <> p_group_id;
  GET DIAGNOSTICS v_cancelled = ROW_COUNT;

  SELECT COALESCE(p.display_name, 'Atleta') INTO v_display
    FROM public.profiles p WHERE p.id = v_uid;

  INSERT INTO public.coaching_join_requests (group_id, user_id, display_name, requested_role)
  VALUES (p_group_id, v_uid, COALESCE(v_display, 'Atleta'), v_role)
  RETURNING id INTO v_req_id;

  RETURN jsonb_build_object(
    'status', 'requested',
    'request_id', v_req_id,
    'cancelled_previous', v_cancelled
  );
END; $fn$;

-- 4. Update coaching_join_requests CHECK to accept both old and new role names
ALTER TABLE public.coaching_join_requests
  DROP CONSTRAINT IF EXISTS coaching_join_requests_requested_role_check;
ALTER TABLE public.coaching_join_requests
  ADD CONSTRAINT coaching_join_requests_requested_role_check
  CHECK (requested_role IN ('atleta', 'professor', 'athlete', 'coach'));

-- 5. Backfill active_coaching_group_id for athletes who are in a group but missing it
UPDATE public.profiles p
  SET active_coaching_group_id = cm.group_id, updated_at = now()
  FROM public.coaching_members cm
  WHERE cm.user_id = p.id
    AND cm.role = 'athlete'
    AND p.active_coaching_group_id IS NULL;

-- 6. Recreate partial unique index with correct role predicate
DROP INDEX IF EXISTS idx_coaching_members_atleta_unique;
CREATE UNIQUE INDEX IF NOT EXISTS idx_coaching_members_athlete_unique
  ON public.coaching_members(user_id)
  WHERE role = 'athlete';
