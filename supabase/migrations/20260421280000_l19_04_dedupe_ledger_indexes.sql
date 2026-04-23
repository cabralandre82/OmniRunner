-- ============================================================================
-- L19-04 — Deduplicate & standardize indexes on coin_ledger + related tables
-- ============================================================================
--
-- Finding (docs/audit/findings/L19-04-*.md):
--   "Migration 2026-02-18 cria idx_ledger_user; migration 2026-03-08 cria
--    idx_coin_ledger_user_created. Nomenclatura inconsistente; provavelmente
--    ambos persistem."
--
-- Reality check (2026-04-21 em local `supabase_db_project-running`):
--   post-L19-01 partition swap, `coin_ledger` tem apenas
--     - coin_ledger_pkey
--     - idx_ledger_user    (user_id, created_at_ms DESC)
--     - idx_ledger_issuer  (issuer_group_id)
--   o `DROP TABLE … CASCADE` no swap derrubou as variantes legacy. Mas em ambientes
--   de desenvolvimento antigos (pré-L19-01) podem existir phantoms:
--     - idx_coin_ledger_user_created
--     - idx_coin_ledger_ref_reason
--     - idx_ledger_user_monolithic / idx_ledger_issuer_monolithic (renamed pre-drop)
--   (ver 20260308000000_scale_indexes_and_rls.sql:50 e
--    20260417200000_coin_ledger_partitioning.sql:227)
--
-- Mesmo sem phantoms hoje, nada impede que futuras migrações repitam o mesmo
-- padrão em outras tabelas financeiras. L19-04 entrega:
--
--   1) DROP IF EXISTS defensivo dos nomes legacy conhecidos (idempotente em
--      ambos os cenários — local limpo e dev com phantoms).
--
--   2) public.fn_find_duplicate_indexes(schema, table) — primitive que detecta
--      dois tipos de redundância:
--        (a) "prefix overlap": duas indexes btree na mesma tabela onde a lista
--            de colunas de A é prefixo da lista de B (plain btree, mesmo ASC/DESC,
--            mesmo WHERE, mesmo INCLUDE). A é redundante; B cobre tudo que A
--            cobria + mais.
--        (b) "exact duplicate": duas indexes com lista de colunas idêntica +
--            mesmo WHERE + mesmo INCLUDE. Escolher o menor lexicograficamente
--            como canônico.
--
--   3) public.fn_assert_no_duplicate_indexes(schemas text[], tables text[])
--      helper boolean que CI pode chamar para rejeitar PRs que introduzam
--      índices duplicados.
--
--   4) Convenção documentada (LEDGER_INDEX_NAMING_RUNBOOK.md):
--        idx_<table_core>_<col1>[_<col2>][_<modifier>]
--      onde <table_core> = table name with "coin_" prefix removed (para evitar
--      drift `idx_coin_ledger_*` vs `idx_ledger_*`).
--
-- Escopo deliberadamente excluído:
--   - CREATE INDEX CONCURRENTLY — migration runs within transaction; usamos
--     CREATE INDEX plain. Se a base tiver >10M linhas, documentamos em runbook
--     como quebrar em `BEGIN; SET lock_timeout; CREATE INDEX CONCURRENTLY …`
--     separado fora do pipeline de migration.
--   - Análise de `pg_stat_user_indexes` para "indexes nunca usados" — fora do
--     escopo deste finding; L19-07 (DBA tuning) já está deferido e cobrirá isso
--     com decisões por índice (keep/drop) baseadas em telemetria real.
-- ============================================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────────────────
-- 1. DROP IF EXISTS phantoms conhecidos
-- ──────────────────────────────────────────────────────────────────────────
-- Idempotente: em envs limpos (post-L19-01 swap completo) todos são no-ops.
-- Em envs pre-L19-01 ou dev antigos, elimina o drift.

