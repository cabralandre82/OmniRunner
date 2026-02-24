-- ============================================================================
-- Omni Runner — Schedule eval-verification-cron Edge Function via pg_cron
-- Date: 2026-02-24
-- Sprint: Phase 22.3.0 (Evaluation Trigger)
-- Origin: Periodic re-evaluation of athlete verification status
-- ============================================================================
-- Runs daily at 03:00 UTC.
-- Re-evaluates athletes who:
--   - Are in CALIBRATING, MONITORED, or DOWNGRADED status
--   - Have recent integrity flags (last 30 days)
--   - Have not been evaluated in the last 24 hours
-- Uses the same eval_athlete_verification RPC (idempotent, SECURITY DEFINER).
-- ZERO override: no manual status setting, no admin bypass.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

SELECT cron.schedule(
  'eval-verification-cron',
  '0 3 * * *',
  $$
  SELECT extensions.http(
    (
      'POST',
      current_setting('app.settings.supabase_url') || '/functions/v1/eval-verification-cron',
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
