-- ============================================================================
-- L08-08 — audit_logs retention + partitioning primitives
-- ============================================================================
--
-- Finding (docs/audit/findings/L08-08-audit-logs-sem-retencao-particionamento.md):
--   `public.audit_logs` grows indefinitely. 100M+ rows after ~2 years,
--   compliance queries take minutes, backups inflate. LGPD Art. 16
--   (retention limited to the purpose) + Art. 37 (accountability window)
--   require an explicit retention window — not "forever".
--
-- Scope of THIS migration (deliberately conservative):
--   (1) Retention config table declaring per-audit-table window in days.
--   (2) Append-only run-log table recording every retention pass.
--   (3) A SECURITY DEFINER helper that DELETEs rows older than the window
--       in a batched loop, with a tightly scoped bypass of the L10-08
--       append-only trigger (session GUC `audit.retention_pass='on'`,
--       honoured for DELETE only — UPDATE / TRUNCATE remain blocked).
--   (4) A monthly partition creator that is a NO-OP when the target
--       table is a regular heap. Ready for the future RANGE partition
--       conversion; does nothing harmful today.
--   (5) A dispatcher (`fn_audit_retention_run_all`) called by pg_cron
--       once per day at 05:15 UTC, isolated with an advisory lock so
--       two workers cannot process the same table in parallel.
--   (6) Update to `fn_audit_reject_mutation` (L10-08) to honour the
--       GUC bypass. UPDATE and TRUNCATE are NEVER bypassable — retention
--       is a pure row-level purge by `created_at`, nothing else.
--
-- Explicitly NOT in this migration (tracked as follow-ups):
--   * Converting live `public.audit_logs` to RANGE PARTITIONED. That is
--     a maintenance-window task (requires exclusive lock / table swap);
--     shipping retention first lets us reclaim size NOW and gives the
--     partition follow-up a known, capped row count to move.
--     Follow-up: `L08-08-partition-audit-logs`.
--   * Moving `portal_audit_log` or any other audit table to partitioned
--     storage — same rationale, separate follow-ups if volume justifies.
--   * Tombstone/soft-delete for forensics: retention is a HARD delete,
--     which is the LGPD-aligned behaviour. If a specific incident needs
--     rows preserved, the runbook §Forensic Freeze playbook disables the
--     config row before the next cron fires.
--
-- LGPD / fiscal retention matrix (see runbook §3 for full derivation):
--   * `public.audit_logs`                 — 730 days (~2 anos)
--   * `public.portal_audit_log`            — 730 days (~2 anos)
--   * `public.cron_edge_retry_attempts`    —  90 days  (ops-only)
--   * `public.wallet_drift_events`         — 365 days  (drift forensics)
--   * `public.custody_daily_cap_changes`   — 1825 days (5 anos fiscal)
--   * `public.coin_ledger_pii_redactions`  — 1825 days (5 anos fiscal)
--   * `public.consent_events`              — NULL       (LGPD Art. 8 §6:
--                                                       prova de consentimento)
--
-- Security properties preserved:
--   * L10-08 trigger remains armed on every registered audit table.
--   * Bypass GUC is per-transaction (`SET LOCAL`), never per-session.
--     A cron worker cannot leak the bypass into a subsequent connection.
--   * Bypass is DELETE-only. UPDATE / TRUNCATE remain blocked with
--     P0010 regardless of the GUC.
--   * Every retention pass leaves an append-only row in
--     `public.audit_logs_retention_runs` — the retention trail is itself
--     append-only and protected by the same L10-08 trigger machinery.
-- ============================================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────────────────
-- 1. Retention config — one row per audit table under retention control
-- ──────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.audit_logs_retention_config (
  schema_name     text NOT NULL,
  table_name      text NOT NULL,
  retention_days  integer
                  CHECK (retention_days IS NULL
                         OR (retention_days BETWEEN 30 AND 3650)),
  enabled         boolean NOT NULL DEFAULT true,
  batch_limit     integer NOT NULL DEFAULT 10000
                  CHECK (batch_limit BETWEEN 100 AND 100000),
  max_iterations  integer NOT NULL DEFAULT 20
                  CHECK (max_iterations BETWEEN 1 AND 200),
  timestamp_column text NOT NULL DEFAULT 'created_at'
                  CHECK (length(trim(timestamp_column)) BETWEEN 1 AND 63),
  note            text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (schema_name, table_name)
);

COMMENT ON TABLE public.audit_logs_retention_config IS
  'L08-08: per-audit-table retention window. `retention_days IS NULL` means '
  '"keep forever" (required for consent_events under LGPD Art. 8 §6). '
  '`enabled=false` pauses retention without deleting the config row — used '
  'by the forensic-freeze playbook.';

