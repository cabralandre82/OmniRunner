-- Support tickets / support messages (in-app helpdesk)

-- Table: support_tickets
CREATE TABLE IF NOT EXISTS public.support_tickets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID NOT NULL,
  subject TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'answered', 'closed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_support_tickets_group_id ON public.support_tickets (group_id);

-- Table: support_messages
CREATE TABLE IF NOT EXISTS public.support_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id UUID NOT NULL REFERENCES public.support_tickets(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  sender_role TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_support_messages_ticket_id ON public.support_messages (ticket_id);

-- Keep ticket "updated_at" in sync when new messages arrive.
CREATE OR REPLACE FUNCTION public.fn_support_ticket_updated_at() RETURNS trigger
  LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.support_tickets
  SET updated_at = now()
  WHERE id = NEW.ticket_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS support_messages_update_ticket_ts ON public.support_messages;
CREATE TRIGGER support_messages_update_ticket_ts
  AFTER INSERT ON public.support_messages
  FOR EACH ROW EXECUTE FUNCTION public.fn_support_ticket_updated_at();

-- Row Level Security --------------------------------------------------------
ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_messages ENABLE ROW LEVEL SECURITY;

-- Helpers
-- `platform_role = 'admin'` is used by the platform admins (see profiles.platform_role).

-- Support ticket policies
DROP POLICY IF EXISTS "support_tickets_select_group" ON public.support_tickets;
CREATE POLICY "support_tickets_select_group" ON public.support_tickets FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.coaching_members cm
      WHERE cm.group_id = public.support_tickets.group_id
        AND cm.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = auth.uid() AND p.platform_role = 'admin'
    )
  );

DROP POLICY IF EXISTS "support_tickets_insert_group" ON public.support_tickets;
CREATE POLICY "support_tickets_insert_group" ON public.support_tickets FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.coaching_members cm
      WHERE cm.group_id = public.support_tickets.group_id
        AND cm.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "support_tickets_update_admin" ON public.support_tickets;
CREATE POLICY "support_tickets_update_admin" ON public.support_tickets FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = auth.uid() AND p.platform_role = 'admin'
    )
  );

-- Support message policies
DROP POLICY IF EXISTS "support_messages_select_group" ON public.support_messages;
CREATE POLICY "support_messages_select_group" ON public.support_messages FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.support_tickets t
      JOIN public.coaching_members cm ON cm.group_id = t.group_id
      WHERE t.id = public.support_messages.ticket_id
        AND cm.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = auth.uid() AND p.platform_role = 'admin'
    )
  );

DROP POLICY IF EXISTS "support_messages_insert_group" ON public.support_messages;
CREATE POLICY "support_messages_insert_group" ON public.support_messages FOR INSERT
  WITH CHECK (
    (sender_id = auth.uid())
    AND (
      EXISTS (
        SELECT 1
        FROM public.support_tickets t
        JOIN public.coaching_members cm ON cm.group_id = t.group_id
        WHERE t.id = public.support_messages.ticket_id
          AND cm.user_id = auth.uid()
      )
      OR EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id = auth.uid() AND p.platform_role = 'admin'
      )
    )
  );
