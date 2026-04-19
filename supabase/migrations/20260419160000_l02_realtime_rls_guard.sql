-- ============================================================================
-- L02-08 — Realtime / Websocket cross-tenant leak (RLS guard + event trigger)
--
-- Audit reference:
--   docs/audit/findings/L02-08-realtime-websocket-cross-tenant-leak.md
--   docs/audit/parts/02-cto-cfo.md  (anchor [2.8])
--
-- Problem
-- ───────
--   Supabase Realtime broadcasts row-level CDC events for every table in the
--   `supabase_realtime` publication. Subscribers connect through the same
--   PostgREST/realtime gateway as PostgREST and the broker applies the
--   subscriber's RLS policies before fan-out (`USING ... auth.uid()` etc).
--
--   This means: **a table added to `supabase_realtime` without a restrictive
--   SELECT policy leaks every INSERT / UPDATE / DELETE to every authenticated
--   subscriber, regardless of tenant.** Athlete A inspects their websocket,
--   tweaks the channel filter, and sees athlete B's wallet credits land in
--   real time. Same pattern bites `coaching_members`, `sessions`,
--   `swap_orders`, `custody_*`, `coin_ledger`.
--
--   The audit could not verify membership directly because the publication
--   is managed out-of-band (Supabase dashboard or `ALTER PUBLICATION`
--   migrations that sometimes ship without RLS hardening alongside).
--
-- Defence (this migration) — defence-in-depth in three layers
-- ────────────────────────────────────────────────────────────
--   (1) `fn_realtime_publication_unsafe_tables(p_publication)` — pure
--       diagnostic. Returns one row per table in the publication that
--       fails the safety contract. Operators can query ad-hoc.
--
--   (2) `fn_assert_realtime_publication_safe(p_publication)` — RAISES
--       `P0009 REALTIME_RLS_VIOLATION` listing every offender if any row
--       comes back from (1). Idempotent / safe to call any time.
--
--   (3) `trg_block_unsafe_realtime_publication` — DDL event trigger on
--       `ddl_command_end` filtered to `ALTER PUBLICATION` /
--       `CREATE PUBLICATION` events on `supabase_realtime`. Re-runs the
--       guard at the SAME transaction as the DDL; failure rolls back the
--       publication change. Closes the loop at the source: even if a
--       future migration / dashboard click forgets to harden RLS first,
--       the database refuses to ship the table to the broker.
--
--   (4) Self-test at migration time: scan the current publication state,
--       RAISE NOTICE for each violation but NEVER abort — operators in
--       environments that intentionally ship unrestricted public data
--       (e.g. `feature_flags` admin-broadcast channel) need the migration
--       to apply, then they explicitly allow-list those tables via
--       `realtime_publication_allowlist`.
--
-- Allow-list semantics
-- ────────────────────
--   `public.realtime_publication_allowlist (table_schema, table_name,
--    reason text NOT NULL, allowed_at timestamptz, allowed_by text)`
--   captures tables that legitimately publish without per-row RLS — e.g.
--   `feature_flags` is global config readable by any authenticated user
--   by design (L18-06 invalidation broadcast). Adding a row here
--   exempts the table from the guard and event trigger. The reason is
--   mandatory so the audit trail shows WHY each exemption exists.
--
-- Operational impact
-- ──────────────────
--   • No schema mutation on existing tables, no RLS policy change.
--   • Guard runs in microseconds (single catalog scan).
--   • Event trigger fires on EVERY DDL but exits in O(1) when the DDL
--     is not publication-related.
--   • If the publication is currently empty (Supabase ships it empty),
--     this migration is a no-op at runtime + future-proofs the system.
-- ============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Allow-list table — captures legitimate exemptions
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.realtime_publication_allowlist (
  table_schema text NOT NULL,
  table_name   text NOT NULL,
  reason       text NOT NULL CHECK (length(trim(reason)) >= 10),
  allowed_at   timestamptz NOT NULL DEFAULT now(),
  allowed_by   text NOT NULL DEFAULT current_user,
  PRIMARY KEY (table_schema, table_name)
);

COMMENT ON TABLE public.realtime_publication_allowlist IS
  'L02-08 — tables intentionally published via supabase_realtime without per-row RLS. Each row needs a written justification; the guard skips these.';

ALTER TABLE public.realtime_publication_allowlist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.realtime_publication_allowlist FORCE ROW LEVEL SECURITY;

