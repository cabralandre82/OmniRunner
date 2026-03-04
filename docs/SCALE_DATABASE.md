# SCALE_DATABASE — Supabase Postgres at 10K Groups / 800K Athletes

**Date:** 2026-03-04
**Scope:** Scale analysis for OmniRunner Supabase Postgres targeting 10,000 coaching groups with 800,000 athletes and 30,000 staff.
**Baseline:** Current schema as of migration `20260307000000_chaos_fixes.sql`.

---

## 1. Volume Projections

### Per-Athlete Annual Assumptions

| Metric | Value |
|---|---|
| Sessions/year | 60 |
| Daily KPI rows/athlete | 1 per day per group membership |
| Coin ledger entries/year | ~130 (sessions + challenges + badges + missions) |
| Notification log entries/year | ~200 |
| Challenge participations/year | ~15 |

### Table Row Estimates by Scale Tier

| Table | 1K Groups / 80K Athletes | 5K Groups / 400K Athletes | 10K Groups / 800K Athletes |
|---|---|---|---|
| `coaching_members` | 85K | 425K | 850K |
| `sessions` | 5M | 25M | **50M** |
| `coaching_athlete_kpis_daily` | 29M | 146M | **292M** |
| `coaching_kpis_daily` | 365K | 1.8M | **3.65M** |
| `coaching_alerts` | 1.5M | 7.5M | **15M** |
| `notification_log` | 16M | 80M | **160M** |
| `coin_ledger` | 10.4M | 52M | **104M** |
| `leaderboard_entries` | 5M | 25M | **50M** |
| `challenge_participants` | 1.2M | 6M | **12M** |
| `challenge_results` | 600K | 3M | 6M |
| `coaching_workout_assignments` | 4M | 20M | **40M** |
| `workout_delivery_items` | 2M | 10M | 20M |
| `coaching_training_attendance` | 2M | 10M | 20M |
| `product_events` | 8M | 40M | 80M |
| `badge_awards` | 3M | 15M | 30M |
| `mission_progress` | 4M | 20M | 40M |
| `profile_progress` | 80K | 400K | 800K |
| `coaching_financial_ledger` | 500K | 2.5M | 5M |
| `coaching_subscriptions` | 80K | 400K | 800K |
| `clearing_cases` | 10K | 50K | 100K |
| `league_snapshots` | 52K | 260K | 520K |
| `api_rate_limits` | 10M | 50M | 100M |

### Storage Estimates (10K tier)

| Table | Avg Row Bytes | Est. Total |
|---|---|---|
| `coaching_athlete_kpis_daily` (292M rows) | ~200B | **~55 GB** |
| `sessions` (50M rows) | ~400B | ~19 GB |
| `notification_log` (160M rows) | ~120B | ~18 GB |
| `coin_ledger` (104M rows) | ~150B | ~15 GB |
| `leaderboard_entries` (50M rows) | ~200B | ~9.5 GB |
| **Total data (excl. indexes)** | | **~130–160 GB** |
| **Including indexes (~1.5×)** | | **~200–250 GB** |

---

## 2. Missing Indexes

The following indexes are absent from current migrations and are required at scale.

### Critical (P0 — required before 5K groups)

| Table | Columns | Rationale |
|---|---|---|
| `coaching_members` | `(user_id, group_id)` | Every RLS policy does `EXISTS (SELECT 1 FROM coaching_members WHERE user_id = auth.uid() AND group_id = ...)`. Current PK is `id`; composite index on `(user_id, group_id)` is the single highest-impact index in the entire database. |
| `coaching_members` | `(group_id, role)` | KPI cron scans `WHERE group_id = g.id AND role = 'athlete'` across all groups. |
| `sessions` | `(user_id, is_verified, start_time_ms)` | `strava-webhook` dedup check, `inactivity_nudge` full scan, KPI temp table creation. Current `idx_sessions_user_start` covers `(user_id, start_time_ms)` but omits `is_verified`. |
| `sessions` | `(status, is_verified, start_time_ms)` partial: `WHERE status >= 3 AND is_verified = true` | KPI cron `_kpi_sessions` temp table: `WHERE s.status >= 3 AND s.is_verified = true AND s.start_time_ms >= v_month_start_ms`. Without this, full seq scan on 50M rows. |
| `coin_ledger` | `(ref_id, reason)` | `settle-challenge` queries `WHERE ref_id = ch.id AND reason = 'challenge_entry_fee'`. At 104M rows this is a full scan per challenge. |
| `coin_ledger` | `(user_id, created_at DESC)` | Wallet screen, clearing-cron per-user balance queries. |
| `leaderboard_entries` | `(leaderboard_id)` — **already PK composite?** Verify. | `DELETE FROM leaderboard_entries WHERE leaderboard_id = lb_id` runs before every recompute. At 50M rows, if `leaderboard_id` is not the leading column, this is a seq scan. |
| `notification_log` | `(sent_at)` partial: `WHERE sent_at < now() - interval '30 days'` | For TTL cleanup. 160M rows with no cleanup = unbounded growth. |

