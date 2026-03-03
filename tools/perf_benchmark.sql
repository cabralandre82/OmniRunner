-- ============================================================================
-- Performance Benchmark Queries
-- ============================================================================
--
-- Run against a seeded database (after perf_seed.ts) to validate
-- index usage and query performance with EXPLAIN ANALYZE.
--
-- Usage:
--   psql 'postgresql://postgres:postgres@127.0.0.1:54322/postgres' \
--        -f tools/perf_benchmark.sql
--
-- ============================================================================

\timing on
\echo ''
\echo '=== Performance Benchmark Suite ==='
\echo ''

-- Helper: pick a seeded group for all subsequent queries
DO $$
BEGIN
  PERFORM set_config(
    'bench.group_id',
    (SELECT id::text FROM coaching_groups WHERE name LIKE 'Perf Group %' LIMIT 1),
    false
  );
  PERFORM set_config(
    'bench.athlete_id',
    (SELECT user_id::text FROM coaching_members
     WHERE group_id = current_setting('bench.group_id')::uuid
       AND role = 'athlete'
     LIMIT 1),
    false
  );
  RAISE NOTICE 'Benchmark group: %', current_setting('bench.group_id');
  RAISE NOTICE 'Benchmark athlete: %', current_setting('bench.athlete_id');
END $$;

-- ─── 1. Dashboard: KPIs for a single group, last 30 days ────────────────────
\echo ''
\echo '── 1. KPIs daily (single group, 30 days) ──'
EXPLAIN ANALYZE
SELECT * FROM coaching_kpis_daily
WHERE group_id = current_setting('bench.group_id')::uuid
  AND day >= CURRENT_DATE - 30
ORDER BY day DESC;

-- ─── 2. CRM: Members with status for a group ────────────────────────────────
\echo ''
\echo '── 2. Members with status (single group) ──'
EXPLAIN ANALYZE
SELECT cm.user_id, cm.display_name, cm.role,
       ms.status
FROM coaching_members cm
LEFT JOIN coaching_member_status ms
  ON ms.group_id = cm.group_id AND ms.user_id = cm.user_id
WHERE cm.group_id = current_setting('bench.group_id')::uuid
  AND cm.role = 'athlete'
ORDER BY cm.display_name
LIMIT 50;

-- ─── 3. Attendance report: sessions with attendance count ────────────────────
\echo ''
\echo '── 3. Sessions with attendance count (30 days) ──'
EXPLAIN ANALYZE
SELECT ts.id, ts.title, ts.starts_at,
       COUNT(ta.id) AS attendance_count
FROM coaching_training_sessions ts
LEFT JOIN coaching_training_attendance ta ON ta.session_id = ts.id
WHERE ts.group_id = current_setting('bench.group_id')::uuid
  AND ts.starts_at >= CURRENT_DATE - 30
GROUP BY ts.id
ORDER BY ts.starts_at DESC
LIMIT 50;

-- ─── 4. Alerts: unresolved alerts for a group ───────────────────────────────
\echo ''
\echo '── 4. Unresolved alerts (single group) ──'
EXPLAIN ANALYZE
SELECT * FROM coaching_alerts
WHERE group_id = current_setting('bench.group_id')::uuid
  AND resolved = false
ORDER BY day DESC
LIMIT 50;

-- ─── 5. Workout assignments for a group this month ──────────────────────────
\echo ''
\echo '── 5. Workout assignments (30 days) ──'
EXPLAIN ANALYZE
SELECT wa.*, wt.name AS template_name
FROM coaching_workout_assignments wa
JOIN coaching_workout_templates wt ON wt.id = wa.template_id
WHERE wa.group_id = current_setting('bench.group_id')::uuid
  AND wa.scheduled_date >= CURRENT_DATE - 30
ORDER BY wa.scheduled_date DESC
LIMIT 50;

