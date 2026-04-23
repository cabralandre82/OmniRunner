-- ============================================================================
-- L08-06 — OLAP staging layer (materialized views + scheduled refresh)
-- ============================================================================
--
-- Finding (docs/audit/findings/L08-06-sem-staging-de-data-warehouse-queries-olap-contra.md):
--   Dashboards em `/platform/*` rodam `SELECT` pesados diretamente sobre os
--   OLTPs críticos (`coin_ledger`, `custody_accounts`, `sessions`).
--   Um dashboard em hora de pico já bloqueou `execute_burn_atomic`
--   esperando por lock — incidente causado por BI tocando OLTP.
--
-- Escopo desta migration (primitivas, não infra):
--   (1) Schema `public_olap` — *namespace* dedicado para agregados.
--       Acesso é concedido SOMENTE ao `service_role` (os dashboards
--       `/platform/*` já usam `createAdminClient()`). Usuários `authenticated`
--       NÃO podem ler MVs — elas contêm agregados plataforma-inteira.
--   (2) `public_olap.mv_refresh_config` — configuração por MV
--       (intervalo, statement_timeout, concurrent on/off, enabled).
--   (3) `public_olap.mv_refresh_runs` — trilha append-only de todo refresh
--       (registrada no registro L10-08, protegida pelo mesmo trigger).
--   (4) Três MVs iniciais cobrindo os hotspots identificados hoje:
--         * `mv_sessions_completed_daily`    — KPI "Corridas (7d)" e correlatos
--         * `mv_coin_ledger_daily_by_reason` — Dashboards financeiros
--         * `mv_custody_accounts_snapshot`   — Dashboard de custódia
--       Cada MV tem UNIQUE INDEX (requisito de `REFRESH ... CONCURRENTLY`).
--   (5) Helper `fn_refresh_mv(mv_name)` SECURITY DEFINER:
--         * set_config('statement_timeout', ..., true) — txn-local
--         * advisory-lock por MV (pg_try_advisory_xact_lock)
--         * janela mínima entre refreshes (config.refresh_interval_seconds)
--         * REFRESH CONCURRENTLY quando populada; não-concurrent somente
--           para o "primeiro refresh" pós-criação (WITH NO DATA).
--         * registra todo desfecho em `mv_refresh_runs`
--   (6) Dispatcher `fn_refresh_all()` chamado por pg_cron.
--   (7) pg_cron schedule `olap-refresh-all` a cada 15 minutos.
--
-- Explicitly NOT in this migration (rastreados como follow-ups):
--   * Réplica dedicada OLAP (pg_logical / FDW / DuckDB / BigQuery). Isso é
--     tarefa de infra — requer janela de manutenção e recursos. As MVs aqui
--     entregam ~80% do isolamento (OLAP lê MV, não OLTP) sem nenhum custo
--     de infra. Follow-up: `L08-06-read-replica`.
--   * Reescrever os consumidores `/platform/*` para apontar às MVs. Isso é
--     PR de portal, não de banco. Esta migration cria a camada; o portal
--     migra incrementalmente. Follow-up: `L08-06-portal-migrate`.
--
-- Propriedades de segurança preservadas:
--   * MVs não são expostas a `authenticated`/`anon` — apenas `service_role`.
--   * `mv_refresh_runs` é append-only (L10-08). Não é bypassável (não existe
--     `olap.retention_pass` análogo; se alguém quiser "limpar" o log, tem que
--     passar pelo mesmo fluxo de retention L08-08 — hoje não está configurado
--     e isso é deliberado: a trilha do OLAP vive para sempre até decidirmos
--     o contrário via ADR explícito).
--   * Advisory locks: concorrência de refresh é impossível (lock por MV
--     `hashtext('olap:<name>')`, lock global `hashtext('olap:refresh_all')`).
--   * `statement_timeout` limita qualquer refresh a um budget conhecido —
--     30 s é default, ajustável por MV. Se o REFRESH exceder, ele é
--     cancelado sem travar OLTP (CONCURRENTLY nem toma exclusive lock).
-- ============================================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────────────────
-- 1. Schema
-- ──────────────────────────────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS public_olap;
COMMENT ON SCHEMA public_olap IS
  'L08-06: staging OLAP — agregados pré-computados para /platform/*. '
  'Leitura apenas via service_role. Não deve conter PII por linha; somente '
  'agregados por dia/reason/group.';

