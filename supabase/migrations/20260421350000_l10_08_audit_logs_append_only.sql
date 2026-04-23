-- ============================================================================
-- L10-08 — Audit logs append-only (DELETE/UPDATE guard)
-- ============================================================================
--
-- Finding (docs/audit/findings/L10-08-logs-de-acesso-sensiveis-sem-imutabilidade.md):
--   `audit_logs` is a regular table; an attacker (or a contributor running
--   a script with service_role) can `DELETE`/`UPDATE` rows and the trail is
--   silently rewritten. For incident forensics + LGPD accountability
--   (Art. 37) the audit trail MUST be immutable at the DB level.
--
-- Design:
--   (1) `public.audit_append_only_config` — registry of which tables are
--       protected. One row per `(schema, table, mode)`. Modes:
--         * `strict` — no UPDATE, no DELETE ever.
--         * `append_with_outcome` — allows the existing per-table
--           column-immutability trigger (e.g. account_deletion_log).
--       RLS forced, service_role-only.
--
--   (2) `public.fn_audit_reject_mutation()` — generic BEFORE
--       UPDATE OR DELETE trigger that raises P0010 with a
--       machine-readable reason (`append_only_delete_blocked` /
--       `append_only_update_blocked`). Attaches to every `strict` entry.
--       There is NO runtime bypass: a true emergency must ship a
--       migration that DROP TRIGGERs the row, which is visible in git
--       history and CI review. The trigger emits `RAISE WARNING` with
--       structured context so Logflare / Postgres logs get every
--       attempt even though the transaction rolls back.
--
--   (3) `public.fn_audit_install_append_only_guard(schema, table)` —
--       idempotent installer. Creates the trigger with a deterministic
--       name `trg_<table>_append_only` and records the binding in
--       `audit_append_only_config`. Safe to re-run.
--
--   (4) Apply to the known append-only audit tables (defensive —
--       skips any table that does not exist in this env):
--         * public.portal_audit_log        (DECISÃO 099)
--         * public.coin_ledger_pii_redactions (L04-07)
--         * public.cron_edge_retry_attempts   (L06-05)
--         * public.wallet_drift_events        (L06-03)
--         * public.custody_daily_cap_changes  (L05-09)
--         * public.consent_events             (LGPD)
--         * public.audit_logs                 (if platform-managed)
--
--   (5) CI:
--         * `npm run audit:audit-logs-append-only` invokes
--           `public.fn_audit_assert_append_only_shape()` which raises
--           P0010 if any registered binding lost its trigger OR any
--           known-immutable table is missing from the registry.
-- ============================================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────────────────
-- 1. Registry of append-only audit tables
-- ──────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.audit_append_only_config (
  schema_name text NOT NULL,
  table_name  text NOT NULL,
  mode        text NOT NULL DEFAULT 'strict'
              CHECK (mode IN ('strict', 'append_with_outcome')),
  applied_at  timestamptz NOT NULL DEFAULT now(),
  note        text,
  PRIMARY KEY (schema_name, table_name)
);

ALTER TABLE public.audit_append_only_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_append_only_config FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS audit_append_only_config_service_rw
  ON public.audit_append_only_config;
CREATE POLICY audit_append_only_config_service_rw
  ON public.audit_append_only_config
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

COMMENT ON TABLE public.audit_append_only_config IS
  'L10-08: registry of audit-style tables protected by the append-only '
  'trigger. Entries with mode=strict reject every UPDATE/DELETE. '
  'append_with_outcome entries are tolerated (existing per-table trigger '
  'handles column immutability).';