-- ─── 6. Announcement feed with read status ──────────────────────────────────
\echo ''
\echo '── 6. Announcements with read status ──'
EXPLAIN ANALYZE
SELECT a.id, a.title, a.pinned, a.created_at,
       EXISTS(
         SELECT 1 FROM coaching_announcement_reads ar
         WHERE ar.announcement_id = a.id
           AND ar.user_id = current_setting('bench.athlete_id')::uuid
       ) AS is_read
FROM coaching_announcements a
WHERE a.group_id = current_setting('bench.group_id')::uuid
ORDER BY a.pinned DESC, a.created_at DESC
LIMIT 50;

-- ─── 7. Financial ledger for a group this month ─────────────────────────────
\echo ''
\echo '── 7. Financial ledger (30 days) ──'
EXPLAIN ANALYZE
SELECT * FROM coaching_financial_ledger
WHERE group_id = current_setting('bench.group_id')::uuid
  AND date >= CURRENT_DATE - 30
ORDER BY date DESC
LIMIT 50;

-- ─── 8. Cross-group: active athletes per group (last 7 days) ────────────────
\echo ''
\echo '── 8. Active athletes per group (cross-group, 7 days) ──'
EXPLAIN ANALYZE
SELECT cm.group_id, COUNT(DISTINCT ta.athlete_user_id) AS active_athletes
FROM coaching_members cm
JOIN coaching_training_attendance ta
  ON ta.group_id = cm.group_id
 AND ta.athlete_user_id = cm.user_id
JOIN coaching_training_sessions ts
  ON ts.id = ta.session_id
 AND ts.starts_at >= NOW() - INTERVAL '7 days'
GROUP BY cm.group_id;

-- ─── 9. Subscriptions with plan info ────────────────────────────────────────
\echo ''
\echo '── 9. Subscriptions with plan (single group) ──'
EXPLAIN ANALYZE
SELECT cs.*, cp.name AS plan_name, cp.monthly_price
FROM coaching_subscriptions cs
JOIN coaching_plans cp ON cp.id = cs.plan_id
WHERE cs.group_id = current_setting('bench.group_id')::uuid
ORDER BY cs.status;

-- ─── 10. Full CRM query with tags aggregation ──────────────────────────────
\echo ''
\echo '── 10. Full CRM with tags (single group) ──'
EXPLAIN ANALYZE
SELECT cm.user_id, cm.display_name,
       ms.status,
       ARRAY_AGG(DISTINCT ct.name) FILTER (WHERE ct.name IS NOT NULL) AS tags
FROM coaching_members cm
LEFT JOIN coaching_member_status ms
  ON ms.group_id = cm.group_id AND ms.user_id = cm.user_id
LEFT JOIN coaching_athlete_tags cat
  ON cat.group_id = cm.group_id AND cat.athlete_user_id = cm.user_id
LEFT JOIN coaching_tags ct ON ct.id = cat.tag_id
WHERE cm.group_id = current_setting('bench.group_id')::uuid
  AND cm.role = 'athlete'
GROUP BY cm.user_id, cm.display_name, ms.status
ORDER BY cm.display_name
LIMIT 50;

-- ─── 11. Athlete KPIs for engagement page (heavy query) ─────────────────────
\echo ''
\echo '── 11. Athlete KPIs (single group, 30 days) ──'
EXPLAIN ANALYZE
SELECT user_id, day, score, sessions_7d
FROM coaching_athlete_kpis_daily
WHERE group_id = current_setting('bench.group_id')::uuid
  AND day >= CURRENT_DATE - 30
ORDER BY day DESC;

-- ─── 12. CRM attendance aggregation ─────────────────────────────────────────
\echo ''
\echo '── 12. CRM attendance aggregation (30 days) ──'
EXPLAIN ANALYZE
SELECT ta.athlete_user_id, COUNT(*) AS total_attendances
FROM coaching_training_attendance ta
WHERE ta.group_id = current_setting('bench.group_id')::uuid
  AND ta.checked_at >= NOW() - INTERVAL '30 days'
GROUP BY ta.athlete_user_id
ORDER BY total_attendances DESC
LIMIT 50;

\echo ''
\echo '=== Benchmark Complete ==='
\echo ''
