-- ============================================================================
-- Omni Runner — pg_cron schedule for auto-topup-check
-- Date: 2026-02-21
-- Sprint: 35.1.3
-- Origin: DECISAO 050 — Auto Top-Up hourly sweep
-- ============================================================================
-- Uses pg_cron + pg_net to invoke the auto-topup-cron Edge Function
-- every hour.  The Edge Function iterates over all enabled groups and
-- delegates to auto-topup-check for each.
--
-- SETUP (per environment — run once manually):
--   ALTER DATABASE postgres SET app.supabase_url = 'https://<ref>.supabase.co';
--   ALTER DATABASE postgres SET app.service_role_key = 'eyJ...';
-- These are NOT stored in the migration for security.
-- ============================================================================

-- Extensions (already available in Supabase, ensure enabled)
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Helper function: pg_cron calls this, it invokes the Edge Function via HTTP
CREATE OR REPLACE FUNCTION public.fn_invoke_auto_topup_cron()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_url  TEXT;
  v_key  TEXT;
BEGIN
  v_url := current_setting('app.supabase_url', true);
  v_key := current_setting('app.service_role_key', true);

  IF v_url IS NULL OR v_key IS NULL THEN
    RAISE LOG '[auto-topup-cron] skipped: app.supabase_url or app.service_role_key not configured';
    RETURN;
  END IF;

  PERFORM net.http_post(
    url     := v_url || '/functions/v1/auto-topup-cron',
    body    := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_key
    )
  );
END;
$$;

COMMENT ON FUNCTION public.fn_invoke_auto_topup_cron IS
  'pg_cron helper: fires auto-topup-cron Edge Function via pg_net. '
  'Requires app.supabase_url and app.service_role_key database settings.';

-- Schedule: every hour at minute 0
SELECT cron.schedule(
  'auto-topup-hourly',
  '0 * * * *',
  'SELECT public.fn_invoke_auto_topup_cron()'
);
