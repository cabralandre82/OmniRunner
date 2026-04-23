# Archive-Old-Sessions Runbook

> **Audit ref:** L12-06 · **Owner:** coo · **Severity:** 🟠 High
> **Migration:** `supabase/migrations/20260421250000_l12_06_archive_sessions_chunked_commits.sql`
> **Edge Function:** `supabase/functions/archive-old-sessions/index.ts`
> **Integration tests:** `tools/test_l12_06_archive_sessions_chunked.ts`
> **Related:** DBA_BLOAT_AND_INDEX_RUNBOOK.md · EDGE_RETRY_WRAPPER_RUNBOOK.md · CRON_HEALTH_RUNBOOK.md

---

## 1. Summary

The weekly `archive-old-sessions` pg_cron job moves `public.sessions`
rows older than 6 months and with status IN (2, 3) into
`public.sessions_archive`. Before L12-06 the entire sweep ran inside a
single PL/pgSQL function, which meant:

* Every chunk's snapshot+locks were held for the duration of ALL
  chunks.
* Autovacuum could not reclaim dead tuples until the function returned.
* A mid-run kill (Supabase upgrade window, connection reset) rolled
  back everything.
* `cron_run_state.last_finished_at` (L12-03) only updated after the
  whole cycle, so the operator dashboard saw "in_progress 35 min"
  instead of per-chunk ticks.

L12-06 extracts the per-chunk work into
`public.fn_archive_sessions_chunk(batch_size, cutoff_months)` and
drives it from an Edge Function
(`supabase/functions/archive-old-sessions/index.ts`). Each RPC
round-trip is a separate Postgres transaction → COMMIT between
chunks, autovacuum can start between chunks, mid-run kills preserve
partial progress.

The pg_cron schedule remains `'45 3 * * 0'` (Sundays 03:45 UTC) and
now points at `public.fn_invoke_archive_sessions_safe()`, which
integrates with:

* `fn_cron_mark_started`/`fn_cron_mark_completed`/`fn_cron_mark_failed`
  (L12-03 lifecycle tracking),
* `fn_invoke_edge_with_retry` (L06-05 pg_net retry + cron_health_alerts
  integration),
* an SQL fallback (the `fn_archive_old_sessions` shim) when the Edge
  Function is unreachable or the `http` extension is absent.

---

## 2. Normal operation

### 2.1 Dashboard checks

```sql
-- Last cycle status + duration.
SELECT name, last_status, last_started_at, last_finished_at,
       last_meta->>'rows_moved_total' AS rows_moved,
       last_meta->>'batches'          AS batches,
       last_meta->>'duration_ms'      AS duration_ms,
       last_meta->>'terminated_by'    AS terminated_by
  FROM public.cron_run_state
 WHERE name = 'archive-old-sessions';

-- How many rows are currently waiting to be archived?
SELECT public.fn_archive_sessions_pending_count(6) AS pending_rows;

-- Retry attempt audit for the last week.
SELECT attempt, http_status, completed_at - started_at AS duration,
       substring(error, 1, 80) AS err_snippet
  FROM public.cron_edge_retry_attempts
 WHERE job_name = 'archive-old-sessions'
   AND started_at > now() - interval '14 days'
 ORDER BY started_at DESC
 LIMIT 30;
```

### 2.2 Healthy shape

| Signal | Expected |
| --- | --- |
| `terminated_by` | `no_more_pending` in steady state; `max_batches` or `max_duration` is acceptable if the table grew a lot or the sweep caught up after an outage. Multiple consecutive `max_duration` → backlog is growing. |
| `pending_rows` post-run | Zero, or <= `max_batches * batch_size` (≤20k by default). |
| `http_status` in retry audit | `200` on the first attempt. Occasional `500`/`504` retried is normal. |
| Duration | 1-10 min typical. >8 min hits the Edge Function's `max_duration_ms` and forces `terminated_by = max_duration`. |
| Autovacuum on `sessions` | Catches up within ~24 h of the Sunday run (autovacuum tuning from L19-02 = `scale_factor = 0.05`). |

---

## 3. Operational scenarios

### 3.1 The backlog is growing (`pending_rows` climbing week over week)

1. Check the last runs:
   ```sql
   SELECT last_started_at, last_finished_at,
          last_meta->>'terminated_by' AS terminated_by,
          last_meta->>'rows_moved_total' AS rows_moved
     FROM public.cron_run_state
    WHERE name = 'archive-old-sessions';
   ```
2. If `terminated_by` is consistently `max_duration` or `max_batches`,
   the default budget (40 batches × 500 rows = 20k rows; 8 min) is not
   enough. Options:
   * Temporarily raise the budget for the next run:
     ```sql
     SELECT net.http_post(
       url     := current_setting('app.settings.supabase_url', true) || 'functions/v1/archive-old-sessions',
       headers := jsonb_build_object(
                    'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true),
                    'Content-Type',  'application/json'
                  ),
       body    := jsonb_build_object(
                    'batch_size',      500,
                    'cutoff_months',   6,
                    'max_batches',     200,
                    'max_duration_ms', 540000
                  )
     );
     ```
     `max_duration_ms` maxes at 540 000 (9 min) to stay well within
     Supabase's 10-min Edge Function ceiling.
   * Schedule an ad-hoc extra run mid-week (pg_cron allows multiple
     schedules per job name only via different names; prefer manual
     invocation via the snippet above).
3. If the backlog is >1 M rows, promote to a follow-up ticket to
   partition `public.sessions` by `start_time_ms` (tracked as Wave 2
   candidate, mirrors L19-01 for `coin_ledger`).