### High Priority (P1)

| Table | Columns | Rationale |
|---|---|---|
| `coaching_athlete_kpis_daily` | `(user_id, group_id, day)` | `compute_coaching_alerts_daily` joins on this. 292M rows. |
| `coaching_workout_assignments` | `(group_id, status, scheduled_date)` | `fn_generate_delivery_items` scans `WHERE wa.group_id = ... AND wa.status = 'planned'`. |
| `challenge_participants` | `(challenge_id, status)` | `settle-challenge` fetches `WHERE challenge_id = ch.id AND status = 'accepted'`. |
| `strava_connections` | `(strava_athlete_id)` | Webhook lookup by Strava athlete ID. Missing = seq scan per incoming webhook. |
| `sessions` | `(strava_activity_id)` | Dedup check in `strava-webhook`: `WHERE strava_activity_id = ...`. |
| `api_rate_limits` | `(window_start)` | `cleanup_rate_limits` deletes old rows. 100M rows. |

### Already Present (verification)

Indexes confirmed in migrations:
- `idx_sessions_user_start` → `(user_id, start_time_ms DESC)` ✓
- `idx_kpis_daily_group_day` → `(group_id, day DESC)` ✓
- `idx_athlete_kpis_daily_group_day` → `(group_id, day DESC)` ✓
- `idx_workout_assignments_athlete_date` → `(athlete_user_id, scheduled_date)` ✓
- `idx_notification_log_dedup` → `(user_id, rule, context_id, sent_at DESC)` ✓
- `idx_coin_ledger_issuer_group_id` → `(issuer_group_id)` ✓

---

## 3. RLS Performance Bottlenecks

### The `coaching_members` Anti-Pattern — #1 System-Wide Bottleneck

Nearly every RLS policy across 15+ tables follows this pattern:

```sql
EXISTS (
  SELECT 1 FROM public.coaching_members cm
  WHERE cm.group_id = <target_table>.group_id
    AND cm.user_id = auth.uid()
    AND cm.role IN ('admin_master', 'coach')
)
```

**Tables affected:** `coaching_plans`, `coaching_subscriptions`, `coaching_financial_ledger`, `coaching_workout_templates`, `coaching_workout_blocks`, `coaching_workout_assignments`, `workout_delivery_batches`, `workout_delivery_items`, `workout_delivery_events`, `coaching_training_sessions`, `coaching_training_attendance`, `clearing_cases`, `clearing_case_items`, `clearing_case_events`, `leaderboards` (assessoria scope), `coaching_announcements`, `coaching_member_status`.

**Impact at 10K groups (850K rows in `coaching_members`):**

1. **Every single SELECT/INSERT/UPDATE/DELETE** on any of these tables triggers a subquery against `coaching_members`.
2. For a staff user who belongs to 3 groups, loading the workout assignments page fires: `SELECT * FROM coaching_workout_assignments WHERE group_id = $1` → RLS evaluates `EXISTS(...)` per **returned row**, not once per query.
3. Without a composite index on `(user_id, group_id)`, Postgres falls back to a sequential scan or a less-selective index scan on the 850K-row table.
4. **Estimated overhead per RLS check:** ~0.1ms with proper index, ~5–15ms without. At 100 rows returned, that's 10ms vs 1500ms.

**Quantified Impact:**

| Scenario | With `(user_id, group_id)` index | Without |
|---|---|---|
| Staff loads 50 workout assignments | 50 × 0.1ms = 5ms | 50 × 8ms = 400ms |
| Athlete reads 30 delivery items | 30 × 0.1ms = 3ms | 30 × 8ms = 240ms |
| Portal loads 200 KPI rows | 200 × 0.1ms = 20ms | 200 × 8ms = 1600ms |