REVOKE ALL ON SCHEMA public_olap FROM PUBLIC;
REVOKE ALL ON SCHEMA public_olap FROM anon;
REVOKE ALL ON SCHEMA public_olap FROM authenticated;
GRANT USAGE ON SCHEMA public_olap TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 2. Refresh config — uma linha por MV
-- ──────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public_olap.mv_refresh_config (
  mv_name                   text PRIMARY KEY
                            CHECK (length(trim(mv_name)) BETWEEN 1 AND 63),
  enabled                   boolean NOT NULL DEFAULT true,
  refresh_interval_seconds  integer NOT NULL DEFAULT 900
                            CHECK (refresh_interval_seconds BETWEEN 60
                                   AND 86400),
  statement_timeout_ms      integer NOT NULL DEFAULT 30000
                            CHECK (statement_timeout_ms BETWEEN 1000
                                   AND 600000),
  concurrent                boolean NOT NULL DEFAULT true,
  note                      text,
  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public_olap.mv_refresh_config IS
  'L08-06: configuração por MV. `refresh_interval_seconds` define janela '
  'mínima entre refreshes (evita spam). `statement_timeout_ms` impede que '
  'um refresh degenerado segure recursos. `concurrent=false` força refresh '
  'bloqueante (só usado em caso de manutenção).';

ALTER TABLE public_olap.mv_refresh_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public_olap.mv_refresh_config FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS mv_refresh_config_service_rw
  ON public_olap.mv_refresh_config;
CREATE POLICY mv_refresh_config_service_rw
  ON public_olap.mv_refresh_config
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

CREATE OR REPLACE FUNCTION public_olap.fn_mv_refresh_config_touch()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS trg_mv_refresh_config_touch
  ON public_olap.mv_refresh_config;
CREATE TRIGGER trg_mv_refresh_config_touch
  BEFORE UPDATE ON public_olap.mv_refresh_config
  FOR EACH ROW
  EXECUTE FUNCTION public_olap.fn_mv_refresh_config_touch();

-- ──────────────────────────────────────────────────────────────────────────
-- 3. Refresh runs — trilha append-only
-- ──────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public_olap.mv_refresh_runs (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mv_name        text NOT NULL,
  started_at     timestamptz NOT NULL DEFAULT now(),
  finished_at    timestamptz,
  duration_ms    integer,
  status         text NOT NULL
                 CHECK (status IN (
                   'ok',
                   'skipped_disabled',
                   'skipped_no_mv',
                   'skipped_no_config',
                   'skipped_locked',
                   'skipped_too_soon',
                   'error'
                 )),
  rows_in_mv     bigint,
  error_message  text,
  created_at     timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public_olap.mv_refresh_runs IS
  'L08-06: trilha append-only de todo refresh (sucesso, pulado ou erro). '
  'Protegida pelo trigger L10-08 — DELETE/UPDATE/TRUNCATE bloqueados. '
  'Retenção: NÃO configurada em L08-08 (keep forever por default). Se o '
  'volume passar a incomodar, adicionar linha em audit_logs_retention_config.';

CREATE INDEX IF NOT EXISTS idx_mv_refresh_runs_mv_started
  ON public_olap.mv_refresh_runs (mv_name, started_at DESC);

ALTER TABLE public_olap.mv_refresh_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public_olap.mv_refresh_runs FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS mv_refresh_runs_service_read
  ON public_olap.mv_refresh_runs;
CREATE POLICY mv_refresh_runs_service_read
  ON public_olap.mv_refresh_runs
  FOR SELECT
  TO service_role
  USING (true);

DROP POLICY IF EXISTS mv_refresh_runs_service_write
  ON public_olap.mv_refresh_runs;
CREATE POLICY mv_refresh_runs_service_write
  ON public_olap.mv_refresh_runs
  FOR INSERT
  TO service_role
  WITH CHECK (true);

-- Registra no registro append-only L10-08 (DELETE/UPDATE/TRUNCATE bloqueados).
DO $install_guard$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'fn_audit_install_append_only_guard'
  ) THEN
    PERFORM public.fn_audit_install_append_only_guard(
      'public_olap',
      'mv_refresh_runs',
      'L08-06: trilha de refresh do staging OLAP'
    );
  ELSE
    RAISE NOTICE '[L08-06] fn_audit_install_append_only_guard ausente — '
                 'trilha mv_refresh_runs NÃO está protegida append-only. '
                 'Aplicar 20260421350000_l10_08_audit_logs_append_only.sql.';
  END IF;
END
$install_guard$;

-- ──────────────────────────────────────────────────────────────────────────
-- 4. Materialized Views iniciais
-- ──────────────────────────────────────────────────────────────────────────
--
-- Cada MV é criada WITH NO DATA. O primeiro refresh (dispatcher ou manual)
-- popula de fato. Isso torna a migration idempotente e rápida mesmo em
-- bancos com histórico grande.
-- ──────────────────────────────────────────────────────────────────────────

-- (a) sessions completed daily — `status >= 3` é "finalizada" (L08-03/04)
--     `start_time_ms` é epoch em ms → bucketing diário em UTC.
CREATE MATERIALIZED VIEW IF NOT EXISTS public_olap.mv_sessions_completed_daily AS
  SELECT
    (start_time_ms / 86400000)::bigint                       AS day_utc_epoch,
    to_timestamp((start_time_ms / 86400000) * 86400)
      AT TIME ZONE 'UTC'                                    AS day_utc,
    count(*)::bigint                                        AS sessions_count,
    coalesce(sum(total_distance_m), 0)::double precision    AS total_distance_m,
    coalesce(sum(moving_ms), 0)::bigint                     AS total_moving_ms,
    count(*) FILTER (WHERE is_verified)::bigint             AS sessions_verified,
    count(DISTINCT user_id)::bigint                         AS unique_users
  FROM public.sessions
  WHERE status >= 3
  GROUP BY 1, 2
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS mv_sessions_completed_daily_pk
  ON public_olap.mv_sessions_completed_daily (day_utc_epoch);

COMMENT ON MATERIALIZED VIEW public_olap.mv_sessions_completed_daily IS
  'L08-06: sessions finalizadas (status>=3) agregadas por dia UTC. '
  'Alimenta o KPI "Corridas (7d)" e séries históricas. Refresh a cada 15 min.';

-- (b) coin_ledger daily by reason — um registro por (dia, reason).
--     `created_at_ms` é epoch em ms (mesma convenção de sessions).
CREATE MATERIALIZED VIEW IF NOT EXISTS public_olap.mv_coin_ledger_daily_by_reason AS
  SELECT
    (created_at_ms / 86400000)::bigint                       AS day_utc_epoch,
    to_timestamp((created_at_ms / 86400000) * 86400)
      AT TIME ZONE 'UTC'                                    AS day_utc,
    reason                                                  AS reason,
    count(*)::bigint                                        AS entry_count,
    coalesce(sum(delta_coins), 0)::bigint                   AS sum_delta_coins,
    coalesce(sum(GREATEST(delta_coins, 0)), 0)::bigint      AS sum_inflow_coins,
    coalesce(sum(LEAST(delta_coins, 0)), 0)::bigint         AS sum_outflow_coins,
    count(DISTINCT user_id)::bigint                         AS unique_users
  FROM public.coin_ledger
  GROUP BY 1, 2, 3
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS mv_coin_ledger_daily_by_reason_pk
  ON public_olap.mv_coin_ledger_daily_by_reason (day_utc_epoch, reason);

COMMENT ON MATERIALIZED VIEW public_olap.mv_coin_ledger_daily_by_reason IS
  'L08-06: coin_ledger agregado por (dia UTC, reason). '
  'Alimenta dashboards financeiros. Refresh a cada 15 min.';

-- (c) custody_accounts snapshot — uma linha por group_id.
--     MV aqui evita `SELECT *` full-scan em `/platform/custody`.
CREATE MATERIALIZED VIEW IF NOT EXISTS public_olap.mv_custody_accounts_snapshot AS
  SELECT
    ca.group_id                                              AS group_id,
    ca.total_deposited_usd                                   AS total_deposited_usd,
    ca.total_committed                                       AS total_committed,
    ca.total_settled_usd                                     AS total_settled_usd,
    (ca.total_deposited_usd - ca.total_committed)            AS available_usd,
    ca.is_blocked                                            AS is_blocked,
    ca.updated_at                                            AS source_updated_at,
    now()                                                    AS snapshot_at
  FROM public.custody_accounts ca
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS mv_custody_accounts_snapshot_pk
  ON public_olap.mv_custody_accounts_snapshot (group_id);

COMMENT ON MATERIALIZED VIEW public_olap.mv_custody_accounts_snapshot IS
  'L08-06: snapshot por grupo de custódia. `snapshot_at` é o instante do '
  'último REFRESH — consumidores podem exibir "atualizado há X min". '
  'Refresh a cada 15 min.';

-- Grants — apenas service_role pode SELECT (MVs contêm plataforma-inteira).
REVOKE ALL ON ALL TABLES IN SCHEMA public_olap FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public_olap FROM anon;
REVOKE ALL ON ALL TABLES IN SCHEMA public_olap FROM authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public_olap TO service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public_olap
  REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public_olap
  REVOKE ALL ON TABLES FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public_olap
  REVOKE ALL ON TABLES FROM authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public_olap
  GRANT SELECT ON TABLES TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 5. Refresh helper — SECURITY DEFINER, txn-local timeout, advisory lock
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public_olap.fn_refresh_mv(
  p_mv_name text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public_olap, public, pg_catalog, pg_temp
AS $$
DECLARE
  v_cfg          public_olap.mv_refresh_config%ROWTYPE;
  v_has_mv       boolean;
  v_is_populated boolean;
  v_lock_key     bigint;
  v_got_lock     boolean;
  v_last_ok      timestamptz;
  v_now          timestamptz := now();
  v_started_at   timestamptz;
  v_run_id       uuid;
  v_duration_ms  integer;
  v_row_count    bigint;
  v_sql          text;
  v_status       text;
  v_err          text;
BEGIN
  IF p_mv_name IS NULL OR length(trim(p_mv_name)) = 0 THEN
    RAISE EXCEPTION 'L08-06: p_mv_name is required'
      USING ERRCODE = '22023';
  END IF;

  -- (a) Config
  SELECT *
    INTO v_cfg
    FROM public_olap.mv_refresh_config
   WHERE mv_name = p_mv_name;

  IF NOT FOUND THEN
    INSERT INTO public_olap.mv_refresh_runs
      (mv_name, started_at, finished_at, duration_ms, status, error_message)
    VALUES
      (p_mv_name, v_now, v_now, 0, 'skipped_no_config',
       'mv_name not present in public_olap.mv_refresh_config');
    RETURN jsonb_build_object(
      'mv_name', p_mv_name,
      'status', 'skipped_no_config'
    );
  END IF;

  IF NOT v_cfg.enabled THEN
    INSERT INTO public_olap.mv_refresh_runs
      (mv_name, started_at, finished_at, duration_ms, status)
    VALUES
      (p_mv_name, v_now, v_now, 0, 'skipped_disabled');
    RETURN jsonb_build_object(
      'mv_name', p_mv_name,
      'status', 'skipped_disabled'
    );
  END IF;

  -- (b) MV presence — if schema/mv missing, record and skip.
  SELECT
    EXISTS (
      SELECT 1 FROM pg_matviews
       WHERE schemaname = 'public_olap' AND matviewname = p_mv_name
    ),
    COALESCE(
      (SELECT ispopulated FROM pg_matviews
        WHERE schemaname = 'public_olap' AND matviewname = p_mv_name),
      false
    )
  INTO v_has_mv, v_is_populated;

  IF NOT v_has_mv THEN
    INSERT INTO public_olap.mv_refresh_runs
      (mv_name, started_at, finished_at, duration_ms, status, error_message)
    VALUES
      (p_mv_name, v_now, v_now, 0, 'skipped_no_mv',
       format('materialized view public_olap.%I does not exist', p_mv_name));
    RETURN jsonb_build_object(
      'mv_name', p_mv_name,
      'status', 'skipped_no_mv'
    );
  END IF;

  -- (c) Too-soon guard: last OK run + interval > now → skip.
  SELECT max(started_at)
    INTO v_last_ok
    FROM public_olap.mv_refresh_runs
   WHERE mv_name = p_mv_name
     AND status = 'ok';

  IF v_last_ok IS NOT NULL
     AND v_last_ok + make_interval(secs => v_cfg.refresh_interval_seconds) > v_now THEN
    INSERT INTO public_olap.mv_refresh_runs
      (mv_name, started_at, finished_at, duration_ms, status)
    VALUES
      (p_mv_name, v_now, v_now, 0, 'skipped_too_soon');
    RETURN jsonb_build_object(
      'mv_name', p_mv_name,
      'status', 'skipped_too_soon',
      'next_eligible_at',
      to_jsonb(v_last_ok + make_interval(secs => v_cfg.refresh_interval_seconds))
    );
  END IF;

  -- (d) Advisory lock — per MV, transaction-scoped.
  v_lock_key := ('x' || substr(md5('olap:' || p_mv_name), 1, 16))::bit(64)::bigint;
  v_got_lock := pg_try_advisory_xact_lock(v_lock_key);

  IF NOT v_got_lock THEN
    INSERT INTO public_olap.mv_refresh_runs
      (mv_name, started_at, finished_at, duration_ms, status)
    VALUES
      (p_mv_name, v_now, v_now, 0, 'skipped_locked');
    RETURN jsonb_build_object(
      'mv_name', p_mv_name,
      'status', 'skipped_locked'
    );
  END IF;

  -- (e) Budget: statement_timeout txn-local.
  PERFORM set_config(
    'statement_timeout',
    v_cfg.statement_timeout_ms::text,
    true
  );

  v_started_at := clock_timestamp();
  v_run_id := gen_random_uuid();
  v_status := 'ok';
  v_err := NULL;

  BEGIN
    IF v_cfg.concurrent AND v_is_populated THEN
      v_sql := format(
        'REFRESH MATERIALIZED VIEW CONCURRENTLY public_olap.%I',
        p_mv_name
      );
    ELSE
      v_sql := format(
        'REFRESH MATERIALIZED VIEW public_olap.%I',
        p_mv_name
      );
    END IF;
    EXECUTE v_sql;

    EXECUTE format(
      'SELECT count(*)::bigint FROM public_olap.%I',
      p_mv_name
    ) INTO v_row_count;
  EXCEPTION WHEN OTHERS THEN
    v_status := 'error';
    v_err := SQLERRM;
  END;

  v_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_started_at)) * 1000)::integer;

  INSERT INTO public_olap.mv_refresh_runs
    (id, mv_name, started_at, finished_at, duration_ms, status,
     rows_in_mv, error_message)
  VALUES
    (v_run_id, p_mv_name, v_started_at, clock_timestamp(), v_duration_ms,
     v_status, v_row_count, v_err);

  RETURN jsonb_build_object(
    'mv_name', p_mv_name,
    'status', v_status,
    'duration_ms', v_duration_ms,
    'rows_in_mv', v_row_count,
    'error_message', v_err
  );
