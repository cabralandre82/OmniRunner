# DBA Query Tuning Runbook

**Finding:** [`L19-07`](../audit/findings/L19-07-pg-stat-statements-nao-referenciado-em-tuning.md).
**Owner:** Platform DBA + Financial SRE.
**Review cadence:** **monthly** (first Tuesday), plus ad-hoc during
any finance-surface incident.

---

## 1. Purpose

Financial surfaces (custody, swap, withdraw, emissão, burn) must
never pay for a subtly-slow query without the DBA seeing it
within a month. Supabase ships `pg_stat_statements` but does not
enable it automatically — this runbook documents:

- how the extension is installed and tightly RLS-gated,
- the monthly review procedure and its SLOs,
- the escalation path when a regression is found, and
- the reset policy (when it is allowed to clear the stats
  window).

## 2. Contract

The database-side primitives are installed by migration
`supabase/migrations/20260421450000_l19_07_pg_stat_statements.sql`:

| Object | Purpose | Grants |
| --- | --- | --- |
| `pg_stat_statements` extension | Upstream stats source | — |
| `public.v_pg_stat_statements_top` | "mean ≥ 100 ms, ORDER BY total_exec_time DESC" slice | `service_role` SELECT only |
| `public.fn_pg_stat_statements_top(p_limit int)` | Named wrapper used by dashboards / psql | `service_role` EXECUTE only |
| `public.fn_pg_stat_statements_reset()` | Resets the stats window | `service_role` EXECUTE only |

The view and the raw `pg_stat_statements` relation are **not**
granted to `anon` / `authenticated` because query text may leak
parameters / PII / service keys when prepared statements fall
back to immediate execution.

## 3. Monthly review procedure

Run the review on the first Tuesday of each month. Log the
outcome in the `#db-perf-reviews` Slack channel using the
template in §7.

1. Connect with the **service-role** key using `psql` (never the
   anon key, never via the REST API).
2. Pull the top 20:

   ```sql
   SELECT * FROM public.fn_pg_stat_statements_top(20);
   ```

3. Classify each row into one of:
   - **ok** — `mean_exec_time ≤ 100 ms` OR `calls < 100` AND
     total cost is negligible (<1 % of total DB CPU).
   - **watch** — `mean_exec_time` between 100 ms and 400 ms OR
     a finance-surface function (`fn_emit_`, `fn_swap_`,
     `fn_burn_`, `fn_custody_`, `fn_withdraw_`) within the
     top 20 regardless of mean. Open a low-priority card.
   - **breach** — `mean_exec_time > 400 ms` on ANY finance
     surface, OR `mean_exec_time > 1000 ms` on any surface.
     Open a P1 card immediately and treat it as an incident
     under §5.

4. For every **watch** or **breach**, capture:
   - queryid,
   - redacted query (strip literals by hand if necessary),
   - calls / total_exec_time / mean_exec_time / stddev_exec_time,
   - hit vs read ratio (`shared_blks_hit / (shared_blks_hit +
     shared_blks_read)` — below 0.99 is a cache-miss smell).

5. File follow-ups:
   - `tuning/<queryid>` card in the "db-perf" project; link to
     the review transcript.
   - If the query lives in an RPC, also link the migration that
     introduced it so the author can review.

6. Post the summary table in `#db-perf-reviews` and link from
   the monthly DBA review meeting agenda.

## 4. What counts as a regression

Month-over-month comparison rules (enforced by the review, not
by CI):

| Metric | Threshold | Action |
| --- | --- | --- |
| `mean_exec_time` | **+50 %** MoM on any top-20 row | open **watch** card |
| `mean_exec_time` | Crosses from < 100 ms to ≥ 100 ms | open **watch** card |
| `mean_exec_time` | **> 400 ms** on a finance surface | **breach**; see §5 |
| `calls` | **10×** MoM on same queryid | investigate call-site spam |
| Top-20 composition | Any finance RPC enters top-20 for the first time | **watch**; document in the ADR of the RPC |

## 5. Breach playbook (finance surface > 400 ms mean)

1. **Immediate.** Page on-call Platform DBA via PagerDuty.
   Classify the breach as P1 if average swap/custody/withdraw
   latency > 1 s in the last hour from `portal.latency.p95`.
2. **Diagnose.** In the same psql session:
   - `EXPLAIN (ANALYZE, BUFFERS)` against representative params.
   - `SELECT * FROM pg_stat_user_indexes WHERE relname = '<table>'`
     to confirm indexes are being used.
   - Pull a correlated trace from Sentry / Grafana using
     `queryid`.
3. **Mitigate** (in order of preference):
   - Add / rebuild an index via a zero-downtime migration
     (`CREATE INDEX CONCURRENTLY`).
   - Rewrite the query (join order, partial index, `SET LOCAL`
     knobs).
   - Increase `work_mem` locally (`SET LOCAL work_mem = '64MB'`)
     only if the fix is truly local.
   - **Never** rollback a finance migration to "fix" latency —
     that introduces ledger correctness risk. Prefer adding an
     index even if it takes a night of off-hours build.
4. **Close.** When `mean_exec_time` is back under 400 ms for
   72 consecutive hours, close the P1 and file an ADR if the
   incident required a query rewrite.

## 6. Reset policy

Resetting the stats window **hides upstream regressions** from
the monthly review and should not be routine.

Allowed triggers:
- After the monthly review is filed (optional; keeps the next
  month's sample clean).
- After a major migration that invalidates comparisons (schema
  changes, index rebuilds, function rewrites of finance RPCs).
- After a breach is closed and the remediated query is verified.

Procedure:

```sql
SELECT public.fn_pg_stat_statements_reset();
```

Log the reset in `#db-perf-reviews` with timestamp + reason.
Unlogged resets are a policy violation.

## 7. Review log template

```
[YYYY-MM-DD] Monthly DBA review
Reviewer: @handle

Top-20 (mean ≥ 100 ms, ORDER BY total_exec_time DESC):

| # | queryid | query (redacted) | calls | mean ms | total ms | class |
|---|---------|------------------|-------|---------|----------|-------|
| 1 |         |                  |       |         |          | ok/watch/breach |
| … |         |                  |       |         |          |                 |

Watch cards opened: tuning/<queryid>, tuning/<queryid>
Breach cards opened: (none) / P1-<link>
Reset after review? yes/no  (reason: …)
```

## 8. Cross-links

- Finding: [`L19-07`](../audit/findings/L19-07-pg-stat-statements-nao-referenciado-em-tuning.md).
- Migration: `supabase/migrations/20260421450000_l19_07_pg_stat_statements.sql`.
- CI guard: `tools/audit/check-pg-stat-statements.ts` (`npm run audit:pg-stat-statements`).
- Related findings:
  - `L08-06` — OLAP staging is exempt from the 100 ms SLO
    because it runs in `public_olap` and is batch-oriented.
  - `L08-08` — `audit_logs` retention cron uses the same
    `service_role` primitive.