### Compound RLS (multi-table chain)

Some policies chain through multiple tables:

- `coaching_workout_blocks` → joins `coaching_workout_templates` then `coaching_members`
- `clearing_case_items` → joins `clearing_cases` then `coaching_members`
- `workout_delivery_events` (athlete) → joins `workout_delivery_items`

Each chain adds a nested loop per row. At scale, these compound lookups can hit 20–50ms per row.

### Recommendation: Materialized Security Context

Replace per-row RLS subqueries with a session-level security context:

```sql
CREATE FUNCTION auth.user_group_roles()
RETURNS TABLE(group_id uuid, role text) STABLE
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT group_id, role FROM coaching_members WHERE user_id = auth.uid();
$$;
```

Then RLS becomes:

```sql
EXISTS (
  SELECT 1 FROM auth.user_group_roles() ugr
  WHERE ugr.group_id = <table>.group_id
    AND ugr.role IN ('admin_master', 'coach')
)
```

This executes the `coaching_members` lookup **once per transaction** instead of once per row, yielding 10–100× improvement for multi-row queries.

---

## 4. Top 15 Expensive Queries

Ranked by estimated I/O cost × execution frequency at 10K scale.

| # | Query / Function | Source | Est. Rows Scanned | Frequency | Severity |
|---|---|---|---|---|---|
| **1** | `compute_coaching_kpis_daily` — `_kpi_sessions` temp table creation | `_analytics_advanced.sql` | 50M (`sessions`) JOIN 850K (`coaching_members`) | Daily cron | **CRITICAL** |
| **2** | `compute_coaching_kpis_daily` — per-group LATERAL joins over `coaching_groups` | `_analytics_advanced.sql` | 10K groups × 6 LATERAL subqueries | Daily cron | **CRITICAL** |
| **3** | `inactivity_nudge` — full scan of `sessions` for 30-day window | `notify-rules/index.ts` | 50M rows (unindexed `is_verified` filter) | Daily (17:00 UTC) | **CRITICAL** |
| **4** | `compute_leaderboard_global` — `DELETE` + `INSERT` on `leaderboard_entries` | `_leaderboard_v2.sql` | DELETE 50M entries (if accumulated), INSERT 200 | Weekly × 3 scopes | **HIGH** |
| **5** | `compute_leaderboard_assessoria` — per-group: scans `sessions` for all members | `_leaderboard_v2.sql` | 10K groups × avg 80 members × scan | Weekly | **HIGH** |
| **6** | RLS `EXISTS` on `coaching_members` — aggregated across all tables | Every authenticated query | 850K per check (no composite index) | Continuous (millions/day) | **HIGH** |
| **7** | `settle-challenge` — `coin_ledger` scan for entry fee sum | `settle-challenge/index.ts` | 104M (scan by `ref_id` without index) | Per challenge settlement | **HIGH** |
| **8** | `league-snapshot` — serial per-group: members → sessions → challenge_results | `league-snapshot/index.ts` | 10K groups × 3 queries each | Weekly | **MEDIUM** |
| **9** | `compute_coaching_alerts_daily` — 5 INSERT...SELECT over `coaching_athlete_kpis_daily` | `_analytics_advanced.sql` | 292M (5 passes) | Daily | **HIGH** |
| **10** | `strava-webhook` — 3 RPCs per event: `eval_athlete_verification`, `recalculate_profile_progress`, `evaluate_badges_retroactive` | `strava-webhook/index.ts` | Cascading: each RPC scans `sessions`, `badges`, `coin_ledger` | 200K/day peak | **HIGH** |
| **11** | `streak_at_risk` — scan `v_user_progression` + cross-check with `sessions` | `notify-rules/index.ts` | 800K users + session check | Daily (20:00 UTC) | **MEDIUM** |
| **12** | `clearing-cron` — aggregates from `coin_ledger` grouped by group pairs | Inferred from clearing tables | 104M full scan | Weekly | **MEDIUM** |
| **13** | `fn_generate_delivery_items` — nested subquery aggregating `coaching_workout_blocks` | `_workout_delivery.sql` | Per batch: scan assignments × blocks | On-demand (staff) | **MEDIUM** |
| **14** | `cleanup_rate_limits` — `DELETE WHERE window_start < now() - '1 hour'` | `baseline_remote_schema.sql` | 100M rows, no partial index | Periodic | **LOW** |
| **15** | `compute_leaderboard_championship` — LATERAL join on `sessions` per participant | `_leaderboard_v2.sql` | Per championship: up to 500 participants × sessions scan | Weekly | **MEDIUM** |

