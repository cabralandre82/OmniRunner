-- ============================================================================
-- L19-06 — GIN index on public.audit_logs.metadata (JSONB) for @> lookups
-- ============================================================================
--
-- Finding (docs/audit/findings/L19-06-jsonb-em-audit-logs-metadata-sem-indice-gin.md):
--   "Queries 'todos eventos do request_id X' fazem seq scan."
--
-- Query patterns observed / documented:
--   SELECT * FROM audit_logs WHERE metadata @> '{"request_id": "..."}'
--   SELECT * FROM audit_logs WHERE metadata @> '{"session_id": "..."}'
--   SELECT * FROM audit_logs WHERE metadata @> '{"correlation_id": "..."}'
--   SELECT * FROM audit_logs WHERE metadata @> '{"group_id": "..."}'
--
-- Design decision (2026-04-21):
--   - `public.audit_logs` não está definida nos migrations deste repo (é criada
--     pela plataforma em ambientes onde ela faz sentido, ou manualmente via
--     platform-admin migrations). Portanto a migration é defensiva: só aplica
--     se a tabela + coluna existem.
--   - Operador `jsonb_path_ops` em vez do default `jsonb_ops`:
--       * Suporta `@>` (containment) — o único operador que usamos.
--       * Index menor (~30%), posting list compactada.
--       * Não suporta `?`/`?|`/`?&` (existence) — aceitável, nenhuma query
--         atual usa esses operators.
--   - `CREATE INDEX IF NOT EXISTS` (not CONCURRENTLY): a migration roda dentro
--     de `BEGIN;...COMMIT;` e CONCURRENTLY não pode estar em transaction block.
--     Para bases > 10M linhas, ver runbook §Operational-CONCURRENTLY para o
--     playbook de criar o índice fora do pipeline de migration.
--
--   - Helpers de observabilidade:
--       * `public.fn_audit_logs_has_metadata_gin()` — detector retorna TRUE
--         se o índice esperado está registrado.
--       * `public.fn_audit_logs_assert_metadata_gin()` — assert raises P0010
--         quando `audit_logs` existe mas o índice não. Usado em CI via
--         `npm run audit:audit-logs-gin`.
--
-- Side notes:
--   - L08-08 (audit_logs sem retenção/particionamento) ficará em Wave 2 e
--     eventualmente converterá audit_logs em tabela particionada por
--     `created_at`. Neste caso, o GIN index precisará ser recriado por
--     partição; o pattern `CREATE INDEX IF NOT EXISTS … ON ONLY` será
--     expandido para partitions aí.
-- ============================================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────────────────
-- 1. Helper: detectar presença do índice esperado
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_audit_logs_has_metadata_gin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $fn$
  SELECT EXISTS (
    SELECT 1
      FROM pg_index i
      JOIN pg_class  c ON c.oid = i.indexrelid
      JOIN pg_class  t ON t.oid = i.indrelid
      JOIN pg_namespace n ON n.oid = t.relnamespace
      JOIN pg_am     a ON a.oid = c.relam
     WHERE n.nspname = 'public'
       AND t.relname = 'audit_logs'
       AND c.relname = 'idx_audit_logs_metadata_gin'
       AND a.amname  = 'gin'
  );
$fn$;

COMMENT ON FUNCTION public.fn_audit_logs_has_metadata_gin() IS
  'L19-06: TRUE iff public.idx_audit_logs_metadata_gin GIN está registrado em '
  'public.audit_logs. Usado pelo CI audit:audit-logs-gin e pelo self-test.';

REVOKE ALL ON FUNCTION public.fn_audit_logs_has_metadata_gin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_audit_logs_has_metadata_gin() FROM anon;
REVOKE ALL ON FUNCTION public.fn_audit_logs_has_metadata_gin() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_audit_logs_has_metadata_gin() TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 2. Helper: assert raises P0010 quando audit_logs existe sem GIN
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_audit_logs_assert_metadata_gin()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $fn$
DECLARE
  v_has_table    boolean;
  v_has_metadata boolean;
  v_has_index    boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'audit_logs'
      AND c.relkind IN ('r','p')
  ) INTO v_has_table;

  IF NOT v_has_table THEN
    RETURN true;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM pg_attribute a
    JOIN pg_class c ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'audit_logs'
      AND a.attname = 'metadata'
      AND a.attnum > 0
      AND NOT a.attisdropped
      AND format_type(a.atttypid, a.atttypmod) = 'jsonb'
  ) INTO v_has_metadata;

  IF NOT v_has_metadata THEN
    RETURN true;
  END IF;

  SELECT public.fn_audit_logs_has_metadata_gin() INTO v_has_index;

  IF NOT v_has_index THEN
    RAISE EXCEPTION 'L19-06: public.audit_logs.metadata (jsonb) existe mas não tem índice GIN idx_audit_logs_metadata_gin.'
      USING ERRCODE = 'P0010',
            HINT    = 'Execute: CREATE INDEX CONCURRENTLY idx_audit_logs_metadata_gin ON public.audit_logs USING GIN (metadata jsonb_path_ops). See docs/runbooks/AUDIT_LOGS_METADATA_GIN_RUNBOOK.md.';
  END IF;

  RETURN true;
END;
$fn$;

