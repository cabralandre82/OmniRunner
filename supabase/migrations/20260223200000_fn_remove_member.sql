-- RPC: staff removes a member from the coaching group.
-- Rules:
--   - Caller must be staff (admin_master, professor, or assistente)
--   - Cannot remove admin_master (owner)
--   - Assistente cannot remove other staff (professor/assistente)
--   - Cannot remove yourself
--   - Clears active_coaching_group_id on the removed user's profile

CREATE OR REPLACE FUNCTION public.fn_remove_member(p_target_user_id UUID, p_group_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  v_uid UUID; v_caller_role TEXT; v_target_role TEXT; v_target_name TEXT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  SELECT role INTO v_caller_role FROM public.coaching_members WHERE group_id = p_group_id AND user_id = v_uid;
  IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin_master', 'professor', 'assistente') THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  SELECT role, display_name INTO v_target_role, v_target_name FROM public.coaching_members WHERE group_id = p_group_id AND user_id = p_target_user_id;
  IF v_target_role IS NULL THEN RAISE EXCEPTION 'MEMBER_NOT_FOUND'; END IF;
  IF v_target_role = 'admin_master' THEN RAISE EXCEPTION 'CANNOT_REMOVE_ADMIN_MASTER'; END IF;
  IF v_caller_role = 'assistente' AND v_target_role IN ('professor', 'assistente') THEN RAISE EXCEPTION 'INSUFFICIENT_ROLE'; END IF;
  IF v_uid = p_target_user_id THEN RAISE EXCEPTION 'CANNOT_REMOVE_SELF'; END IF;

  DELETE FROM public.coaching_members WHERE group_id = p_group_id AND user_id = p_target_user_id;
  UPDATE public.profiles SET active_coaching_group_id = NULL, updated_at = now() WHERE id = p_target_user_id AND active_coaching_group_id = p_group_id;

  RETURN jsonb_build_object('status', 'removed', 'user_id', p_target_user_id, 'display_name', COALESCE(v_target_name, ''), 'role', v_target_role);
END; $fn$;