-- Service role only — neither anon nor authenticated needs to see this.
DROP POLICY IF EXISTS service_role_all ON public.realtime_publication_allowlist;
CREATE POLICY service_role_all ON public.realtime_publication_allowlist
  FOR ALL TO service_role
  USING (true) WITH CHECK (true);

-- Seed today's known-safe broadcast tables. Each entry MUST have a
-- defensible reason — anyone reading this list six months from now should
-- understand why the table is exempt from the per-row RLS contract.
INSERT INTO public.realtime_publication_allowlist (table_schema, table_name, reason, allowed_by)
VALUES
  ('public', 'feature_flags',
   'L18-06 — feature flags are global runtime config readable by every authenticated client; broadcast invalidation is a design feature.',
   'l02-08-migration')
ON CONFLICT (table_schema, table_name) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Diagnostic: which tables in the publication fail the safety contract?
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_realtime_publication_unsafe_tables(
  p_publication text DEFAULT 'supabase_realtime'
)
RETURNS TABLE (
  table_schema    text,
  table_name      text,
  rls_enabled     boolean,
  has_select_pol  boolean,
  has_open_pol    boolean,    -- true if any SELECT/ALL policy has polqual IS NULL ("USING (true)")
  reason          text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
BEGIN
  RETURN QUERY
  WITH pub_tables AS (
    SELECT pt.schemaname AS table_schema,
           pt.tablename  AS table_name,
           c.oid         AS reloid,
           c.relrowsecurity AS rls_enabled
      FROM pg_publication_tables pt
      JOIN pg_class     c ON c.relname = pt.tablename
      JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = pt.schemaname
     WHERE pt.pubname = p_publication
  ),
  pol_summary AS (
    SELECT pt.table_schema,
           pt.table_name,
           pt.rls_enabled,
           bool_or(p.polcmd IN ('r', '*') AND p.polqual IS NOT NULL) AS has_select_pol,
           bool_or(p.polcmd IN ('r', '*') AND p.polqual IS NULL)     AS has_open_pol
      FROM pub_tables pt
      LEFT JOIN pg_policy p ON p.polrelid = pt.reloid
     GROUP BY pt.table_schema, pt.table_name, pt.rls_enabled
  )
  SELECT ps.table_schema,
         ps.table_name,
         ps.rls_enabled,
         COALESCE(ps.has_select_pol, false) AS has_select_pol,
         COALESCE(ps.has_open_pol,   false) AS has_open_pol,
         CASE
           WHEN NOT ps.rls_enabled                              THEN 'rls_disabled'
           WHEN COALESCE(ps.has_open_pol, false)                THEN 'tautological_select_policy_using_true'
           WHEN NOT COALESCE(ps.has_select_pol, false)          THEN 'no_select_policy'
           ELSE 'ok'
         END AS reason
    FROM pol_summary ps
   WHERE NOT EXISTS (
     SELECT 1
       FROM public.realtime_publication_allowlist al
      WHERE al.table_schema = ps.table_schema
        AND al.table_name   = ps.table_name
   )
     AND (
       NOT ps.rls_enabled
       OR COALESCE(ps.has_open_pol, false)
       OR NOT COALESCE(ps.has_select_pol, false)
     );
END;
$$;

COMMENT ON FUNCTION public.fn_realtime_publication_unsafe_tables(text) IS
  'L02-08 — diagnostic helper: returns one row per table in the named publication that fails the per-row RLS contract (RLS enabled + at least one SELECT policy with polqual IS NOT NULL + no SELECT policy with polqual IS NULL). Rows from realtime_publication_allowlist are excluded.';

GRANT EXECUTE ON FUNCTION public.fn_realtime_publication_unsafe_tables(text) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Assertion wrapper — RAISES on any violation
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_assert_realtime_publication_safe(
  p_publication text DEFAULT 'supabase_realtime'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
DECLARE
  v_violation_count integer;
  v_summary         text;
BEGIN
  SELECT count(*),
         string_agg(
           format('%I.%I (%s)', table_schema, table_name, reason),
           ', '
           ORDER BY table_schema, table_name
         )
    INTO v_violation_count, v_summary
    FROM public.fn_realtime_publication_unsafe_tables(p_publication);

  IF v_violation_count > 0 THEN
    RAISE EXCEPTION 'REALTIME_RLS_VIOLATION: % table(s) in publication % lack restrictive RLS — %',
      v_violation_count, p_publication, v_summary
      USING ERRCODE = 'P0009',
            HINT = 'Each offender must either (a) have RLS enabled with at least one SELECT policy whose USING expression is not NULL/true, or (b) be added to public.realtime_publication_allowlist with a written reason. See docs/runbooks/REALTIME_RLS_RUNBOOK.md.';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.fn_assert_realtime_publication_safe(text) IS
  'L02-08 — RAISES P0009 REALTIME_RLS_VIOLATION listing every table in the publication that fails the safety contract. Used by the DDL event trigger and callable ad-hoc by operators.';

GRANT EXECUTE ON FUNCTION public.fn_assert_realtime_publication_safe(text) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. DDL event trigger — re-asserts on every publication-touching DDL
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_realtime_publication_ddl_guard()
RETURNS event_trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
DECLARE
  v_obj record;
  v_touched boolean := false;
BEGIN
  -- Walk every command in this DDL transaction; only act on publication
  -- objects so unrelated DDL (CREATE TABLE, ALTER FUNCTION, etc.) costs
  -- one catalog scan and exits.
  FOR v_obj IN
    SELECT * FROM pg_event_trigger_ddl_commands()
   LOOP
    IF v_obj.classid = 'pg_publication'::regclass
       OR v_obj.object_type = 'publication'
       OR v_obj.command_tag IN ('ALTER PUBLICATION', 'CREATE PUBLICATION')
    THEN
      v_touched := true;
      EXIT;
    END IF;
  END LOOP;

  IF NOT v_touched THEN
    RETURN;
  END IF;

  -- Re-validate the canonical realtime publication. Other publications
  -- (logical replication to a warm standby, etc.) are out of scope —
  -- they don't fan out to authenticated end-users.
  PERFORM public.fn_assert_realtime_publication_safe('supabase_realtime');
END;
$$;

COMMENT ON FUNCTION public.fn_realtime_publication_ddl_guard() IS
  'L02-08 — event-trigger handler: rolls back any DDL that leaves supabase_realtime in an unsafe state (table without restrictive RLS and not in allowlist).';

-- DROP / CREATE pattern keeps the migration idempotent across re-applies
-- (event triggers do not support `CREATE OR REPLACE`).
DROP EVENT TRIGGER IF EXISTS trg_block_unsafe_realtime_publication;

CREATE EVENT TRIGGER trg_block_unsafe_realtime_publication
  ON ddl_command_end
  WHEN TAG IN ('ALTER PUBLICATION', 'CREATE PUBLICATION')
  EXECUTE FUNCTION public.fn_realtime_publication_ddl_guard();

COMMENT ON EVENT TRIGGER trg_block_unsafe_realtime_publication IS
  'L02-08 — fires after ALTER/CREATE PUBLICATION; aborts the txn if the resulting supabase_realtime publication contains a table that violates the per-row RLS contract.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Self-test at migration time — informational only
-- ─────────────────────────────────────────────────────────────────────────────
--
-- We deliberately use RAISE NOTICE (not EXCEPTION) here so the migration
-- can apply against any environment regardless of pre-existing state. The
-- event trigger will enforce going forward; the operator team uses the
-- notices below to triage existing offenders post-migration.
--
DO $$
DECLARE
  v_offender record;
  v_count    integer := 0;
BEGIN
  -- Skip silently if the publication doesn't exist (rare — fresh
  -- non-Supabase Postgres). The event trigger remains armed and will
  -- catch any later CREATE PUBLICATION supabase_realtime.
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    RAISE NOTICE '[L02-08] supabase_realtime publication not present — guard armed for future creation.';
    RETURN;
  END IF;

  FOR v_offender IN
    SELECT * FROM public.fn_realtime_publication_unsafe_tables('supabase_realtime')
  LOOP
    v_count := v_count + 1;
    RAISE NOTICE '[L02-08.violation] %.%  reason=%  rls_enabled=%  has_select_pol=%  has_open_pol=%',
      v_offender.table_schema, v_offender.table_name, v_offender.reason,
      v_offender.rls_enabled, v_offender.has_select_pol, v_offender.has_open_pol;
  END LOOP;

  IF v_count = 0 THEN
    RAISE NOTICE '[L02-08] supabase_realtime publication clean — no violations.';
  ELSE
    RAISE NOTICE '[L02-08] % violation(s) listed above. The DDL event trigger will block future ALTER PUBLICATION attempts until each is either (a) hardened with restrictive RLS or (b) added to public.realtime_publication_allowlist.', v_count;
  END IF;
END;
$$;

COMMIT;
