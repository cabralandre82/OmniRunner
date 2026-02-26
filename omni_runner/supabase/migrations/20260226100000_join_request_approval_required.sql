-- Fix: professors joining assessorias and deep-link joins must go through
-- the same approval flow as athletes. No one enters without admin approval.
--
-- Changes:
--   1. Add requested_role column to coaching_join_requests
--   2. Update fn_request_join to accept optional p_role parameter
--   3. Update fn_approve_join_request to use requested_role
--   4. Drop fn_join_as_professor (no longer needed)

-- 1. Add requested_role column
ALTER TABLE public.coaching_join_requests
  ADD COLUMN IF NOT EXISTS requested_role TEXT NOT NULL DEFAULT 'atleta'
  CHECK (requested_role IN ('atleta', 'professor'));

-- 2. Recreate fn_request_join with optional role
--    Rule: only ONE pending request per user per role at a time.
--    If the user already has a pending request for another group (same role),
--    it is auto-cancelled before creating the new one.
CREATE OR REPLACE FUNCTION public.fn_request_join(p_group_id UUID, p_role TEXT DEFAULT 'atleta')
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  v_uid UUID; v_display TEXT; v_req_id UUID; v_role TEXT;
  v_cancelled INT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  v_role := COALESCE(p_role, 'atleta');
  IF v_role NOT IN ('atleta', 'professor') THEN
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

  -- Cancel any other pending requests for the same role (one active request at a time)
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

-- 2b. Add 'cancelled' as valid status (original CHECK only had pending/approved/rejected)
ALTER TABLE public.coaching_join_requests
  DROP CONSTRAINT IF EXISTS coaching_join_requests_status_check;
ALTER TABLE public.coaching_join_requests
  ADD CONSTRAINT coaching_join_requests_status_check
  CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled'));

-- 3. Recreate fn_approve_join_request using requested_role
--    Safety net: also cancels any other pending requests for the same user+role
CREATE OR REPLACE FUNCTION public.fn_approve_join_request(p_request_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  v_uid UUID; v_req RECORD; v_now_ms BIGINT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  SELECT * INTO v_req FROM public.coaching_join_requests
    WHERE id = p_request_id AND status = 'pending' FOR UPDATE;
  IF v_req IS NULL THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND_OR_ALREADY_PROCESSED'; END IF;

  -- Only admin_master can approve professor requests; admin_master or professor can approve athletes
  IF v_req.requested_role = 'professor' THEN
    IF NOT EXISTS (SELECT 1 FROM public.coaching_members
      WHERE group_id = v_req.group_id AND user_id = v_uid AND role = 'admin_master') THEN
      RAISE EXCEPTION 'ONLY_ADMIN_CAN_APPROVE_PROFESSOR';
    END IF;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM public.coaching_members
      WHERE group_id = v_req.group_id AND user_id = v_uid AND role IN ('admin_master', 'professor')) THEN
      RAISE EXCEPTION 'NOT_AUTHORIZED';
    END IF;
  END IF;

  v_now_ms := EXTRACT(EPOCH FROM now())::BIGINT * 1000;

  -- Mark this request as approved
  UPDATE public.coaching_join_requests
    SET status = 'approved', reviewed_at = now(), reviewed_by = v_uid
    WHERE id = p_request_id;

  -- Cancel all other pending requests for same user + same role (defense in depth)
  UPDATE public.coaching_join_requests
    SET status = 'cancelled', reviewed_at = now()
    WHERE user_id = v_req.user_id
      AND requested_role = v_req.requested_role
      AND status = 'pending'
      AND id <> p_request_id;

  -- Remove previous membership of same role (if switching groups)
  DELETE FROM public.coaching_members
    WHERE user_id = v_req.user_id AND role = v_req.requested_role;

  INSERT INTO public.coaching_members (user_id, group_id, display_name, role, joined_at_ms)
  VALUES (v_req.user_id, v_req.group_id, v_req.display_name, v_req.requested_role, v_now_ms)
  ON CONFLICT (group_id, user_id) DO NOTHING;

  UPDATE public.profiles
    SET active_coaching_group_id = v_req.group_id, updated_at = now()
    WHERE id = v_req.user_id;

  RETURN jsonb_build_object('status', 'approved', 'user_id', v_req.user_id, 'role', v_req.requested_role);
END; $fn$;

-- 4. Drop fn_join_as_professor (entry without approval no longer allowed)
DROP FUNCTION IF EXISTS public.fn_join_as_professor(UUID);
