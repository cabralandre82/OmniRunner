# Sessions time-series index runbook

> Finding: [L08-03](../audit/findings/L08-03-sem-indice-de-analytics-time-series-em-sessions.md)
> Migration: [`20260421330000_l08_03_sessions_time_series_index.sql`](../../supabase/migrations/20260421330000_l08_03_sessions_time_series_index.sql)
> Scope: DB (analytics/dashboards) · Owner: platform-data

## 1. TL;DR

Dashboards that scan `public.sessions` by *time* across **all** users (CDO
realtime, staff funnel, anti-cheat anomaly sweep) were falling back to a
Seq Scan because the only indexes on `sessions` were `(user_id, ...)`
composites.

**Fix** adds two indexes (via `ADD INDEX IF NOT EXISTS`):

1. **BRIN** on `start_time_ms` — tiny (~8 KiB/1M rows), perfect for
   wide-window range scans (`start_time_ms BETWEEN $lo AND $hi`).
2. **Partial btree** on `(status, start_time_ms DESC) WHERE status >= 3`
   — for "last N finalized sessions across all users" and anti-cheat
   recent-activity queries where the window is narrow and the coherence
   invariant (L08-04) ensures `moving_ms > 0` on hits.

Both are created by migration `20260421330000_l08_03_sessions_time_series_index.sql`,
enforced in CI by `npm run audit:sessions-time-series-index`, and
observable via `SELECT public.fn_sessions_has_time_series_indexes();`.

## 2. When to use which index

| Query shape                                                                                      | Best index                              | Why                                                     |
| ------------------------------------------------------------------------------------------------ | --------------------------------------- | ------------------------------------------------------- |
| `WHERE user_id=$u ORDER BY start_time_ms DESC LIMIT N` (feed, profile, mobile)                   | `idx_sessions_user` (already existed)   | Leading col is `user_id`; tight composite.              |
| `WHERE start_time_ms BETWEEN $lo AND $hi` (wide, hours/days; all users; dashboard refresh tick) | `idx_sessions_start_time_brin`          | BRIN prunes heap ranges cheaply.                        |
| `WHERE status>=3 AND start_time_ms>$t ORDER BY start_time_ms DESC LIMIT N` (last N finalized) | `idx_sessions_status_start_time` (partial btree) | Column order matches sort/filter; predicate bounds heap. |
| `WHERE status>=3 AND user_id=$u ...`                                                             | `idx_sessions_status` (already existed) | Leading col is `user_id`.                               |

Call sites as of 2026-04-21:

* Portal dashboards `portal/src/app/api/platform/dashboard/*` → range scans,
  pick up BRIN.
* `fn_compute_kpis_batch` (run from `lifecycle-cron`) → per-user, uses
  `idx_sessions_user`.
* Anti-cheat sweep `fn_check_recent_anomalies` → narrow window, will use
  the partial btree.

## 3. Invariant and detection

```sql
SELECT public.fn_sessions_has_time_series_indexes(); -- boolean
SELECT public.fn_sessions_assert_time_series_indexes(); -- raises P0010 if drift
```

CI gate (`npm run audit:sessions-time-series-index`) runs
`fn_sessions_assert_time_series_indexes()` and fails the pipeline if
either index is missing or has drifted to a different access method /
predicate.

Ad-hoc probe for operators:

```sql
SELECT
  c.relname AS indexname,
  am.amname AS method,
  pg_size_pretty(pg_relation_size(c.oid)) AS size,
  pg_get_indexdef(i.indexrelid) AS def,
  pg_get_expr(i.indpred, i.indrelid) AS predicate
FROM pg_index i
JOIN pg_class c  ON c.oid = i.indexrelid
JOIN pg_class t  ON t.oid = i.indrelid
JOIN pg_am    am ON am.oid = c.relam
WHERE t.relname = 'sessions'
ORDER BY c.relname;
```

Healthy shape:

