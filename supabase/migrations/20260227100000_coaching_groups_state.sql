-- Add state (UF) to coaching_groups for league geographic filtering
-- Reference: DECISAO 085

BEGIN;

ALTER TABLE public.coaching_groups
  ADD COLUMN IF NOT EXISTS state TEXT DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_coaching_groups_state
  ON public.coaching_groups(state)
  WHERE state <> '';

-- Update fn_create_assessoria to accept state
CREATE OR REPLACE FUNCTION public.fn_create_assessoria(
  p_name TEXT,
  p_city TEXT DEFAULT '',
  p_state TEXT DEFAULT ''
)
RETURNS JSONB AS $$
DECLARE
  v_uid          UUID;
  v_display_name TEXT;
  v_group_id     UUID;
  v_invite_code  TEXT;
  v_now_ms       BIGINT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  IF (SELECT user_role FROM public.profiles WHERE id = v_uid) <> 'ASSESSORIA_STAFF' THEN
    RAISE EXCEPTION 'STAFF_ROLE_REQUIRED';
  END IF;

  IF length(trim(p_name)) < 3 OR length(trim(p_name)) > 80 THEN
    RAISE EXCEPTION 'INVALID_NAME';
  END IF;

  SELECT display_name INTO v_display_name
    FROM public.profiles WHERE id = v_uid;

  v_group_id := gen_random_uuid();
  v_now_ms   := EXTRACT(EPOCH FROM now())::BIGINT * 1000;

  INSERT INTO public.coaching_groups (id, name, coach_user_id, city, state, created_at_ms, approval_status)
  VALUES (v_group_id, trim(p_name), v_uid, COALESCE(trim(p_city), ''), COALESCE(upper(trim(p_state)), ''), v_now_ms, 'pending_approval')
  RETURNING invite_code INTO v_invite_code;

  INSERT INTO public.coaching_members (user_id, group_id, display_name, role, joined_at_ms)
  VALUES (v_uid, v_group_id, COALESCE(v_display_name, 'Coach'), 'admin_master', v_now_ms);

  UPDATE public.profiles
    SET active_coaching_group_id = v_group_id, updated_at = now()
    WHERE id = v_uid;

  RETURN jsonb_build_object(
    'group_id', v_group_id,
    'invite_code', v_invite_code,
    'invite_link', 'https://omnirunner.app/invite/' || v_invite_code
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