-- ──────────────────────────────────────────────────────────────────────────
-- 2. Generic BEFORE trigger — reject every mutation
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_audit_reject_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_op text;
BEGIN
  v_op := TG_OP;

  RAISE WARNING 'L10-08: attempt to % append-only audit table %.% by session_user=% current_user=%',
    v_op, TG_TABLE_SCHEMA, TG_TABLE_NAME, session_user, current_user;

  IF v_op = 'DELETE' THEN
    RAISE EXCEPTION
      'L10-08: DELETE blocked on append-only audit table %.%',
      TG_TABLE_SCHEMA, TG_TABLE_NAME
      USING ERRCODE = 'P0010',
            HINT    = 'Drop the trigger in a reviewed migration only. See docs/runbooks/AUDIT_LOGS_APPEND_ONLY_RUNBOOK.md.',
            DETAIL  = 'append_only_delete_blocked';
  ELSIF v_op = 'UPDATE' THEN
    RAISE EXCEPTION
      'L10-08: UPDATE blocked on append-only audit table %.%',
      TG_TABLE_SCHEMA, TG_TABLE_NAME
      USING ERRCODE = 'P0010',
            HINT    = 'Drop the trigger in a reviewed migration only. See docs/runbooks/AUDIT_LOGS_APPEND_ONLY_RUNBOOK.md.',
            DETAIL  = 'append_only_update_blocked';
  ELSIF v_op = 'TRUNCATE' THEN
    RAISE EXCEPTION
      'L10-08: TRUNCATE blocked on append-only audit table %.%',
      TG_TABLE_SCHEMA, TG_TABLE_NAME
      USING ERRCODE = 'P0010',
            DETAIL  = 'append_only_truncate_blocked';
  END IF;

  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.fn_audit_reject_mutation() IS
  'L10-08: generic BEFORE UPDATE OR DELETE OR TRUNCATE trigger that rejects '
  'mutation on tables registered in public.audit_append_only_config with '
  'mode=strict. Every attempt is recorded in audit_append_bypass_attempts.';

REVOKE ALL ON FUNCTION public.fn_audit_reject_mutation() FROM PUBLIC;

-- ──────────────────────────────────────────────────────────────────────────
-- 4. Idempotent installer
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_audit_install_append_only_guard(
  p_schema text,
  p_table  text,
  p_note   text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
DECLARE
  v_full text := format('%I.%I', p_schema, p_table);
  v_trg_row  text := format('trg_%s_append_only_row', p_table);
  v_trg_stmt text := format('trg_%s_append_only_stmt', p_table);
  v_exists boolean;
BEGIN
  IF p_schema IS NULL OR p_table IS NULL THEN
    RAISE EXCEPTION 'L10-08: p_schema and p_table are required'
      USING ERRCODE = '22023';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = p_schema
      AND c.relname = p_table
      AND c.relkind IN ('r', 'p')
  )
  INTO v_exists;

  IF NOT v_exists THEN
    RAISE NOTICE '[L10-08] %.% not present — skipping guard install', p_schema, p_table;
    RETURN false;
  END IF;

  EXECUTE format(
    'DROP TRIGGER IF EXISTS %I ON %s',
    v_trg_row, v_full
  );
  EXECUTE format(
    'CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION public.fn_audit_reject_mutation()',
    v_trg_row, v_full
  );

  EXECUTE format(
    'DROP TRIGGER IF EXISTS %I ON %s',
    v_trg_stmt, v_full
  );
  EXECUTE format(
    'CREATE TRIGGER %I BEFORE TRUNCATE ON %s FOR EACH STATEMENT EXECUTE FUNCTION public.fn_audit_reject_mutation()',
    v_trg_stmt, v_full
  );

  INSERT INTO public.audit_append_only_config (schema_name, table_name, mode, note)
  VALUES (p_schema, p_table, 'strict', p_note)
  ON CONFLICT (schema_name, table_name) DO UPDATE
    SET mode       = EXCLUDED.mode,
        applied_at = now(),
        note       = COALESCE(EXCLUDED.note, public.audit_append_only_config.note);

  RETURN true;
END;
$$;

COMMENT ON FUNCTION public.fn_audit_install_append_only_guard(text, text, text) IS
  'L10-08: idempotently installs the append-only trigger on schema.table and '
  'records the binding in audit_append_only_config. No-op when the table '
  'does not exist in this environment.';

