-- Fix: fn_create_assessoria was missing created_at_ms in the INSERT into coaching_groups.
-- The column is NOT NULL without a default, causing a constraint violation.

CREATE OR REPLACE FUNCTION public.fn_create_assessoria(p_name text, p_city text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_uid          UUID;
  v_display_name TEXT;
  v_group_id     UUID;
  v_invite_code  TEXT;
  v_now_ms       BIGINT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = v_uid AND user_role = 'ASSESSORIA_STAFF'
  ) THEN
    RAISE EXCEPTION 'NOT_STAFF';
  END IF;

  IF length(trim(p_name)) < 3 OR length(trim(p_name)) > 80 THEN
    RAISE EXCEPTION 'INVALID_NAME';
  END IF;

  SELECT display_name INTO v_display_name
    FROM public.profiles WHERE id = v_uid;

  v_group_id := gen_random_uuid();
  v_now_ms   := EXTRACT(EPOCH FROM now())::BIGINT * 1000;

  INSERT INTO public.coaching_groups (id, name, coach_user_id, city, created_at_ms)
  VALUES (v_group_id, trim(p_name), v_uid, COALESCE(trim(p_city), ''), v_now_ms)
  RETURNING invite_code INTO v_invite_code;

  INSERT INTO public.coaching_members (user_id, group_id, display_name, role, joined_at_ms)
  VALUES (v_uid, v_group_id, COALESCE(v_display_name, 'Coach'), 'admin_master', v_now_ms);

  UPDATE public.profiles
    SET active_coaching_group_id = v_group_id, updated_at = now()
    WHERE id = v_uid;

  RETURN jsonb_build_object(
    'status', 'created',
    'group_id', v_group_id,
    'invite_code', v_invite_code,
    'invite_link', 'https://omnirunner.app/invite/' || v_invite_code
  );
END;
$function$;
