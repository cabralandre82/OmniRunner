-- Fix: infinite recursion in coaching_members RLS policy.
--
-- The original "coaching_members_group_read" policy did:
--   EXISTS (SELECT 1 FROM coaching_members cm2 WHERE cm2.group_id = ... AND cm2.user_id = auth.uid())
-- which re-triggers the same RLS check on coaching_members → infinite loop.
--
-- Solution: a SECURITY DEFINER function runs as the function owner (bypassing RLS),
-- so the subquery no longer triggers the policy recursively.

-- 1. Helper: returns all group_ids the current user belongs to (bypasses RLS).
CREATE OR REPLACE FUNCTION public.user_coaching_group_ids()
RETURNS SETOF uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = 'public'
AS $$
  SELECT group_id FROM public.coaching_members WHERE user_id = auth.uid();
$$;

-- 2. Drop the recursive policy.
DROP POLICY IF EXISTS "coaching_members_group_read" ON "public"."coaching_members";

-- 3. Re-create: users can see all members of groups they belong to.
CREATE POLICY "coaching_members_group_read"
  ON "public"."coaching_members"
  FOR SELECT
  USING (group_id IN (SELECT public.user_coaching_group_ids()));

-- Grant execute to authenticated (anon doesn't need coaching access).
GRANT EXECUTE ON FUNCTION public.user_coaching_group_ids() TO authenticated;
GRANT EXECUTE ON FUNCTION public.user_coaching_group_ids() TO service_role;
