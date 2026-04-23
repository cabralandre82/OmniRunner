# Clearing-Cron Cutoff Runbook

> **Audit ref:** L12-08 · **Owner:** cfo/coo · **Severity:** 🟠 High
> **Migration:** `supabase/migrations/20260421270000_l12_08_clearing_cron_deterministic_cutoff.sql`
> **Integration tests:** `tools/test_l12_08_clearing_cron_deterministic_cutoff.ts`
> **Related:** EDGE_RETRY_WRAPPER_RUNBOOK.md · CLEARING_STUCK_RUNBOOK.md · CRON_HEALTH_RUNBOOK.md

---

## 1. Summary

The nightly `clearing-cron` job consolidates `coin_ledger` entries
with `reason='challenge_prize_pending'` into `clearing_cases` groups.
Before L12-08 it fired at **02:00 UTC = 23:00 BRT** — *before* the
Brazilian civil day ends — and the aggregator used `now()` as the
upper cutoff, so:

1. Ledger entries created between 23:00-24:00 BRT on day D did *not*
   show up in day D's clearing run; they showed up on day D+1.
2. pg_cron jitter (±seconds to minutes) meant the exact cutoff was
   non-deterministic — an entry at 01:59:59 UTC could be in one run,
   an entry at 02:00:05 UTC could be in the next.

L12-08 fixes both by:

* Rescheduling the cron to `15 3 * * *` (= **00:15 BRT**, 15 min
  after midnight BRT, offset to avoid the 03:00 UTC thundering herd
  from L12-02).
* Introducing `public.fn_clearing_cutoff_utc(p_timezone, p_as_of)`
  which returns the start of today *in the given TZ* as a UTC
  timestamptz.
* Rewriting `fn_invoke_clearing_cron_safe` to:
  - pre-compute the cutoff with `America/Sao_Paulo` as default TZ,
  - pass `{ cutoff_utc, timezone, run_kind }` in the Edge Function
    body (contract, even though the Edge Function itself is
    implemented separately),
  - persist the cutoff in `cron_run_state.last_meta.cutoff_utc` so
    ops can audit "what window did last night's run close?".

The aggregator contract is now:

```sql
-- Always use the canonical cutoff; do NOT use `now()` directly.
WITH cutoff AS (
  SELECT public.fn_clearing_cutoff_utc('America/Sao_Paulo') AS ts
)
SELECT ...
  FROM public.coin_ledger
 WHERE reason = 'challenge_prize_pending'
   AND created_at < (SELECT ts FROM cutoff);
```

---

## 2. Normal operation

### 2.1 Dashboard checks

```sql
-- Last successful run + the exact cutoff it used.
SELECT name, last_status, last_started_at, last_finished_at,
       last_meta->>'cutoff_utc' AS cutoff_utc,
       last_meta->>'timezone'   AS tz,
       last_error
  FROM public.cron_run_state
 WHERE name = 'clearing-cron';

-- Retry trail for the last week (fn_invoke_edge_with_retry audit).
SELECT started_at, attempt, http_status,
       substring(error, 1, 120) AS err
  FROM public.cron_edge_retry_attempts
 WHERE job_name = 'clearing-cron'
   AND started_at > now() - interval '14 days'
 ORDER BY started_at DESC
 LIMIT 30;

-- Pending-prize inventory (what WILL be aggregated in the next run).
SELECT count(*)                     AS rows,
       min(created_at)              AS earliest,
       max(created_at)              AS latest,
       public.fn_clearing_cutoff_utc('America/Sao_Paulo') AS next_cutoff
  FROM public.coin_ledger
 WHERE reason = 'challenge_prize_pending'
   AND created_at < public.fn_clearing_cutoff_utc('America/Sao_Paulo');
```

### 2.2 Healthy shape

| Signal | Expected |
| --- | --- |
| Run time | Every day at ~03:15 UTC (00:15 BRT), duration < 60 s for typical loads |
| `cutoff_utc` | Equals start of current BRT day, i.e. `YYYY-MM-DD 03:00:00+00` during BRT (UTC-3) |
| `last_status` | `completed` on >95% of runs over 30 days |
| Retry count | 1 attempt typical; 2-3 during network blips is fine |

---

## 3. Operational scenarios

### 3.1 "This week's clearing report is missing my Friday burn"

1. Check whether the burn actually has `reason='challenge_prize_pending'`:
   ```sql
   SELECT id, user_id, delta_coins, reason, ref_id, created_at
     FROM public.coin_ledger
    WHERE user_id = '<user>'
      AND created_at > '<friday_start_utc>'
    ORDER BY created_at DESC LIMIT 20;
   ```
   Burns with `reason='challenge_prize_pending'` are the only rows
   aggregated by clearing-cron. Other reasons (e.g.,
   `challenge_team_won`) are out of scope.
2. Determine which BRT day that burn belongs to:
   ```sql
   SELECT created_at,
          (created_at AT TIME ZONE 'America/Sao_Paulo') AS brt_wall
     FROM public.coin_ledger
    WHERE id = '<ledger_id>';
   ```
