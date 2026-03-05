-- Staff can read sessions, challenge_participants of members in their groups.
-- Uses SECURITY DEFINER helper to avoid RLS recursion.

CREATE OR REPLACE FUNCTION public.staff_group_member_ids()
RETURNS SETOF UUID LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT cm.user_id
  FROM public.coaching_members cm
  WHERE cm.group_id IN (
    SELECT cm2.group_id FROM public.coaching_members cm2
    WHERE cm2.user_id = auth.uid()
    AND cm2.role IN ('admin_master', 'professor', 'assistente')
  );
$$;

DROP POLICY IF EXISTS "sessions_staff_read" ON public.sessions;
CREATE POLICY "sessions_staff_read"
  ON public.sessions FOR SELECT
  USING (user_id IN (SELECT staff_group_member_ids()));

DROP POLICY IF EXISTS "challenge_parts_staff_read" ON public.challenge_participants;
CREATE POLICY "challenge_parts_staff_read"
  ON public.challenge_participants FOR SELECT
  USING (user_id IN (SELECT staff_group_member_ids()));
