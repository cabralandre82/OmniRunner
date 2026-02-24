-- ============================================================================
-- MATCHMAKING QUEUE: challenge_queue table + RPC + RLS
-- ============================================================================
-- Enables public matchmaking for 1v1 challenges. Users declare an intent
-- (metric, target range, stake, duration) and the system pairs compatible
-- opponents automatically. No browsing — queue-based like online gaming.
-- ============================================================================

-- ── 1. Table ────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.challenge_queue (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Intent parameters
  metric          TEXT NOT NULL CHECK (metric IN ('distance', 'pace', 'time')),
  target          NUMERIC,                                -- e.g. 5000 (meters) or NULL (open)
  entry_fee_coins INT  NOT NULL DEFAULT 0 CHECK (entry_fee_coins >= 0),
  window_ms       BIGINT NOT NULL CHECK (window_ms > 0),  -- challenge duration

  -- Skill bracket (computed from recent performance)
  skill_bracket   TEXT NOT NULL DEFAULT 'beginner'
                  CHECK (skill_bracket IN ('beginner', 'intermediate', 'advanced', 'elite')),

  -- Matching tolerances
  target_tolerance_pct NUMERIC NOT NULL DEFAULT 0.25,     -- 25% tolerance on target

  -- Status
  status          TEXT NOT NULL DEFAULT 'waiting'
                  CHECK (status IN ('waiting', 'matched', 'expired', 'cancelled')),
  matched_with_user_id UUID REFERENCES auth.users(id),
  matched_challenge_id UUID REFERENCES public.challenges(id),
  matched_at      TIMESTAMPTZ,

  -- Lifecycle
  expires_at      TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '24 hours'),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Only one active (waiting) entry per user
CREATE UNIQUE INDEX IF NOT EXISTS idx_queue_one_active_per_user
  ON public.challenge_queue (user_id)
  WHERE status = 'waiting';

-- Fast lookup for matching candidates
CREATE INDEX IF NOT EXISTS idx_queue_matching
  ON public.challenge_queue (metric, entry_fee_coins, skill_bracket, status)
  WHERE status = 'waiting';

-- ── 2. RLS ──────────────────────────────────────────────────────────────────

ALTER TABLE public.challenge_queue ENABLE ROW LEVEL SECURITY;

-- Users can read their own queue entries
CREATE POLICY "queue_own_read" ON public.challenge_queue
  FOR SELECT USING (auth.uid() = user_id);

-- Users can insert their own entries (EF handles the real logic, but
-- this allows the service_role insert to work when user_id matches)
CREATE POLICY "queue_own_insert" ON public.challenge_queue
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Users can cancel their own waiting entries
CREATE POLICY "queue_own_cancel" ON public.challenge_queue
  FOR UPDATE USING (auth.uid() = user_id AND status = 'waiting')
  WITH CHECK (status = 'cancelled');

-- ── 3. Auto-expire cron (reuse pg_cron) ─────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_expire_queue_entries()
RETURNS void AS $$
BEGIN
  UPDATE public.challenge_queue
  SET    status = 'expired', updated_at = now()
  WHERE  status = 'waiting'
  AND    expires_at < now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Schedule: every 5 minutes, expire stale queue entries
SELECT cron.schedule(
  'expire-matchmaking-queue',
  '*/5 * * * *',
  $$SELECT public.fn_expire_queue_entries()$$
);

-- ── 4. RPC: compute skill bracket from recent sessions ──────────────────────

CREATE OR REPLACE FUNCTION public.fn_compute_skill_bracket(p_user_id UUID)
RETURNS TEXT AS $$
DECLARE
  v_avg_pace NUMERIC;
