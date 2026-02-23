-- ============================================================================
-- Lifecycle Cron — Scheduled jobs for championship and challenge transitions
-- ============================================================================
-- Requires pg_cron and pg_net extensions (available on Supabase hosted).
-- Runs lifecycle-cron EF every 5 minutes to handle:
--   - Championship open→active, active→completed
--   - Challenge settlement for expired active challenges
--   - Challenge expiration for stale pending challenges
-- ============================================================================

-- Enable extensions if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- Schedule lifecycle-cron every 5 minutes
SELECT cron.schedule(
  'lifecycle-cron',
  '*/5 * * * *',
  $$
  SELECT extensions.http(
    (
      'POST',
      current_setting('app.settings.supabase_url') || '/functions/v1/lifecycle-cron',
      ARRAY[
        extensions.http_header('Authorization', 'Bearer ' || current_setting('app.settings.service_role_key')),
        extensions.http_header('Content-Type', 'application/json')
      ],
      'application/json',
      '{}'
    )::extensions.http_request
  );
  $$
);
