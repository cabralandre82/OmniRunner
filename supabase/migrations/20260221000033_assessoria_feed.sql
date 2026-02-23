-- ============================================================================
-- Assessoria Feed: lightweight social events per coaching group (Phase 20)
--
-- Privacy: only members of the same coaching group can read feed items.
-- No global feed. No cross-group visibility.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.assessoria_feed (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  actor_user_id   UUID NOT NULL REFERENCES auth.users(id),
  actor_name      TEXT NOT NULL,
  event_type      TEXT NOT NULL,
  payload         JSONB NOT NULL DEFAULT '{}',
  created_at_ms   BIGINT NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT feed_event_type_check CHECK (
    event_type IN (
      'session_completed',
      'challenge_won',
      'badge_unlocked',
      'championship_started',
      'streak_milestone',
      'level_up',
      'member_joined'
    )
  )
);

CREATE INDEX idx_feed_group_time
  ON public.assessoria_feed(group_id, created_at_ms DESC);

CREATE INDEX idx_feed_actor
  ON public.assessoria_feed(actor_user_id);

ALTER TABLE public.assessoria_feed ENABLE ROW LEVEL SECURITY;

-- Members can read feed items from their own group only.
CREATE POLICY "feed_member_read"
  ON public.assessoria_feed FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = assessoria_feed.group_id
        AND cm.user_id = auth.uid()
    )
  );

-- Authenticated users can insert feed items for their own group.
CREATE POLICY "feed_member_insert"
  ON public.assessoria_feed FOR INSERT
  WITH CHECK (
    auth.uid() = actor_user_id
    AND EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = assessoria_feed.group_id
        AND cm.user_id = auth.uid()
    )
  );

-- Service role can insert (for Edge Functions).
CREATE POLICY "feed_service_insert"
  ON public.assessoria_feed FOR INSERT
  TO service_role
  WITH CHECK (true);

-- RPC: paginated feed fetch (newest first, max 50 per page)
CREATE OR REPLACE FUNCTION public.fn_get_assessoria_feed(
  p_group_id UUID,
  p_limit    INT DEFAULT 30,
  p_before_ms BIGINT DEFAULT NULL
)
RETURNS TABLE (
  id            UUID,
  actor_user_id UUID,
  actor_name    TEXT,
  event_type    TEXT,
  payload       JSONB,
  created_at_ms BIGINT
)
LANGUAGE sql STABLE SECURITY DEFINER
AS $$
  SELECT
    f.id,
    f.actor_user_id,
    f.actor_name,
    f.event_type,
    f.payload,
    f.created_at_ms
  FROM public.assessoria_feed f
  WHERE f.group_id = p_group_id
    AND (p_before_ms IS NULL OR f.created_at_ms < p_before_ms)
  ORDER BY f.created_at_ms DESC
  LIMIT LEAST(p_limit, 50);
$$;

-- Auto-cleanup: remove feed items older than 90 days (optional cron job)
-- This can be scheduled via pg_cron or a periodic Edge Function.