---

## 5. Lock Contention Hotspots

### 5.1 `wallets` — Single-Row Hot Update

`increment_wallet_balance` does `UPDATE wallets SET balance_coins = balance_coins + p_delta WHERE user_id = p_user_id`. At scale:

- **Strava webhook:** each verified session triggers `recalculate_profile_progress` → badge evaluation → coin ledger → `increment_wallet_balance`.
- **Challenge settlement:** all participants' wallets updated in parallel via `Promise.all`.
- **A user with 3 active challenges settling simultaneously** = 3 concurrent UPDATEs to the same `wallets` row → row-level lock contention → serialized.

**Risk:** At 200K strava events/day, peak throughput of ~2.3 events/second. Each event touching `wallets` with a ~50ms lock hold = manageable, but settlement bursts (50 challenges settling at lifecycle-cron) × 10 participants each = 500 concurrent wallet updates.

### 5.2 `coaching_workout_assignments` — `FOR UPDATE` Lock

`fn_assign_workout` (chaos fix M16) uses:

```sql
SELECT count(*) FROM coaching_workout_assignments
WHERE athlete_user_id = p_athlete_user_id
  AND scheduled_date >= v_week_start AND scheduled_date < v_week_start + 7
FOR UPDATE;
```

This locks **all assignments for that athlete in the week**. If a coach bulk-assigns 80 athletes in rapid succession using the same date range, the FOR UPDATE can cascade: each call waits for prior locks to release.

### 5.3 `leaderboard_entries` — DELETE + INSERT Cycle

Every leaderboard recompute does:

```sql
DELETE FROM leaderboard_entries WHERE leaderboard_id = lb_id;
INSERT INTO leaderboard_entries (...) SELECT ...;
```

During the DELETE phase (up to 200 rows per leaderboard, but with global scope potentially more), an `AccessExclusiveLock` on affected rows blocks concurrent reads. Users querying leaderboards during recompute see delays or timeouts.

### 5.4 `challenges` — Optimistic Status Transition

`settle-challenge` does `UPDATE challenges SET status = 'completing' WHERE id = ch.id AND status IN ('active', 'completing')`. Two concurrent settlements of the same challenge will serialize on this row lock. The guard `status IN ('active', 'completing')` handles idempotency, but the second caller holds a lock waiting for the first's transaction to commit.

---

## 6. WAL (Write-Ahead Log) Impact

### 6.1 Leaderboard DELETE+INSERT = WAL Storm

At 10K scale, weekly leaderboard computation:

| Scope | Leaderboards | Entries Deleted | Entries Inserted | WAL Bytes |
|---|---|---|---|---|
| Global (weekly + monthly) | 2 | 400 | 400 | ~160 KB |
| Assessoria (10K groups × 2 periods) | 20K | ~1.6M | ~1.6M | **~640 MB** |
| Championship | ~100 | 20K | 20K | ~8 MB |
| **Total per cycle** | | **~1.6M deletes** | **~1.6M inserts** | **~650 MB** |

Each DELETE generates a WAL record (~200B), and each INSERT generates another. This creates **650+ MB of WAL per weekly leaderboard cycle**, causing:

- Replication lag spikes on read replicas
- Checkpoint pressure (fsync storms)
- Increased backup size

**Fix:** Replace DELETE+INSERT with `INSERT ... ON CONFLICT DO UPDATE` or use `MERGE` (PG15+). Better yet, use `TRUNCATE` for scope-specific entries using partitioning.

### 6.2 Daily KPI Cron

`compute_coaching_kpis_daily` upserts one row per group (10K) into `coaching_kpis_daily`, plus `compute_coaching_alerts_daily` inserts up to 5 alert types × 850K athletes = up to 4.25M rows.

**Estimated daily WAL from KPI pipeline:** ~1.5–2 GB

