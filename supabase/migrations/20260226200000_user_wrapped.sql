-- User Wrapped: cached retrospective stats per period
-- Reference: ROADMAP_NEXT.md §1 OmniWrapped

CREATE TABLE IF NOT EXISTS public.user_wrapped (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  period_type   TEXT NOT NULL CHECK (period_type IN ('month', 'quarter', 'year')),
  period_key    TEXT NOT NULL,
  data          JSONB NOT NULL DEFAULT '{}',
  created_at_ms BIGINT NOT NULL,

  UNIQUE(user_id, period_type, period_key)
);

CREATE INDEX idx_user_wrapped_user ON public.user_wrapped(user_id, period_type);

ALTER TABLE public.user_wrapped ENABLE ROW LEVEL SECURITY;

CREATE POLICY "wrapped_own_read" ON public.user_wrapped
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "wrapped_service_insert" ON public.user_wrapped
  FOR INSERT WITH CHECK (true);

CREATE POLICY "wrapped_service_upsert" ON public.user_wrapped
  FOR UPDATE USING (true);
