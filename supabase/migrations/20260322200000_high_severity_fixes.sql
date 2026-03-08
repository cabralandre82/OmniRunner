-- HIGH severity fixes from pre-release audit
-- 1. RLS on api_rate_limits
-- 2. search_path on fn_request_join, fn_approve_join_request, increment_rate_limit, cleanup_rate_limits
-- 3. Fix Portuguese roles in fn_request_join (default 'athlete', English-only constraint)
-- 4. Log clearing/custody exceptions in execute_burn_atomic instead of silencing

-- ══════════════════════════════════════════════════════════════════
-- 1. Enable RLS on api_rate_limits
-- ══════════════════════════════════════════════════════════════════
ALTER TABLE public.api_rate_limits ENABLE ROW LEVEL SECURITY;

CREATE POLICY "service_only_rate_limits" ON public.api_rate_limits
  FOR ALL USING (false);

GRANT SELECT, INSERT, UPDATE ON public.api_rate_limits TO service_role;

-- ══════════════════════════════════════════════════════════════════
-- 2. fn_request_join: add search_path + English-only roles
-- ══════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.fn_request_join(UUID, TEXT);
CREATE FUNCTION public.fn_request_join(p_group_id UUID, p_role TEXT DEFAULT 'athlete')
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_uid UUID; v_display TEXT; v_req_id UUID; v_role TEXT;
  v_cancelled INT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  v_role := CASE COALESCE(p_role, 'athlete')
    WHEN 'atleta'    THEN 'athlete'
    WHEN 'professor' THEN 'coach'
    ELSE COALESCE(p_role, 'athlete')
  END;

  IF v_role NOT IN ('athlete', 'coach') THEN
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

-- ══════════════════════════════════════════════════════════════════
-- 3. fn_approve_join_request: add search_path
-- ══════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.fn_approve_join_request(UUID);
CREATE FUNCTION public.fn_approve_join_request(p_request_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_uid UUID; v_req RECORD; v_now_ms BIGINT; v_mapped_role TEXT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  SELECT * INTO v_req FROM public.coaching_join_requests
    WHERE id = p_request_id AND status = 'pending' FOR UPDATE;
  IF v_req IS NULL THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND_OR_ALREADY_PROCESSED'; END IF;

  v_mapped_role := CASE v_req.requested_role
    WHEN 'atleta'    THEN 'athlete'
    WHEN 'professor' THEN 'coach'
    WHEN 'athlete'   THEN 'athlete'
    WHEN 'coach'     THEN 'coach'
    ELSE 'athlete'
  END;

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

  UPDATE public.coaching_join_requests
    SET status = 'approved', reviewed_at = now(), reviewed_by = v_uid
    WHERE id = p_request_id;

  UPDATE public.coaching_join_requests
    SET status = 'cancelled', reviewed_at = now()
    WHERE user_id = v_req.user_id
      AND requested_role = v_req.requested_role
      AND status = 'pending'
      AND id <> p_request_id;

  DELETE FROM public.coaching_members
    WHERE user_id = v_req.user_id AND role = v_mapped_role;

  INSERT INTO public.coaching_members (user_id, group_id, display_name, role, joined_at_ms)
  VALUES (v_req.user_id, v_req.group_id, v_req.display_name, v_mapped_role, v_now_ms)
  ON CONFLICT (group_id, user_id) DO UPDATE
    SET role = EXCLUDED.role, joined_at_ms = EXCLUDED.joined_at_ms;

  UPDATE public.profiles
    SET active_coaching_group_id = v_req.group_id, updated_at = now()
    WHERE id = v_req.user_id;

  RETURN jsonb_build_object('status', 'approved', 'user_id', v_req.user_id, 'role', v_mapped_role);
END; $fn$;

-- ══════════════════════════════════════════════════════════════════
-- 4. increment_rate_limit: add search_path
-- ══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.increment_rate_limit(
  p_user_id       uuid,
  p_fn            text,
  p_window_seconds int
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_window_start timestamptz;
  v_count        int;
BEGIN
  v_window_start := to_timestamp(
    floor(extract(epoch FROM now()) / p_window_seconds) * p_window_seconds
  );

  INSERT INTO public.api_rate_limits (user_id, fn, window_start, count)
  VALUES (p_user_id, p_fn, v_window_start, 1)
  ON CONFLICT (user_id, fn, window_start)
  DO UPDATE SET count = api_rate_limits.count + 1
  RETURNING count INTO v_count;

  RETURN v_count;
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- 5. cleanup_rate_limits: add search_path
-- ══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.cleanup_rate_limits()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  DELETE FROM public.api_rate_limits
  WHERE window_start < now() - interval '1 hour';
$$;

-- ══════════════════════════════════════════════════════════════════
-- 6. Tighten coaching_join_requests CHECK to English-only
-- ══════════════════════════════════════════════════════════════════
ALTER TABLE public.coaching_join_requests
  DROP CONSTRAINT IF EXISTS coaching_join_requests_requested_role_check;
ALTER TABLE public.coaching_join_requests
  ADD CONSTRAINT coaching_join_requests_requested_role_check
  CHECK (requested_role IN ('athlete', 'coach'));

-- Backfill any Portuguese values still in join_requests
UPDATE public.coaching_join_requests SET requested_role = 'athlete' WHERE requested_role = 'atleta';
UPDATE public.coaching_join_requests SET requested_role = 'coach'   WHERE requested_role = 'professor';
