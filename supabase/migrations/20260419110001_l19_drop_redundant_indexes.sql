-- ============================================================================
-- L19-03 — Drop 16 redundant indexes
-- ============================================================================
--
-- The audit (L19-03) flagged the duplicated `idx_sessions_user_start`
-- (added by `20260303700000_portal_performance_indexes.sql:7`) which
-- exactly matches `idx_sessions_user` from `20260218000000_full_schema.sql:79`
-- (`(user_id, start_time_ms DESC)`). A wider audit via the query in
-- the finding (`SELECT tablename, array_agg(indexname) ... GROUP BY
-- normalized_def HAVING count(*) > 1`) revealed 15 additional cases
-- across 14 tables.
--
-- Categories:
--
--   (a) UNIQUE-constraint-shadowed plain INDEX
--       The plain INDEX serves the same query workload as the UNIQUE
--       constraint's auto-generated index AND duplicates its storage
--       footprint. Drop the plain INDEX; the UNIQUE constraint's
--       index does the read-side work.
--
--          asaas_customer_map           : drop idx_acm_group_athlete
--          coaching_device_links        : drop idx_device_links_athlete_provider
--          coaching_workout_assignments : drop idx_workout_assignments_athlete_date
--          training_plan_weeks          : drop idx_plan_weeks_plan
--                                         (uq_plan_week_number is on
--                                          (plan_id, week_number); plan_id-only
--                                          queries hit the leftmost prefix)
--
--   (b) PK-shadowed plain INDEX
--       Same as (a) but the shadow is the table's primary key.
--
--          coaching_announcement_reads  : drop idx_announcement_reads_ann_user
--                                         (pk is composite (announcement_id,user_id))
--          strava_connections           : drop idx_strava_connections_user
--                                         (pk IS user_id — 1 connection per user)
--
--   (c) UNIQUE single-column constraint shadow
--       UNIQUE INDEX on the same single column as a separate plain INDEX.
--
--          running_dna                  : drop idx_running_dna_user
--          session_journal_entries      : drop idx_session_journal_session
--          token_intents                : drop idx_token_intents_nonce
--
--   (d) Sibling plain INDEXes with identical column lists
--       Both indexes added in different migrations with overlapping
--       intent. Drop the one with the less descriptive name (or the
--       one added later via an "additional indexes" migration that
--       didn't notice the existing index).
--
--          coaching_member_status       : drop idx_member_status_group
--                                         (descriptive twin: idx_member_status_group_status)
--          coaching_members             : drop idx_coaching_members_group
--                                         (descriptive twin: idx_coaching_members_group_role)
--          challenge_participants       : drop idx_challenge_parts_user
--                                         (descriptive twin: idx_challenge_participants_user_status)
--          workout_delivery_items       : drop idx_delivery_items_athlete
--                                         (descriptive twin: idx_delivery_items_athlete_status)
--
--   (e) `LIKE INCLUDING ALL` clone duplication
--       `coin_ledger_archive` was created with `LIKE coin_ledger
--       INCLUDING ALL` (mig `20260320000000`), which cloned the FK
--       index for issuer_group_id once. Postgres then created a
--       second auto-named index when the FK constraint was added,
--       producing `..._idx` and `..._idx1`. They are byte-identical.
--
--          coin_ledger_archive          : drop coin_ledger_archive_issuer_group_id_idx1
--
--   (f) Audit-flagged exact duplicate
--       The original case from L19-03.
--
--          sessions                     : drop idx_sessions_user_start
--                                         (twin: idx_sessions_user)
--          sessions                     : drop idx_sessions_strava_dedup
--                                         (twin: idx_sessions_strava_activity, kept
--                                          because `20260309000000_disaster_fixes.sql`
--                                          deliberately recreated this name)
--
-- All DROPs are `IF EXISTS` so re-running the migration is safe and
-- so a future `LIKE INCLUDING ALL` cleanup that already removed an
-- index does not break this migration.
--
-- Validation post-migration:
--
--   SELECT tablename, array_agg(indexname) AS dups
--   FROM (
--     SELECT schemaname, tablename, indexname,
--            regexp_replace(regexp_replace(indexdef,
--              '^CREATE (UNIQUE )?INDEX [^ ]+ ON', 'INDEX ON'),
--              '\s+', ' ', 'g') AS norm
--     FROM pg_indexes WHERE schemaname='public'
--   ) x
--   GROUP BY tablename, norm HAVING count(*) > 1;
--
-- Should return 0 rows.

-- ─────────────────────────────────────────────────────────────────────────────
-- (a) UNIQUE-constraint-shadowed plain INDEX
-- ─────────────────────────────────────────────────────────────────────────────

DROP INDEX IF EXISTS public.idx_acm_group_athlete;
DROP INDEX IF EXISTS public.idx_device_links_athlete_provider;
DROP INDEX IF EXISTS public.idx_workout_assignments_athlete_date;
DROP INDEX IF EXISTS public.idx_plan_weeks_plan;

-- ─────────────────────────────────────────────────────────────────────────────
-- (b) PK-shadowed plain INDEX
-- ─────────────────────────────────────────────────────────────────────────────

DROP INDEX IF EXISTS public.idx_announcement_reads_ann_user;
DROP INDEX IF EXISTS public.idx_strava_connections_user;

-- ─────────────────────────────────────────────────────────────────────────────
-- (c) UNIQUE single-column constraint shadow
-- ─────────────────────────────────────────────────────────────────────────────

DROP INDEX IF EXISTS public.idx_running_dna_user;
DROP INDEX IF EXISTS public.idx_session_journal_session;
DROP INDEX IF EXISTS public.idx_token_intents_nonce;

-- ─────────────────────────────────────────────────────────────────────────────
-- (d) Sibling plain INDEXes with identical column lists
-- ─────────────────────────────────────────────────────────────────────────────

DROP INDEX IF EXISTS public.idx_member_status_group;
DROP INDEX IF EXISTS public.idx_coaching_members_group;
DROP INDEX IF EXISTS public.idx_challenge_parts_user;
DROP INDEX IF EXISTS public.idx_delivery_items_athlete;

-- ─────────────────────────────────────────────────────────────────────────────
-- (e) LIKE INCLUDING ALL clone duplication
-- ─────────────────────────────────────────────────────────────────────────────

DROP INDEX IF EXISTS public.coin_ledger_archive_issuer_group_id_idx1;

-- ─────────────────────────────────────────────────────────────────────────────
-- (f) Audit-flagged exact duplicate (L19-03 original)
-- ─────────────────────────────────────────────────────────────────────────────

DROP INDEX IF EXISTS public.idx_sessions_user_start;
DROP INDEX IF EXISTS public.idx_sessions_strava_dedup;

-- ─────────────────────────────────────────────────────────────────────────────
-- Code-review guard: future "additional indexes" migrations
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Helper function `pg_indexes_redundant_pairs()` returns any new
-- duplicates that creep in. Run from the integration test suite to
-- catch regressions before they hit prod.
--
-- The function is SECURITY INVOKER (no privilege escalation needed)
-- so anon cannot use it; we GRANT EXECUTE only to service_role for
-- ops/test queries.

CREATE OR REPLACE FUNCTION public.pg_indexes_redundant_pairs()
RETURNS TABLE (
  table_name      text,
  duplicate_set   text[],
  normalized_def  text
)
LANGUAGE sql
STABLE
SET search_path = public, pg_catalog, pg_temp
AS $$
  SELECT schemaname || '.' || tablename                     AS table_name,
         array_agg(indexname ORDER BY indexname)            AS duplicate_set,
         normalized_def
    FROM (
      SELECT schemaname,
             tablename,
             indexname,
             regexp_replace(
               regexp_replace(
                 indexdef,
                 '^CREATE (UNIQUE )?INDEX [^ ]+ ON', 'INDEX ON'
               ),
               '\s+', ' ', 'g'
             ) AS normalized_def
        FROM pg_indexes
       WHERE schemaname = 'public'
    ) AS norm
   GROUP BY schemaname, tablename, normalized_def
  HAVING count(*) > 1;
$$;

COMMENT ON FUNCTION public.pg_indexes_redundant_pairs() IS
  'L19-03: returns ANY pair of indexes in `public` schema with identical column list + predicate (after normalizing index name + whitespace). Use in CI/integration tests to fail when a new migration accidentally re-creates a redundant index.';

REVOKE ALL ON FUNCTION public.pg_indexes_redundant_pairs() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pg_indexes_redundant_pairs() TO service_role;

-- Companion helper for integration tests (PostgREST cannot read
-- pg_catalog.pg_indexes directly via the schema route). Returns
-- TRUE if a public.<table> has an index named <name>.
CREATE OR REPLACE FUNCTION public.pg_index_exists(p_table text, p_index text)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public, pg_catalog, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM pg_indexes
     WHERE schemaname = 'public'
       AND tablename  = p_table
       AND indexname  = p_index
  );
$$;

COMMENT ON FUNCTION public.pg_index_exists(text, text) IS
  'L19-03: thin wrapper used by integration tests to assert specific indexes were dropped/kept. Service-role-only.';

REVOKE ALL ON FUNCTION public.pg_index_exists(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pg_index_exists(text, text) TO service_role;

-- Companion helper: list a table's column names (also unreachable
-- via PostgREST schema route by default). Service-role-only.
CREATE OR REPLACE FUNCTION public.pg_table_columns(p_table text)
RETURNS TABLE (column_name text)
LANGUAGE sql
STABLE
SET search_path = public, information_schema, pg_temp
AS $$
  SELECT c.column_name::text
    FROM information_schema.columns c
   WHERE c.table_schema = 'public'
     AND c.table_name   = p_table
   ORDER BY c.ordinal_position;
$$;

COMMENT ON FUNCTION public.pg_table_columns(text) IS
  'L19-02/03: list column names of a public table. Used by integration tests to detect schema drift between sibling tables (e.g. sessions vs sessions_archive). Service-role-only.';

REVOKE ALL ON FUNCTION public.pg_table_columns(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pg_table_columns(text) TO service_role;