BEGIN
  -- Average pace (seconds per km) from last 10 verified sessions with distance > 1km
  SELECT AVG(
    CASE WHEN total_distance_m > 0
         THEN (duration_ms / 1000.0) / (total_distance_m / 1000.0)
         ELSE NULL
    END
  )
  INTO v_avg_pace
  FROM (
    SELECT total_distance_m, duration_ms
    FROM   public.sessions
    WHERE  user_id = p_user_id
    AND    is_verified = true
    AND    total_distance_m >= 1000
    ORDER  BY created_at DESC
    LIMIT  10
  ) recent;

  IF v_avg_pace IS NULL THEN
    RETURN 'beginner';
  END IF;

  -- Pace thresholds (seconds per km)
  -- Elite:        < 4:00/km (240s)
  -- Advanced:     4:00-5:00/km (240-300s)
  -- Intermediate: 5:00-6:30/km (300-390s)
  -- Beginner:     > 6:30/km (390s+)
  RETURN CASE
    WHEN v_avg_pace < 240  THEN 'elite'
    WHEN v_avg_pace < 300  THEN 'advanced'
    WHEN v_avg_pace < 390  THEN 'intermediate'
    ELSE 'beginner'
  END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ── 5. RPC: atomic matchmake attempt ────────────────────────────────────────
-- Called by the Edge Function. Tries to find a compatible waiting entry and
-- locks it atomically. Returns the matched row or NULL.

CREATE OR REPLACE FUNCTION public.fn_try_match(
  p_user_id         UUID,
  p_metric          TEXT,
  p_target          NUMERIC,
  p_entry_fee_coins INT,
  p_window_ms       BIGINT,
  p_skill_bracket   TEXT
)
RETURNS TABLE (
  queue_id         UUID,
  matched_user_id  UUID,
  matched_target   NUMERIC,
  matched_window_ms BIGINT
) AS $$
DECLARE
  v_match RECORD;
BEGIN
  -- Find best match: same metric, same stake, compatible skill, not expired
  -- Adjacent skill brackets are allowed (beginner↔intermediate, etc.)
  SELECT cq.id, cq.user_id, cq.target, cq.window_ms
  INTO   v_match
  FROM   public.challenge_queue cq
  WHERE  cq.status = 'waiting'
  AND    cq.metric = p_metric
  AND    cq.entry_fee_coins = p_entry_fee_coins
  AND    cq.expires_at > now()
  AND    cq.user_id != p_user_id
  -- Skill compatibility: same or adjacent bracket
  AND    (
    cq.skill_bracket = p_skill_bracket
    OR (p_skill_bracket = 'beginner'      AND cq.skill_bracket = 'intermediate')
    OR (p_skill_bracket = 'intermediate'  AND cq.skill_bracket IN ('beginner', 'advanced'))
    OR (p_skill_bracket = 'advanced'      AND cq.skill_bracket IN ('intermediate', 'elite'))
    OR (p_skill_bracket = 'elite'         AND cq.skill_bracket = 'advanced')
  )
  -- Target compatibility: both null, or within 25% tolerance
  AND    (
    (p_target IS NULL AND cq.target IS NULL)
    OR (
      p_target IS NOT NULL AND cq.target IS NOT NULL
      AND ABS(p_target - cq.target) <= GREATEST(p_target, cq.target) * cq.target_tolerance_pct
    )
  )
  ORDER BY
    -- Prefer exact skill match over adjacent
    CASE WHEN cq.skill_bracket = p_skill_bracket THEN 0 ELSE 1 END,
    -- FIFO: oldest waiting entry first
    cq.created_at ASC
  LIMIT 1
  FOR UPDATE SKIP LOCKED;

  IF v_match IS NULL THEN
    RETURN;
  END IF;

  -- Mark matched entry
  UPDATE public.challenge_queue
  SET    status = 'matched',
         matched_with_user_id = p_user_id,
         matched_at = now(),
         updated_at = now()
  WHERE  id = v_match.id;

  queue_id := v_match.id;
  matched_user_id := v_match.user_id;
  matched_target := v_match.target;
  matched_window_ms := v_match.window_ms;
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