### 3.2 A run failed (`last_status = 'failed'`)

1. Inspect the failure:
   ```sql
   SELECT last_started_at, last_finished_at, last_error, last_meta
     FROM public.cron_run_state
    WHERE name = 'archive-old-sessions';

   SELECT started_at, attempt, http_status, substring(error, 1, 200)
     FROM public.cron_edge_retry_attempts
    WHERE job_name = 'archive-old-sessions'
      AND started_at > now() - interval '7 days'
    ORDER BY started_at DESC
    LIMIT 10;
   ```
2. If the failure is on the Edge Function side (`http_status` >=500),
   check the Edge Function logs for stack traces. Most common:
   * **`CHUNK_ERROR`** with error containing `lock_not_available` →
     portal contention on `sessions`. Expected occasionally; the
     next week's run will pick up where this one left off.
   * **`CONFIG_ERROR`** → `SUPABASE_URL` / `SERVICE_ROLE_KEY`
     secrets missing; fix in the Supabase dashboard.
3. If the SQL fallback shim ran, `last_meta.mode = 'sql_fallback'`.
   That means the Edge Function was unreachable but archival still
   moved forward (just without COMMIT-between-chunks). Investigate
   the Edge Function separately; do NOT retry the archive — it
   already drained what it could.

### 3.3 Ad-hoc archival (operator)

Prefer the Edge Function so you still get chunked COMMITs:

```bash
curl -X POST "$SUPABASE_URL/functions/v1/archive-old-sessions" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"batch_size": 500, "cutoff_months": 6, "max_batches": 40, "max_duration_ms": 480000}'
```

Response shape:
```json
{
  "ok": true,
  "data": {
    "rows_moved_total": 4283,
    "batches": 9,
    "duration_ms": 3210,
    "terminated_by": "no_more_pending",
    "cutoff_ms": 1744732800000
  }
}
```

If you're in psql with superuser and want to skip HTTP:

```sql
SELECT public.fn_archive_old_sessions();
-- returns INTEGER (rows moved). Single outer transaction → no
-- COMMIT between chunks; use only for small catch-up runs.
```

### 3.4 Aborting a runaway run

The default budget caps wall-clock at 8 min and batches at 40. If
you still need to abort:

1. Identify the backend:
   ```sql
   SELECT pid, query_start, now() - query_start AS duration, state, query
     FROM pg_stat_activity
    WHERE query ILIKE '%fn_archive_sessions_chunk%'
       OR query ILIKE '%sessions_archive%';
   ```
2. Cancel (soft) or terminate (hard):
   ```sql
   SELECT pg_cancel_backend(<pid>);     -- polite
   SELECT pg_terminate_backend(<pid>);  -- forceful
   ```
3. Because each chunk is its own transaction, already-archived rows
   stay archived. Nothing to clean up.

---

## 4. Tunables

| Parameter | Default | Range | Source |
| --- | --- | --- | --- |
| `p_batch_size` | 500 | 1..10000 | chunk RPC |
| `p_cutoff_months` | 6 | 1..120 | chunk RPC |
| `max_batches` | 40 | 1..500 | Edge body |
| `max_duration_ms` | 480 000 (8 min) | 1 000..540 000 | Edge body |
| `p_max_attempts` | 3 | 1..10 | L06-05 retry wrapper |
| `p_backoff_base_seconds` | 15 (this job) | 1..60 | L06-05 retry wrapper |
| Schedule | `45 3 * * 0` (Sun 03:45 UTC) | cron | pg_cron job `archive-old-sessions` |

The schedule was picked in L12-02 to avoid the 03:00 UTC herd. If you
change it, also review `cron_sla_thresholds` (L12-04) which expects
`expected_duration=600, max_runtime=1800` for this job.

---

## 5. Rollback

If the Edge Function has a bug, revert the cron schedule to call the
SQL shim directly:

```sql
SELECT cron.unschedule('archive-old-sessions');

SELECT cron.schedule(
  'archive-old-sessions',
  '45 3 * * 0',
  $cron$ SELECT public.fn_archive_old_sessions(); $cron$
);
```

That regresses to L19-02 behaviour (chunked inside one transaction)
but keeps archival moving. Re-apply L12-06 after the Edge Function
fix lands.

`fn_archive_sessions_chunk` and `fn_archive_sessions_pending_count`
are safe to leave installed — they are additive and don't affect
anything until called.

---

## 6. Observability signals

* **`cron_health_alerts` with `kind = 'edge_invocation_failed_after_retries'`
  and `endpoint = 'archive-old-sessions'`** — Edge Function exhausted
  retries. Investigate via `cron_edge_retry_attempts`; the SQL
  fallback will have taken over.
* **`cron_run_state.last_status = 'failed'`** — the safe wrapper
  itself errored. Check `last_error`.
* **`fn_archive_sessions_pending_count()` climbing > 100 k** — backlog
  accumulating; see §3.1.
* **Autovacuum log spam for `public.sessions`** — chunked COMMITs are
  doing their job; autovacuum is now reclaiming tuples between
  chunks. Expected, not a problem.

---

## 7. Related

* L12-01 — reconcile-wallets-daily cron
* L12-02 — cron herd redistribution
* L12-03 — cron overlap protection (cron_run_state)
* L12-04 — cron SLA monitoring
* L06-05 — Edge Function retry wrapper
* L19-01 — coin_ledger monthly partitioning (partition-detach archive)
* L19-02 — archive via partition detach (previous iteration of this job)