3. Determine whether it fell BEFORE or AFTER the cutoff used by the
   relevant clearing-cron run:
   ```sql
   SELECT last_started_at, last_meta->>'cutoff_utc'
     FROM public.cron_run_state
    WHERE name = 'clearing-cron'
    -- or look at the historical audit if you keep one
   ;
   ```
   If the burn's `created_at` ≥ `cutoff_utc`, it will be consolidated
   in the NEXT run — this is expected behaviour post-L12-08.

### 3.2 A run failed

1. Confirm via `cron_run_state`:
   ```sql
   SELECT last_started_at, last_finished_at, last_status,
          last_error, last_meta
     FROM public.cron_run_state
    WHERE name = 'clearing-cron';
   ```
2. Check the retry audit:
   ```sql
   SELECT attempt, http_status, started_at, completed_at, error
     FROM public.cron_edge_retry_attempts
    WHERE job_name = 'clearing-cron'
      AND started_at > now() - interval '24 hours'
    ORDER BY started_at DESC;
   ```
3. Common failures:
   * **`http_extension_missing` (skipped)** — sandbox environment,
     ignore.
   * **DNS / 5xx** — retry wrapper already retried 3× with
     exponential backoff and emitted a critical `cron_health_alerts`
     row. Investigate the Edge Function logs (separate tool) and
     rerun:
     ```sql
     SELECT public.fn_invoke_clearing_cron_safe();
     ```
     Manual reruns respect the advisory lock and `cron_run_state`
     idempotency.

### 3.3 Ad-hoc replay of a specific day

If you need to replay the aggregation for a specific BRT day (e.g.,
to investigate a dispute), compute the two cutoffs manually:

```sql
-- Window = [prev_day_start_brt, target_day_start_brt)
SELECT public.fn_clearing_cutoff_utc(
         'America/Sao_Paulo',
         '2026-04-20 17:00:00+00'::timestamptz) AS window_start,
       public.fn_clearing_cutoff_utc(
         'America/Sao_Paulo',
         '2026-04-21 17:00:00+00'::timestamptz) AS window_end;
```

Then pass those to the aggregator logic (Edge Function body or SQL
depending on the follow-up implementation). Because the cutoff is a
pure function of `p_as_of` and `p_timezone`, replays are fully
deterministic.

### 3.4 Changing the TZ

The TZ is currently hard-coded in `fn_invoke_clearing_cron_safe` as
`'America/Sao_Paulo'`. If the product expands to a non-BR primary
market, update the helper + re-run the migration. Do NOT change the
TZ mid-run — the `cutoff_utc` of an in-flight run would silently
switch day boundaries.

---

## 4. Tunables

| Parameter | Default | Notes |
| --- | --- | --- |
| Schedule | `15 3 * * *` | 00:15 BRT; 15 min offset avoids 03:00 UTC herd |
| Timezone | `America/Sao_Paulo` | Product is BR-first |
| `max_attempts` | 3 | L06-05 retry wrapper |
| `backoff_base_seconds` | 10 | L06-05 retry wrapper |
| L12-02 SLA (`expected_duration`) | 600 s | `cron_sla_thresholds` — unchanged by L12-08 |

---

## 5. Rollback

If the 00:15 BRT schedule causes unforeseen issues (e.g., the Edge
Function consumer turns out to require 02:00 UTC timing for some
contract reason), revert the cron:

```sql
SELECT cron.unschedule('clearing-cron');
SELECT cron.schedule(
  'clearing-cron',
  '0 2 * * *',
  $cron$ SELECT public.fn_invoke_clearing_cron_safe(); $cron$
);
```

The `fn_clearing_cutoff_utc` helper is additive and safe to leave
installed regardless of schedule.

---

## 6. Observability signals

* **`cron_health_alerts` with `kind='edge_invocation_failed_after_retries'`
  and `endpoint='clearing-cron'`** — Edge Function exhausted retries.
  CFO-side gets delayed payouts; investigate within 4 h SLA.
* **`cron_run_state.last_meta.cutoff_utc` not equal to start of BRT
  day** — bug in `fn_clearing_cutoff_utc` OR TZ changed unexpectedly.
  Compare with the helper's output at the same `p_as_of` to diagnose.
* **Pending-prize inventory growing (`count(*)` query in §2.1
  trending up week-over-week)** — the aggregator Edge Function is
  not draining what the cutoff exposes. Likely the Edge Function is
  consistently failing (see retry audit) or the cron is being
  throttled by overlap protection.

---

## 7. Related

* L12-01 — reconcile-wallets-daily cron
* L12-02 — cron herd redistribution (this job was moved out of 02:00 UTC)
* L12-03 — cron overlap protection (cron_run_state.last_meta carries the cutoff)
* L12-04 — cron SLA monitoring
* L12-06 — archive-old-sessions (same chunked-commit pattern used at scale)
* L12-07 — onboarding-nudge timezone (per-user TZ; clearing-cron uses a single product-level TZ)
* L06-05 — Edge Function retry wrapper
* CLEARING_STUCK_RUNBOOK — what to do when settlements hang
