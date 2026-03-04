-- Schedule the onboarding-nudge function to run daily at 10:00 UTC
-- Sends D0-D7 push notifications to new users.

SELECT cron.schedule(
  'onboarding-nudge-daily',
  '0 10 * * *',
  $$
  SELECT net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/onboarding-nudge',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
  $$
);
