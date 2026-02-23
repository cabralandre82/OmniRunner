-- Coaching join requests: athletes request to join, staff approves/rejects.
-- Replaces the old "instant join" flow.

CREATE TABLE IF NOT EXISTS public.coaching_join_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected')),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  reviewed_at TIMESTAMPTZ,
  reviewed_by UUID REFERENCES auth.users(id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_join_requests_one_pending
  ON public.coaching_join_requests (group_id, user_id)
  WHERE status = 'pending';

ALTER TABLE public.coaching_join_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "join_requests_select_own"
  ON public.coaching_join_requests FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "join_requests_select_staff"
  ON public.coaching_join_requests FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_join_requests.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'professor', 'assistente')
    )
  );

CREATE POLICY "join_requests_insert_own"
  ON public.coaching_join_requests FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "join_requests_update_staff"
  ON public.coaching_join_requests FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_join_requests.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'professor')
    )
  );

-- RPC: athlete requests to join
CREATE OR REPLACE FUNCTION public.fn_request_join(p_group_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  v_uid UUID; v_display TEXT; v_req_id UUID;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.coaching_groups WHERE id = p_group_id) THEN
    RAISE EXCEPTION 'GROUP_NOT_FOUND';
  END IF;
  IF EXISTS (SELECT 1 FROM public.coaching_members WHERE group_id = p_group_id AND user_id = v_uid) THEN
    RETURN jsonb_build_object('status', 'already_member');
  END IF;
  IF EXISTS (SELECT 1 FROM public.coaching_join_requests WHERE group_id = p_group_id AND user_id = v_uid AND status = 'pending') THEN
    RETURN jsonb_build_object('status', 'already_requested');
  END IF;
  SELECT COALESCE(display_name, email, 'Atleta') INTO v_display FROM public.profiles WHERE id = v_uid;
  INSERT INTO public.coaching_join_requests (group_id, user_id, display_name)
  VALUES (p_group_id, v_uid, COALESCE(v_display, 'Atleta'))
  RETURNING id INTO v_req_id;
  RETURN jsonb_build_object('status', 'requested', 'request_id', v_req_id);
END; $fn$;

-- RPC: staff approves join request
CREATE OR REPLACE FUNCTION public.fn_approve_join_request(p_request_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  v_uid UUID; v_req RECORD; v_now_ms BIGINT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT * INTO v_req FROM public.coaching_join_requests WHERE id = p_request_id AND status = 'pending' FOR UPDATE;
  IF v_req IS NULL THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND_OR_ALREADY_PROCESSED'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.coaching_members WHERE group_id = v_req.group_id AND user_id = v_uid AND role IN ('admin_master', 'professor')) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  v_now_ms := EXTRACT(EPOCH FROM now())::BIGINT * 1000;
  UPDATE public.coaching_join_requests SET status = 'approved', reviewed_at = now(), reviewed_by = v_uid WHERE id = p_request_id;
  DELETE FROM public.coaching_members WHERE user_id = v_req.user_id AND role = 'atleta';
  INSERT INTO public.coaching_members (user_id, group_id, display_name, role, joined_at_ms)
  VALUES (v_req.user_id, v_req.group_id, v_req.display_name, 'atleta', v_now_ms)
  ON CONFLICT (group_id, user_id) DO NOTHING;
  UPDATE public.profiles SET active_coaching_group_id = v_req.group_id, updated_at = now() WHERE id = v_req.user_id;
  RETURN jsonb_build_object('status', 'approved', 'user_id', v_req.user_id);
END; $fn$;

-- RPC: staff rejects join request
CREATE OR REPLACE FUNCTION public.fn_reject_join_request(p_request_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  v_uid UUID; v_req RECORD;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT * INTO v_req FROM public.coaching_join_requests WHERE id = p_request_id AND status = 'pending' FOR UPDATE;
  IF v_req IS NULL THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND_OR_ALREADY_PROCESSED'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.coaching_members WHERE group_id = v_req.group_id AND user_id = v_uid AND role IN ('admin_master', 'professor')) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  UPDATE public.coaching_join_requests SET status = 'rejected', reviewed_at = now(), reviewed_by = v_uid WHERE id = p_request_id;
  RETURN jsonb_build_object('status', 'rejected', 'user_id', v_req.user_id);
END; $fn$;