ALTER TABLE public.audit_logs_retention_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs_retention_config FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS audit_logs_retention_config_service_rw
  ON public.audit_logs_retention_config;
CREATE POLICY audit_logs_retention_config_service_rw
  ON public.audit_logs_retention_config
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Auto-bump updated_at
CREATE OR REPLACE FUNCTION public.fn_audit_logs_retention_config_touch()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_logs_retention_config_touch
  ON public.audit_logs_retention_config;
CREATE TRIGGER trg_audit_logs_retention_config_touch
  BEFORE UPDATE ON public.audit_logs_retention_config
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_logs_retention_config_touch();

-- ──────────────────────────────────────────────────────────────────────────
-- 2. Retention runs — append-only execution log
-- ──────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.audit_logs_retention_runs (
  id              bigserial PRIMARY KEY,
  schema_name     text NOT NULL,
  table_name      text NOT NULL,
  ran_at          timestamptz NOT NULL DEFAULT now(),
  cutoff_at       timestamptz,
  retention_days  integer,
  rows_deleted    bigint NOT NULL DEFAULT 0
                  CHECK (rows_deleted >= 0),
  iterations      integer NOT NULL DEFAULT 0
                  CHECK (iterations >= 0),
  duration_ms     integer NOT NULL DEFAULT 0
                  CHECK (duration_ms >= 0),
  status          text NOT NULL
                  CHECK (status IN (
                    'ok',
                    'skipped_disabled',
                    'skipped_no_retention',
                    'skipped_no_table',
                    'skipped_no_column',
                    'skipped_locked',
                    'error'
                  )),
  error_message   text,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_retention_runs_ran_at
  ON public.audit_logs_retention_runs (ran_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_retention_runs_schema_table_ran_at
  ON public.audit_logs_retention_runs (schema_name, table_name, ran_at DESC);

COMMENT ON TABLE public.audit_logs_retention_runs IS
  'L08-08: append-only log of retention passes. One row per (table, cron fire). '
  'Used by the runbook detection signals and the CI guard `audit:audit-logs-retention`.';

ALTER TABLE public.audit_logs_retention_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs_retention_runs FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS audit_logs_retention_runs_service_rw
  ON public.audit_logs_retention_runs;
CREATE POLICY audit_logs_retention_runs_service_rw
  ON public.audit_logs_retention_runs
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ──────────────────────────────────────────────────────────────────────────
-- 3. Update L10-08 trigger to honour a GUC-scoped DELETE bypass
-- ──────────────────────────────────────────────────────────────────────────
--
-- Bypass properties (defended in runbook §2 Invariants table):
--   * Bypass is checked via `current_setting('audit.retention_pass', true)`.
--     Missing setting returns NULL → the `=` is FALSE → no bypass.
--   * Only the exact literal 'on' enables the bypass; typos / different
--     casings / boolean-like ('true', '1') are REJECTED.
--   * Bypass is DELETE-only. UPDATE and TRUNCATE still raise P0010 even
--     when the GUC is 'on' — retention is a DELETE-by-timestamp purge;
--     any UPDATE path would be a redaction and belongs to L04-07 / LGPD
--     opt-out flows, not retention.
--   * The bypass path still emits a RAISE NOTICE so Logflare shows which
--     rows were retention-deleted (ops visibility without row-level dump).
--
CREATE OR REPLACE FUNCTION public.fn_audit_reject_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_op     text;
  v_bypass text;
BEGIN
  v_op     := TG_OP;
  v_bypass := current_setting('audit.retention_pass', true);

  -- L08-08 retention bypass: only for DELETE, only when GUC is exactly 'on'.
  IF v_op = 'DELETE' AND v_bypass = 'on' THEN
    RAISE NOTICE 'L08-08: retention DELETE on %.% (row allowed via audit.retention_pass)',
      TG_TABLE_SCHEMA, TG_TABLE_NAME;
    RETURN OLD;
  END IF;

  RAISE WARNING 'L10-08: attempt to % append-only audit table %.% by session_user=% current_user=%',
    v_op, TG_TABLE_SCHEMA, TG_TABLE_NAME, session_user, current_user;

  IF v_op = 'DELETE' THEN
    RAISE EXCEPTION
      'L10-08: DELETE blocked on append-only audit table %.%',
      TG_TABLE_SCHEMA, TG_TABLE_NAME
      USING ERRCODE = 'P0010',
            HINT    = 'Drop the trigger in a reviewed migration only, or set audit.retention_pass=on inside the retention helper. See docs/runbooks/AUDIT_LOGS_APPEND_ONLY_RUNBOOK.md.',
            DETAIL  = 'append_only_delete_blocked';
  ELSIF v_op = 'UPDATE' THEN
    RAISE EXCEPTION
      'L10-08: UPDATE blocked on append-only audit table %.% (bypass ignored — retention never UPDATEs)',
      TG_TABLE_SCHEMA, TG_TABLE_NAME
      USING ERRCODE = 'P0010',
            HINT    = 'Drop the trigger in a reviewed migration only. See docs/runbooks/AUDIT_LOGS_APPEND_ONLY_RUNBOOK.md.',
            DETAIL  = 'append_only_update_blocked';
  ELSIF v_op = 'TRUNCATE' THEN
    RAISE EXCEPTION
      'L10-08: TRUNCATE blocked on append-only audit table %.% (bypass ignored — retention never TRUNCATEs)',
      TG_TABLE_SCHEMA, TG_TABLE_NAME
      USING ERRCODE = 'P0010',
            DETAIL  = 'append_only_truncate_blocked';
  END IF;

  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.fn_audit_reject_mutation() IS
  'L10-08 + L08-08: BEFORE UPDATE/DELETE/TRUNCATE trigger. Rejects every '
  'mutation on append-only audit tables with P0010. L08-08 narrowly allows '
  'DELETE when the txn sets audit.retention_pass=on (used only by the '
  'retention helper). UPDATE and TRUNCATE are NEVER bypassable.';

-- ──────────────────────────────────────────────────────────────────────────
-- 4. Retention helper — batched DELETE with scoped bypass
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_audit_retention_delete_batch(
  p_schema  text,
  p_table   text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $fn$
DECLARE
  v_cfg            public.audit_logs_retention_config%ROWTYPE;
  v_column_exists  boolean;
  v_table_exists   boolean;
  v_cutoff         timestamptz;
  v_start          timestamptz := clock_timestamp();
  v_total_deleted  bigint := 0;
  v_iter_deleted   bigint := 0;
  v_iteration      integer := 0;
  v_status         text := 'ok';
  v_error          text;
  v_sql            text;
BEGIN
  -- Load config (tolerate missing row — caller asked for an unknown table).
  SELECT * INTO v_cfg
  FROM public.audit_logs_retention_config
  WHERE schema_name = p_schema AND table_name = p_table;

  IF NOT FOUND THEN
    INSERT INTO public.audit_logs_retention_runs
      (schema_name, table_name, cutoff_at, retention_days,
       rows_deleted, iterations, duration_ms, status, error_message)
    VALUES
      (p_schema, p_table, NULL, NULL,
       0, 0,
       GREATEST(0, (extract(epoch from clock_timestamp() - v_start) * 1000)::int),
       'skipped_no_retention', 'config row missing');
    RETURN jsonb_build_object(
      'status', 'skipped_no_retention',
      'rows_deleted', 0,
      'iterations', 0
    );
  END IF;

  IF NOT v_cfg.enabled THEN
    INSERT INTO public.audit_logs_retention_runs
      (schema_name, table_name, cutoff_at, retention_days,
       rows_deleted, iterations, duration_ms, status)
    VALUES
      (p_schema, p_table, NULL, v_cfg.retention_days,
       0, 0,
       GREATEST(0, (extract(epoch from clock_timestamp() - v_start) * 1000)::int),
       'skipped_disabled');
    RETURN jsonb_build_object(
      'status', 'skipped_disabled',
      'rows_deleted', 0,
      'iterations', 0
    );
  END IF;

  IF v_cfg.retention_days IS NULL THEN
    INSERT INTO public.audit_logs_retention_runs
      (schema_name, table_name, cutoff_at, retention_days,
       rows_deleted, iterations, duration_ms, status, error_message)
    VALUES
      (p_schema, p_table, NULL, NULL,
       0, 0,
       GREATEST(0, (extract(epoch from clock_timestamp() - v_start) * 1000)::int),
       'skipped_no_retention', 'retention_days is NULL (keep forever)');
    RETURN jsonb_build_object(
      'status', 'skipped_no_retention',
      'rows_deleted', 0,
      'iterations', 0
    );
  END IF;

  -- Table must exist in this env (platform-managed tables may be absent).
  SELECT EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = p_schema
      AND c.relname = p_table
      AND c.relkind IN ('r','p')
  ) INTO v_table_exists;

  IF NOT v_table_exists THEN
    INSERT INTO public.audit_logs_retention_runs
      (schema_name, table_name, cutoff_at, retention_days,
       rows_deleted, iterations, duration_ms, status, error_message)
    VALUES
      (p_schema, p_table, NULL, v_cfg.retention_days,
       0, 0,
       GREATEST(0, (extract(epoch from clock_timestamp() - v_start) * 1000)::int),
       'skipped_no_table', format('%I.%I not present in this database', p_schema, p_table));
    RETURN jsonb_build_object(
      'status', 'skipped_no_table',
      'rows_deleted', 0,
      'iterations', 0
    );
  END IF;

  -- Column must exist (customers may use a different timestamp column).
  SELECT EXISTS (
    SELECT 1
    FROM pg_attribute a
    JOIN pg_class c ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = p_schema
      AND c.relname = p_table
      AND a.attname = v_cfg.timestamp_column
      AND a.attnum > 0
      AND NOT a.attisdropped
  ) INTO v_column_exists;

  IF NOT v_column_exists THEN
    INSERT INTO public.audit_logs_retention_runs
      (schema_name, table_name, cutoff_at, retention_days,
       rows_deleted, iterations, duration_ms, status, error_message)
    VALUES
      (p_schema, p_table, NULL, v_cfg.retention_days,
       0, 0,
       GREATEST(0, (extract(epoch from clock_timestamp() - v_start) * 1000)::int),
       'skipped_no_column',
       format('column %I not found on %I.%I', v_cfg.timestamp_column, p_schema, p_table));
    RETURN jsonb_build_object(
      'status', 'skipped_no_column',
      'rows_deleted', 0,
      'iterations', 0
    );
  END IF;

  v_cutoff := now() - make_interval(days => v_cfg.retention_days);

  -- Scoped bypass: ONLY this transaction, ONLY for DELETE on append-only tables.
  PERFORM set_config('audit.retention_pass', 'on', true);

  BEGIN
    v_sql := format(
      'DELETE FROM %I.%I WHERE ctid IN ('
      '  SELECT ctid FROM %I.%I'
      '  WHERE %I < $1'
      '  ORDER BY %I ASC'
      '  LIMIT %s'
      ')',
      p_schema, p_table,
      p_schema, p_table,
      v_cfg.timestamp_column,
      v_cfg.timestamp_column,
      v_cfg.batch_limit
    );

    LOOP
      v_iteration := v_iteration + 1;
      EXECUTE v_sql USING v_cutoff;
      GET DIAGNOSTICS v_iter_deleted = ROW_COUNT;
      v_total_deleted := v_total_deleted + v_iter_deleted;

      EXIT WHEN v_iter_deleted = 0;
      EXIT WHEN v_iteration >= v_cfg.max_iterations;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    v_status := 'error';
    v_error  := SQLERRM;
  END;

  -- Record result (INSERT always happens — failures are observable).
  INSERT INTO public.audit_logs_retention_runs
    (schema_name, table_name, cutoff_at, retention_days,
     rows_deleted, iterations, duration_ms, status, error_message)
  VALUES
    (p_schema, p_table, v_cutoff, v_cfg.retention_days,
     v_total_deleted, v_iteration,
     GREATEST(0, (extract(epoch from clock_timestamp() - v_start) * 1000)::int),
     v_status, v_error);

  IF v_status = 'error' THEN
    RAISE WARNING 'L08-08: retention on %.% failed after % rows: %',
      p_schema, p_table, v_total_deleted, v_error;
  END IF;

  RETURN jsonb_build_object(
    'status',       v_status,
    'rows_deleted', v_total_deleted,
    'iterations',   v_iteration,
    'cutoff_at',    v_cutoff,
    'error',        v_error
  );
END;
$fn$;

COMMENT ON FUNCTION public.fn_audit_retention_delete_batch(text, text) IS
  'L08-08: deletes rows older than config.retention_days from <schema>.<table> '
  'in batches of config.batch_limit, up to config.max_iterations per call. '
  'Uses audit.retention_pass=on (txn-local) to satisfy the L10-08 append-only '
  'trigger. Always writes a row to audit_logs_retention_runs.';

REVOKE ALL ON FUNCTION public.fn_audit_retention_delete_batch(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_audit_retention_delete_batch(text, text) FROM anon;
REVOKE ALL ON FUNCTION public.fn_audit_retention_delete_batch(text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_audit_retention_delete_batch(text, text) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 5. Dispatcher — called by pg_cron, iterates config
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_audit_retention_run_all()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $fn$
DECLARE
  v_row        public.audit_logs_retention_config%ROWTYPE;
  v_result     jsonb;
  v_results    jsonb := '[]'::jsonb;
  v_got_lock   boolean;
  v_total      bigint := 0;
  v_tables     integer := 0;
BEGIN
  -- Advisory lock key: stable hash of 'audit_logs_retention_run_all'.
  -- Using pg_try_advisory_xact_lock avoids overlapping runs.
  v_got_lock := pg_try_advisory_xact_lock(8082408808::bigint);
  IF NOT v_got_lock THEN
    RAISE NOTICE 'L08-08: previous retention run still holds the lock — skipping';
    RETURN jsonb_build_object('status', 'skipped_locked', 'tables', 0);
  END IF;

  FOR v_row IN
    SELECT *
    FROM public.audit_logs_retention_config
    WHERE enabled = true
      AND retention_days IS NOT NULL
    ORDER BY schema_name, table_name
  LOOP
    BEGIN
      v_result := public.fn_audit_retention_delete_batch(v_row.schema_name, v_row.table_name);
      v_total := v_total + COALESCE((v_result->>'rows_deleted')::bigint, 0);
      v_tables := v_tables + 1;
      v_results := v_results || jsonb_build_object(
        'schema', v_row.schema_name,
        'table',  v_row.table_name,
        'result', v_result
      );
    EXCEPTION WHEN OTHERS THEN
      -- One failing table must not block the others.
      INSERT INTO public.audit_logs_retention_runs
        (schema_name, table_name, cutoff_at, retention_days,
         rows_deleted, iterations, duration_ms, status, error_message)
      VALUES
        (v_row.schema_name, v_row.table_name, NULL, v_row.retention_days,
         0, 0, 0, 'error', SQLERRM);
      RAISE WARNING 'L08-08: retention run on %.% failed: %',
        v_row.schema_name, v_row.table_name, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'status',       'ok',
    'tables',       v_tables,
    'total_deleted', v_total,
    'per_table',    v_results
  );
END;
$fn$;

COMMENT ON FUNCTION public.fn_audit_retention_run_all() IS
  'L08-08: iterates audit_logs_retention_config (enabled AND retention_days IS NOT NULL) '
  'and calls fn_audit_retention_delete_batch per row. One failing table does not '
  'block the others — each failure is logged in audit_logs_retention_runs.';

REVOKE ALL ON FUNCTION public.fn_audit_retention_run_all() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_audit_retention_run_all() FROM anon;
REVOKE ALL ON FUNCTION public.fn_audit_retention_run_all() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_audit_retention_run_all() TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 6. Monthly partition creator — NO-OP for unpartitioned tables
-- ──────────────────────────────────────────────────────────────────────────
--
-- Contract: when <schema>.<table> is a RANGE partitioned table by some
-- timestamp column, create the child partition covering [target_month,
-- target_month + 1 month) if it does not already exist. Otherwise return
-- `{"status": "skipped_not_partitioned"}`. This lets us ship the helper
-- NOW and have it be useful the moment we convert a live table to
-- partitioned storage (follow-up L08-08-partition-audit-logs) — no code
-- change needed at that point.
--
CREATE OR REPLACE FUNCTION public.fn_audit_ensure_monthly_partition(
  p_schema       text,
  p_table        text,
  p_month_start  date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $fn$
DECLARE
  v_relkind      char;
  v_partstrat    char;
  v_child_name   text;
  v_child_exists boolean;
  v_month_end    date := (p_month_start + INTERVAL '1 month')::date;
BEGIN
  IF p_month_start IS NULL THEN
    RAISE EXCEPTION 'L08-08: p_month_start is required'
      USING ERRCODE = '22023';
  END IF;

  IF date_trunc('month', p_month_start)::date <> p_month_start THEN
    RAISE EXCEPTION 'L08-08: p_month_start must be the first day of a month (got %)', p_month_start
      USING ERRCODE = '22023';
  END IF;

  SELECT c.relkind
  INTO v_relkind
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = p_schema AND c.relname = p_table;

  IF v_relkind IS NULL THEN
    RETURN jsonb_build_object('status', 'skipped_no_table');
  END IF;

  IF v_relkind <> 'p' THEN
    RETURN jsonb_build_object('status', 'skipped_not_partitioned');
  END IF;

  SELECT p.partstrat
  INTO v_partstrat
  FROM pg_partitioned_table p
  JOIN pg_class c ON c.oid = p.partrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = p_schema AND c.relname = p_table;

  IF v_partstrat <> 'r' THEN
    RETURN jsonb_build_object('status', 'skipped_not_range_partitioned',
                              'partstrat', v_partstrat::text);
  END IF;

  v_child_name := format('%s_y%sm%s',
    p_table,
    to_char(p_month_start, 'YYYY'),
    to_char(p_month_start, 'MM')
  );

  SELECT EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = p_schema AND c.relname = v_child_name
  ) INTO v_child_exists;

  IF v_child_exists THEN
    RETURN jsonb_build_object(
      'status', 'already_exists',
      'partition', format('%I.%I', p_schema, v_child_name)
    );
  END IF;

  EXECUTE format(
    'CREATE TABLE %I.%I PARTITION OF %I.%I FOR VALUES FROM (%L) TO (%L)',
    p_schema, v_child_name,
    p_schema, p_table,
    p_month_start, v_month_end
  );

  RETURN jsonb_build_object(
    'status', 'created',
    'partition', format('%I.%I', p_schema, v_child_name),
    'from', p_month_start,
    'to',   v_month_end
  );
END;
$fn$;

COMMENT ON FUNCTION public.fn_audit_ensure_monthly_partition(text, text, date) IS
  'L08-08: idempotent monthly partition creator. No-op if the target table is '
  'not RANGE partitioned. Ready for the follow-up that converts audit_logs to '
  'partitioned storage.';

REVOKE ALL ON FUNCTION public.fn_audit_ensure_monthly_partition(text, text, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_audit_ensure_monthly_partition(text, text, date) FROM anon;
REVOKE ALL ON FUNCTION public.fn_audit_ensure_monthly_partition(text, text, date) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_audit_ensure_monthly_partition(text, text, date) TO service_role;

-- Monthly creator for all partitioned audit tables — called by cron.
CREATE OR REPLACE FUNCTION public.fn_audit_retention_ensure_next_month_all()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $fn$
DECLARE
  v_row      public.audit_logs_retention_config%ROWTYPE;
  v_result   jsonb;
  v_results  jsonb := '[]'::jsonb;
  v_target   date := (date_trunc('month', now()) + INTERVAL '1 month')::date;
BEGIN
  FOR v_row IN
    SELECT *
    FROM public.audit_logs_retention_config
    WHERE enabled = true
    ORDER BY schema_name, table_name
  LOOP
    BEGIN
      v_result := public.fn_audit_ensure_monthly_partition(
        v_row.schema_name, v_row.table_name, v_target);
      v_results := v_results || jsonb_build_object(
        'schema', v_row.schema_name,
        'table',  v_row.table_name,
        'target', v_target,
        'result', v_result
      );
    EXCEPTION WHEN OTHERS THEN
      v_results := v_results || jsonb_build_object(
        'schema', v_row.schema_name,
        'table',  v_row.table_name,
        'target', v_target,
        'error',  SQLERRM
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'status',     'ok',
    'month',      v_target,
    'per_table',  v_results
  );
END;
$fn$;

COMMENT ON FUNCTION public.fn_audit_retention_ensure_next_month_all() IS
  'L08-08: ensures next-month partition exists for every enabled retention-config '
  'entry that is already on partitioned storage. No-op today (nothing partitioned); '
  'useful immediately after the partition conversion follow-up lands.';

REVOKE ALL ON FUNCTION public.fn_audit_retention_ensure_next_month_all() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_audit_retention_ensure_next_month_all() FROM anon;
REVOKE ALL ON FUNCTION public.fn_audit_retention_ensure_next_month_all() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_audit_retention_ensure_next_month_all() TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 7. Register retention_runs in the L10-08 append-only registry
-- ──────────────────────────────────────────────────────────────────────────
SELECT public.fn_audit_install_append_only_guard(
  'public',
  'audit_logs_retention_runs',
  'L08-08: retention run log is itself append-only (append forever, never updated).'
);

-- Update the known-table list so the L10-08 assert treats this one as expected.
CREATE OR REPLACE FUNCTION public.fn_audit_assert_append_only_shape()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
DECLARE
  v_missing text[] := ARRAY[]::text[];
  v_row record;
  v_known text[];
  v_t text;
BEGIN
  FOR v_row IN
    SELECT schema_name, table_name
    FROM public.audit_append_only_config
    WHERE mode = 'strict'
  LOOP
    IF NOT public.fn_audit_has_append_only_guard(v_row.schema_name, v_row.table_name) THEN
      v_missing := v_missing || format('%s.%s', v_row.schema_name, v_row.table_name);
    END IF;
  END LOOP;

  v_known := ARRAY[
    'portal_audit_log',
    'coin_ledger_pii_redactions',
    'cron_edge_retry_attempts',
    'wallet_drift_events',
    'custody_daily_cap_changes',
    'consent_events',
    'audit_logs',
    'audit_logs_retention_runs'
  ];

  FOREACH v_t IN ARRAY v_known LOOP
    IF EXISTS (
      SELECT 1 FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = v_t AND c.relkind IN ('r','p')
    ) AND NOT EXISTS (
      SELECT 1 FROM public.audit_append_only_config
      WHERE schema_name = 'public' AND table_name = v_t
    ) THEN
      v_missing := v_missing || format('unregistered:public.%s', v_t);
    END IF;
  END LOOP;

  IF array_length(v_missing, 1) IS NOT NULL THEN
    RAISE EXCEPTION 'L10-08: append-only protection missing for: %', array_to_string(v_missing, ', ')
      USING ERRCODE = 'P0010',
            HINT    = 'Invoke public.fn_audit_install_append_only_guard(schema, table) for each. See docs/runbooks/AUDIT_LOGS_APPEND_ONLY_RUNBOOK.md.';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_audit_assert_append_only_shape() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_audit_assert_append_only_shape() FROM anon;
REVOKE ALL ON FUNCTION public.fn_audit_assert_append_only_shape() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_audit_assert_append_only_shape() TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 8. Seed retention config (defensive: only for tables present in this env)
-- ──────────────────────────────────────────────────────────────────────────
INSERT INTO public.audit_logs_retention_config
  (schema_name, table_name, retention_days, enabled, note)
VALUES
  ('public', 'audit_logs',                  730,  true,
   'LGPD Art. 37 accountability window (~2 years). Platform-managed table — safe no-op if absent.'),
  ('public', 'portal_audit_log',            730,  true,
   'Portal admin actions — 2 years for internal incident forensics.'),
  ('public', 'cron_edge_retry_attempts',     90,  true,
   'Ops-only visibility; 90 days covers quarterly SLO review cycle.'),
  ('public', 'wallet_drift_events',         365,  true,
   'Drift forensics — 1 year to cross-reference with yearly reconciliation cadence.'),
  ('public', 'custody_daily_cap_changes',  1825,  true,
   'Fiscal retention (Lei 9.430/96) — 5 years for BCB/receita trail.'),
  ('public', 'coin_ledger_pii_redactions', 1825,  true,
   'Fiscal retention — 5 years mirrors coin_ledger immutable window.'),
  ('public', 'consent_events',              NULL, true,
   'LGPD Art. 8 §6 — consent proof must be retained as long as processing occurs. NULL = keep forever.')
ON CONFLICT (schema_name, table_name) DO NOTHING;

-- ──────────────────────────────────────────────────────────────────────────
-- 9. Assert helper — shape check used by CI
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_audit_retention_assert_shape()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $fn$
DECLARE
  v_count  integer;
  v_known  text[];
  v_t      text;
  v_missing text[] := ARRAY[]::text[];
BEGIN
  -- At least the 7 canonical entries must exist.
  SELECT count(*) INTO v_count
  FROM public.audit_logs_retention_config;
  IF v_count < 7 THEN
    RAISE EXCEPTION 'L08-08: retention config has only % rows (expected >= 7)', v_count
      USING ERRCODE = 'P0010';
  END IF;

  v_known := ARRAY[
    'audit_logs',
    'portal_audit_log',
    'cron_edge_retry_attempts',
    'wallet_drift_events',
    'custody_daily_cap_changes',
    'coin_ledger_pii_redactions',
    'consent_events'
  ];
  FOREACH v_t IN ARRAY v_known LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.audit_logs_retention_config
      WHERE schema_name = 'public' AND table_name = v_t
    ) THEN
      v_missing := v_missing || v_t;
    END IF;
  END LOOP;

  IF array_length(v_missing, 1) IS NOT NULL THEN
    RAISE EXCEPTION 'L08-08: retention config missing entries for: %',
      array_to_string(v_missing, ', ')
      USING ERRCODE = 'P0010';
  END IF;

  -- consent_events must be keep-forever.
  IF NOT EXISTS (
    SELECT 1 FROM public.audit_logs_retention_config
    WHERE schema_name = 'public'
      AND table_name  = 'consent_events'
      AND retention_days IS NULL
  ) THEN
    RAISE EXCEPTION 'L08-08: consent_events must have retention_days=NULL (LGPD Art. 8 §6)'
      USING ERRCODE = 'P0010';
  END IF;

  -- Retention runs table must be append-only-guarded.
  IF NOT public.fn_audit_has_append_only_guard('public', 'audit_logs_retention_runs') THEN
    RAISE EXCEPTION 'L08-08: audit_logs_retention_runs is not protected by the append-only trigger'
      USING ERRCODE = 'P0010';
  END IF;
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_audit_retention_assert_shape() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_audit_retention_assert_shape() FROM anon;
REVOKE ALL ON FUNCTION public.fn_audit_retention_assert_shape() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_audit_retention_assert_shape() TO service_role;

COMMIT;

-- ============================================================================
-- 10. pg_cron schedules (outside the BEGIN block; cron.schedule is global)
-- ============================================================================
DO $schedule$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE '[L08-08] pg_cron extension not available in this env — skipping schedules';
    RETURN;
  END IF;

  BEGIN
    PERFORM cron.unschedule('audit-logs-retention-daily');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM cron.schedule(
    'audit-logs-retention-daily',
    '15 5 * * *',
    $cron$ SELECT public.fn_audit_retention_run_all(); $cron$
  );

  BEGIN
    PERFORM cron.unschedule('audit-logs-retention-next-month');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM cron.schedule(
    'audit-logs-retention-next-month',
    '0 2 25 * *',
    $cron$ SELECT public.fn_audit_retention_ensure_next_month_all(); $cron$
  );
END
$schedule$;

-- ============================================================================
-- Self-test (separate transaction — visible errors abort the migration)
-- ============================================================================
DO $L08_08_selftest$
DECLARE
  v_result     jsonb;
  v_count      integer;
  v_bypass_ok  boolean := false;
BEGIN
  -- (a) Config seeded with expected cardinality + invariants.
  PERFORM public.fn_audit_retention_assert_shape();

  -- (b) Helper returns skipped_no_retention for unknown table.
  v_result := public.fn_audit_retention_delete_batch('public', '__l08_08_nonexistent_zzz__');
  IF v_result->>'status' <> 'skipped_no_retention' THEN
    RAISE EXCEPTION 'L08-08 selftest: unknown table should yield skipped_no_retention, got %', v_result;
  END IF;

  -- (c) Helper returns skipped_no_retention for consent_events (keep forever).
  v_result := public.fn_audit_retention_delete_batch('public', 'consent_events');
  IF v_result->>'status' <> 'skipped_no_retention' THEN
    RAISE EXCEPTION 'L08-08 selftest: consent_events must be keep-forever, got %', v_result;
  END IF;

  -- (d) Retention runs table exists and has rows from steps (b)(c).
  SELECT count(*) INTO v_count FROM public.audit_logs_retention_runs;
  IF v_count < 2 THEN
    RAISE EXCEPTION 'L08-08 selftest: expected >= 2 retention_runs rows, got %', v_count;
  END IF;

  -- (e) Append-only guard really blocks DELETE on retention_runs without bypass.
  BEGIN
    DELETE FROM public.audit_logs_retention_runs
     WHERE id = (SELECT id FROM public.audit_logs_retention_runs LIMIT 1);
    RAISE EXCEPTION 'L08-08 selftest: DELETE on audit_logs_retention_runs should have been blocked';
  EXCEPTION WHEN SQLSTATE 'P0010' THEN
    NULL;
  END;

  -- (f) Append-only guard still blocks UPDATE even with bypass GUC.
  BEGIN
    PERFORM set_config('audit.retention_pass', 'on', true);
    UPDATE public.audit_logs_retention_runs
       SET error_message = 'selftest tamper'
     WHERE id = (SELECT id FROM public.audit_logs_retention_runs LIMIT 1);
    RAISE EXCEPTION 'L08-08 selftest: UPDATE on audit_logs_retention_runs must NEVER be bypassable';
  EXCEPTION WHEN SQLSTATE 'P0010' THEN
    v_bypass_ok := true;
  END;
  IF NOT v_bypass_ok THEN
    RAISE EXCEPTION 'L08-08 selftest: UPDATE bypass check did not fire';
  END IF;

  -- (g) Partition helper is a no-op for unpartitioned tables.
  v_result := public.fn_audit_ensure_monthly_partition(
    'public', 'audit_logs_retention_runs', date_trunc('month', now())::date);
  IF v_result->>'status' NOT IN ('skipped_not_partitioned', 'skipped_no_table') THEN
    RAISE EXCEPTION 'L08-08 selftest: partition helper on unpartitioned table must skip, got %', v_result;
  END IF;

  -- (h) Partition helper rejects non-month-start dates.
  BEGIN
    v_result := public.fn_audit_ensure_monthly_partition(
      'public', 'audit_logs_retention_runs', '2026-04-15'::date);
    RAISE EXCEPTION 'L08-08 selftest: partition helper should reject non-month-start date';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  RAISE NOTICE '[L08-08.selftest] OK — retention primitives shipped, invariants enforced';
END
$L08_08_selftest$;
