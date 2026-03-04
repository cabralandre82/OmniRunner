-- Session journal entries — User notes per workout session (TodayScreen "Diário de corrida")
-- P1-4: Journal persistence for TodayScreen
CREATE TABLE IF NOT EXISTS public.session_journal_entries (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id        UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  user_id           UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  notes             TEXT,
  mood_emoji        TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(session_id)
);

CREATE INDEX IF NOT EXISTS idx_session_journal_session
  ON public.session_journal_entries (session_id);
CREATE INDEX IF NOT EXISTS idx_session_journal_user
  ON public.session_journal_entries (user_id);

ALTER TABLE public.session_journal_entries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "session_journal_own_read" ON public.session_journal_entries
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "session_journal_own_insert" ON public.session_journal_entries
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "session_journal_own_update" ON public.session_journal_entries
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "session_journal_own_delete" ON public.session_journal_entries
  FOR DELETE USING (auth.uid() = user_id);
