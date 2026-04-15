-- Allow athletes (coaching_members) to use in-app support alongside staff.
-- App sends sender_role = 'athlete' | 'staff'; platform admin continues to use 'platform'.

-- 1. Widen sender_role on support_messages
ALTER TABLE public.support_messages
  DROP CONSTRAINT IF EXISTS support_messages_sender_role_check;

ALTER TABLE public.support_messages
  ADD CONSTRAINT support_messages_sender_role_check
  CHECK (sender_role IN ('staff', 'platform', 'athlete'));

-- 2. Tickets: any member of the assessoria may read / create / update tickets for that group
DROP POLICY IF EXISTS support_tickets_staff_read ON public.support_tickets;
DROP POLICY IF EXISTS "staff_read_own_tickets" ON public.support_tickets;
CREATE POLICY "member_read_support_tickets" ON public.support_tickets
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = support_tickets.group_id
        AND cm.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.platform_role = 'admin'
    )
  );

DROP POLICY IF EXISTS "staff_insert_tickets" ON public.support_tickets;
CREATE POLICY "member_insert_support_tickets" ON public.support_tickets
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = support_tickets.group_id
        AND cm.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "staff_update_own_tickets" ON public.support_tickets;
CREATE POLICY "member_update_support_tickets" ON public.support_tickets
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = support_tickets.group_id
        AND cm.user_id = auth.uid()
    )
  );

-- 3. Messages: any group member may read thread; insert must match assessoria role
DROP POLICY IF EXISTS "staff_read_own_messages" ON public.support_messages;
CREATE POLICY "member_read_support_messages" ON public.support_messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.support_tickets t
      JOIN public.coaching_members cm ON cm.group_id = t.group_id
      WHERE t.id = support_messages.ticket_id
        AND cm.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.platform_role = 'admin'
    )
  );

DROP POLICY IF EXISTS "staff_insert_messages" ON public.support_messages;
CREATE POLICY "member_insert_support_messages" ON public.support_messages
  FOR INSERT WITH CHECK (
    sender_id = auth.uid()
    AND sender_role IN ('athlete', 'staff')
    AND EXISTS (
      SELECT 1
      FROM public.support_tickets t
      JOIN public.coaching_members cm
        ON cm.group_id = t.group_id AND cm.user_id = auth.uid()
      WHERE t.id = support_messages.ticket_id
        AND (
          (sender_role = 'athlete' AND cm.role IN ('athlete', 'atleta'))
          OR (sender_role = 'staff' AND cm.role IN ('admin_master', 'coach', 'assistant'))
        )
    )
  );