### 6.3 Strava Webhook WAL

At 200K events/day, each creating:
- 1 `sessions` INSERT (~400B)
- 1 `product_events` INSERT (~200B)
- 1 `coin_ledger` INSERT (~150B)
- 1 `wallets` UPDATE (~100B)
- 1 `profile_progress` UPDATE (~100B)
- Optional: `challenge_participants` UPDATE, `park_activities` INSERT

**Estimated daily WAL from Strava:** ~200K × ~1KB = **~200 MB/day**

### 6.4 Total Daily WAL Budget

| Source | Estimated WAL/day |
|---|---|
| Strava webhooks | 200 MB |
| KPI + alerts cron | 1.5–2 GB |
| Leaderboard recompute (amortized) | ~93 MB/day |
| Notification log | ~60 MB |
| User queries (CRUD) | ~500 MB |
| **Total** | **~2.5–3.5 GB/day** |

Supabase Pro plan default WAL retention is 1 GB. At this rate, WAL will wrap frequently, increasing checkpoint frequency and I/O pressure.

---

## 7. Cron Scalability Failures

### 7.1 `compute_coaching_kpis_daily` — O(groups × athletes) Full Scan

**Current behavior:** Called once with `p_day`, creates a temp table from a JOIN of `sessions × coaching_members` (50M × 850K), then runs 10 LATERAL subqueries per group across ALL 10K groups in a single transaction.

**At 10K groups:**
- Temp table `_kpi_sessions`: ~5M rows (30 days of verified sessions for all athletes). Index creation on temp table helps but doesn't fix the root cause.
- 10K groups × 10 LATERAL subqueries = 100K subquery executions
- Estimated runtime: **20–45 minutes** (currently probably <1 min at 100 groups)
- Single transaction means: crash at group 9,500 → everything rolls back

**Fix required:** Batch by group. Process groups in chunks of 100, each in its own transaction:

```sql
CREATE FUNCTION compute_coaching_kpis_daily_batch(
  p_day date,
  p_group_ids uuid[]
) RETURNS integer;
```

### 7.2 `league-snapshot` — Serial N+1 Queries Per Group

**Current behavior** (from `league-snapshot/index.ts`):

```typescript
for (const enrollment of enrollments) {
  // Query 1: coaching_members for this group
  // Query 2: sessions for all member IDs
  // Query 3: challenge_results for member IDs
}
```

**At 10K groups:** 10K × 3 queries = **30,000 sequential database round-trips** in a single Edge Function invocation. At 5ms per query, that's **2.5 minutes** — well beyond the 60s Edge Function timeout.

**Fix:** Replace N+1 with a single SQL function:

```sql
CREATE FUNCTION fn_compute_league_snapshots(p_season_id uuid)
RETURNS TABLE(...) AS $$
  SELECT g.id, SUM(s.total_distance_m), COUNT(DISTINCT s.user_id), ...
  FROM league_enrollments le
  JOIN coaching_members cm ON cm.group_id = le.group_id
  JOIN sessions s ON s.user_id = cm.user_id AND s.is_verified = true
    AND s.start_time_ms BETWEEN $start AND $end
  WHERE le.season_id = p_season_id
  GROUP BY g.id;
$$;
```

### 7.3 `lifecycle-cron` — Serial Challenge Settlement

**Current behavior:** Fetches up to 50 expired challenges, then for each one calls `settle-challenge` via HTTP (`fetch`). Each settlement is a full Edge Function invocation with its own auth, DB connection, and multi-query logic.

**At 10K groups:** If 200 challenges expire in a 5-minute window:
- Only 50 processed per cron tick (hardcoded `.limit(50)`)
- Each settlement: 5–10 DB queries + HTTP overhead = ~500ms
- Total: 50 × 500ms = **25 seconds** per tick, leaving 150 unsettled → backlog accumulates

**Fix:** Remove the HTTP-per-challenge pattern. Use a single SQL function or process in batches of 200.

### 7.4 `notify-rules` — Inactivity Nudge Full Scan

**Current behavior:**

```typescript
const { data: recentUsers } = await db
  .from("sessions")
  .select("user_id")
  .gte("start_time_ms", thirtyDaysAgoMs)
  .eq("is_verified", true);
```

