-- Migration: Customizable branding per assessoria
-- DECISÃO 102

CREATE TABLE IF NOT EXISTS public.portal_branding (
  group_id     UUID PRIMARY KEY REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  logo_url     TEXT,
  primary_color TEXT DEFAULT '#2563eb',
  sidebar_bg   TEXT DEFAULT '#ffffff',
  sidebar_text TEXT DEFAULT '#111827',
  accent_color TEXT DEFAULT '#2563eb',
  updated_at   TIMESTAMPTZ DEFAULT now() NOT NULL
);

ALTER TABLE public.portal_branding ENABLE ROW LEVEL SECURITY;

CREATE POLICY "branding_staff_read" ON public.portal_branding
  FOR SELECT USING (
    group_id IN (
      SELECT group_id FROM public.coaching_members
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "branding_admin_write" ON public.portal_branding
  FOR ALL USING (
    group_id IN (
      SELECT group_id FROM public.coaching_members
      WHERE user_id = auth.uid() AND role = 'admin_master'
    )
  );

CREATE POLICY "branding_platform_read" ON public.portal_branding
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profiles WHERE id = auth.uid() AND platform_role = 'admin'
    )
  );
