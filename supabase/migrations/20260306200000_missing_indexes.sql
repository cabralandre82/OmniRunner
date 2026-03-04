-- Performance indexes identified by audit (P2-4)
-- Missing indexes for commonly queried columns
-- All use CREATE INDEX IF NOT EXISTS for idempotency

BEGIN;

-- 1. coaching_workout_assignments — athlete workout lookups by date
CREATE INDEX IF NOT EXISTS idx_workout_assignments_athlete_date
  ON public.coaching_workout_assignments (athlete_user_id, scheduled_date);

-- 2. coaching_workout_assignments — template lookups
CREATE INDEX IF NOT EXISTS idx_workout_assignments_template
  ON public.coaching_workout_assignments (template_id);

-- 3. coaching_tp_sync — pending sync queries
CREATE INDEX IF NOT EXISTS idx_tp_sync_status
  ON public.coaching_tp_sync (sync_status);

-- 4. billing_events — dedup checks (purchase_id + event_type)
CREATE INDEX IF NOT EXISTS idx_billing_events_purchase_type
  ON public.billing_events (purchase_id, event_type);

-- 5. product_events — analytics queries (user_id + event_name)
CREATE INDEX IF NOT EXISTS idx_product_events_user_event
  ON public.product_events (user_id, event_name);

-- 6. coaching_device_links — device lookups by athlete and provider
CREATE INDEX IF NOT EXISTS idx_device_links_athlete_provider
  ON public.coaching_device_links (athlete_user_id, provider);

-- 7. strava_connections — user_id (PK provides implicit index; explicit for consistency)
CREATE INDEX IF NOT EXISTS idx_strava_connections_user
  ON public.strava_connections (user_id);

-- 8. challenge_participants — user challenge queries (may already exist from full_schema)
CREATE INDEX IF NOT EXISTS idx_challenge_participants_user_status
  ON public.challenge_participants (user_id, status);

-- 9. workout_delivery_items — athlete delivery queries (may already exist)
CREATE INDEX IF NOT EXISTS idx_delivery_items_athlete_status
  ON public.workout_delivery_items (athlete_user_id, status);

-- 10. session_journal_entries — user+session lookups
CREATE INDEX IF NOT EXISTS idx_session_journal_user_session
  ON public.session_journal_entries (user_id, session_id);

COMMIT;