DROP INDEX IF EXISTS public.idx_coin_ledger_user_created;
DROP INDEX IF EXISTS public.idx_coin_ledger_ref_reason;
DROP INDEX IF EXISTS public.idx_ledger_user_monolithic;
DROP INDEX IF EXISTS public.idx_ledger_issuer_monolithic;

-- NOTE: idx_ledger_user, idx_ledger_issuer, idx_ledger_reason e
-- idx_ledger_issue_snapshot (L03-02) são os nomes canônicos. NÃO dropar.

-- ──────────────────────────────────────────────────────────────────────────
-- 2. Helper: fn_find_duplicate_indexes
-- ──────────────────────────────────────────────────────────────────────────
-- Retorna pares (redundant, canonical, kind, reason) para toda tabela em que
-- detectarmos sobreposição. Só inclui índices plain btree (não UNIQUE, não
-- expression-based) porque unicidade/expressões têm semântica própria que NÃO
-- é redundância mesmo quando as colunas coincidem.

CREATE OR REPLACE FUNCTION public.fn_find_duplicate_indexes(
  p_schema text DEFAULT 'public',
  p_table  text DEFAULT NULL
)
RETURNS TABLE (
  schemaname          text,
  tablename           text,
  redundant_index     text,
  canonical_index     text,
  kind                text,   -- 'exact_duplicate' | 'prefix_overlap'
  reason              text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $fn$
  WITH raw AS (
    SELECT
      n.nspname::text                           AS schemaname,
      c.relname::text                           AS tablename,
      i.relname::text                           AS indexname,
      ix.indnatts                               AS total_cols,
      ix.indnkeyatts                            AS key_cols,
      ix.indisunique                            AS is_unique,
      ix.indisprimary                           AS is_primary,
      am.amname                                 AS access_method,
      pg_get_expr(ix.indpred, ix.indrelid, true) AS predicate,
      (
        SELECT string_agg(
                 format('%s:%s',
                   pg_get_indexdef(ix.indexrelid, k, true),
                   CASE WHEN (ix.indoption[k - 1] & 1) = 1 THEN 'DESC' ELSE 'ASC' END
                 ),
                 '|' ORDER BY k
               )
        FROM generate_series(1, ix.indnkeyatts::int) AS k
      )                                         AS key_sig,
      (
        SELECT string_agg(pg_get_indexdef(ix.indexrelid, k, true), '|' ORDER BY k)
        FROM generate_series(ix.indnkeyatts::int + 1, ix.indnatts::int) AS k
      )                                         AS include_sig
    FROM pg_index ix
    JOIN pg_class i ON i.oid = ix.indexrelid
    JOIN pg_class c ON c.oid = ix.indrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_am     am ON am.oid = i.relam
    WHERE n.nspname = p_schema
      AND (p_table IS NULL OR c.relname = p_table)
      AND c.relkind IN ('r','p')                -- regular + partitioned
      AND am.amname = 'btree'
      AND ix.indisvalid
      AND ix.indislive
      AND NOT ix.indisprimary                   -- PK é sempre canônico
      AND NOT ix.indisunique                    -- UNIQUE tem valor próprio
      AND ix.indisready
  ),
  exact_pairs AS (
    SELECT
      a.schemaname,
      a.tablename,
      CASE WHEN a.indexname < b.indexname THEN b.indexname ELSE a.indexname END AS redundant_index,
      CASE WHEN a.indexname < b.indexname THEN a.indexname ELSE b.indexname END AS canonical_index,
      'exact_duplicate'::text AS kind,
      format(
        'mesmo key_sig=%L, include_sig=%L, predicate=%L',
        a.key_sig, COALESCE(a.include_sig, ''), COALESCE(a.predicate, '')
      ) AS reason
    FROM raw a
    JOIN raw b
      ON b.schemaname = a.schemaname
     AND b.tablename  = a.tablename
     AND b.indexname  > a.indexname
     AND b.key_sig    = a.key_sig
     AND COALESCE(b.include_sig, '') = COALESCE(a.include_sig, '')
     AND COALESCE(b.predicate, '')   = COALESCE(a.predicate, '')
  ),
  prefix_pairs AS (
    SELECT
      a.schemaname,
      a.tablename,
      a.indexname AS redundant_index,
      b.indexname AS canonical_index,
      'prefix_overlap'::text AS kind,
      format(
        'key_sig de %I é prefixo de %I (a=%L, b=%L); include/predicate iguais',
        a.indexname, b.indexname, a.key_sig, b.key_sig
      ) AS reason
    FROM raw a
    JOIN raw b
      ON b.schemaname = a.schemaname
     AND b.tablename  = a.tablename
     AND b.indexname <> a.indexname
     AND b.key_sig LIKE a.key_sig || '|%'
     AND COALESCE(b.include_sig, '') = COALESCE(a.include_sig, '')
     AND COALESCE(b.predicate, '')   = COALESCE(a.predicate, '')
  )
  SELECT schemaname, tablename, redundant_index, canonical_index, kind, reason
    FROM exact_pairs
  UNION ALL
  SELECT schemaname, tablename, redundant_index, canonical_index, kind, reason
    FROM prefix_pairs
  ORDER BY schemaname, tablename, redundant_index;
$fn$;

COMMENT ON FUNCTION public.fn_find_duplicate_indexes(text, text) IS
  'L19-04: detecta índices btree plain redundantes em uma tabela. Retorna '
  '(redundant_index, canonical_index, kind, reason). `kind` ∈ '
  '{exact_duplicate, prefix_overlap}. Só escaneia btree non-unique non-pk; '
  'UNIQUE e expression-based são ignorados porque podem coexistir com plain '
  'indexes sem redundância. See LEDGER_INDEX_NAMING_RUNBOOK.md.';

REVOKE ALL ON FUNCTION public.fn_find_duplicate_indexes(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_find_duplicate_indexes(text, text) FROM anon;
REVOKE ALL ON FUNCTION public.fn_find_duplicate_indexes(text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_find_duplicate_indexes(text, text) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 3. Assert wrapper: fn_assert_no_duplicate_indexes
-- ──────────────────────────────────────────────────────────────────────────
-- Boolean helper que RAISE se encontrar qualquer duplicata nos schemas/tabelas
-- fornecidos. Usado em CI e self-tests.

CREATE OR REPLACE FUNCTION public.fn_assert_no_duplicate_indexes(
  p_schemas text[] DEFAULT ARRAY['public']::text[],
  p_tables  text[] DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $fn$
DECLARE
  v_row  record;
  v_list text := '';
  v_cnt  integer := 0;
BEGIN
  IF p_schemas IS NULL OR array_length(p_schemas, 1) IS NULL THEN
    RAISE EXCEPTION 'p_schemas must be non-empty' USING ERRCODE = '22023';
  END IF;

  FOR v_row IN
    SELECT d.*
      FROM unnest(p_schemas) AS s(schemaname)
      CROSS JOIN LATERAL (
        SELECT *
          FROM public.fn_find_duplicate_indexes(s.schemaname, NULL)
         WHERE (p_tables IS NULL) OR (tablename = ANY (p_tables))
      ) d
  LOOP
    v_cnt := v_cnt + 1;
    v_list := v_list || format(
      E'\n  - %I.%I: %I redundante vs %I (%s) — %s',
      v_row.schemaname, v_row.tablename,
      v_row.redundant_index, v_row.canonical_index,
      v_row.kind, v_row.reason
    );
  END LOOP;

  IF v_cnt > 0 THEN
    RAISE EXCEPTION 'L19-04: %s índices duplicados encontrados: %',
      v_cnt::text, v_list
      USING ERRCODE = 'P0010',
            HINT = 'See docs/runbooks/LEDGER_INDEX_NAMING_RUNBOOK.md. '
                   'Drop redundantes com DROP INDEX CONCURRENTLY (prod) '
                   'ou adicione WHERE/INCLUDE ao canônico para justificar ambos.';
  END IF;

  RETURN true;
END;
$fn$;

COMMENT ON FUNCTION public.fn_assert_no_duplicate_indexes(text[], text[]) IS
  'L19-04: raises P0010 se fn_find_duplicate_indexes retornar qualquer linha '
  'nos schemas/tabelas fornecidos. Usado em CI (npm run audit:duplicate-indexes) '
  'e no self-test da própria migration.';

REVOKE ALL ON FUNCTION public.fn_assert_no_duplicate_indexes(text[], text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_assert_no_duplicate_indexes(text[], text[]) FROM anon;
REVOKE ALL ON FUNCTION public.fn_assert_no_duplicate_indexes(text[], text[]) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_assert_no_duplicate_indexes(text[], text[]) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 4. Self-test DO block
-- ──────────────────────────────────────────────────────────────────────────
DO $selftest$
DECLARE
  v_count          integer;
  v_duplicate_cnt  integer;
BEGIN
  -- (a) Fase 0: garantir que as 2 funções foram registradas com SECURITY DEFINER.
  SELECT count(*)::int INTO v_count
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN ('fn_find_duplicate_indexes', 'fn_assert_no_duplicate_indexes')
     AND p.prosecdef = true;
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'L19-04 selftest: expected 2 SECURITY DEFINER functions, got %', v_count;
  END IF;

  -- (b) Fase 1: sem duplicatas em coin_ledger — passa sem raise.
  PERFORM public.fn_assert_no_duplicate_indexes(
    p_schemas => ARRAY['public']::text[],
    p_tables  => ARRAY['coin_ledger']::text[]
  );

  -- (c) Fase 2: verify fn_find_duplicate_indexes com escopo a tabela limpa
  -- devolve 0 rows.
  SELECT count(*)::int INTO v_duplicate_cnt
    FROM public.fn_find_duplicate_indexes('public', 'coin_ledger');
  IF v_duplicate_cnt <> 0 THEN
    RAISE EXCEPTION 'L19-04 selftest: coin_ledger tem % duplicates após dedup',
      v_duplicate_cnt;
  END IF;

  -- (d) Fase 3: fabricar duplicata sintética em temp schema + assertar que
  -- a detecção dispara. Usamos um schema temporário para não contaminar public.
  CREATE SCHEMA IF NOT EXISTS l19_04_test;
  CREATE TABLE IF NOT EXISTS l19_04_test.t (
    a int, b int, c int
  );
  -- Limpar quaisquer índices remanescentes de apply anterior
  EXECUTE 'DROP INDEX IF EXISTS l19_04_test.t_a_idx';
  EXECUTE 'DROP INDEX IF EXISTS l19_04_test.t_a_b_idx';
  EXECUTE 'CREATE INDEX t_a_idx   ON l19_04_test.t (a)';
  EXECUTE 'CREATE INDEX t_a_b_idx ON l19_04_test.t (a, b)';

  SELECT count(*)::int INTO v_duplicate_cnt
    FROM public.fn_find_duplicate_indexes('l19_04_test', 't');
  IF v_duplicate_cnt <> 1 THEN
    RAISE EXCEPTION 'L19-04 selftest: expected 1 prefix overlap in l19_04_test.t, got %',
      v_duplicate_cnt;
  END IF;

  -- (e) Fase 4: assert wrapper raise com P0010 quando há duplicatas.
  BEGIN
    PERFORM public.fn_assert_no_duplicate_indexes(
      p_schemas => ARRAY['l19_04_test']::text[],
      p_tables  => ARRAY['t']::text[]
    );
    RAISE EXCEPTION 'L19-04 selftest: expected assert to RAISE on duplicates';
  EXCEPTION
    WHEN sqlstate 'P0010' THEN
      NULL; -- expected
  END;

  -- Cleanup
  DROP SCHEMA l19_04_test CASCADE;

  RAISE NOTICE '[L19-04.selftest] OK — 4 phases pass';
END $selftest$;

COMMIT;
