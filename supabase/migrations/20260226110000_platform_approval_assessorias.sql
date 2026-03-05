-- Platform approval for assessorias.
-- Every new assessoria starts as 'pending_approval' and only becomes
-- visible/usable after a platform admin approves it.
--
-- Platform admins are identified by profiles.platform_role = 'admin'.

-- 1. Add platform_role to profiles (only you, the platform owner)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS platform_role TEXT DEFAULT NULL
  CHECK (platform_role IS NULL OR platform_role IN ('admin'));

-- 2. Add approval_status to coaching_groups
ALTER TABLE public.coaching_groups
  ADD COLUMN IF NOT EXISTS approval_status TEXT NOT NULL DEFAULT 'pending_approval'
  CHECK (approval_status IN ('pending_approval', 'approved', 'rejected', 'suspended'));

ALTER TABLE public.coaching_groups
  ADD COLUMN IF NOT EXISTS approval_reviewed_at TIMESTAMPTZ DEFAULT NULL;

ALTER TABLE public.coaching_groups
  ADD COLUMN IF NOT EXISTS approval_reviewed_by UUID DEFAULT NULL REFERENCES auth.users(id);

ALTER TABLE public.coaching_groups
  ADD COLUMN IF NOT EXISTS approval_reject_reason TEXT DEFAULT NULL;

-- Existing groups should be approved (they were created before this gate existed)
UPDATE public.coaching_groups SET approval_status = 'approved' WHERE approval_status = 'pending_approval';

-- 3. Update fn_create_assessoria — new groups start as pending_approval
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

  INSERT INTO public.coaching_groups (id, name, coach_user_id, city, created_at_ms, approval_status)
  VALUES (v_group_id, trim(p_name), v_uid, COALESCE(trim(p_city), ''), v_now_ms, 'pending_approval')
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
    'invite_link', 'https://omnirunner.app/invite/' || v_invite_code,
    'approval_status', 'pending_approval'
  );
END;
$function$;

-- 4. Platform admin approves an assessoria
CREATE OR REPLACE FUNCTION public.fn_platform_approve_assessoria(p_group_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  v_uid UUID; v_group RECORD;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND platform_role = 'admin') THEN
    RAISE EXCEPTION 'NOT_PLATFORM_ADMIN';
  END IF;

  SELECT * INTO v_group FROM public.coaching_groups WHERE id = p_group_id FOR UPDATE;
  IF v_group IS NULL THEN RAISE EXCEPTION 'GROUP_NOT_FOUND'; END IF;

  IF v_group.approval_status = 'approved' THEN
    RETURN jsonb_build_object('status', 'already_approved');
  END IF;

  UPDATE public.coaching_groups
    SET approval_status = 'approved',
        approval_reviewed_at = now(),
        approval_reviewed_by = v_uid,
        approval_reject_reason = NULL
    WHERE id = p_group_id;

  RETURN jsonb_build_object('status', 'approved', 'group_id', p_group_id);
END; $fn$;

-- 5. Platform admin rejects an assessoria
CREATE OR REPLACE FUNCTION public.fn_platform_reject_assessoria(p_group_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  v_uid UUID; v_group RECORD;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND platform_role = 'admin') THEN
    RAISE EXCEPTION 'NOT_PLATFORM_ADMIN';
  END IF;

  SELECT * INTO v_group FROM public.coaching_groups WHERE id = p_group_id FOR UPDATE;
  IF v_group IS NULL THEN RAISE EXCEPTION 'GROUP_NOT_FOUND'; END IF;

  UPDATE public.coaching_groups
    SET approval_status = 'rejected',
        approval_reviewed_at = now(),
        approval_reviewed_by = v_uid,
        approval_reject_reason = COALESCE(p_reason, '')
    WHERE id = p_group_id;

  RETURN jsonb_build_object('status', 'rejected', 'group_id', p_group_id);
END; $fn$;

-- 6. Platform admin suspends an assessoria
CREATE OR REPLACE FUNCTION public.fn_platform_suspend_assessoria(p_group_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  v_uid UUID;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND platform_role = 'admin') THEN
    RAISE EXCEPTION 'NOT_PLATFORM_ADMIN';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.coaching_groups WHERE id = p_group_id) THEN
    RAISE EXCEPTION 'GROUP_NOT_FOUND';
  END IF;

  UPDATE public.coaching_groups
    SET approval_status = 'suspended',
        approval_reviewed_at = now(),
        approval_reviewed_by = v_uid,
        approval_reject_reason = COALESCE(p_reason, '')
    WHERE id = p_group_id;

  RETURN jsonb_build_object('status', 'suspended', 'group_id', p_group_id);
END; $fn$;

-- 7. Update fn_search_coaching_groups to only return approved groups
--    (unless caller is platform admin — they see all)
DROP FUNCTION IF EXISTS public.fn_search_coaching_groups(TEXT, UUID[]);
CREATE OR REPLACE FUNCTION public.fn_search_coaching_groups(
  p_query TEXT DEFAULT NULL,
  p_group_ids UUID[] DEFAULT NULL
)
RETURNS TABLE(
  id UUID,
  name TEXT,
  city TEXT,
  coach_display_name TEXT,
  member_count BIGINT
) LANGUAGE plpgsql SECURITY DEFINER STABLE AS $fn$
DECLARE
  v_is_platform_admin BOOLEAN;
BEGIN
  SELECT EXISTS(
    SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND platform_role = 'admin'
  ) INTO v_is_platform_admin;

  RETURN QUERY
    SELECT
      g.id,
      g.name,
      g.city,
      COALESCE(p.display_name, 'Coach') AS coach_display_name,
      (SELECT COUNT(*) FROM public.coaching_members cm WHERE cm.group_id = g.id) AS member_count
    FROM public.coaching_groups g
    LEFT JOIN public.profiles p ON p.id = g.coach_user_id
    WHERE
      (v_is_platform_admin OR g.approval_status = 'approved')
      AND (
        (p_group_ids IS NOT NULL AND g.id = ANY(p_group_ids))
        OR
        (p_query IS NOT NULL AND g.name ILIKE '%' || p_query || '%')
      )
    ORDER BY g.name
    LIMIT 20;
END; $fn$;

-- 8. Update fn_lookup_group_by_invite_code to only return approved groups
DROP FUNCTION IF EXISTS public.fn_lookup_group_by_invite_code(TEXT);
CREATE OR REPLACE FUNCTION public.fn_lookup_group_by_invite_code(p_code TEXT)
RETURNS TABLE(
  id UUID,
  name TEXT,
  city TEXT,
  member_count BIGINT
) LANGUAGE plpgsql SECURITY DEFINER STABLE AS $fn$
BEGIN
  RETURN QUERY
    SELECT
      g.id,
      g.name,
      g.city,
      (SELECT COUNT(*) FROM public.coaching_members cm WHERE cm.group_id = g.id) AS member_count
    FROM public.coaching_groups g
    WHERE g.invite_code = p_code
      AND g.approval_status = 'approved'
    LIMIT 1;
END; $fn$;

-- 9. RLS: platform admin can read all coaching_groups (for the portal admin page)
DROP POLICY IF EXISTS "coaching_groups_platform_admin_read" ON public.coaching_groups;
CREATE POLICY "coaching_groups_platform_admin_read"
  ON public.coaching_groups FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid() AND platform_role = 'admin'
    )
  );
