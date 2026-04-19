-- ============================================================================
-- L12-02 — Redistribute thundering herd (02:00–04:00 UTC overlap)
-- ============================================================================
--
-- Pre-migration schedule (audit finding L12-02):
--
--   00:00 02:00 UTC daily   clearing-cron
--   00:00 03:00 UTC daily   eval-verification-cron
--   00:00 03:00 UTC SUN     archive-old-sessions   ← collides with eval-verification on Sundays
--   00:00 04:00 UTC SUN     archive-old-ledger
--   00:00 03:00 UTC day-1   coin_ledger_ensure_partition_monthly  ← collides on day-1 of month
--
-- Risk: when the Sunday-3am window fires both eval-verification AND
-- archive-old-sessions simultaneously, DB CPU saturates, the portal
-- session-write path queues, and the user opening the app at 03:01
-- on Sunday morning sees a 10s spinner. On a Sunday that is the 1st
-- of the month, a third job (partition-monthly DDL) joins the herd
-- and we've seen `pg_locks` saturation in the staging mirror.
--
-- Post-migration schedule:
--
--   00:00 02:00 UTC daily   clearing-cron                          (unchanged)
--   00:15 03:00 UTC daily   eval-verification-cron                  (+15min)
--   00:45 03:00 UTC SUN     archive-old-sessions                    (+45min)
--   00:30 04:00 UTC daily   reconcile-wallets-daily                 (added by L12-01 — see next mig)
--   00:15 05:00 UTC SUN     archive-old-ledger                      (+1h15m)
--   00:30 05:00 UTC day-1   coin_ledger_ensure_partition_monthly    (+2h30m, off the cluster)
--
-- Minimum spacing achieved: 15 minutes (clearing → eval-verification
-- → archive-old-sessions). The audit recommends ≥15min as the floor;
-- our jobs are bounded at <5min in steady-state per current Sentry
-- traces, so 15min gives 3× headroom.
--
-- Each unschedule + reschedule is wrapped in BEGIN/EXCEPTION blocks
-- so re-running the migration is safe (no-op if pg_cron is absent
-- in local dev, idempotent if it's present).

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE '[L12-02] pg_cron not installed; skipping reschedule';
    RETURN;
  END IF;

  -- ─── eval-verification-cron: 0 3 → 15 3 ───────────────────────────────────
  --
  -- The HTTP body is preserved bit-for-bit from
  -- 20260224000004_verification_cron.sql so behaviour is unchanged
  -- aside from the firing minute.
  BEGIN PERFORM cron.unschedule('eval-verification-cron');
  EXCEPTION WHEN OTHERS THEN NULL; END;

  PERFORM cron.schedule(
    'eval-verification-cron',
    '15 3 * * *',
    $cron$
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
    $cron$
  );

  -- ─── archive-old-sessions: 0 3 SUN → 45 3 SUN ────────────────────────────
  BEGIN PERFORM cron.unschedule('archive-old-sessions');
  EXCEPTION WHEN OTHERS THEN NULL; END;

  PERFORM cron.schedule(
    'archive-old-sessions',
    '45 3 * * 0',
    $cron$ SELECT public.fn_archive_old_sessions(); $cron$
  );

  -- ─── archive-old-ledger: 0 4 SUN → 15 5 SUN ──────────────────────────────
  BEGIN PERFORM cron.unschedule('archive-old-ledger');
  EXCEPTION WHEN OTHERS THEN NULL; END;

  PERFORM cron.schedule(
    'archive-old-ledger',
    '15 5 * * 0',
    $cron$ SELECT public.fn_archive_old_ledger(); $cron$
  );

  -- ─── coin_ledger_ensure_partition_monthly: 0 3 day-1 → 30 5 day-1 ────────
  BEGIN PERFORM cron.unschedule('coin_ledger_ensure_partition_monthly');
  EXCEPTION WHEN OTHERS THEN NULL; END;

  PERFORM cron.schedule(
    'coin_ledger_ensure_partition_monthly',
    '30 5 1 * *',
    $cron$
      SELECT public.coin_ledger_ensure_partition((CURRENT_DATE + INTERVAL '2 months')::date);
    $cron$
  );

  RAISE NOTICE '[L12-02] redistributed 4 cron jobs (eval-verification, archive-old-sessions, archive-old-ledger, coin_ledger_partition_monthly) to break the 03:00–04:00 UTC herd';
END$$;