END
$$;

COMMENT ON FUNCTION public_olap.fn_refresh_mv(text) IS
  'L08-06: refresh de uma MV com budget (statement_timeout), advisory lock '
  'por MV e janela mínima (refresh_interval_seconds). Sempre registra em '
  'mv_refresh_runs — sucesso, skipped_* ou error.';

REVOKE ALL ON FUNCTION public_olap.fn_refresh_mv(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public_olap.fn_refresh_mv(text) FROM anon;
REVOKE ALL ON FUNCTION public_olap.fn_refresh_mv(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public_olap.fn_refresh_mv(text) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 6. Dispatcher — chamado por pg_cron, itera toda a config habilitada
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public_olap.fn_refresh_all()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public_olap, public, pg_catalog, pg_temp
AS $$
DECLARE
  v_got_global_lock boolean;
  v_row             record;
  v_result          jsonb;
  v_results         jsonb := '[]'::jsonb;
  v_started_at      timestamptz := clock_timestamp();
BEGIN
  v_got_global_lock := pg_try_advisory_xact_lock(
    ('x' || substr(md5('olap:refresh_all'), 1, 16))::bit(64)::bigint
  );

  IF NOT v_got_global_lock THEN
    RETURN jsonb_build_object(
      'status', 'skipped_locked',
      'note', 'another fn_refresh_all is already running'
    );
  END IF;

  FOR v_row IN
    SELECT mv_name
      FROM public_olap.mv_refresh_config
     WHERE enabled = true
     ORDER BY mv_name
  LOOP
    BEGIN
      v_result := public_olap.fn_refresh_mv(v_row.mv_name);
    EXCEPTION WHEN OTHERS THEN
      -- Blindagem: uma MV que quebra não deve parar as outras.
      BEGIN
        INSERT INTO public_olap.mv_refresh_runs
          (mv_name, started_at, finished_at, duration_ms, status, error_message)
        VALUES
          (v_row.mv_name, clock_timestamp(), clock_timestamp(), 0,
           'error', SQLERRM);
      EXCEPTION WHEN OTHERS THEN NULL; END;
      v_result := jsonb_build_object(
        'mv_name', v_row.mv_name,
        'status', 'error',
        'error_message', SQLERRM
      );
    END;
    v_results := v_results || jsonb_build_array(v_result);
  END LOOP;

  RETURN jsonb_build_object(
    'status', 'ok',
    'duration_ms',
      (EXTRACT(EPOCH FROM (clock_timestamp() - v_started_at)) * 1000)::integer,
    'results', v_results
  );
END
$$;

COMMENT ON FUNCTION public_olap.fn_refresh_all() IS
  'L08-06: dispatcher invocado pelo pg_cron. Advisory lock global impede '
  'duas instâncias simultâneas. Erros por MV são isolados — uma MV travada '
  'não derruba as outras.';

REVOKE ALL ON FUNCTION public_olap.fn_refresh_all() FROM PUBLIC;
REVOKE ALL ON FUNCTION public_olap.fn_refresh_all() FROM anon;
REVOKE ALL ON FUNCTION public_olap.fn_refresh_all() FROM authenticated;
GRANT EXECUTE ON FUNCTION public_olap.fn_refresh_all() TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 7. Assert shape — usado pelo CI para detectar drift
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public_olap.fn_olap_assert_shape()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public_olap, public, pg_catalog, pg_temp
AS $$
DECLARE
  v_known   text[];
  v_name    text;
  v_missing text[] := ARRAY[]::text[];
  v_no_idx  text[] := ARRAY[]::text[];
BEGIN
  -- Lista canônica de MVs shippadas nesta migration.
  v_known := ARRAY[
    'mv_sessions_completed_daily',
    'mv_coin_ledger_daily_by_reason',
    'mv_custody_accounts_snapshot'
  ];

  FOREACH v_name IN ARRAY v_known LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_matviews
       WHERE schemaname = 'public_olap' AND matviewname = v_name
    ) THEN
      v_missing := array_append(v_missing, v_name);
      CONTINUE;
    END IF;

    -- Cada MV precisa de UNIQUE INDEX para REFRESH CONCURRENTLY funcionar.
    IF NOT EXISTS (
      SELECT 1
        FROM pg_indexes i
        JOIN pg_class c ON c.relname = i.indexname
       WHERE i.schemaname = 'public_olap'
         AND i.tablename = v_name
         AND i.indexdef ILIKE 'CREATE UNIQUE INDEX%'
    ) THEN
      v_no_idx := array_append(v_no_idx, v_name);
    END IF;

    -- Deve existir linha de config habilitada (ou, ao menos, presente).
    IF NOT EXISTS (
      SELECT 1 FROM public_olap.mv_refresh_config WHERE mv_name = v_name
    ) THEN
      RAISE EXCEPTION 'L08-06: missing mv_refresh_config row for %', v_name
        USING ERRCODE = 'P0010';
    END IF;
  END LOOP;

  IF array_length(v_missing, 1) IS NOT NULL THEN
    RAISE EXCEPTION 'L08-06: missing materialized views: %', v_missing
      USING ERRCODE = 'P0010';
  END IF;

  IF array_length(v_no_idx, 1) IS NOT NULL THEN
    RAISE EXCEPTION 'L08-06: materialized views without UNIQUE INDEX (breaks REFRESH CONCURRENTLY): %',
      v_no_idx
      USING ERRCODE = 'P0010';
  END IF;

  -- mv_refresh_runs precisa estar no registro append-only (L10-08).
  IF EXISTS (
    SELECT 1 FROM pg_tables
     WHERE schemaname = 'public'
       AND tablename = 'audit_append_only_config'
  ) THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.audit_append_only_config
       WHERE schema_name = 'public_olap'
         AND table_name = 'mv_refresh_runs'
    ) THEN
      RAISE EXCEPTION 'L08-06: mv_refresh_runs not registered in audit_append_only_config (L10-08)'
        USING ERRCODE = 'P0010';
    END IF;
  END IF;