| indexname                          | method | approx size (100k rows) | notes                                       |
| ---------------------------------- | ------ | ----------------------- | ------------------------------------------- |
| `idx_sessions_start_time_brin`     | brin   | tens of KiB             | `pages_per_range = 32`                      |
| `idx_sessions_status_start_time`   | btree  | ~few MiB                | `WHERE status >= 3`                         |
| `idx_sessions_user`                | btree  | ~few MiB                | `(user_id, start_time_ms DESC)` — existing  |
| `idx_sessions_status`              | btree  | ~few MiB                | `(user_id, status)` — existing              |
| `idx_sessions_verified`            | btree  | ~few MiB                | `(user_id) WHERE is_verified = true`        |

## 4. Playbook — applying or rebuilding in production

### 4.1 Fresh apply (Supabase CLI)

```bash
supabase db push
# self-test DO block runs at COMMIT and confirms both indexes + the
# partial btree predicate.
```

Local cost (fresh DB): ~50 ms. Production on a 50M-row sessions table:
**several minutes** with an `AccessExclusiveLock` because
`CREATE INDEX` (non-concurrent) inside this migration. DO NOT ship
during peak hours.

### 4.2 Out-of-band `CREATE INDEX CONCURRENTLY` (recommended for prod)

If `sessions` is > 5M rows:

1. **Skip the migration** in prod (copy only the helper functions if you
   want CI to stay green) and run the two index creations manually:

   ```bash
   psql "$DATABASE_URL" <<'SQL'
   -- NOTE: run each CREATE as its own statement; CONCURRENTLY
   -- cannot run inside a transaction block.
   CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sessions_start_time_brin
     ON public.sessions USING BRIN (start_time_ms)
     WITH (pages_per_range = 32);

   CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sessions_status_start_time
     ON public.sessions (status, start_time_ms DESC)
     WHERE status >= 3;
   SQL
   ```

2. Verify `pg_index.indisvalid = true` for both (`CONCURRENTLY` leaves
   `indisvalid=false` on failure; drop + recreate).
3. Apply the migration (`supabase db push`). The `CREATE INDEX IF NOT
   EXISTS` becomes a no-op; the helper functions + CI guard get
   installed; the self-test DO block validates everything.

### 4.3 Rebuild after bloat

```sql
-- Background rebuild (PG 12+) — no AccessExclusiveLock.
REINDEX INDEX CONCURRENTLY public.idx_sessions_start_time_brin;
REINDEX INDEX CONCURRENTLY public.idx_sessions_status_start_time;
```

## 5. Tuning

* `pages_per_range = 32` is a good default for tables receiving ~1k
  inserts/minute. For very high ingest (> 10k/min) consider `16` for
  tighter min/max granularity at the cost of a slightly larger index.
* `BRIN` auto-summarises new ranges on INSERT starting in PG 15. On
  older PG, schedule `SELECT brin_summarize_new_values('public.idx_sessions_start_time_brin'::regclass);`
  hourly (e.g., via `pg_cron`).

## 6. Rollback

```sql
BEGIN;
DROP INDEX IF EXISTS public.idx_sessions_start_time_brin;
DROP INDEX IF EXISTS public.idx_sessions_status_start_time;
DROP FUNCTION IF EXISTS public.fn_sessions_assert_time_series_indexes();
DROP FUNCTION IF EXISTS public.fn_sessions_has_time_series_indexes();
COMMIT;
```

CI (`npm run audit:sessions-time-series-index`) will turn red
immediately — that's intentional; do not rollback unless you have a
replacement plan.

## 7. Observability

Watch these in the dashboard:

* `pg_stat_user_indexes.idx_scan` on both indexes — should climb after
  every dashboard refresh tick.
* `pg_stat_user_indexes.idx_tup_fetch` on `idx_sessions_start_time_brin`
  — tells you BRIN is pruning effectively (low ratio = good).
* Slow-query log: any `sessions` query > 500 ms without an
  `idx_sessions_*` index in its plan → investigate.

## 8. Cross-refs

* L08-04 (coherence CHECK) — predicate `status >= 3` assumes L08-04
  invariant; do not drop L08-04 without revisiting this finding.
* L19-04 (duplicate index detector) — `fn_find_duplicate_indexes` will
  flag drift if someone later adds a redundant `idx_sessions_*` over
  `(start_time_ms)`.
* L19-08 (CHECK constraint naming) — naming convention for helpers
  follows `fn_<subject>_(has|assert)_<invariant>`.
