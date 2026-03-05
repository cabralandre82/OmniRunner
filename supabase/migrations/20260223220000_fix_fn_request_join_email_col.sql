-- Fix fn_request_join: profiles table has no 'email' column.
-- Use only display_name from profiles; fall back to 'Atleta'.

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
  SELECT COALESCE(p.display_name, 'Atleta') INTO v_display
    FROM public.profiles p WHERE p.id = v_uid;
  INSERT INTO public.coaching_join_requests (group_id, user_id, display_name)
  VALUES (p_group_id, v_uid, COALESCE(v_display, 'Atleta'))
  RETURNING id INTO v_req_id;
  RETURN jsonb_build_object('status', 'requested', 'request_id', v_req_id);
END; $fn$;