END
$$;

COMMENT ON FUNCTION public_olap.fn_olap_assert_shape() IS
  'L08-06: invariantes do staging OLAP. Falha com P0010 se alguma MV foi '
  'removida, perdeu índice único, ou saiu do registro append-only.';

REVOKE ALL ON FUNCTION public_olap.fn_olap_assert_shape() FROM PUBLIC;
REVOKE ALL ON FUNCTION public_olap.fn_olap_assert_shape() FROM anon;
REVOKE ALL ON FUNCTION public_olap.fn_olap_assert_shape() FROM authenticated;
GRANT EXECUTE ON FUNCTION public_olap.fn_olap_assert_shape() TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 8. Seed config — uma linha por MV shippada
-- ──────────────────────────────────────────────────────────────────────────
INSERT INTO public_olap.mv_refresh_config
  (mv_name, enabled, refresh_interval_seconds, statement_timeout_ms,
   concurrent, note)
VALUES
  ('mv_sessions_completed_daily',    true,  900, 30000, true,
   'L08-06: sessions status>=3 agregado por dia UTC'),
  ('mv_coin_ledger_daily_by_reason', true,  900, 45000, true,
   'L08-06: coin_ledger agregado por (dia UTC, reason) — volume maior, timeout 45s'),
  ('mv_custody_accounts_snapshot',   true,  900, 15000, true,
   'L08-06: snapshot por grupo — custody_accounts é pequeno, 15s timeout')