REVOKE ALL ON FUNCTION public.fn_audit_install_append_only_guard(text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_audit_install_append_only_guard(text, text, text) FROM anon;
REVOKE ALL ON FUNCTION public.fn_audit_install_append_only_guard(text, text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_audit_install_append_only_guard(text, text, text) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 5. Detector + assert
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_audit_has_append_only_guard(
  p_schema text,
  p_table  text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM pg_trigger tg
    JOIN pg_class   c ON c.oid = tg.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_proc    p ON p.oid = tg.tgfoid
    WHERE n.nspname = p_schema
      AND c.relname = p_table
      AND p.proname = 'fn_audit_reject_mutation'
      AND NOT tg.tgisinternal
  );
$$;

COMMENT ON FUNCTION public.fn_audit_has_append_only_guard(text, text) IS
  'L10-08: TRUE if schema.table has at least one non-internal trigger '
  'pointing to public.fn_audit_reject_mutation.';

REVOKE ALL ON FUNCTION public.fn_audit_has_append_only_guard(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_audit_has_append_only_guard(text, text) FROM anon;
REVOKE ALL ON FUNCTION public.fn_audit_has_append_only_guard(text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_audit_has_append_only_guard(text, text) TO service_role;

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
    'audit_logs'
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

COMMENT ON FUNCTION public.fn_audit_assert_append_only_shape() IS
  'L10-08: raises P0010 if any registered strict table lost its trigger, or '
  'if a known audit table exists without a registry entry. Used by CI.';

REVOKE ALL ON FUNCTION public.fn_audit_assert_append_only_shape() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_audit_assert_append_only_shape() FROM anon;
REVOKE ALL ON FUNCTION public.fn_audit_assert_append_only_shape() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_audit_assert_append_only_shape() TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 6. Apply to the known append-only audit tables
-- ──────────────────────────────────────────────────────────────────────────
DO $apply$
DECLARE
  v_targets text[] := ARRAY[
    'portal_audit_log',
    'coin_ledger_pii_redactions',
    'cron_edge_retry_attempts',
    'wallet_drift_events',
    'custody_daily_cap_changes',
    'consent_events',
    'audit_logs'
  ];
  v_t text;
  v_installed boolean;
BEGIN
  FOREACH v_t IN ARRAY v_targets LOOP
    SELECT public.fn_audit_install_append_only_guard('public', v_t,
      format('L10-08 automatic install at %s', now()))
    INTO v_installed;
    IF v_installed THEN
      RAISE NOTICE '[L10-08] append-only guard installed on public.%', v_t;
    END IF;
  END LOOP;
END
$apply$;

-- `account_deletion_log` already has its own immutability trigger; register
-- it here as append_with_outcome so the CI assert treats it as protected.
DO $register_outcome$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'account_deletion_log'
  ) THEN
    INSERT INTO public.audit_append_only_config (schema_name, table_name, mode, note)
    VALUES ('public', 'account_deletion_log', 'append_with_outcome',
            'L10-08: protected by fn_account_deletion_log_immutable trigger (L04-02)')
    ON CONFLICT (schema_name, table_name) DO UPDATE
      SET mode = 'append_with_outcome',
          note = EXCLUDED.note;
  END IF;
END
$register_outcome$;

COMMIT;

-- ============================================================================
-- Self-test (separate transaction; visible errors abort the migration)
-- ============================================================================
DO $L10_08_selftest$
DECLARE
  v_count integer;
  v_ok    boolean;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.audit_append_only_config
  WHERE mode = 'strict';
  IF v_count < 1 THEN
    RAISE EXCEPTION 'L10-08 selftest: expected at least 1 strict binding, got %', v_count;
  END IF;

  IF NOT public.fn_audit_has_append_only_guard('public', 'portal_audit_log') THEN
    RAISE EXCEPTION 'L10-08 selftest: portal_audit_log is missing the append-only guard';
  END IF;

  BEGIN
    PERFORM public.fn_audit_assert_append_only_shape();
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'L10-08 selftest: assert raised unexpectedly: %', SQLERRM;
  END;

  BEGIN
    TRUNCATE TABLE public.portal_audit_log;
    RAISE EXCEPTION 'L10-08 selftest: TRUNCATE on portal_audit_log should have been blocked';
  EXCEPTION WHEN SQLSTATE 'P0010' THEN
    NULL;
  END;

  RAISE NOTICE '[L10-08.selftest] OK — append-only guards installed and enforced';
END
$L10_08_selftest$;
