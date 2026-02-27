-- Migration: Portal audit log for staff and platform admin actions
-- DECISÃO 099

CREATE TABLE IF NOT EXISTS public.portal_audit_log (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  actor_id   UUID NOT NULL REFERENCES auth.users(id),
  group_id   UUID REFERENCES public.coaching_groups(id),
  action     TEXT NOT NULL,
  target_type TEXT,
  target_id  TEXT,
  metadata   JSONB DEFAULT '{}'::JSONB,
  ip_address TEXT,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE INDEX idx_portal_audit_actor ON public.portal_audit_log(actor_id);
CREATE INDEX idx_portal_audit_group ON public.portal_audit_log(group_id);
CREATE INDEX idx_portal_audit_action ON public.portal_audit_log(action);
CREATE INDEX idx_portal_audit_created ON public.portal_audit_log(created_at DESC);

ALTER TABLE public.portal_audit_log ENABLE ROW LEVEL SECURITY;

-- Platform admins can read all logs; staff can read their group's logs
CREATE POLICY "audit_platform_read" ON public.portal_audit_log
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profiles WHERE id = auth.uid() AND platform_role = 'admin'
    )
    OR
    group_id IN (
      SELECT group_id FROM public.coaching_members
      WHERE user_id = auth.uid() AND role IN ('admin_master', 'professor')
    )
  );

-- Insert only via service_role (API routes)
-- No UPDATE or DELETE policies — log is append-only

COMMENT ON TABLE public.portal_audit_log IS
  'Append-only audit trail for all portal staff and platform admin actions.';
