-- ============================================================================
-- Omni Runner — Schedule clearing-cron Edge Function via pg_cron
-- Date: 2026-02-21
-- Sprint: Phase 97.2.0
-- Origin: Clearing aggregation + expiry
-- ============================================================================
-- Runs daily at 02:00 UTC.
-- Aggregates challenge_prize_pending ledger entries into clearing_cases
-- grouped by (week, losing_group → winning_group).
-- Also expires overdue clearing_cases past their 7-day deadline.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

SELECT cron.schedule(
  'clearing-cron',
  '0 2 * * *',
  $$
  SELECT extensions.http(
    (
      'POST',
      current_setting('app.settings.supabase_url') || '/functions/v1/clearing-cron',
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