This returns **every session in the last 30 days** — at 10K scale, that's ~4M rows transferred to the Edge Function. Then it does a second query for last-5-days sessions, builds a Set difference in JavaScript, and iterates.

**At 800K athletes:** This query alone transfers ~4M `user_id` values (~64 MB) to the Edge Function. The Edge Function will OOM or timeout.

**Fix:** Push the set-difference into SQL:

```sql
SELECT DISTINCT user_id FROM sessions
WHERE start_time_ms >= $thirtyDaysAgo AND is_verified = true
EXCEPT
SELECT DISTINCT user_id FROM sessions
WHERE start_time_ms >= $fiveDaysAgo AND is_verified = true;
```

### 7.5 `auto-topup-cron` and `clearing-cron` — Assumed Full Scans

Based on table structure, `clearing-cron` likely scans all of `coin_ledger` (104M rows) to aggregate pending cross-group prizes. Without `(issuer_group_id, reason)` index, this is catastrophic.

---

## 8. Partitioning Recommendations

### 8.1 `coaching_athlete_kpis_daily` — **Partition by Range on `day`**

**292M rows**, monotonically increasing by date. Classic time-series.

```sql
CREATE TABLE coaching_athlete_kpis_daily (
  id uuid DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL,
  user_id uuid NOT NULL,
  day date NOT NULL,
  ...
) PARTITION BY RANGE (day);

-- Monthly partitions
CREATE TABLE coaching_athlete_kpis_daily_2026_01
  PARTITION OF coaching_athlete_kpis_daily
  FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
```

**Benefits:**
- KPI cron writes only to current partition (~800K rows instead of 292M)
- Alerts query reads current day partition only
- Old data can be detached/archived without `DELETE` WAL
- Index scans narrowed to partition size

### 8.2 `sessions` — **Partition by Range on `start_time_ms`**

**50M rows.** Every KPI computation, leaderboard, challenge binding queries filter by `start_time_ms`.

```sql
PARTITION BY RANGE (start_time_ms);
-- Quarterly partitions (ms boundaries)
```

**Complication:** `start_time_ms` is `bigint` (epoch ms), not `date`. Partitioning on bigint range works but requires computed partition boundaries.

### 8.3 `notification_log` — **Partition by Range on `sent_at`**

**160M rows** with no cleanup mechanism. Partition monthly, drop partitions older than 90 days.

### 8.4 `coin_ledger` — **Partition by Range on `created_at`**

**104M rows.** Clearing-cron and reconciliation queries are time-bounded. Partition monthly.

### 8.5 `leaderboard_entries` — **Partition by List on `leaderboard_id` prefix**

Alternative: partition by hash on `leaderboard_id`. The DELETE+INSERT pattern benefits from partition-level TRUNCATE instead of row-level DELETE.

### 8.6 `api_rate_limits` — **Partition by Range on `window_start`**

**100M rows.** `cleanup_rate_limits` does `DELETE WHERE window_start < now() - '1 hour'`. With hourly partitions, this becomes `DROP PARTITION` — instant, zero WAL.

### Priority Order

1. `coaching_athlete_kpis_daily` (highest row count, daily writes)
2. `notification_log` (unbounded growth, no cleanup)
3. `sessions` (foundation for all analytics)
4. `coin_ledger` (clearing-cron full scans)
5. `api_rate_limits` (cleanup WAL)
6. `leaderboard_entries` (DELETE+INSERT WAL)

---

## 9. Connection Pool Estimation

### Supabase Architecture

Supabase uses **Supavisor** (PgBouncer-compatible) in front of Postgres. Key constraints:

| Plan | Direct Connections | Pooler Connections | Pooler Mode |
|---|---|---|---|
| Pro | 60 | 200 | Transaction |
| Team | 120 | 400 | Transaction |
| Enterprise | Custom | Custom | Custom |

### Connection Consumers at 10K Scale

| Consumer | Connections Needed | Mode |
|---|---|---|
| Edge Functions (concurrent) | 20–50 | Transaction pooling |
| PostgREST (API) | 20–40 | Transaction pooling |
| Realtime subscriptions | 10–20 | Persistent |
| pg_cron background workers | 3–5 | Direct |
| Portal (Next.js server) | 5–10 | Transaction pooling |
| Supabase Dashboard/Studio | 2–3 | Direct |
| Migrations / Admin | 1–2 | Direct |
| **Total needed** | **61–130** | |

