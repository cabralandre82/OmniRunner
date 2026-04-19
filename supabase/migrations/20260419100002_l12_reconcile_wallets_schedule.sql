-- ============================================================================
-- L12-01 — Schedule reconcile-wallets-daily
-- ============================================================================
--
-- The audit (L12-01) found that the `reconcile-wallets-cron` Edge
-- Function exists at `supabase/functions/reconcile-wallets-cron/`
-- and the underlying RPC `reconcile_all_wallets()` exists in
-- `20260227500000_wallet_reconcile_and_session_retention.sql:109`,
-- but no `cron.schedule` call ever ties them together. The result:
--
--   - Reconciliation never runs in production.
--   - Drift between `wallets.balance_coins` and
--     `SUM(coin_ledger.delta_coins)` accumulates indefinitely.
--   - Runbooks (CUSTODY_INCIDENT, CLEARING_STUCK) reference
--     `reconcile-wallets` as a defensive sweep that, in practice,
--     does not exist.
--
-- This migration registers the missing schedule. Time chosen
-- (04:30 UTC daily) is the gap engineered by the L12-02
-- redistribution (sits cleanly between eval-verification at 03:15
-- and archive-old-ledger at 05:15-Sun / partition-monthly at
-- 05:30-day-1).
--
-- Direct HTTP fire (no advisory-lock wrapper):
--
--   - daily cadence makes overlap effectively impossible (a single
--     reconcile pass over current production wallet count completes
--     in <30s based on staging traces);
--   - the underlying RPC is fully idempotent (drift correction is
--     `UPDATE wallets SET balance_coins = SUM(...)` — converges to
--     the same value regardless of how many concurrent runs); and
--   - the wrapper machinery from L12-03 is justified by the */5
--     cadence of the matchmaking/release/lifecycle jobs, not by
--     the reconciliation flow.
--
-- Authorization: service-role bearer in the Authorization header.
-- The Edge Function rejects any other token (constant-time compare)
-- so a leaked anon key cannot trigger reconciliation.

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE '[L12-01] pg_cron not installed; skipping schedule';
    RETURN;
  END IF;

  -- Defensive unschedule for re-applied migrations.
  BEGIN PERFORM cron.unschedule('reconcile-wallets-daily');
  EXCEPTION WHEN OTHERS THEN NULL; END;

  PERFORM cron.schedule(
    'reconcile-wallets-daily',
    '30 4 * * *',
    $cron$
    SELECT extensions.http(
      (
        'POST',
        current_setting('app.settings.supabase_url') || '/functions/v1/reconcile-wallets-cron',
        ARRAY[
          extensions.http_header('Authorization', 'Bearer ' || current_setting('app.settings.service_role_key')),
          extensions.http_header('Content-Type', 'application/json')
        ],
        'application/json',
        '{}'
      )::extensions.http_request
    );
    $cron$
  );

  -- Seed `cron_run_state` (from the L12-03 migration) so ops queries
  -- show the job as `never_run` immediately after rollout, instead
  -- of the row being missing entirely. The Edge Function will move
  -- it through `running → completed/failed` once it is enhanced to
  -- call the cron-state helpers (tracked separately).
  INSERT INTO public.cron_run_state(name, last_status)
  VALUES ('reconcile-wallets-daily', 'never_run')
  ON CONFLICT (name) DO NOTHING;

  RAISE NOTICE '[L12-01] scheduled reconcile-wallets-daily at 04:30 UTC';
END$$;
