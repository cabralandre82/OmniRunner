-- Schedule the onboarding-nudge function to run daily at 10:00 UTC
-- Sends D0-D7 push notifications to new users.

DO $$
BEGIN
  PERFORM cron.schedule(
    'onboarding-nudge-daily',
    '0 10 * * *',
    $cron$
    SELECT net.http_post(
      url := current_setting('app.settings.supabase_url') || '/functions/v1/onboarding-nudge',
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
        'Content-Type', 'application/json'
      ),
      body := '{}'::jsonb
    );
    $cron$
  );
EXCEPTION WHEN undefined_function THEN
  RAISE NOTICE 'pg_cron not available, skipping onboarding nudge schedule';
WHEN OTHERS THEN
  RAISE NOTICE 'Could not schedule onboarding nudge: %', SQLERRM;
END $$;