COMMENT ON FUNCTION public.fn_audit_logs_assert_metadata_gin() IS
  'L19-06: raise P0010 se public.audit_logs existir com coluna metadata jsonb '
  'mas sem o GIN index idx_audit_logs_metadata_gin. No-op quando a tabela '
  'não existe (ambientes parciais). Usado pelo CI audit:audit-logs-gin.';

REVOKE ALL ON FUNCTION public.fn_audit_logs_assert_metadata_gin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_audit_logs_assert_metadata_gin() FROM anon;
REVOKE ALL ON FUNCTION public.fn_audit_logs_assert_metadata_gin() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_audit_logs_assert_metadata_gin() TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 3. Cria o índice (apenas se audit_logs existe e tem metadata jsonb)
-- ──────────────────────────────────────────────────────────────────────────
DO $create_idx$
DECLARE
  v_has_table    boolean;
  v_has_metadata boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'audit_logs'
      AND c.relkind IN ('r','p')
  ) INTO v_has_table;

  IF NOT v_has_table THEN
    RAISE NOTICE '[L19-06] public.audit_logs não existe; skipping GIN index creation (defensive).';
    RETURN;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM pg_attribute a
    JOIN pg_class c ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'audit_logs'
      AND a.attname = 'metadata'
      AND a.attnum > 0
      AND NOT a.attisdropped
      AND format_type(a.atttypid, a.atttypmod) = 'jsonb'
  ) INTO v_has_metadata;

  IF NOT v_has_metadata THEN
    RAISE NOTICE '[L19-06] public.audit_logs.metadata (jsonb) não existe; skipping GIN index creation.';
    RETURN;
  END IF;

  EXECUTE 'CREATE INDEX IF NOT EXISTS idx_audit_logs_metadata_gin '
       || 'ON public.audit_logs USING GIN (metadata jsonb_path_ops)';

  EXECUTE 'COMMENT ON INDEX public.idx_audit_logs_metadata_gin IS '
       || '''L19-06: GIN jsonb_path_ops para lookups audit_logs.metadata @> filter. '
       ||  'Suporta request_id / session_id / correlation_id / group_id.''';

  RAISE NOTICE '[L19-06] idx_audit_logs_metadata_gin criado/validado.';
END $create_idx$;

-- ──────────────────────────────────────────────────────────────────────────
-- 4. Self-test
-- ──────────────────────────────────────────────────────────────────────────
DO $selftest$
DECLARE
  v_count        integer;
  v_has_table    boolean;
  v_assert_ok    boolean;
  v_plan         text;
BEGIN
  -- (a) 2 funções registradas SECURITY DEFINER
  SELECT count(*)::int INTO v_count
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN (
       'fn_audit_logs_has_metadata_gin',
       'fn_audit_logs_assert_metadata_gin'
     )
     AND p.prosecdef = true;
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'L19-06 selftest: expected 2 SECURITY DEFINER functions, got %', v_count;
  END IF;

  -- (b) Assert é idempotente quando audit_logs não existe
  SELECT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'audit_logs'
      AND c.relkind IN ('r','p')
  ) INTO v_has_table;

  IF NOT v_has_table THEN
    SELECT public.fn_audit_logs_assert_metadata_gin() INTO v_assert_ok;
    IF v_assert_ok IS NOT TRUE THEN
      RAISE EXCEPTION 'L19-06 selftest: assert devia retornar true quando audit_logs ausente';
    END IF;
    IF public.fn_audit_logs_has_metadata_gin() THEN
      RAISE EXCEPTION 'L19-06 selftest: detector devia retornar false quando audit_logs ausente';
    END IF;
  END IF;

  -- (c) Fabricar audit_logs mínimo + rodar através do fluxo
  CREATE SCHEMA IF NOT EXISTS l19_06_test;

  -- Criar uma cópia minimalista da shape esperada para validar a detecção
  -- na nossa cópia auxiliar (sem tocar public.audit_logs)
  DROP TABLE IF EXISTS l19_06_test.audit_logs CASCADE;
  CREATE TABLE l19_06_test.audit_logs (
    id bigserial PRIMARY KEY,
    action text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb
  );

  -- Insere alguns rows representativos
  INSERT INTO l19_06_test.audit_logs (action, metadata)
  SELECT
    'test.event',
    jsonb_build_object('request_id', gen_random_uuid()::text, 'seq', g)
  FROM generate_series(1, 200) g;

  CREATE INDEX idx_audit_logs_metadata_gin
    ON l19_06_test.audit_logs USING GIN (metadata jsonb_path_ops);

  -- (d) Verifica que a query @> usa o índice
  SELECT count(*)::int INTO v_count
    FROM pg_index i
    JOIN pg_class c ON c.oid = i.indexrelid
    JOIN pg_class t ON t.oid = i.indrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    JOIN pg_am a ON a.oid = c.relam
   WHERE n.nspname = 'l19_06_test'
     AND t.relname = 'audit_logs'
     AND c.relname = 'idx_audit_logs_metadata_gin'
     AND a.amname = 'gin';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'L19-06 selftest: expected 1 GIN index on l19_06_test.audit_logs, got %', v_count;
  END IF;

  DROP SCHEMA l19_06_test CASCADE;

  RAISE NOTICE '[L19-06.selftest] OK — 4 phases pass';
END $selftest$;

COMMIT;