ON CONFLICT (mv_name) DO NOTHING;

COMMIT;

-- ============================================================================
-- 9. pg_cron schedule (outside BEGIN — cron.schedule is global)
-- ============================================================================
DO $schedule$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE '[L08-06] pg_cron extension not available in this env — skipping schedules';
    RETURN;
  END IF;

  BEGIN
    PERFORM cron.unschedule('olap-refresh-all');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM cron.schedule(
    'olap-refresh-all',
    '*/15 * * * *',
    $cron$ SELECT public_olap.fn_refresh_all(); $cron$
  );
END
$schedule$;

-- ============================================================================
-- 10. Self-test (separate transaction — erros abortam a migration)
-- ============================================================================
DO $L08_06_selftest$
DECLARE
  v_result    jsonb;
  v_second    jsonb;
  v_count     integer;
  v_blocked   boolean := false;
BEGIN
  -- (a) Invariantes estruturais.
  PERFORM public_olap.fn_olap_assert_shape();

  -- (b) Helper para MV inexistente → skipped_no_config (não está no config).
  v_result := public_olap.fn_refresh_mv('__l08_06_ghost_mv__');
  IF v_result->>'status' <> 'skipped_no_config' THEN
    RAISE EXCEPTION 'L08-06 selftest: unknown mv should yield skipped_no_config, got %', v_result;
  END IF;

  -- (c) Refresh de MV real (WITH NO DATA → primeiro refresh é não-concurrent).
  v_result := public_olap.fn_refresh_mv('mv_custody_accounts_snapshot');
  IF v_result->>'status' NOT IN ('ok') THEN
    RAISE EXCEPTION 'L08-06 selftest: first refresh must succeed, got %', v_result;
  END IF;

  -- (d) Refresh imediato subsequente → skipped_too_soon (guard de janela).
  v_second := public_olap.fn_refresh_mv('mv_custody_accounts_snapshot');
  IF v_second->>'status' <> 'skipped_too_soon' THEN
    RAISE EXCEPTION 'L08-06 selftest: second immediate refresh should be skipped_too_soon, got %', v_second;
  END IF;

  -- (e) Trilha registrada: pelo menos 3 linhas (ghost + ok + too_soon).
  SELECT count(*) INTO v_count FROM public_olap.mv_refresh_runs;
  IF v_count < 3 THEN
    RAISE EXCEPTION 'L08-06 selftest: expected >= 3 refresh_runs rows, got %', v_count;
  END IF;

  -- (f) Append-only guard: DELETE em mv_refresh_runs é bloqueado.
  IF EXISTS (
    SELECT 1 FROM pg_tables
     WHERE schemaname = 'public'
       AND tablename = 'audit_append_only_config'
  ) THEN
    BEGIN
      DELETE FROM public_olap.mv_refresh_runs
       WHERE id = (SELECT id FROM public_olap.mv_refresh_runs LIMIT 1);
      RAISE EXCEPTION 'L08-06 selftest: DELETE on mv_refresh_runs should be blocked';
    EXCEPTION WHEN SQLSTATE 'P0010' THEN
      v_blocked := true;
    END;
    IF NOT v_blocked THEN
      RAISE EXCEPTION 'L08-06 selftest: append-only guard did not fire on DELETE';
    END IF;
  END IF;

  -- (g) Dispatcher roda sem erro e retorna status=ok (todas já refreshed em (c) ou serão).
  v_result := public_olap.fn_refresh_all();
  IF v_result->>'status' NOT IN ('ok', 'skipped_locked') THEN
    RAISE EXCEPTION 'L08-06 selftest: dispatcher should return ok/skipped_locked, got %', v_result;
  END IF;

  RAISE NOTICE '[L08-06.selftest] OK — staging OLAP shippado, invariantes enforced';
END
$L08_06_selftest$;
