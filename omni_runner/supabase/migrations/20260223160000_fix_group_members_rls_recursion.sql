-- Fix: infinite recursion in group_members RLS policies.
-- Same pattern as coaching_members: SELECT policy references itself.

-- 1. Helper: returns all group_ids the current user is an active member of (bypasses RLS).
CREATE OR REPLACE FUNCTION public.user_social_group_ids()
RETURNS SETOF uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = 'public'
AS $$
  SELECT group_id FROM public.group_members
  WHERE user_id = auth.uid() AND status = 'active';
$$;

-- 2. Helper: checks if user is admin/moderator of a specific group (bypasses RLS).
CREATE OR REPLACE FUNCTION public.is_group_admin_or_mod(p_group_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.group_members
    WHERE group_id = p_group_id
      AND user_id = auth.uid()
      AND role IN ('admin', 'moderator')
      AND status = 'active'
  );
$$;

-- 3. Drop recursive policies.
DROP POLICY IF EXISTS "group_members_read" ON "public"."group_members";
DROP POLICY IF EXISTS "group_members_update_mod" ON "public"."group_members";

-- 4. Re-create SELECT policy without self-reference.
CREATE POLICY "group_members_read"
  ON "public"."group_members"
  FOR SELECT
  USING (group_id IN (SELECT public.user_social_group_ids()));

-- 5. Re-create UPDATE policy without self-reference.
CREATE POLICY "group_members_update_mod"
  ON "public"."group_members"
  FOR UPDATE
  USING (
    auth.uid() = user_id
    OR public.is_group_admin_or_mod(group_id)
  );

-- Grant execute.
GRANT EXECUTE ON FUNCTION public.user_social_group_ids() TO authenticated;
GRANT EXECUTE ON FUNCTION public.user_social_group_ids() TO service_role;
GRANT EXECUTE ON FUNCTION public.is_group_admin_or_mod(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_group_admin_or_mod(uuid) TO service_role;