### Peak Concurrency Analysis

At 800K athletes with 25% DAU (200K):
- **Strava webhooks:** 200K/day = ~2.3/sec average, bursts to 10–20/sec (morning runs). Each webhook holds a connection for ~200ms across 5–8 queries. Peak: **~4 concurrent connections**.
- **App API calls:** 200K DAU × ~50 API calls/day = 10M calls/day = ~115/sec. At 50ms per call: **~6 concurrent connections**.
- **Staff (30K):** Portal + App. 5K concurrent at peak. ~20 calls/min each = ~1,667/sec. At 100ms per call (RLS overhead): **~167 concurrent connections**.

**Total peak: ~180 concurrent connections.** Pro plan (200 pooler) is borderline. **Team plan recommended at 5K groups, Enterprise at 10K.**

### Recommendation

| Scale | Supabase Plan | Pooler Mode | Max Pool |
|---|---|---|---|
| 1K groups | Pro | Transaction | 200 |
| 5K groups | Team | Transaction | 400 |
| 10K groups | Enterprise | Transaction | 800+ |

Enable `prepared_statements = false` in Supavisor configuration to support transaction pooling for all clients. Edge Functions already use fresh connections per invocation.

---

## 10. Prioritized Recommendations

### P0 — Blocking at 2–3K Groups (do immediately)

| # | Action | Impact | Effort |
|---|---|---|---|
| **R1** | Create composite index `CREATE INDEX idx_coaching_members_user_group ON coaching_members (user_id, group_id) INCLUDE (role)` | Eliminates #1 bottleneck. Every RLS policy becomes O(1) instead of O(N). Estimated 10–100× improvement on all authenticated queries. | 1 migration, 0 code change |
| **R2** | Create index `idx_coaching_members_group_role ON coaching_members (group_id, role)` | KPI cron membership subqueries. | 1 migration |
| **R3** | Create index on `sessions (status, is_verified, start_time_ms)` WHERE `status >= 3 AND is_verified = true` | KPI cron temp table creation drops from 50M scan to range scan. | 1 migration |
| **R4** | Create index `idx_coin_ledger_ref_reason ON coin_ledger (ref_id, reason)` | `settle-challenge` per-challenge fee lookup drops from 104M scan to index lookup. | 1 migration |
| **R5** | Create index `idx_strava_connections_athlete_id ON strava_connections (strava_athlete_id)` | Strava webhook lookup: 200K/day at O(N) → O(1). | 1 migration |
| **R6** | Create index `idx_sessions_strava_activity ON sessions (strava_activity_id) WHERE strava_activity_id IS NOT NULL` | Strava dedup check. | 1 migration |

### P1 — Required Before 5K Groups

| # | Action | Impact | Effort |
|---|---|---|---|
| **R7** | Implement `auth.user_group_roles()` materialized security function; refactor RLS to use it | Reduces per-row RLS cost by 10–100×. | 1 migration + RLS rewrite |
| **R8** | Rewrite `compute_coaching_kpis_daily` to batch by group (chunks of 100) with separate transactions | Prevents 45-minute single-transaction failure. Enables parallel execution. | SQL function rewrite |
| **R9** | Partition `coaching_athlete_kpis_daily` by month on `day` | Writes confined to current partition. Alert queries pruned to current day. | Migration + partition maintenance cron |
| **R10** | Replace leaderboard `DELETE + INSERT` with `INSERT ... ON CONFLICT DO UPDATE` + a `deleted_at` soft-delete or use atomic `MERGE` | Eliminates 650 MB/week WAL from leaderboard churn. | SQL function rewrite |
| **R11** | Rewrite `league-snapshot` to use a single SQL function instead of N+1 per-group queries | 30,000 queries → 1 query. Fixes Edge Function timeout at >500 groups. | Edge function + SQL function |
| **R12** | Rewrite `inactivity_nudge` to use SQL set-difference instead of client-side | Prevents OOM on 4M rows transferred to Edge Function. | Edge function rewrite |
| **R13** | Add TTL/cleanup for `notification_log`: partition by month, drop partitions >90 days | Prevents unbounded growth (160M+ rows). | Migration + cron |

### P2 — Required Before 10K Groups

| # | Action | Impact | Effort |
|---|---|---|---|
| **R14** | Partition `sessions` by quarter on `start_time_ms` | All analytics queries benefit from partition pruning. | Complex migration (FK dependencies) |
| **R15** | Partition `coin_ledger` by month on `created_at` | Clearing-cron scans confined to recent partitions. | Migration |
| **R16** | Partition `api_rate_limits` by hour on `window_start`; replace DELETE cleanup with DROP PARTITION | Instant cleanup, zero WAL. | Migration + cron |
| **R17** | Rewrite `lifecycle-cron` challenge settlement to batch within a single function call | Eliminates HTTP-per-challenge overhead. 50 × 500ms → single 2s call. | Edge function rewrite |
| **R18** | Add read replica for portal analytics queries | Offload KPI dashboards, CRM queries from primary. | Supabase config |
| **R19** | Implement connection pooling strategy: upgrade to Enterprise, configure 800+ pool slots | Prevents connection exhaustion at peak. | Infrastructure |
| **R20** | Strava webhook: debounce the 3 cascading RPCs (`eval_athlete_verification`, `recalculate_profile_progress`, `evaluate_badges_retroactive`) into a single async queue | 200K/day × 3 RPCs = 600K background calls. Queue allows batching. | Architecture change |
| **R21** | Add `pg_stat_statements` monitoring and alert on queries >1s | Observability for catching regressions before they cascade. | Supabase config |
| **R22** | Implement `VACUUM` schedule tuning: `autovacuum_vacuum_scale_factor = 0.01` for hot tables (`wallets`, `profile_progress`, `sessions`) | Prevents bloat on tables with heavy UPDATE patterns. | `ALTER TABLE SET (autovacuum_...)` |

### Implementation Order (Critical Path)

```
Week 1:  R1, R2, R3, R4, R5, R6 (indexes — zero-risk migrations)
Week 2:  R7 (RLS security function), R10 (leaderboard WAL fix)
Week 3:  R8 (KPI batch), R11 (league-snapshot), R12 (inactivity nudge)
Week 4:  R9 (KPI partitioning), R13 (notification TTL)
Week 5+: R14–R22 (partitioning, infrastructure, architecture)
```

---

## Appendix A: SQL for Critical Missing Indexes

```sql
-- R1: THE most important index in the entire database
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_coaching_members_user_group
  ON public.coaching_members (user_id, group_id) INCLUDE (role);

-- R2: KPI cron group membership scans
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_coaching_members_group_role
  ON public.coaching_members (group_id, role);

-- R3: KPI cron session scan (partial)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sessions_verified_time
  ON public.sessions (start_time_ms)
  WHERE status >= 3 AND is_verified = true;

-- R4: settle-challenge fee lookup
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_coin_ledger_ref_reason
  ON public.coin_ledger (ref_id, reason);

-- R5: Strava webhook athlete lookup
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_strava_connections_athlete_id
  ON public.strava_connections (strava_athlete_id);

-- R6: Strava dedup check
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sessions_strava_activity
  ON public.sessions (strava_activity_id)
  WHERE strava_activity_id IS NOT NULL;

-- P1: Additional high-value indexes
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_athlete_kpis_user_group_day
  ON public.coaching_athlete_kpis_daily (user_id, group_id, day DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_challenge_participants_challenge_status
  ON public.challenge_participants (challenge_id, status);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_coin_ledger_user_created
  ON public.coin_ledger (user_id, created_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_workout_assignments_group_status_date
  ON public.coaching_workout_assignments (group_id, status, scheduled_date)
  WHERE status = 'planned';
```

## Appendix B: Estimated Query Performance After Fixes

| Query | Before (est.) | After R1–R6 | After R7–R13 |
|---|---|---|---|
| Staff loads workout assignments (50 rows) | 400ms | 5ms | 3ms |
| Athlete reads delivery items (30 rows) | 240ms | 3ms | 2ms |
| KPI cron (10K groups) | 45 min | 15 min | 3 min |
| League snapshot (10K groups) | >60s (timeout) | >60s | 5s |
| Strava webhook (single event) | 800ms | 150ms | 100ms |
| Inactivity nudge (full eval) | OOM | 30s | 3s |
| Leaderboard weekly recompute WAL | 650 MB | 650 MB | 10 MB |
